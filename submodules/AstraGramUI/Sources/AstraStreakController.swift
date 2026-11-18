import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import Security

private func astraIsRussian(_ context: AccountContext) -> Bool {
    return context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.lowercased().hasPrefix("ru")
}

func astraDaysText(_ count: Int, isRussian: Bool) -> String {
    if !isRussian {
        return count == 1 ? "1 day" : "\(count) days"
    }
    let mod10 = count % 10
    let mod100 = count % 100
    if mod10 == 1 && mod100 != 11 {
        return "\(count) день"
    } else if (2 ... 4).contains(mod10) && !(12 ... 14).contains(mod100) {
        return "\(count) дня"
    } else {
        return "\(count) дней"
    }
}

/// The text shown in a profile for a streak.
public func astraStreakSummary(_ state: AstraStreakState?, isRussian: Bool) -> String {
    guard let state = state else {
        return isRussian ? "Не начат" : "Not started"
    }
    if let _ = state.restorableDay {
        return isRussian ? "🔥 \(state.displayCount) · можно восстановить" : "🔥 \(state.displayCount) · can be restored"
    }
    if state.count == 0 {
        return isRussian ? "🔥 0 · сегодня \(min(state.todayMine, AstraStreak.messagesPerDay))/\(AstraStreak.messagesPerDay)" : "🔥 0 · today \(min(state.todayMine, AstraStreak.messagesPerDay))/\(AstraStreak.messagesPerDay)"
    }
    return "🔥 " + astraDaysText(state.count, isRussian: isRussian)
}

// MARK: - The streak bot

/// The bot that keeps a streak for someone without AstraGram: AstraGram sends it the streak numbers (never the texts),
/// and the bot shows them to the other person, reminds them, and takes their restore requests.
public enum AstraStreakBot {
    /// The AstraGram streak bot and its server (astragram/streak-bot). The settings can point elsewhere; empty means these.
    static let defaultUsername = "infoastragram_bot"
    static let defaultURL = "https://astragram-streak-bot.dedsec-reth0.workers.dev"

    public static var username: String {
        let value = AstraGramSettings.current.streakBotUsername.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        return value.isEmpty ? AstraStreakBot.defaultUsername : value
    }

    static var serverURL: String {
        let value = AstraGramSettings.current.streakBotURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? AstraStreakBot.defaultURL : value
    }

    public static var isAvailable: Bool {
        return !AstraStreakBot.username.isEmpty && AstraStreakBot.serverURL.hasPrefix("https://")
    }

    public static var link: String {
        return "https://t.me/\(AstraStreakBot.username)"
    }

