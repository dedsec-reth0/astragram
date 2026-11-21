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
    return context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
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
        AstraStreakBot.request(path: path, token: token, body: body, statusCompletion: { object, _ in
            completion(object)
        })
    }

    /// `statusCompletion` also gets the HTTP status (0 without an answer).
    private static func request(path: String, token: String, body: [String: Any], statusCompletion completion: @escaping ([String: Any]?, Int) -> Void) {
        var base = AstraStreakBot.serverURL
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard base.hasPrefix("https://"), let url = URL(string: base + path), let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil, 0)
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
                completion(object, status)
            } else {
                completion(nil, status)
            }
        }).resume()
    }

    enum BadgeResult {
        /// The Telegram IDs of everyone who shows the badge.
        case users(Set<Int64>)
        /// The server does not know the token (Start not pressed yet, or the link expired).
        case notLinked
        case failed
    }

    /// Tells the server whether this account shows the AstraGram badge; with it on, gets back which of `check` (the
    /// people in the account's chats and contacts) show it too. The server never hands out the whole list.
    static func badge(accountPeerId: EnginePeer.Id, show: Bool, check: [Int64] = [], completion: @escaping (BadgeResult) -> Void) {
        guard AstraStreakBot.isAvailable, let token = AstraStreakBot.token(accountPeerId: accountPeerId) else {
            completion(.notLinked)
            return
        }
        AstraStreakBot.request(path: "/api/badge", token: token, body: ["show": show, "check": check.map { NSNumber(value: $0) }], statusCompletion: { object, status in
            if status == 401 {
                completion(.notLinked)
                return
            }
            guard let object = object, let users = object["users"] as? [NSNumber] else {
                completion(.failed)
                return
            }
            completion(.users(Set(users.map { $0.int64Value })))
        })
    }

    struct VisualGiftsResult {
        /// The visual gifts of the people asked about, by Telegram ID.
        var users: [Int64: [Int64]]
        /// The account's own list as the server keeps it.
        var mine: [Int64]
    }

    /// Sends the account's visual gifts (`set`, when given) and gets the visual gifts of `check` (the people in the
    /// account's chats and contacts); nil when the server did not answer or the bot is not connected.
    static func visualGifts(accountPeerId: EnginePeer.Id, set: [Int64]?, check: [Int64], completion: @escaping (VisualGiftsResult?) -> Void) {
        guard AstraStreakBot.isAvailable, let token = AstraStreakBot.token(accountPeerId: accountPeerId) else {
            completion(nil)
            return
        }
        // Gift IDs are 64-bit: they go as strings, which JavaScript cannot round.
        var body: [String: Any] = ["check": check.map { NSNumber(value: $0) }]
        if let set {
            body["gifts"] = set.map { "\($0)" }
        }
        func ids(_ value: Any?) -> [Int64] {
            guard let list = value as? [Any] else {
                return []
            }
            return list.compactMap { item -> Int64? in
                if let string = item as? String {
                    return Int64(string)
                }
                return (item as? NSNumber)?.int64Value
            }
        }
        AstraStreakBot.request(path: "/api/gifts", token: token, body: body, completion: { object in
            guard let object = object else {
                completion(nil)
                return
            }
            var users: [Int64: [Int64]] = [:]
            if let map = object["users"] as? [String: Any] {
                for (user, gifts) in map {
                    if let user = Int64(user) {
                        users[user] = ids(gifts)
                    }
                }
            }
            completion(VisualGiftsResult(users: users, mine: ids(object["mine"])))
        })
    }

    struct SyncResult {
        /// The days the other people asked to restore in the bot.
        var restores: [(peerId: EnginePeer.Id, day: Int32)]
        /// The account's streaks on all of its devices, with their start days (nil from a server before the shared list).
        var streaks: [EnginePeer.Id: Int32]?
        /// Streaks a device turned off.
        var stopped: Set<EnginePeer.Id>
        /// The starts and stops this sync handed over.
        var sentEvents: [Int64: Int32]
    }

    private static func userPeerId(_ id: Int64) -> EnginePeer.Id {
        return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id))
    }

    /// Sends the numbers of the streaks and what was turned on or off on this device; returns what the server keeps for
    /// the account, or nil when it did not take them (no connection, or Start not pressed in the bot yet).
    /// `startDays` are the stored ones (a state's `startDay` is cut to the year it counts).
    static func sync(accountPeerId: EnginePeer.Id, states: [EnginePeer.Id: AstraStreakState], startDays: [EnginePeer.Id: Int32], completion: @escaping (SyncResult?) -> Void) {
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
                "day": state.today,
                "startDay": startDays[peerId] ?? state.startDay
            ]
            if let restorableDay = state.restorableDay {
                pair["restorableDay"] = restorableDay
            }
            pairs.append(pair)
        }
        let events = AstraStreakEvents.pending(accountPeerId: accountPeerId)
        var starts: [[String: Any]] = []
        var stops: [Int64] = []
        for (friend, startDay) in events {
            if startDay == AstraStreakEvents.stopped {
                stops.append(friend)
            } else {
                starts.append(["friend": friend, "startDay": startDay])
            }
        }
        let body: [String: Any] = [
            "v": 2,
            "pairs": pairs,
            "starts": starts,
            "stops": stops,
            "need": AstraStreak.messagesPerDay,
            "tz": TimeZone.current.secondsFromGMT()
        ]
        AstraStreakBot.request(path: "/api/sync", token: token, body: body, completion: { object in
            guard let object = object else {
                completion(nil)
                return
            }
            var result = SyncResult(restores: [], streaks: nil, stopped: Set(), sentEvents: events)
            if let restores = object["restores"] as? [[String: Any]] {
                for restore in restores {
                    if let friend = (restore["friend"] as? NSNumber)?.int64Value, let day = (restore["day"] as? NSNumber)?.int32Value {
                        result.restores.append((peerId: AstraStreakBot.userPeerId(friend), day: day))
                    }
                }
            }
            if let streaks = object["streaks"] as? [[String: Any]] {
                var shared: [EnginePeer.Id: Int32] = [:]
                for streak in streaks {
                    if let friend = (streak["friend"] as? NSNumber)?.int64Value, let startDay = (streak["startDay"] as? NSNumber)?.int32Value, friend > 0, startDay > 0 {
                        shared[AstraStreakBot.userPeerId(friend)] = startDay
                    }
                }
                result.streaks = shared
            }
            if let stopped = object["stopped"] as? [NSNumber] {
                result.stopped = Set(stopped.map { AstraStreakBot.userPeerId($0.int64Value) })
            }
            completion(result)
        })
    }
}

