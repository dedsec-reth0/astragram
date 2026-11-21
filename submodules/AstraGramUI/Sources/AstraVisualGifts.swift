import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// A visual gift one AstraGram user gave another (`AstraVisualGifts`), as the server keeps it.
public struct AstraReceivedGift: Codable, Equatable {
    /// The server's ID: the recipient takes the gift off with it.
    public var id: Int64
    public var gift: Int64
    /// The giver's Telegram ID.
    public var from: Int64
    public var date: Int32
}

/// AstraGram: visual gifts. In the gift shop a user puts any of Telegram's gifts on their profile, or gives one to
/// someone, without buying it. The gifts are drawn only in AstraGram, with an "AstraGram" ribbon so nobody takes them
/// for bought ones: on the user's own profile at once, and on other AstraGram users' profiles through the streak bot's
/// server, which hands an app the lists of the people in its own chats and contacts only (as with the AstraGram badge).
public enum AstraVisualGifts {
    /// The most gifts one profile shows (the server keeps as many).
    public static let maxGifts = 100

    /// One visual gift on a profile: put there by its owner (`received` nil) or given by someone.
    public struct Entry: Equatable {
        public var gift: Int64
        public var date: Int32
        public var received: AstraReceivedGift?
    }

    private static let refreshInterval: Double = 30.0 * 60.0
    private static var timers: [EnginePeer.Id: SwiftSignalKit.Timer] = [:]
    private static let changedPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    private static var revision = 0

