import Foundation
import UIKit
import BackgroundTasks
import UserNotifications
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData

/// AstraGram: notifications without push.
///
/// A sideloaded Telegram gets no push notifications: Telegram's servers push only to the official app (its signing
/// certificate and API ID). Instead, AstraGram
/// * posts a local notification for every new message that arrives while the app is in the background (right after it
///   is closed, and whenever iOS keeps it running), and
/// * asks iOS to wake it up from time to time (background app refresh), connects for a short time, and the messages
///   that arrive are notified the same way.
/// iOS decides when to wake the app up (typically every 15–60 minutes, rarely in Low Power Mode or after the app was
/// swiped away), so these notifications come late.
final class AstraBackgroundNotifier {
    private let application: UIApplication
    private let sharedContext: Signal<SharedApplicationContext, NoError>
    private let refreshTaskId: String
    private var messagesDisposable: Disposable?
    // Keyed by account too: a channel or supergroup message has the same id on every account that is in it, and each
    // account notifies it on its own.
    private struct NotifiedKey: Hashable {
        let accountId: AccountRecordId
        let messageId: MessageId
    }
    private var notifiedIds = Set<NotifiedKey>()

    /// Created during app launch: background task handlers must be registered before launch ends.
    init(application: UIApplication, sharedContext: Signal<SharedApplicationContext, NoError>, baseAppBundleId: String) {
        self.application = application
        self.sharedContext = sharedContext
        // AltStore changes the bundle identifier when it signs the app, but not the permitted task identifiers in
        // Info.plist: the identifier is taken from there.
        let permittedTaskIds = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        self.refreshTaskId = permittedTaskIds.first(where: { $0.hasSuffix(".refresh") }) ?? "\(baseAppBundleId).refresh"

        // New messages of every logged-in account, notified while the app is not in the foreground.
        self.messagesDisposable = (sharedContext
        |> take(1)
        |> mapToSignal { sharedApplicationContext -> Signal<(primary: AccountContext?, accounts: [(AccountRecordId, AccountContext, Int32)], currentAuth: UnauthorizedAccount?), NoError> in
            return sharedApplicationContext.sharedContext.activeAccountContexts
        }
        |> mapToSignal { _, contexts, _ -> Signal<(AccountContext, [Message]), NoError> in
            let signals = contexts.map { _, context, _ -> Signal<(AccountContext, [Message]), NoError> in
                return context.account.stateManager.notificationMessages
                |> map { items -> (AccountContext, [Message]) in
                    var messages: [Message] = []
                    for (itemMessages, _, notify, _) in items {
                        // Muted chats notify only messages with a keyword alert.
                        if notify {
                            messages.append(contentsOf: itemMessages)
                        } else {
                            messages.append(contentsOf: itemMessages.filter { AstraBackgroundNotifier.matchesKeywordAlert($0.text) })
                        }
                    }
                    return (context, messages)
                }
            }
            // Every account's messages, as they come.
            return Signal { subscriber in
                let disposables = DisposableSet()
                for signal in signals {
                    disposables.add(signal.start(next: { value in
                        subscriber.putNext(value)
                    }))
                }
                return disposables
            }
        }
        |> mapToSignal { context, messages -> Signal<(AccountContext, [Message], Bool, EngineGlobalNotificationSettings), NoError> in
            // Telegram's passcode and its "Message Preview" switches are kept: with a passcode set, or previews off,
            // a notification names nobody and quotes nothing.
            return combineLatest(
                context.sharedContext.appLockContext.autolockDeadline |> take(1),
                context.engine.data.get(TelegramEngine.EngineData.Item.NotificationSettings.Global())
            )
            |> map { deadline, settings in
                return (context, messages, deadline != nil, settings)
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] context, messages, hasPasscode, settings in
            self?.notify(context: context, messages: messages, hasPasscode: hasPasscode, settings: settings)
        })

        if #available(iOS 13.0, *) {
            let _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: self.refreshTaskId, using: DispatchQueue.main, launchHandler: { [weak self] task in
                self?.performRefresh(task: task)
            })
        }
        let _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.scheduleRefresh()
            // AstraGram: voice messages, round videos and music stop when the app is minimized (Settings → AstraGram
            // → Chats).
            if AstraGramSettings.current.pauseMediaOnMinimize, let self {
                let _ = (self.sharedContext
                |> take(1)
                |> deliverOnMainQueue).startStandalone(next: { sharedApplicationContext in
                    sharedApplicationContext.sharedContext.mediaManager.playlistControl(.playback(.pause), type: nil)
                })
            }
        })
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { _, _ in })
    }

    deinit {
        self.messagesDisposable?.dispose()
    }

    /// "Keyword alerts": whether `text` contains one of the words.
    static func matchesKeywordAlert(_ text: String) -> Bool {
        let keywords = AstraGramSettings.current.keywordAlerts
        if keywords.isEmpty || text.isEmpty {
            return false
        }
        let lowercased = text.lowercased()
        return keywords.contains(where: { !$0.isEmpty && lowercased.contains($0.lowercased()) })
    }

    private func notify(context: AccountContext, messages: [Message], hasPasscode: Bool, settings: EngineGlobalNotificationSettings) {
        // Only while in the background: "inactive" is also Control Center or a Face ID prompt over the open app.
        guard AstraGramSettings.current.backgroundNotifications, self.application.applicationState == .background else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        for message in messages {
            let key = NotifiedKey(accountId: context.account.id, messageId: message.id)
            if self.notifiedIds.contains(key) || !message.flags.contains(.Incoming) || AstraGramSettings.shouldHideMessage(message) {
                continue
            }
            self.notifiedIds.insert(key)

            let content = UNMutableNotificationContent()
            let chatTitle = message.peers[message.id.peerId].flatMap { EnginePeer($0).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) } ?? "AstraGram"
            var body = message.text
            if body.isEmpty {
                body = AstraStringsCompat.isRussian(presentationData) ? "Медиа" : "Media"
            }
            if message.id.peerId.namespace != Namespaces.Peer.CloudUser, let author = message.author, author.id != message.id.peerId {
                body = EnginePeer(author).displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) + ": " + body
            }
            content.title = chatTitle
            let displayPreviews: Bool
            if message.id.peerId.namespace == Namespaces.Peer.CloudUser {
                displayPreviews = settings.privateChats.displayPreviews
            } else if let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info {
                displayPreviews = settings.channels.displayPreviews
            } else {
                displayPreviews = settings.groupChats.displayPreviews
            }
            if hasPasscode {
                // Not even who wrote: the chat list itself is behind the passcode.
                content.title = "AstraGram"
            }
            // A chat locked with Face ID, a secret chat, a passcode or previews turned off: no text in the notification.
            if hasPasscode || !displayPreviews || AstraGramSettings.current.lockedChats.contains(message.id.peerId.toInt64()) || message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                body = AstraStringsCompat.isRussian(presentationData) ? "Новое сообщение" : "New message"
            }
            content.body = body
            content.sound = .default
            content.threadIdentifier = "\(message.id.peerId.toInt64())"
            var userInfo: [AnyHashable: Any] = [
                "accountId": context.account.id.int64,
                "peerId": message.id.peerId.toInt64(),
                "messageId.namespace": message.id.namespace,
                "messageId.id": message.id.id
            ]
            // A tap on a forum topic's message opens that topic: AppDelegate reads "threadId" as a forum topic id, so it
            // is set only in forums (in other chats a thread id is a comment or reply thread, not a topic).
            if let threadId = message.threadId, let channel = message.peers[message.id.peerId] as? TelegramChannel, channel.flags.contains(.isForum) {
                userInfo["threadId"] = threadId
            }
            content.userInfo = userInfo
            // The identifier has Telegram's "m<peer>:<namespace>:<id>" form, so ClearNotificationsManager recognizes it and
            // takes the notification down when the chat is read; the account suffix keeps the accounts' notifications apart.
            let request = UNNotificationRequest(identifier: "m\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)_astra\(context.account.id.int64)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
        if self.notifiedIds.count > 2000 {
            self.notifiedIds.removeAll()
        }
    }

    private func scheduleRefresh() {
        guard #available(iOS 13.0, *), AstraGramSettings.current.backgroundNotifications else {
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15.0 * 60.0)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let error {
            // NSLog, not Logger.shared: this also runs when the app goes to the background before launch has set
            // up the shared logger (for example on the API ID screen), where Logger.shared asserts.
            NSLog("[AstraGram] Could not schedule background refresh: \(error)")
        }
    }

    @available(iOS 13.0, *)
    private func performRefresh(task: BGTask) {
        // The next wakeup is requested first, so it is not lost if this one runs out of time.
        self.scheduleRefresh()

        // Connect for a short time: the messages that arrive are notified by the subscription above.
        let disposable = (self.sharedContext
        |> take(1)
        |> mapToSignal { sharedApplicationContext -> Signal<(SharedApplicationContext, [Account]), NoError> in
            return sharedApplicationContext.sharedContext.activeAccountContexts
            |> take(1)
            |> map { _, contexts, _ -> (SharedApplicationContext, [Account]) in
                return (sharedApplicationContext, contexts.map { $0.1.account })
            }
        }
        |> deliverOnMainQueue).start(next: { sharedApplicationContext, accounts in
            sharedApplicationContext.wakeupManager.allowBackgroundTimeExtension(timeout: 25.0, extendNow: true)
            for account in accounts {
                sharedApplicationContext.notificationManager.beginPollingState(account: account)
            }
        })
        var completed = false
        let complete: (Bool) -> Void = { success in
            if !completed {
                completed = true
                disposable.dispose()
                task.setTaskCompleted(success: success)
            }
        }
        // The expiration handler is not called on the main queue; `complete` belongs to it.
        task.expirationHandler = {
            Queue.mainQueue().async {
                complete(false)
            }
        }
        Queue.mainQueue().after(25.0, {
            complete(true)
        })
    }
}

private enum AstraStringsCompat {
    static func isRussian(_ presentationData: PresentationData) -> Bool {
        let code = presentationData.strings.baseLanguageCode.lowercased()
        return code.hasPrefix("ru") || code.hasPrefix("uk") || code.hasPrefix("be")
    }
}