/// What was done to the streaks on this device since the streak bot last took it: the friends whose streak was started
/// (with its start day) or turned off. The bot keeps the account's list for all of its devices from these; a device
/// that is not linked to the bot keeps them until it is.
enum AstraStreakEvents {
    static let stopped: Int32 = -1

    private static func key(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.streakEvents.\(accountPeerId.toInt64())"
    }

    static func pending(accountPeerId: EnginePeer.Id) -> [Int64: Int32] {
        guard let stored = UserDefaults.standard.dictionary(forKey: AstraStreakEvents.key(accountPeerId)) as? [String: NSNumber] else {
            return [:]
        }
        var result: [Int64: Int32] = [:]
        for (friend, value) in stored {
            if let friend = Int64(friend) {
                result[friend] = value.int32Value
            }
        }
        return result
    }

    private static func store(_ events: [Int64: Int32], accountPeerId: EnginePeer.Id) {
        let key = AstraStreakEvents.key(accountPeerId)
        if events.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            var stored: [String: NSNumber] = [:]
            for (friend, value) in events {
                stored["\(friend)"] = NSNumber(value: value)
            }
            UserDefaults.standard.set(stored, forKey: key)
        }
    }

    /// A streak started (`startDay`) or turned off (nil) on this device. Only the last thing done to a friend is kept.
    static func note(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, startDay: Int32?) {
        guard peerId.namespace == Namespaces.Peer.CloudUser else {
            return
        }
        var events = AstraStreakEvents.pending(accountPeerId: accountPeerId)
        events[peerId.id._internalGetInt64Value()] = startDay ?? AstraStreakEvents.stopped
        AstraStreakEvents.store(events, accountPeerId: accountPeerId)
    }

    /// Forgets the events a sync handed over, unless something was done to that friend again since.
    static func handedOver(_ sent: [Int64: Int32], accountPeerId: EnginePeer.Id) {
        var events = AstraStreakEvents.pending(accountPeerId: accountPeerId)
        for (friend, value) in sent where events[friend] == value {
            events.removeValue(forKey: friend)
        }
        AstraStreakEvents.store(events, accountPeerId: accountPeerId)
    }
}