    private static func mineKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.mine.\(accountPeerId.toInt64())"
    }

    /// When each of the account's own gifts was put on (shown on the gift's screen).
    private static func mineDatesKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.mineDates.\(accountPeerId.toInt64())"
    }

    /// Set while the account's own list has changed and the server has not taken it yet.
    private static func unsentKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.unsent.\(accountPeerId.toInt64())"
    }

    /// Set once the server has taken (or handed over) this account's list. A list from before that (version 1.0.26 kept
    /// lists the server never got) counts as unsent.
    private static func syncedKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.synced.\(accountPeerId.toInt64())"
    }

    private static func isUnsent(_ accountPeerId: EnginePeer.Id) -> Bool {
        if UserDefaults.standard.bool(forKey: AstraVisualGifts.unsentKey(accountPeerId)) {
            return true
        }
        return !UserDefaults.standard.bool(forKey: AstraVisualGifts.syncedKey(accountPeerId)) && !AstraVisualGifts.mine(accountPeerId: accountPeerId).isEmpty
    }

    private static func othersKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.others.\(accountPeerId.toInt64())"
    }

    private static func othersDateKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.othersDate.\(accountPeerId.toInt64())"
    }

    private static func receivedKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.received.\(accountPeerId.toInt64())"
    }

    private static func mineReceivedKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.mineReceived.\(accountPeerId.toInt64())"
    }

    /// The account's own gifts, in the order they were put on.
    public static func mine(accountPeerId: EnginePeer.Id) -> [Int64] {
        let stored = UserDefaults.standard.stringArray(forKey: AstraVisualGifts.mineKey(accountPeerId)) ?? []
        return stored.compactMap { Int64($0) }
    }

    private static func mineDates(accountPeerId: EnginePeer.Id) -> [String: Int32] {
        return (UserDefaults.standard.dictionary(forKey: AstraVisualGifts.mineDatesKey(accountPeerId)) as? [String: NSNumber] ?? [:]).mapValues { $0.int32Value }
    }

    /// The other people's own gifts this account last got from the server, by their Telegram ID.
    private static func others(accountPeerId: EnginePeer.Id) -> [Int64: [Int64]] {
        guard let stored = UserDefaults.standard.dictionary(forKey: AstraVisualGifts.othersKey(accountPeerId)) as? [String: [String]] else {
            return [:]
        }
        var result: [Int64: [Int64]] = [:]
        for (user, gifts) in stored {
            if let user = Int64(user) {
                result[user] = gifts.compactMap { Int64($0) }
            }
        }
        return result
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// The gifts others gave the people this account knows, by their Telegram ID.
    private static func received(accountPeerId: EnginePeer.Id) -> [Int64: [AstraReceivedGift]] {
        let stored = AstraVisualGifts.decode([String: [AstraReceivedGift]].self, key: AstraVisualGifts.receivedKey(accountPeerId)) ?? [:]
        var result: [Int64: [AstraReceivedGift]] = [:]
        for (user, gifts) in stored {
            if let user = Int64(user) {
                result[user] = gifts
            }
        }
        return result
    }

    /// The gifts others gave this account.
    private static func mineReceived(accountPeerId: EnginePeer.Id) -> [AstraReceivedGift] {
        return AstraVisualGifts.decode([AstraReceivedGift].self, key: AstraVisualGifts.mineReceivedKey(accountPeerId)) ?? []
    }

    private static func changed() {
        AstraVisualGifts.revision += 1
        AstraVisualGifts.changedPromise.set(AstraVisualGifts.revision)
    }

    /// The visual gifts of `peerId` as this account sees them, newest given first, then the ones put on by the owner.
    public static func entries(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> [Entry] {
        guard peerId.namespace == Namespaces.Peer.CloudUser else {
            return []
        }
        let own: [Int64]
        let given: [AstraReceivedGift]
        var dates: [String: Int32] = [:]
        if peerId == accountPeerId {
            own = AstraVisualGifts.mine(accountPeerId: accountPeerId)
            given = AstraVisualGifts.mineReceived(accountPeerId: accountPeerId)
            dates = AstraVisualGifts.mineDates(accountPeerId: accountPeerId)
        } else {
            let user = peerId.id._internalGetInt64Value()
            own = AstraVisualGifts.others(accountPeerId: accountPeerId)[user] ?? []
            given = AstraVisualGifts.received(accountPeerId: accountPeerId)[user] ?? []
            let date = (UserDefaults.standard.dictionary(forKey: AstraVisualGifts.othersDateKey(accountPeerId))?["\(user)"] as? NSNumber)?.int32Value ?? 0
            for id in own {
                dates["\(id)"] = date
            }
        }
        // A gift with no known date shows today's rather than 1970's (the start of the day, so it stays the same and the
        // item still matches its entry).
        let fallback = Int32(Date().timeIntervalSince1970) / 86400 * 86400
        return given.map { Entry(gift: $0.gift, date: $0.date, received: $0) } + own.map { Entry(gift: $0, date: (dates["\($0)"] ?? 0) > 0 ? dates["\($0)"]! : fallback, received: nil) }
    }

    public static func hasGifts(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> Bool {
        return !AstraVisualGifts.entries(accountPeerId: accountPeerId, peerId: peerId).isEmpty
    }

    public static func entriesSignal(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> Signal<[Entry], NoError> {
        return AstraVisualGifts.changedPromise.get()
        |> map { _ -> [Entry] in
            return AstraVisualGifts.entries(accountPeerId: accountPeerId, peerId: peerId)
        }
        |> distinctUntilChanged
    }

    /// Puts `ids` on the account's profile (replacing what was there) and sends them to the server.
    static func setMine(context: AccountContext, ids: [Int64], completion: @escaping (Bool) -> Void) {
        let accountPeerId = context.account.peerId
        var seen = Set<Int64>()
        let unique = Array(ids.filter { seen.insert($0).inserted }.prefix(AstraVisualGifts.maxGifts))
        var dates = AstraVisualGifts.mineDates(accountPeerId: accountPeerId)
        let now = Int32(Date().timeIntervalSince1970)
        for id in unique where dates["\(id)"] == nil {
            dates["\(id)"] = now
        }
        dates = dates.filter { key, _ in unique.contains(where: { "\($0)" == key }) }
        UserDefaults.standard.set(dates.mapValues { NSNumber(value: $0) }, forKey: AstraVisualGifts.mineDatesKey(accountPeerId))
        UserDefaults.standard.set(unique.map { "\($0)" }, forKey: AstraVisualGifts.mineKey(accountPeerId))
        UserDefaults.standard.set(true, forKey: AstraVisualGifts.unsentKey(accountPeerId))
        AstraVisualGifts.changed()
        AstraVisualGifts.refresh(context: context, sendMine: true, completion: { sent in
            completion(sent)
            if !sent {
                // Right after connecting, the server may not know the token yet: one more try soon, then every half hour.
                Queue.mainQueue().after(30.0, {
                    AstraVisualGifts.refresh(context: context, sendMine: false, completion: { _ in })
                })
            }
        })
    }

    /// Takes one of the account's own gifts off its profile.
    static func removeMine(context: AccountContext, gift: Int64) {
        let ids = AstraVisualGifts.mine(accountPeerId: context.account.peerId).filter { $0 != gift }
        AstraVisualGifts.setMine(context: context, ids: ids, completion: { _ in })
    }

    enum GiveResult {
        case given
        /// Today's gifts are used up.
        case limit
        case failed
    }

    /// Gives `gift` to `to` for free: it shows on their profile in AstraGram, from this account.
    static func give(context: AccountContext, to: EnginePeer.Id, gift: Int64, completion: @escaping (GiveResult) -> Void) {
        let accountPeerId = context.account.peerId
        AstraStreakBot.visualGifts(accountPeerId: accountPeerId, set: nil, send: (to: to.id._internalGetInt64Value(), gift: gift), check: [to.id._internalGetInt64Value()], completion: { result in
            Queue.mainQueue().async {
                guard let result = result else {
                    completion(.failed)
                    return
                }
                if result.status == 429 {
                    completion(.limit)
                    return
                }
                guard result.sent != nil else {
                    completion(.failed)
                    return
                }
                // The recipient's profile shows it at once.
                var received = AstraVisualGifts.received(accountPeerId: accountPeerId)
                for (user, gifts) in result.received {
                    received[user] = gifts
                }
                AstraVisualGifts.storeReceived(received, accountPeerId: accountPeerId)
                completion(.given)
            }
        })
    }

    /// Takes a gift someone gave this account off its profile.
    static func hideReceived(context: AccountContext, id: Int64, completion: @escaping (Bool) -> Void) {
        let accountPeerId = context.account.peerId
        let current = AstraVisualGifts.mineReceived(accountPeerId: accountPeerId)
        AstraVisualGifts.encode(current.filter { $0.id != id }, key: AstraVisualGifts.mineReceivedKey(accountPeerId))
        AstraVisualGifts.changed()
        AstraStreakBot.visualGifts(accountPeerId: accountPeerId, set: nil, hide: [id], check: [], completion: { result in
            Queue.mainQueue().async {
                if let mineReceived = result?.mineReceived {
                    AstraVisualGifts.encode(mineReceived, key: AstraVisualGifts.mineReceivedKey(accountPeerId))
                    AstraVisualGifts.changed()
                }
                completion(result != nil)
            }
        })
    }

    private static func storeReceived(_ received: [Int64: [AstraReceivedGift]], accountPeerId: EnginePeer.Id) {
        var stored: [String: [AstraReceivedGift]] = [:]
        for (user, gifts) in received where !gifts.isEmpty {
            stored["\(user)"] = gifts
        }
        if AstraVisualGifts.received(accountPeerId: accountPeerId) != received.filter({ !$0.value.isEmpty }) {
            AstraVisualGifts.encode(stored, key: AstraVisualGifts.receivedKey(accountPeerId))
            AstraVisualGifts.changed()
        }
    }

    private static var lastRefresh: [EnginePeer.Id: Double] = [:]

    /// Asks again when the last answer is more than a minute old: on an account switch, and when a profile is opened.
    static func refreshIfStale(context: AccountContext) {
        let peerId = context.account.peerId
        let now = CFAbsoluteTimeGetCurrent()
        if let last = AstraVisualGifts.lastRefresh[peerId], now - last < 60.0 {
            return
        }
        AstraVisualGifts.lastRefresh[peerId] = now
        AstraVisualGifts.refresh(context: context, sendMine: false, completion: { _ in })
    }

    /// Keeps the other people's gifts up to date while the app runs: at launch and every half hour, when the streak bot
    /// is connected (the shop connects it; it is never connected only for this).
    static func start(context: AccountContext) {
        let peerId = context.account.peerId
        if AstraVisualGifts.timers[peerId] != nil {
            AstraVisualGifts.refreshIfStale(context: context)
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: AstraVisualGifts.refreshInterval, repeat: true, completion: {
            AstraVisualGifts.refresh(context: context, sendMine: false, completion: { _ in })
        }, queue: Queue.mainQueue())
        AstraVisualGifts.timers[peerId] = timer
        timer.start()
        Queue.mainQueue().after(5.0, {
            AstraVisualGifts.refreshIfStale(context: context)
        })
    }

    /// Asks the server for the gifts of the people in the chat list and contacts (and sends the account's own list
    /// with `sendMine`); `completion` says whether the server answered.
    /// A list the server has not taken yet (the bot was not connected, or the server not reached) goes with the next
    /// refresh; until then the server's copy of the account's list is not taken over it.
    static func refresh(context: AccountContext, sendMine: Bool, completion: @escaping (Bool) -> Void) {
        let accountPeerId = context.account.peerId
        let unsent = AstraVisualGifts.isUnsent(accountPeerId)
        let send = (sendMine || unsent) && AstraStreakBot.isLinked(accountPeerId: accountPeerId)
        // Other people's gifts can be asked with another account's connection on this device.
        guard AstraStreakBot.isAvailable, send || AstraStreakBot.tokenForLookup(accountPeerId: accountPeerId) != nil else {
            completion(false)
            return
        }
        let _ = (AstraBadgeSync.candidates(context: context) |> deliverOnMainQueue).start(next: { check in
            let mine: [Int64]? = send ? AstraVisualGifts.mine(accountPeerId: accountPeerId) : nil
            AstraStreakBot.visualGifts(accountPeerId: accountPeerId, set: mine, check: check, completion: { result in
                Queue.mainQueue().async {
                    guard let result = result, result.status == 200 else {
                        completion(false)
                        return
                    }
                    var stored: [String: [String]] = [:]
                    for (user, gifts) in result.users where !gifts.isEmpty {
                        stored["\(user)"] = gifts.map { "\($0)" }
                    }
                    let previous = AstraVisualGifts.others(accountPeerId: accountPeerId)
                    UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: result.usersDate.map { ("\($0.key)", NSNumber(value: $0.value)) }), forKey: AstraVisualGifts.othersDateKey(accountPeerId))
                    if previous != result.users.filter({ !$0.value.isEmpty }) {
                        UserDefaults.standard.set(stored, forKey: AstraVisualGifts.othersKey(accountPeerId))
                        AstraVisualGifts.changed()
                    }
                    AstraVisualGifts.storeReceived(result.received, accountPeerId: accountPeerId)
                    if let mineReceived = result.mineReceived, mineReceived != AstraVisualGifts.mineReceived(accountPeerId: accountPeerId) {
                        AstraVisualGifts.encode(mineReceived, key: AstraVisualGifts.mineReceivedKey(accountPeerId))
                        AstraVisualGifts.changed()
                    }
                    if send {
                        UserDefaults.standard.removeObject(forKey: AstraVisualGifts.unsentKey(accountPeerId))
                        UserDefaults.standard.set(true, forKey: AstraVisualGifts.syncedKey(accountPeerId))
                    } else if let serverMine = result.mine, !AstraVisualGifts.isUnsent(accountPeerId) {
                        UserDefaults.standard.set(true, forKey: AstraVisualGifts.syncedKey(accountPeerId))
                        if serverMine != AstraVisualGifts.mine(accountPeerId: accountPeerId) {
                            // Another device of this account changed the account's own list.
                            UserDefaults.standard.set(serverMine.map { "\($0)" }, forKey: AstraVisualGifts.mineKey(accountPeerId))
                            AstraVisualGifts.changed()
                        }
                    }
                    // Sent only when this account's own connection took it (a lookup with another account's token
                    // does not send it).
                    completion(!sendMine || send)
                }
            })
        })
    }
}

public extension ProfileGiftsContext.State.StarGift {
    /// A gift from AstraGram's gift shop: not bought, drawn only in AstraGram.
    var astraIsVisual: Bool {
        return self.reference == nil && self.collectionIds == [AstraVisualGifts.marker]
    }
}

extension AstraVisualGifts {
    /// Kept in a synthetic item's collections, which no real gift has (Telegram's collection IDs are positive).
    static let marker: Int32 = Int32.min + 0x4153

    static func item(gift: StarGift.Gift, entry: Entry, fromPeer: EnginePeer?) -> ProfileGiftsContext.State.StarGift {
        return ProfileGiftsContext.State.StarGift(
            gift: .generic(gift),
            reference: nil,
            fromPeer: fromPeer,
            date: entry.date,
            text: nil,
            entities: nil,
            nameHidden: entry.received == nil,
            savedToProfile: true,
            pinnedToTop: false,
            convertStars: nil,
            canUpgrade: false,
            canExportDate: nil,
            upgradeStars: nil,
            transferStars: nil,
            canTransferDate: nil,
            canResaleDate: nil,
            collectionIds: [AstraVisualGifts.marker],
            prepaidUpgradeHash: nil,
            upgradeSeparate: false,
            dropOriginalDetailsStars: nil,
            number: nil,
            isRefunded: false,
            canCraftAt: nil
        )
    }

    /// The entry a synthetic item of `peerId`'s profile was made from.
    public static func entry(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, item: ProfileGiftsContext.State.StarGift) -> Entry? {
        guard item.astraIsVisual, case let .generic(gift) = item.gift else {
            return nil
        }
        return AstraVisualGifts.entries(accountPeerId: accountPeerId, peerId: peerId).first(where: { entry in
            // A giver this device does not know has no peer: such an item matches by gift and date.
            entry.gift == gift.id && entry.date == item.date && (item.fromPeer == nil ? (entry.received == nil) == item.nameHidden : entry.received?.from == item.fromPeer?.id.id._internalGetInt64Value())
        })
    }
}

/// A profile's gifts with its visual gifts after the pinned ones and before the rest (in the "All" view only).
public func astraVisualGiftsState(context: AccountContext, peerId: EnginePeer.Id, state: Signal<ProfileGiftsContext.State, NoError>) -> Signal<ProfileGiftsContext.State, NoError> {
    let catalog = context.engine.payments.cachedStarGifts()
    |> map { gifts -> [Int64: StarGift.Gift] in
        var result: [Int64: StarGift.Gift] = [:]
        for gift in gifts ?? [] {
            if case let .generic(gift) = gift {
                result[gift.id] = gift
            }
        }
        return result
    }
    if peerId != context.account.peerId {
        Queue.mainQueue().async {
            AstraVisualGifts.refreshIfStale(context: context)
        }
    }
    // The givers, when this device knows them.
    let entries = AstraVisualGifts.entriesSignal(accountPeerId: context.account.peerId, peerId: peerId)
    |> mapToSignal { entries -> Signal<([AstraVisualGifts.Entry], [EnginePeer.Id: EnginePeer]), NoError> in
        let givers = Set(entries.compactMap { $0.received.map { EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value($0.from)) } })
        if givers.isEmpty {
            return .single((entries, [:]))
        }
        return context.engine.data.get(EngineDataMap(givers.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> ([AstraVisualGifts.Entry], [EnginePeer.Id: EnginePeer]) in
            var result: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in peers {
                if let peer {
                    result[id] = peer
                }
            }
            return (entries, result)
        }
    }
    return combineLatest(state, entries, catalog)
    |> map { state, entriesAndPeers, catalog -> ProfileGiftsContext.State in
        let (entries, peers) = entriesAndPeers
        let items = entries.compactMap { entry -> ProfileGiftsContext.State.StarGift? in
            guard let gift = catalog[entry.gift] else {
                return nil
            }
            let fromPeer = entry.received.flatMap { peers[EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value($0.from))] }
            return AstraVisualGifts.item(gift: gift, entry: entry, fromPeer: fromPeer)
        }
        if items.isEmpty {
            return state
        }
        // The owner's pinned gifts keep their place at the top.
        func inserted(_ list: [ProfileGiftsContext.State.StarGift]) -> [ProfileGiftsContext.State.StarGift] {
            let pinned = list.prefix(while: { $0.pinnedToTop })
            return Array(pinned) + items + list.dropFirst(pinned.count)
        }
        var state = state
        state.gifts = inserted(state.gifts)
        if state.filter == .All {
            state.filteredGifts = inserted(state.filteredGifts)
        }
        state.count = (state.count ?? 0) + Int32(items.count)
        return state
    }
}