    // The token that proves to the bot's server which account sends the numbers: in the Keychain, one per account.
    private static func keychainQuery(_ accountPeerId: EnginePeer.Id) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "org.astragram.streakbot",
            kSecAttrAccount as String: "\(accountPeerId.toInt64())"
        ]
    }

    static func token(accountPeerId: EnginePeer.Id) -> String? {
        var query = AstraStreakBot.keychainQuery(accountPeerId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func setToken(_ token: String?, accountPeerId: EnginePeer.Id) {
        let query = AstraStreakBot.keychainQuery(accountPeerId)
        SecItemDelete(query as CFDictionary)
        guard let token = token else {
            return
        }
        var attributes = query
        attributes[kSecValueData as String] = token.data(using: .utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public static func isLinked(accountPeerId: EnginePeer.Id) -> Bool {
        return AstraStreakBot.token(accountPeerId: accountPeerId) != nil
    }

    /// Opens the bot with a new token: the bot ties the token to the Telegram account that presses Start.
    static func link(context: AccountContext, navigationController: NavigationController?) {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        AstraStreakBot.setToken(token, accountPeerId: context.account.peerId)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: "\(AstraStreakBot.link)?start=l\(token)", forceExternal: false, presentationData: presentationData, navigationController: navigationController, dismissInput: {})
    }

    /// Connects the bot without leaving the app: AstraGram itself sends the bot "/start l<token>" from this account,
    /// which is what pressing Start on the link would send. The bot's reply stays in the bot's chat.
    static func linkSilently(context: AccountContext, completion: @escaping (Bool) -> Void) {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard AstraStreakBot.isAvailable, SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            completion(false)
            return
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let account = context.account
        // Called exactly once: with the bot found, or with false when it cannot be found (no network, the lookup
        // ending without a result, or no answer in 10 s), so the caller always goes on (the invite is still sent).
        var finished = false
        let finish: (Bool) -> Void = { linked in
            if !finished {
                finished = true
                completion(linked)
            }
        }
        let _ = (context.engine.peers.resolvePeerByName(name: AstraStreakBot.username, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> take(1)
        |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer = peer else {
                finish(false)
                return
            }
            AstraStreakBot.setToken(token, accountPeerId: account.peerId)
            let _ = enqueueMessages(account: account, peerId: peer.id, messages: [.message(text: "/start l\(token)", attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).startStandalone()
            finish(true)
        }, completed: {
            finish(false)
        })
    }

    static func unlink(accountPeerId: EnginePeer.Id) {
        if let token = AstraStreakBot.token(accountPeerId: accountPeerId) {
            AstraStreakBot.request(path: "/api/unlink", token: token, body: [:], completion: { _ in })
        }
        AstraStreakBot.setToken(nil, accountPeerId: accountPeerId)
    }

    private static func request(path: String, token: String, body: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
        var base = AstraStreakBot.serverURL
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard base.hasPrefix("https://"), let url = URL(string: base + path), let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 30.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                completion(object)
            } else {
                completion(nil)
            }
        }).resume()
    }

    /// Sends the numbers of the streaks; returns the days the other people asked to restore in the bot, or nil when the
    /// server did not take them (no connection, or Start not pressed in the bot yet).
    static func sync(accountPeerId: EnginePeer.Id, states: [EnginePeer.Id: AstraStreakState], completion: @escaping ([(peerId: EnginePeer.Id, day: Int32)]?) -> Void) {
        guard AstraStreakBot.isAvailable, let token = AstraStreakBot.token(accountPeerId: accountPeerId) else {
            completion(nil)
            return
        }
        var pairs: [[String: Any]] = []
        for (peerId, state) in states where peerId.namespace == Namespaces.Peer.CloudUser {
            var pair: [String: Any] = [
                "friend": peerId.id._internalGetInt64Value(),
                "count": state.count,
                "mine": state.todayMine,
                "theirs": state.todayTheirs,
                "todayDone": state.todayDone,
                "restoresLeft": state.restoresLeft,
                "lostCount": state.lostCount,
                "day": state.today
            ]
            if let restorableDay = state.restorableDay {
                pair["restorableDay"] = restorableDay
            }
            pairs.append(pair)
        }
        AstraStreakBot.request(path: "/api/sync", token: token, body: ["pairs": pairs, "need": AstraStreak.messagesPerDay, "tz": TimeZone.current.secondsFromGMT()], completion: { object in
            guard let object = object else {
                completion(nil)
                return
            }
            var result: [(peerId: EnginePeer.Id, day: Int32)] = []
            if let restores = object["restores"] as? [[String: Any]] {
                for restore in restores {
                    if let friend = (restore["friend"] as? NSNumber)?.int64Value, let day = (restore["day"] as? NSNumber)?.int32Value {
                        result.append((peerId: EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(friend)), day: day))
                    }
                }
            }
            completion(result)
        })
    }
}

// MARK: - Keeping the values up to date

/// Counts the streaks of an account whenever their chats change, keeps the values shown in the chat list, and sends
/// the numbers to the streak bot when it is linked.
public final class AstraStreakManager {
    private static var managers: [EnginePeer.Id: AstraStreakManager] = [:]

    public static func start(context: AccountContext) {
        let peerId = context.account.peerId
        if AstraStreakManager.managers[peerId] == nil {
            AstraStreakManager.managers[peerId] = AstraStreakManager(context: context)
        }
    }