extension AstraMessageStore {
    /// Turns a streak on (from `startDay`) or off (nil) by the user's hand: the streak bot hands it to the account's other
    /// devices.
    func astraUserSetStreak(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, startDay: Int32?) {
        self.setStreak(peerId: peerId, startDay: startDay)
        AstraStreakEvents.note(accountPeerId: accountPeerId, peerId: peerId, startDay: startDay)
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
    /// The streaks on this device with their start days, as stored.
    private var localStreaks: [EnginePeer.Id: Int32] = [:]
    private var localStreaksDisposable: Disposable?
    private var lastSync: Double = 0.0
    private var lastSyncedStates: [EnginePeer.Id: AstraStreakState] = [:]
    /// The bot token the numbers were last sent with: a new link (a new token) sends them again at once.
    private var lastSyncedToken: String?
    private let statesPromise = ValuePromise<[EnginePeer.Id: AstraStreakState]>([:], ignoreRepeated: true)
    /// The streaks the bot keeps for the account (on all of its devices), from the last sync; nil until one answered with
    /// the list.
    private let sharedPromise = ValuePromise<Set<EnginePeer.Id>?>(nil, ignoreRepeated: true)
    /// The next sync goes now, not after the usual wait.
    private var forceSync = false
    private var syncCompletions: [(Bool) -> Void] = []

    var statesSignal: Signal<[EnginePeer.Id: AstraStreakState], NoError> {
        return self.statesPromise.get()
    }

    var sharedSignal: Signal<Set<EnginePeer.Id>?, NoError> {
        return self.sharedPromise.get()
    }

    /// Sends the streaks to the bot now; `completion` says whether the bot took them.
    func syncNow(completion: @escaping (Bool) -> Void) {
        self.syncCompletions.append(completion)
        self.forceSync = true
        self.syncIfNeeded()
    }

    private func finishSync(_ success: Bool) {
        let completions = self.syncCompletions
        self.syncCompletions = []
        for completion in completions {
            completion(success)
        }
    }

    private init(context: AccountContext) {
        self.accountPeerId = context.account.peerId
        self.account = context.account
        self.store = AstraMessageStore.forAccount(context.account)
        let account = self.account
        let store = self.store

        let streaks = store.streaks()
        self.localStreaksDisposable = (streaks |> deliverOnMainQueue).start(next: { [weak self] streaks in
            self?.localStreaks = streaks
        })
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
            self.finishSync(false)
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        let accountPeerId = self.accountPeerId
        let changed = self.states != self.lastSyncedStates || token != self.lastSyncedToken || !AstraStreakEvents.pending(accountPeerId: accountPeerId).isEmpty
        if !self.forceSync && !(changed && now - self.lastSync > 60.0) && now - self.lastSync < 15.0 * 60.0 {
            return
        }
        self.forceSync = false
        self.lastSync = now
        let states = self.states
        self.lastSyncedStates = states
        self.lastSyncedToken = token
        let store = self.store
        AstraStreakBot.sync(accountPeerId: accountPeerId, states: states, startDays: self.localStreaks, completion: { [weak self] result in
            Queue.mainQueue().async {
                guard let result = result else {
                    if let self, self.lastSyncedToken == token {
                        self.lastSyncedToken = nil
                    }
                    self?.finishSync(false)
                    return
                }
                AstraStreakEvents.handedOver(result.sentEvents, accountPeerId: accountPeerId)
                self?.merge(result)
                self?.finishSync(true)
                var applied = false
                for restore in result.restores {
                    // Only what the rules allow now: yesterday, while it can still be restored.
                    if let state = states[restore.peerId], state.restorableDay == restore.day, state.restoresLeft > 0 {
                        store.addStreakRestore(peerId: restore.peerId, day: restore.day)
                        applied = true
                    }
                }
                if applied {
                    self?.lastSync = 0.0
                    // Counted again now, not at the next minute tick.
                    self?.refresh()
                }
            }
        })
    }

    /// Takes the account's list from the bot: streaks started on another device come here with the same start day, and
    /// streaks turned off there go off here too. A friend with something done on this device that the bot has not
    /// taken yet is left as it is: that newer change goes out with the next sync.
    private func merge(_ result: AstraStreakBot.SyncResult) {
        guard let shared = result.streaks else {
            return
        }
        self.sharedPromise.set(Set(shared.keys))
        let pending = AstraStreakEvents.pending(accountPeerId: self.accountPeerId)
        func isPending(_ peerId: EnginePeer.Id) -> Bool {
            return pending[peerId.id._internalGetInt64Value()] != nil
        }
        for (peerId, startDay) in shared where !isPending(peerId) && self.localStreaks[peerId] != startDay {
            self.store.setStreakStartDay(peerId: peerId, startDay: startDay)
        }
        for peerId in result.stopped where !isPending(peerId) && self.localStreaks[peerId] != nil && shared[peerId] == nil {
            self.store.setStreak(peerId: peerId, startDay: nil)
        }
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
    let openPet: () -> Void
    let save: () -> Void
    let context: AccountContext

    init(context: AccountContext, start: @escaping () -> Void, stop: @escaping () -> Void, restore: @escaping () -> Void, linkBot: @escaping () -> Void, unlinkBot: @escaping () -> Void, invite: @escaping () -> Void, openPet: @escaping () -> Void, save: @escaping () -> Void) {
        self.context = context
        self.save = save
        self.openPet = openPet
        self.start = start
        self.stop = stop
        self.restore = restore
        self.linkBot = linkBot
        self.unlinkBot = unlinkBot
        self.invite = invite
    }
}

/// What a row of the streak screen does when tapped.
private enum AstraStreakRowAction: Equatable {
    case none
    case start
    case stop
    case restore
    case linkBot
    case unlinkBot
    case invite
    case openPet
    case save
}

/// The streak screen in Telegram's settings style: rows with icons (or the people's avatars), grouped in blocks, with
/// short footers.
private enum AstraStreakEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case row(Int32, Int32, UIImage?, EnginePeer?, String, String, AstraStreakRowAction)
    case button(Int32, Int32, String, ItemListActionKind, AstraStreakRowAction)
    case footer(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .row(_, section, _, _, _, _, _), let .button(_, section, _, _, _), let .footer(_, section, _):
            return ItemListSectionId(section)
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .row(id, _, _, _, _, _, _), let .button(id, _, _, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func ==(lhs: AstraStreakEntry, rhs: AstraStreakEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a1, b1, c1), .header(a2, b2, c2)):
            return a1 == a2 && b1 == b2 && c1 == c2
        case let (.row(a1, b1, i1, p1, c1, d1, e1), .row(a2, b2, i2, p2, c2, d2, e2)):
            return a1 == a2 && b1 == b2 && i1 === i2 && p1 == p2 && c1 == c2 && d1 == d2 && e1 == e2
        case let (.button(a1, b1, c1, d1, e1), .button(a2, b2, c2, d2, e2)):
            return a1 == a2 && b1 == b2 && c1 == c2 && d1 == d2 && e1 == e2
        case let (.footer(a1, b1, c1), .footer(a2, b2, c2)):
            return a1 == a2 && b1 == b2 && c1 == c2
        default:
            return false
        }
    }

