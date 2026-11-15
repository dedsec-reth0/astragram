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
    private var notifiedIds = Set<MessageId>()

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
        |> deliverOnMainQueue).start(next: { [weak self] context, messages in
            self?.notify(context: context, messages: messages)
        })

        if #available(iOS 13.0, *) {
            let _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: self.refreshTaskId, using: DispatchQueue.main, launchHandler: { [weak self] task in
                self?.performRefresh(task: task)
            })
        }
        let _ = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.scheduleRefresh()
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

    private func notify(context: AccountContext, messages: [Message]) {
        guard AstraGramSettings.current.backgroundNotifications, self.application.applicationState != .active else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        for message in messages {
            if self.notifiedIds.contains(message.id) || !message.flags.contains(.Incoming) || AstraGramSettings.shouldHideMessage(message) {
                continue
            }
            self.notifiedIds.insert(message.id)

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
            // A chat locked with Face ID does not show its messages in a notification either.
            if AstraGramSettings.current.lockedChats.contains(message.id.peerId.toInt64()) {
                body = AstraStringsCompat.isRussian(presentationData) ? "Новое сообщение" : "New message"
            }
            content.body = body
            content.sound = .default
            content.threadIdentifier = "\(message.id.peerId.toInt64())"
            content.userInfo = [
                "accountId": context.account.id.int64,
                "peerId": message.id.peerId.toInt64(),
                "messageId.namespace": message.id.namespace,
                "messageId.id": message.id.id
            ]
            let request = UNNotificationRequest(identifier: "astra-\(context.account.id.int64)-\(message.id.peerId.toInt64())-\(message.id.id)", content: content, trigger: nil)
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
            Logger.shared.log("AstraGram", "Could not schedule background refresh: \(error)")
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