    static func forAccount(_ peerId: EnginePeer.Id) -> AstraStreakManager? {
        return AstraStreakManager.managers[peerId]
    }

    private let accountPeerId: EnginePeer.Id
    private let account: Account
    private let store: AstraMessageStore
    private var disposable: Disposable?
    private var timer: SwiftSignalKit.Timer?
    private let refreshPipe = ValuePipe<Void>()
    private var states: [EnginePeer.Id: AstraStreakState] = [:]
    private var lastSync: Double = 0.0
    private var lastSyncedStates: [EnginePeer.Id: AstraStreakState] = [:]
    /// The bot token the numbers were last sent with: a new link (a new token) sends them again at once.
    private var lastSyncedToken: String?
    private let statesPromise = ValuePromise<[EnginePeer.Id: AstraStreakState]>([:], ignoreRepeated: true)

    var statesSignal: Signal<[EnginePeer.Id: AstraStreakState], NoError> {
        return self.statesPromise.get()
    }

    private init(context: AccountContext) {
        self.accountPeerId = context.account.peerId
        self.account = context.account
        self.store = AstraMessageStore.forAccount(context.account)
        let account = self.account
        let store = self.store

        let streaks = store.streaks()
        // Recounted when a chat with a streak gets a message, when a restore is saved, and every minute (the day changes).
        let topMessages = streaks
        |> mapToSignal { streaks -> Signal<[EnginePeer.Id: Int32], NoError> in
            return AstraStreak.topMessageIds(account: account, peerIds: Array(streaks.keys))
        }
        let ticks: Signal<Void, NoError> = .single(Void()) |> then(self.refreshPipe.signal())

        self.disposable = (combineLatest(streaks, topMessages, ticks)
        |> mapToSignal { streaks, _, _ -> Signal<[EnginePeer.Id: AstraStreakState], NoError> in
            if streaks.isEmpty {
                return .single([:])
            }
            let signals = streaks.map { peerId, startDay -> Signal<(EnginePeer.Id, AstraStreakState), NoError> in
                return store.streakRestores(peerId: peerId)
                |> mapToSignal { restores in
                    return AstraStreak.compute(account: account, peerId: peerId, startDay: startDay, localRestores: restores)
                }
                |> map { (peerId, $0) }
            }
            return combineLatest(signals)
            |> map { pairs -> [EnginePeer.Id: AstraStreakState] in
                var result: [EnginePeer.Id: AstraStreakState] = [:]
                for (peerId, state) in pairs {
                    result[peerId] = state
                }
                return result
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] states in
            self?.apply(states)
        })

        self.timer = SwiftSignalKit.Timer(timeout: 60.0, repeat: true, completion: { [weak self] in
            self?.refreshPipe.putNext(Void())
        }, queue: .mainQueue())
        self.timer?.start()
    }

    func refresh() {
        self.refreshPipe.putNext(Void())
    }

    private func apply(_ states: [EnginePeer.Id: AstraStreakState]) {
        let removed = Set(self.states.keys).subtracting(states.keys)
        for peerId in removed {
            AstraStreak.setCached(accountPeerId: self.accountPeerId, peerId: peerId, state: nil)
        }
        for (peerId, state) in states {
            AstraStreak.setCached(accountPeerId: self.accountPeerId, peerId: peerId, state: state)
        }
        self.states = states
        self.statesPromise.set(states)
        self.syncIfNeeded()
    }