    static func <(lhs: AstraStreakEntry, rhs: AstraStreakEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraStreakArguments
        let perform: (AstraStreakRowAction) -> Void = { action in
            switch action {
            case .none:
                break
            case .start:
                arguments.start()
            case .stop:
                arguments.stop()
            case .restore:
                arguments.restore()
            case .linkBot:
                arguments.linkBot()
            case .unlinkBot:
                arguments.unlinkBot()
            case .invite:
                arguments.invite()
            case .openPet:
                arguments.openPet()
            case .save:
                arguments.save()
            }
        }
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .row(_, _, icon, peer, title, label, action):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, context: peer != nil ? arguments.context : nil, iconPeer: peer, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: action == .none ? .none : .arrow, action: action == .none ? nil : {
                perform(action)
            })
        case let .button(_, _, title, kind, action):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: kind, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                perform(action)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Icons of the streak screens.
enum AstraStreakIcons {
    static let flame = AstraGramSettingsIcons.symbol("flame.fill", UIColor(rgb: 0xFF6A00))
    static let restore = AstraGramSettingsIcons.symbol("arrow.counterclockwise", UIColor(rgb: 0x34C759))
    static let pet = AstraGramSettingsIcons.symbol("face.smiling.inverse", UIColor(rgb: 0xFF9F0A))
    static let calendar = AstraGramSettingsIcons.symbol("calendar", UIColor(rgb: 0xFF453A))
    static let me = AstraGramSettingsIcons.symbol("person.fill", UIColor(rgb: 0x0A84FF))
    static let them = AstraGramSettingsIcons.symbol("bubble.left.fill", UIColor(rgb: 0x34C759))
    static let save = AstraGramSettingsIcons.symbol("icloud.and.arrow.up.fill", UIColor(rgb: 0x007AFF))
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
        context: context,
        start: {
            let isRussian = astraIsRussian(context)
            let _ = (peer |> take(1) |> deliverOnMainQueue).start(next: { peer in
                guard let peer = peer, AstraStreakBot.isAvailable, !peer.astraUsesAstraGram else {
                    // Both on AstraGram: each phone counts the streak by itself, no bot is needed.
                    store.astraUserSetStreak(accountPeerId: accountPeerId, peerId: peerId, startDay: AstraStreak.today())
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
                    store.astraUserSetStreak(accountPeerId: accountPeerId, peerId: peerId, startDay: AstraStreak.today())
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
                    store.astraUserSetStreak(accountPeerId: accountPeerId, peerId: peerId, startDay: AstraStreak.today())
                    AstraHaptics.success()
                }))
                alert.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
                top.present(alert, animated: true)
            })
        },
        stop: {
            let isRussian = astraIsRussian(context)
            showAlert(title: isRussian ? "Выключить огонёк?" : "Turn off the streak?", text: isRussian ? "Счёт и восстановления этого огонька пропадут. Начать можно заново, но с нуля." : "The count and restores of this streak are lost. You can start again, from zero.", actionTitle: isRussian ? "Выключить" : "Turn Off", destructive: true, action: {
                store.astraUserSetStreak(accountPeerId: accountPeerId, peerId: peerId, startDay: nil)
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
                AstraStreakManager.forAccount(accountPeerId)?.refresh()
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
            showAlert(title: isRussian ? "Отключить бота?" : "Disconnect the bot?", text: isRussian ? "AstraGram перестанет отправлять боту числа огоньков, а бот удалит то, что о вас хранил. Значок AstraGram работает через бота, поэтому тоже выключится." : "AstraGram stops sending the bot the numbers of your streaks, and the bot deletes what it kept about you. The AstraGram badge works through the bot, so it is turned off too.", actionTitle: isRussian ? "Отключить" : "Disconnect", destructive: true, action: {
                // The badge needs the bot: left on, it would connect the bot again.
                AstraGramSettings.update { $0.astraBadge = false }
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
        },
        openPet: {
            astraTopViewController()?.present(AstraStreakPetController(context: context, peerId: peerId), animated: true)
        },
        save: {
            let isRussian = astraIsRussian(context)
            let syncNow = {
                guard let manager = AstraStreakManager.forAccount(accountPeerId) else {
                    return
                }
                manager.syncNow(completion: { success in
                    toast(success
                        ? (isRussian ? "Огонёк сохранён: он будет на всех ваших устройствах" : "Streak saved: it will be on all your devices")
                        : (isRussian ? "Пока не сохранилось. AstraGram попробует снова через минуту" : "Not saved yet. AstraGram tries again in a minute"))
                })
            }
            if AstraStreakBot.isLinked(accountPeerId: accountPeerId) {
                syncNow()
                return
            }
            showAlert(title: isRussian ? "Сохранить огонёк?" : "Save the streak?", text: isRussian ? "Сейчас огонёк есть только на этом устройстве. Чтобы он был на всех ваших устройствах и не пропал при переустановке, AstraGram подключит бота огоньков @\(AstraStreakBot.username): ему уходят ID собеседников с огоньком, день начала, счёт и сколько сообщений написано сегодня. Тексты сообщений не отправляются." : "The streak is only on this device now. To have it on all your devices and keep it after reinstalling, AstraGram connects the streak bot @\(AstraStreakBot.username): it gets the IDs of people you have a streak with, the start day, the count and how many messages were written today. Message texts are not sent.", actionTitle: isRussian ? "Сохранить" : "Save", action: {
                AstraStreakBot.linkSilently(context: context, completion: { linked in
                    guard linked else {
                        toast(isRussian ? "Не удалось подключить бота огоньков" : "Couldn't connect the streak bot")
                        return
                    }
                    botLinked.set(true)
                    // The bot ties the token to the account once it gets "/start" from it: the sync waits a moment.
                    Queue.mainQueue().after(5.0, {
                        syncNow()
                    })
                })
            })
        }
    )

    let states: Signal<[EnginePeer.Id: AstraStreakState], NoError> = Signal<[EnginePeer.Id: AstraStreakState], NoError>.single([:]) |> then(
        (Signal<Void, NoError>.single(Void()) |> deliverOnMainQueue)
        |> mapToSignal { _ -> Signal<[EnginePeer.Id: AstraStreakState], NoError> in
            return AstraStreakManager.forAccount(accountPeerId)?.statesSignal ?? .single([:])
        }
    )
    let shared: Signal<Set<EnginePeer.Id>?, NoError> = Signal<Set<EnginePeer.Id>?, NoError>.single(nil) |> then(
        (Signal<Void, NoError>.single(Void()) |> deliverOnMainQueue)
        |> mapToSignal { _ -> Signal<Set<EnginePeer.Id>?, NoError> in
            return AstraStreakManager.forAccount(accountPeerId)?.sharedSignal ?? .single(nil)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        store.streaks(),
        states,
        peer,
        botLinked.get(),
        shared
    )
    |> map { presentationData, streaks, states, peer, botLinked, shared -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.astraUsesRussianTexts
        let name = peer?.compactDisplayTitle ?? ""
        let need = AstraStreak.messagesPerDay
        var entries: [AstraStreakEntry] = []
        let isOn = streaks[peerId] != nil
        let state = states[peerId]

        func progress(_ value: Int32) -> String {
            let done = min(Int(value), need)
            if done >= need {
                return isRussian ? "\(need) из \(need) ✓" : "\(need) of \(need) ✓"
            }
            return isRussian ? "\(done) из \(need)" : "\(done) of \(need)"
        }

        if isOn {
            entries.append(.header(1, 0, isRussian ? "ОГОНЁК С \(name.uppercased())" : "STREAK WITH \(name.uppercased())"))
            if let state = state {
                entries.append(.row(2, 0, AstraStreakIcons.flame, nil, isRussian ? "Огонёк" : "Streak", astraDaysText(state.displayCount, isRussian: isRussian), .none))
                entries.append(.row(3, 0, AstraStreakIcons.calendar, nil, isRussian ? "Осталось восстановлений" : "Restores Left", isRussian ? "\(state.restoresLeft) из \(AstraStreak.restoresPerWeek)" : "\(state.restoresLeft) of \(AstraStreak.restoresPerWeek)", .none))

                entries.append(.header(10, 1, isRussian ? "СЕГОДНЯ" : "TODAY"))
                // Icons the size of the other rows' (an avatar row is taller, and one's own avatar is drawn as Saved Messages).
                entries.append(.row(11, 1, AstraStreakIcons.me, nil, isRussian ? "Вы" : "You", progress(Int32(state.todayMine)), .none))
                entries.append(.row(12, 1, AstraStreakIcons.them, nil, name, progress(Int32(state.todayTheirs)), .none))
                let statusText: String
                if state.todayDone {
                    statusText = isRussian ? "Сегодня засчитано — огонёк горит." : "Today counts — the streak is alive."
                } else if state.restorableDay != nil {
                    statusText = isRussian ? "Вчера не набралось по \(need) сообщения. Восстановите вчерашний день, иначе огонёк начнётся заново." : "Yesterday didn't reach \(need) messages each. Restore it, or the streak starts over."
                } else {
                    statusText = isRussian ? "Напишите друг другу хотя бы по \(need) сообщения, чтобы день засчитался." : "Write at least \(need) messages each for today to count."
                }
                entries.append(.footer(19, 1, statusText))

                entries.append(.row(20, 2, AstraStreakIcons.pet, nil, isRussian ? "Серийчик" : "Streak Buddy", "", .openPet))
                if state.restorableDay != nil {
                    if state.restoresLeft > 0 {
                        entries.append(.row(21, 2, AstraStreakIcons.restore, nil, isRussian ? "Восстановить вчера" : "Restore Yesterday", "", .restore))
                    } else {
                        entries.append(.row(21, 2, AstraStreakIcons.restore, nil, isRussian ? "Восстановлений не осталось" : "No Restores Left", "", .none))
                    }
                }
            } else {
                entries.append(.footer(19, 0, isRussian ? "Считаю…" : "Counting…"))
            }

            // Still only on this device: the bot is not connected, the start has not reached it yet, or its list (from
            // the last sync) does not have this streak.
            let startNotSent = AstraStreakEvents.pending(accountPeerId: accountPeerId)[peerId.id._internalGetInt64Value()] != nil
            let missingFromBot = shared.map { !$0.contains(peerId) } ?? false
            if AstraStreakBot.isAvailable && peerId.namespace == Namespaces.Peer.CloudUser && (!botLinked || startNotSent || missingFromBot) {
                entries.append(.row(25, 5, AstraStreakIcons.save, nil, isRussian ? "Сохранить огонёк" : "Save Streak", "", .save))
                entries.append(.footer(29, 5, isRussian ? "Огонёк пока есть только на этом устройстве. Сохраните его, чтобы он был на всех ваших устройствах и не пропал при переустановке." : "This streak is only on this device for now. Save it to have it on all your devices and keep it after reinstalling."))
            }

            if AstraStreakBot.isAvailable, let peer = peer, !peer.astraUsesAstraGram {
                entries.append(.header(30, 3, isRussian ? "БОТ ОГОНЬКОВ" : "STREAK BOT"))
                entries.append(.button(31, 3, isRussian ? "Пригласить \(name) в бота" : "Invite \(name) to the Bot", .generic, .invite))
                if botLinked {
                    entries.append(.button(32, 3, isRussian ? "Отключить бота" : "Disconnect Bot", .destructive, .unlinkBot))
                } else {
                    entries.append(.button(32, 3, isRussian ? "Подключить бота" : "Connect Bot", .generic, .linkBot))
                }
                entries.append(.footer(39, 3, isRussian ? "У \(name) нет AstraGram: счёт, напоминания и восстановление — в боте @\(AstraStreakBot.username). Боту уходят только числа." : "\(name) doesn't use AstraGram: the count, reminders and restores are in the bot @\(AstraStreakBot.username). The bot gets only numbers."))
            }

            entries.append(.button(40, 4, isRussian ? "Выключить огонёк" : "Turn Off Streak", .destructive, .stop))
            entries.append(.footer(49, 4, isRussian ? "Пропущенный день можно восстановить на следующий день — до \(AstraStreak.restoresPerWeek) раз в неделю." : "A missed day can be restored the next day — up to \(AstraStreak.restoresPerWeek) times a week."))
        } else {
            entries.append(.header(1, 0, isRussian ? "ОГОНЁК С \(name.uppercased())" : "STREAK WITH \(name.uppercased())"))
            entries.append(.row(2, 0, AstraStreakIcons.flame, nil, isRussian ? "Начать огонёк" : "Start a Streak", "", .start))
            entries.append(.footer(9, 0, isRussian ? "Пишите друг другу каждый день хотя бы по \(need) сообщения — огонёк будет расти, а Серийчик в чате взрослеть. Работает и с теми, у кого нет AstraGram." : "Write at least \(need) messages each every day — the streak grows and the buddy in the chat grows up. Works with people without AstraGram too."))
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

private final class AstraStreaksListArguments {
    let context: AccountContext
    let open: (EnginePeer.Id) -> Void
    let syncDevices: () -> Void

    init(context: AccountContext, open: @escaping (EnginePeer.Id) -> Void, syncDevices: @escaping () -> Void) {
        self.context = context
        self.open = open
        self.syncDevices = syncDevices
    }
}

private enum AstraStreaksListEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case streak(Int32, Int32, EnginePeer, String)
    case syncDevices(Int32, Int32, String)
    case footer(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .streak(_, section, _, _), let .syncDevices(_, section, _), let .footer(_, section, _):
            return ItemListSectionId(section)
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .streak(id, _, _, _), let .syncDevices(id, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func <(lhs: AstraStreaksListEntry, rhs: AstraStreaksListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraStreaksListArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .streak(_, _, peer, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, context: arguments.context, iconPeer: peer, title: peer.compactDisplayTitle, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.open(peer.id)
            })
        case let .syncDevices(_, _, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.syncDevices()
            })
        case let .footer(_, _, text):
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
    let botLinked = ValuePromise<Bool>(AstraStreakBot.isLinked(accountPeerId: accountPeerId), ignoreRepeated: true)
    let syncDevices: () -> Void = {
        guard let top = astraTopViewController() else {
            return
        }
        let isRussian = astraIsRussian(context)
        let alert = UIAlertController(
            title: isRussian ? "Огоньки на всех устройствах?" : "Streaks on all devices?",
            message: isRussian
                ? "Список огоньков этого аккаунта будет общим на всех устройствах, где он подключён: огонёк, начатый на одном, появится на других. Для этого AstraGram подключит бота огоньков @\(AstraStreakBot.username): ему уходят ID собеседников с огоньком, день начала, счёт и сколько сообщений написано сегодня. Тексты сообщений не отправляются. Подключите так каждое устройство."
                : "This account's streaks will be the same on every device where this is on: a streak started on one shows up on the others. For this AstraGram connects the streak bot @\(AstraStreakBot.username): it gets the IDs of people you have a streak with, the start day, the count and how many messages were written today. Message texts are not sent. Turn this on on each device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: isRussian ? "Подключить" : "Connect", style: .default, handler: { _ in
            AstraStreakBot.linkSilently(context: context, completion: { linked in
                if linked {
                    botLinked.set(true)
                    AstraStreakManager.forAccount(accountPeerId)?.refresh()
                }
            })
        }))
        top.present(alert, animated: true)
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

    let arguments = AstraStreaksListArguments(context: context, open: open, syncDevices: syncDevices)
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, peers, states, botLinked.get())
    |> map { presentationData, peers, states, botLinked -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let isRussian = presentationData.strings.baseLanguageCode.astraUsesRussianTexts
        let sorted = peers.sorted { (states[$0.id]?.displayCount ?? 0) > (states[$1.id]?.displayCount ?? 0) }
        var entries: [AstraStreaksListEntry] = []
        // Streaks to save today first, then the burning ones, then the ones that have only started.
        let atRisk = sorted.filter { states[$0.id]?.restorableDay != nil }
        let burning = sorted.filter { states[$0.id]?.restorableDay == nil && (states[$0.id]?.displayCount ?? 0) > 0 }
        let starting = sorted.filter { states[$0.id]?.restorableDay == nil && (states[$0.id]?.displayCount ?? 0) == 0 }
        var id: Int32 = 0
        func add(_ section: Int32, _ title: String, _ list: [EnginePeer]) {
            guard !list.isEmpty else {
                return
            }
            id += 1
            entries.append(.header(id, section, title))
            for peer in list {
                id += 1
                entries.append(.streak(id, section, peer, astraStreakSummary(states[peer.id], isRussian: isRussian)))
            }
        }
        add(0, isRussian ? "НУЖНО ВОССТАНОВИТЬ" : "NEEDS A RESTORE", atRisk)
        add(1, isRussian ? "ГОРЯТ" : "BURNING", burning)
        add(2, isRussian ? "НАЧАТЫ" : "JUST STARTED", starting)
        id += 1
        if sorted.isEmpty {
            entries.append(.footer(id, 3, isRussian ? "Огоньков пока нет. Откройте профиль собеседника → «Огонёк» → «Начать огонёк»." : "No streaks yet. Open someone's profile → Streak → Start a Streak."))
        } else {
            entries.append(.footer(id, 3, isRussian ? "Огонёк растёт, когда вы оба пишете каждый день хотя бы по \(AstraStreak.messagesPerDay) сообщения. Число видно у имени в списке чатов." : "A streak grows when both of you write at least \(AstraStreak.messagesPerDay) messages every day. The number shows beside the name in the chat list."))
        }
        if AstraStreakBot.isAvailable {
            id += 1
            entries.append(.header(id, 4, isRussian ? "НА ВСЕХ УСТРОЙСТВАХ" : "ON ALL DEVICES"))
            id += 1
            if botLinked {
                entries.append(.footer(id, 4, isRussian ? "Огоньки этого аккаунта общие на всех устройствах, где подключён бот огоньков. Новое устройство получает их в течение нескольких минут." : "This account's streaks are shared by every device where the streak bot is connected. A new device gets them within a few minutes."))
            } else {
                entries.append(.syncDevices(id, 4, isRussian ? "Синхронизировать огоньки" : "Sync Streaks"))
                id += 1
                entries.append(.footer(id, 4, isRussian ? "Огоньки хранятся на устройстве. Чтобы они были на всех ваших устройствах, подключите синхронизацию на каждом из них." : "Streaks are kept on the device. To have them on all your devices, turn on sync on each of them."))
            }
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(isRussian ? "Огоньки" : "Streaks"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}