    /// The bot gets the numbers when they change, at most once a minute, and every 15 minutes otherwise. A sync the
    /// server did not take is retried the next minute: right after linking the token is sent before Start is pressed in
    /// the bot, and the server turns it away until then.
    private func syncIfNeeded() {
        guard AstraStreakBot.isAvailable, let token = AstraStreakBot.token(accountPeerId: self.accountPeerId) else {
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        let changed = self.states != self.lastSyncedStates || token != self.lastSyncedToken
        if !(changed && now - self.lastSync > 60.0) && now - self.lastSync < 15.0 * 60.0 {
            return
        }
        self.lastSync = now
        let states = self.states
        self.lastSyncedStates = states
        self.lastSyncedToken = token
        let store = self.store
        AstraStreakBot.sync(accountPeerId: self.accountPeerId, states: states, completion: { [weak self] restores in
            Queue.mainQueue().async {
                guard let restores = restores else {
                    if let self, self.lastSyncedToken == token {
                        self.lastSyncedToken = nil
                    }
                    return
                }
                var applied = false
                for restore in restores {
                    // Only what the rules allow now: yesterday, while it can still be restored.
                    if let state = states[restore.peerId], state.restorableDay == restore.day, state.restoresLeft > 0 {
                        store.addStreakRestore(peerId: restore.peerId, day: restore.day)
                        applied = true
                    }
                }
                if applied {
                    self?.lastSync = 0.0
                }
            }
        })
    }
}

// MARK: - The streak screen

private final class AstraStreakArguments {
    let start: () -> Void
    let stop: () -> Void
    let restore: () -> Void
    let linkBot: () -> Void
    let unlinkBot: () -> Void
    let invite: () -> Void

    init(start: @escaping () -> Void, stop: @escaping () -> Void, restore: @escaping () -> Void, linkBot: @escaping () -> Void, unlinkBot: @escaping () -> Void, invite: @escaping () -> Void) {
        self.start = start
        self.stop = stop
        self.restore = restore
        self.linkBot = linkBot
        self.unlinkBot = unlinkBot
        self.invite = invite
    }
}

private enum AstraStreakEntry: ItemListNodeEntry {
    case header(String)
    case value(Int32, String, String)
    case action(Int32, String, Bool)
    case destructive(Int32, String)
    case info(Int32, String)
    case sectionFooter(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .header, .value(0 ..< 100, _, _):
            return 0
        case let .value(id, _, _), let .action(id, _, _), let .destructive(id, _), let .info(id, _):
            return ItemListSectionId(id / 100)
        case let .sectionFooter(_, section, _):
            return ItemListSectionId(section)
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .value(id, _, _), let .action(id, _, _), let .destructive(id, _), let .info(id, _):
            return id
        case let .sectionFooter(id, _, _):
            return id
        }
    }

    static func <(lhs: AstraStreakEntry, rhs: AstraStreakEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraStreakArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .value(_, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .action(id, title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                switch id {
                case 101:
                    arguments.start()
                case 102:
                    arguments.restore()
                case 201:
                    arguments.invite()
                case 202:
                    arguments.linkBot()
                default:
                    break
                }
            })
        case let .destructive(id, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if id == 203 {
                    arguments.unlinkBot()
                } else {
                    arguments.stop()
                }
            })
        case let .info(_, text), let .sectionFooter(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// The streak with one person: how it stands, restoring yesterday, the bot for someone without AstraGram.
public func astraStreakController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?
    let store = AstraMessageStore.forAccount(context.account)
    AstraStreakManager.start(context: context)
    let accountPeerId = context.account.peerId
    let botLinked = ValuePromise<Bool>(AstraStreakBot.isLinked(accountPeerId: accountPeerId), ignoreRepeated: true)

    let peer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))

    func showAlert(title: String, text: String, actionTitle: String, destructive: Bool = false, action: @escaping () -> Void) {
        guard let top = astraTopViewController() else {
            return
        }
        let isRussian = astraIsRussian(context)
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: actionTitle, style: destructive ? .destructive : .default, handler: { _ in
            action()
        }))
        top.present(alert, animated: true)
    }

    func send(_ text: String) {
        let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).startStandalone()
    }

    func toast(_ text: String) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
    }

    let arguments = AstraStreakArguments(
        start: {
            let isRussian = astraIsRussian(context)
            let _ = (peer |> take(1) |> deliverOnMainQueue).start(next: { peer in
                guard let peer = peer, AstraStreakBot.isAvailable, !peer.astraUsesAstraGram else {
                    // Both on AstraGram: each phone counts the streak by itself, no bot is needed.
                    store.setStreak(peerId: peerId, startDay: AstraStreak.today())
                    AstraHaptics.success()
                    return
                }
                guard let top = astraTopViewController() else {
                    return
                }
                let name = peer.compactDisplayTitle
                let alert = UIAlertController(
                    title: isRussian ? "Начать огонёк с \(name)?" : "Start a streak with \(name)?",
                    message: isRussian
                        ? "У \(name) обычный Telegram, поэтому счёт \(name) увидит в боте @\(AstraStreakBot.username). AstraGram сам подключит бота с вашей стороны и отправит \(name) ссылку на бота — \(name) достаточно один раз нажать в нём «Старт». Боту уходят только числа: счёт и сколько сообщений написано сегодня, тексты — никогда."
                        : "\(name) uses plain Telegram, so \(name) sees the count in the bot @\(AstraStreakBot.username). AstraGram connects the bot on your side and sends \(name) a link to it; \(name) only presses Start in it once. The bot gets only numbers: the count and how many messages were written today, never texts.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: isRussian ? "Начать и пригласить" : "Start and Invite", style: .default, handler: { _ in
                    store.setStreak(peerId: peerId, startDay: AstraStreak.today())
                    AstraHaptics.success()
                    let finish = {
                        let inviteLink = "\(AstraStreakBot.link)?start=f\(accountPeerId.id._internalGetInt64Value())"
                        send(isRussian ? "Давай держать огонёк 🔥 Каждый день по \(AstraStreak.messagesPerDay) сообщения друг другу. Счёт и напоминания — в боте, нажми «Старт»: \(inviteLink)" : "Let's keep a streak 🔥 \(AstraStreak.messagesPerDay) messages to each other every day. The count and reminders are in the bot, press Start: \(inviteLink)")
                        toast(isRussian ? "Огонёк начат, приглашение отправлено" : "Streak started, invitation sent")
                        AstraStreakManager.forAccount(accountPeerId)?.refresh()
                    }
                    if AstraStreakBot.isLinked(accountPeerId: accountPeerId) {
                        finish()
                    } else {
                        AstraStreakBot.linkSilently(context: context, completion: { linked in
                            if linked {
                                botLinked.set(true)
                            }
                            finish()
                        })
                    }
                }))
                alert.addAction(UIAlertAction(title: isRussian ? "Только начать" : "Just Start", style: .default, handler: { _ in
                    store.setStreak(peerId: peerId, startDay: AstraStreak.today())
                    AstraHaptics.success()
                }))
                alert.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
                top.present(alert, animated: true)
            })
        },
        stop: {
            let isRussian = astraIsRussian(context)
            showAlert(title: isRussian ? "Выключить огонёк?" : "Turn off the streak?", text: isRussian ? "Счёт и восстановления этого огонька пропадут. Начать можно заново, но с нуля." : "The count and restores of this streak are lost. You can start again, from zero.", actionTitle: isRussian ? "Выключить" : "Turn Off", destructive: true, action: {
                store.setStreak(peerId: peerId, startDay: nil)
            })
        },
        restore: {
            let isRussian = astraIsRussian(context)
            guard let state = AstraStreak.cached(accountPeerId: accountPeerId, peerId: peerId), let day = state.restorableDay, state.restoresLeft > 0 else {
                return
            }
            let text = AstraStreak.restoreMessageText(day: day, isRussian: isRussian)
            let visibleText = text.trimmingCharacters(in: AstraStreak.invisibleCharacters)
            showAlert(title: isRussian ? "Восстановить огонёк?" : "Restore the streak?", text: isRussian ? "Вчерашний день засчитается. В чат уйдёт сообщение «\(visibleText)», чтобы восстановление увидел и собеседник. Останется восстановлений на этой неделе: \(state.restoresLeft - 1)." : "Yesterday will count. The message “\(visibleText)” goes to the chat, so the other person sees the restore too. Restores left this week: \(state.restoresLeft - 1).", actionTitle: isRussian ? "Восстановить" : "Restore", action: {
                store.addStreakRestore(peerId: peerId, day: day)
                send(text)
                AstraHaptics.success()
            })
        },
        linkBot: {
            let isRussian = astraIsRussian(context)
            showAlert(title: isRussian ? "Подключить бота огоньков?" : "Connect the streak bot?", text: isRussian ? "Бот покажет огонёк тем, у кого нет AstraGram, напомнит им написать и примет их восстановления. Для этого AstraGram будет отправлять на сервер бота ID собеседников с огоньком, счёт и сколько сообщений написано сегодня. Тексты сообщений не отправляются." : "The bot shows the streak to people without AstraGram, reminds them to write, and takes their restores. For this AstraGram sends the bot's server the IDs of people you have a streak with, the count, and how many messages were written today. Message texts are not sent.", actionTitle: isRussian ? "Подключить" : "Connect", action: {
                AstraStreakBot.linkSilently(context: context, completion: { linked in
                    if linked {
                        botLinked.set(true)
                        toast(isRussian ? "Бот огоньков подключён" : "Streak bot connected")
                        AstraStreakManager.forAccount(accountPeerId)?.refresh()
                    } else {
                        AstraStreakBot.link(context: context, navigationController: navigationControllerImpl?())
                        botLinked.set(true)
                        AstraStreakManager.forAccount(accountPeerId)?.refresh()
                    }
                })
            })
        },
        unlinkBot: {
            let isRussian = astraIsRussian(context)
            showAlert(title: isRussian ? "Отключить бота?" : "Disconnect the bot?", text: isRussian ? "AstraGram перестанет отправлять боту числа огоньков, а бот удалит то, что о вас хранил." : "AstraGram stops sending the bot the numbers of your streaks, and the bot deletes what it kept about you.", actionTitle: isRussian ? "Отключить" : "Disconnect", destructive: true, action: {
                AstraStreakBot.unlink(accountPeerId: accountPeerId)
                botLinked.set(false)
            })
        },
        invite: {
            let isRussian = astraIsRussian(context)
            // The link names who invited, so the bot can tell the other person whose streak is on its way.
            let inviteLink = "\(AstraStreakBot.link)?start=f\(accountPeerId.id._internalGetInt64Value())"
            let text = isRussian ? "Давай держать огонёк 🔥 Каждый день по \(AstraStreak.messagesPerDay) сообщения друг другу. Счёт и напоминания — в боте: \(inviteLink)" : "Let's keep a streak 🔥 \(AstraStreak.messagesPerDay) messages to each other every day. The count and reminders are in the bot: \(inviteLink)"
            showAlert(title: isRussian ? "Пригласить в бота?" : "Invite to the bot?", text: isRussian ? "В чат уйдёт сообщение:\n\n\(text)" : "This message goes to the chat:\n\n\(text)", actionTitle: isRussian ? "Отправить" : "Send", action: {
                send(text)
                toast(isRussian ? "Приглашение отправлено" : "Invitation sent")
            })
        }
    )

    let states: Signal<[EnginePeer.Id: AstraStreakState], NoError> = Signal<[EnginePeer.Id: AstraStreakState], NoError>.single([:]) |> then(
        (Signal<Void, NoError>.single(Void()) |> deliverOnMainQueue)
        |> mapToSignal { _ -> Signal<[EnginePeer.Id: AstraStreakState], NoError> in
            return AstraStreakManager.forAccount(accountPeerId)?.statesSignal ?? .single([:])
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        store.streaks(),
        states,
        peer,
        botLinked.get()
    )
    |> map { presentationData, streaks, states, peer, botLinked -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let name = peer?.compactDisplayTitle ?? ""
        let need = AstraStreak.messagesPerDay
        var entries: [AstraStreakEntry] = []
        let isOn = streaks[peerId] != nil
        let state = states[peerId]

        if isOn {
            entries.append(.header(isRussian ? "ОГОНЁК С \(name.uppercased())" : "STREAK WITH \(name.uppercased())"))
            if let state = state {
                entries.append(.value(1, isRussian ? "🔥 Огонёк" : "🔥 Streak", astraDaysText(state.displayCount, isRussian: isRussian)))
                entries.append(.value(2, isRussian ? "Вы сегодня" : "You today", "\(min(state.todayMine, need))/\(need)"))
                entries.append(.value(3, isRussian ? "\(name) сегодня" : "\(name) today", "\(min(state.todayTheirs, need))/\(need)"))
                entries.append(.value(4, isRussian ? "Восстановлений на неделе" : "Restores this week", "\(state.restoresLeft)/\(AstraStreak.restoresPerWeek)"))
                let statusText: String
                if state.todayDone {
                    statusText = isRussian ? "Сегодня засчитано, огонёк горит." : "Today counts, the streak is alive."
                } else if state.restorableDay != nil {
                    statusText = isRussian ? "Вчера не набралось по \(need) сообщения. Восстановите вчерашний день сегодня, иначе огонёк начнётся заново." : "Yesterday did not reach \(need) messages each. Restore yesterday today, or the streak starts over."
                } else {
                    statusText = isRussian ? "Чтобы день засчитался, каждому нужно написать сегодня хотя бы \(need) сообщения." : "For today to count, each of you writes at least \(need) messages today."
                }
                entries.append(.info(5, statusText))
            } else {
                entries.append(.info(5, isRussian ? "Считаю…" : "Counting…"))
            }
            if let state = state, state.restorableDay != nil {
                entries.append(.action(102, isRussian ? "Восстановить вчерашний день" : "Restore Yesterday", state.restoresLeft > 0))
            }
            entries.append(.destructive(103, isRussian ? "Выключить огонёк" : "Turn Off Streak"))
            entries.append(.sectionFooter(104, 1, isRussian ? "День засчитывается, когда каждый из вас написал хотя бы \(need) сообщения. Пропущенный день можно восстановить на следующий день, не больше \(AstraStreak.restoresPerWeek) раз в неделю. Если день не набран и не восстановлен, огонёк гаснет и начинается заново. Считается на этом устройстве по сообщениям чата, поэтому работает и с теми, у кого нет AstraGram." : "A day counts when each of you wrote at least \(need) messages. A missed day can be restored on the next day, at most \(AstraStreak.restoresPerWeek) times a week. A day neither reached nor restored ends the streak, and it starts over. Counted on this device from the chat's messages, so it works with people without AstraGram too."))

            if AstraStreakBot.isAvailable {
                if let peer = peer, !peer.astraUsesAstraGram {
                    entries.append(.action(201, isRussian ? "Пригласить \(name) в бота" : "Invite \(name) to the Bot", true))
                }
                if botLinked {
                    entries.append(.destructive(203, isRussian ? "Отключить бота огоньков" : "Disconnect Streak Bot"))
                } else {
                    entries.append(.action(202, isRussian ? "Подключить бота огоньков" : "Connect Streak Bot", true))
                }
                entries.append(.sectionFooter(204, 2, isRussian ? "У кого нет AstraGram, следит за огоньком в боте @\(AstraStreakBot.username): видит счёт, получает напоминание вечером и может восстановить вчерашний день. Бот знает только числа, тексты сообщений к нему не попадают." : "People without AstraGram follow the streak in the bot @\(AstraStreakBot.username): they see the count, get a reminder in the evening, and can restore yesterday. The bot knows only the numbers; message texts never reach it."))
            } else {
                entries.append(.sectionFooter(204, 2, isRussian ? "Бот огоньков для тех, у кого нет AstraGram, ещё не запущен. Огонёк уже считается в AstraGram, бот подключится в одном из следующих обновлений." : "The streak bot for people without AstraGram is not running yet. The streak is already counted in AstraGram; the bot comes in a later update."))
            }
        } else {
            entries.append(.header(isRussian ? "ОГОНЁК С \(name.uppercased())" : "STREAK WITH \(name.uppercased())"))
            entries.append(.action(101, isRussian ? "🔥 Начать огонёк" : "🔥 Start a Streak", true))
            entries.append(.sectionFooter(104, 1, isRussian ? "Пишите друг другу каждый день хотя бы по \(need) сообщения, и огонёк будет расти. Пропуск можно восстановить \(AstraStreak.restoresPerWeek) раз в неделю. Если огонёк погаснет, всё начнётся заново. Работает и с теми, у кого нет AstraGram." : "Write to each other at least \(need) messages every day, and the streak grows. A miss can be restored \(AstraStreak.restoresPerWeek) times a week. If the streak goes out, it starts over. Works with people without AstraGram too."))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isRussian ? "Огонёк" : "Streak"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}

/// Pushes the streak screen from anywhere (a profile, the chat list menu).
public func astraOpenStreak(context: AccountContext, peerId: EnginePeer.Id) {
    let controller = astraStreakController(context: context, peerId: peerId)
    if let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController {
        navigationController.pushViewController(controller)
    }
}

// MARK: - All streaks

private enum AstraStreaksListEntry: ItemListNodeEntry {
    case streak(Int, EnginePeer.Id, String, String)
    case empty(String)
    case footer(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .streak(index, _, _, _):
            return index
        case .empty:
            return 100000
        case .footer:
            return 100001
        }
    }

    static func <(lhs: AstraStreaksListEntry, rhs: AstraStreaksListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let open = arguments as! (EnginePeer.Id) -> Void
        switch self {
        case let .streak(_, peerId, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                open(peerId)
            })
        case let .empty(text), let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Every streak of the account, the longest first.
public func astraStreaksListController(context: AccountContext) -> ViewController {
    var pushImpl: ((ViewController) -> Void)?
    AstraStreakManager.start(context: context)
    let accountPeerId = context.account.peerId
    let store = AstraMessageStore.forAccount(context.account)
    let open: (EnginePeer.Id) -> Void = { peerId in
        pushImpl?(astraStreakController(context: context, peerId: peerId))
    }

    let peers = store.streaks()
    |> mapToSignal { streaks -> Signal<[EnginePeer], NoError> in
        return context.engine.data.get(EngineDataMap(streaks.keys.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [EnginePeer] in
            return peers.values.compactMap { $0 }
        }
    }
    let states: Signal<[EnginePeer.Id: AstraStreakState], NoError> = (Signal<Void, NoError>.single(Void()) |> deliverOnMainQueue)
    |> mapToSignal { _ -> Signal<[EnginePeer.Id: AstraStreakState], NoError> in
        return AstraStreakManager.forAccount(accountPeerId)?.statesSignal ?? .single([:])
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, peers, states)
    |> map { presentationData, peers, states -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.lowercased().hasPrefix("ru")
        let sorted = peers.sorted { (states[$0.id]?.displayCount ?? 0) > (states[$1.id]?.displayCount ?? 0) }
        var entries: [AstraStreaksListEntry] = []
        for (index, peer) in sorted.enumerated() {
            entries.append(.streak(index, peer.id, peer.compactDisplayTitle, astraStreakSummary(states[peer.id], isRussian: isRussian)))
        }
        if sorted.isEmpty {
            entries.append(.empty(isRussian ? "Огоньков пока нет. Откройте профиль собеседника и нажмите «Огонёк»." : "No streaks yet. Open someone's profile and tap Streak."))
        }
        entries.append(.footer(isRussian ? "Огонёк растёт, когда вы оба пишете каждый день хотя бы по \(AstraStreak.messagesPerDay) сообщения. Число видно у имени в списке чатов." : "A streak grows when both of you write at least \(AstraStreak.messagesPerDay) messages every day. The number shows beside the name in the chat list."))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isRussian ? "Огоньки" : "Streaks"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, open))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
