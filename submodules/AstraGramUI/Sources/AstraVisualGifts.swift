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
    /// The giver's Telegram ID (0: an anonymous giver, for anyone but the recipient).
    public var from: Int64
    public var date: Int32
    /// What the giver wrote with the gift.
    public var text: String? = nil
    /// The giver's name is kept from everyone but the recipient.
    public var anonymous: Bool? = nil
    /// What the recipient set on it.
    public var meta: AstraGiftMeta? = nil
}

/// The look a visual gift was upgraded to, as Telegram's unique gifts have: the names of a model, a pattern and a
/// backdrop from Telegram's list for the gift, and AstraGram's own number for it.
public struct AstraUniqueLook: Codable, Equatable {
    public var number: Int32
    public var model: String
    public var pattern: String
    public var backdrop: String
}

/// What a visual gift's owner set on it, as on Telegram's own gifts.
public struct AstraGiftMeta: Codable, Equatable {
    /// When it was pinned to the top of the profile (pinned gifts go in that order); nil: not pinned.
    public var pinnedAt: Int32?
    /// Shown to its owner only.
    public var hidden: Bool?
    public var unique: AstraUniqueLook?

    public var isPinned: Bool {
        return (self.pinnedAt ?? 0) > 0
    }

    public var isHidden: Bool {
        return self.hidden == true
    }
}

/// The visual gift someone wears as their status.
public struct AstraWornGift: Codable, Equatable {
    public var ref: String
    public var gift: Int64
    public var unique: AstraUniqueLook?
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
        public var meta: AstraGiftMeta = AstraGiftMeta()

        /// How the server names this gift on its owner's profile.
        public var ref: String {
            if let received = self.received {
                return "r\(received.id)"
            }
            return "o\(self.gift)"
        }
    }

    /// The most gifts pinned to the top of a profile (as on Telegram).
    public static let maxPinned = 6

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

    private static func mineMetaKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.mineMeta.\(accountPeerId.toInt64())"
    }

    private static func othersMetaKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.othersMeta.\(accountPeerId.toInt64())"
    }

    private static func wornKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.worn.\(accountPeerId.toInt64())"
    }

    /// What the account set on its own gifts, by gift ID.
    private static func mineMeta(accountPeerId: EnginePeer.Id) -> [String: AstraGiftMeta] {
        return AstraVisualGifts.decode([String: AstraGiftMeta].self, key: AstraVisualGifts.mineMetaKey(accountPeerId)) ?? [:]
    }

    /// What other people set on their own gifts, by Telegram ID and gift ID.
    private static func othersMeta(accountPeerId: EnginePeer.Id) -> [String: [String: AstraGiftMeta]] {
        return AstraVisualGifts.decode([String: [String: AstraGiftMeta]].self, key: AstraVisualGifts.othersMetaKey(accountPeerId)) ?? [:]
    }

    /// The gifts worn as a status, by Telegram ID.
    public static func worn(accountPeerId: EnginePeer.Id) -> [Int64: AstraWornGift] {
        let stored = AstraVisualGifts.decode([String: AstraWornGift].self, key: AstraVisualGifts.wornKey(accountPeerId)) ?? [:]
        var result: [Int64: AstraWornGift] = [:]
        for (user, gift) in stored {
            if let user = Int64(user) {
                result[user] = gift
            }
        }
        return result
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
        let ownMeta: [String: AstraGiftMeta]
        if peerId == accountPeerId {
            own = AstraVisualGifts.mine(accountPeerId: accountPeerId)
            given = AstraVisualGifts.mineReceived(accountPeerId: accountPeerId)
            dates = AstraVisualGifts.mineDates(accountPeerId: accountPeerId)
            ownMeta = AstraVisualGifts.mineMeta(accountPeerId: accountPeerId)
        } else {
            let user = peerId.id._internalGetInt64Value()
            own = AstraVisualGifts.others(accountPeerId: accountPeerId)[user] ?? []
            given = AstraVisualGifts.received(accountPeerId: accountPeerId)[user] ?? []
            let date = (UserDefaults.standard.dictionary(forKey: AstraVisualGifts.othersDateKey(accountPeerId))?["\(user)"] as? NSNumber)?.int32Value ?? 0
            for id in own {
                dates["\(id)"] = date
            }
            ownMeta = AstraVisualGifts.othersMeta(accountPeerId: accountPeerId)["\(user)"] ?? [:]
        }
        // A gift with no known date shows today's rather than 1970's (the start of the day, so it stays the same and the
        // item still matches its entry).
        let fallback = Int32(Date().timeIntervalSince1970) / 86400 * 86400
        return given.map { Entry(gift: $0.gift, date: $0.date, received: $0, meta: $0.meta ?? AstraGiftMeta()) } + own.map { Entry(gift: $0, date: (dates["\($0)"] ?? 0) > 0 ? dates["\($0)"]! : fallback, received: nil, meta: ownMeta["\($0)"] ?? AstraGiftMeta()) }
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
    static func give(context: AccountContext, to: EnginePeer.Id, gift: Int64, text caption: String = "", anonymous: Bool = false, completion: @escaping (GiveResult) -> Void) {
        let accountPeerId = context.account.peerId
        var change = AstraStreakBot.VisualGiftsChange()
        change.send = (to: to.id._internalGetInt64Value(), gift: gift, text: caption, anonymous: anonymous)
        AstraStreakBot.visualGifts(accountPeerId: accountPeerId, change: change, check: [to.id._internalGetInt64Value()], completion: { result in
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
                // A message in the chat, as Telegram sends for a real gift.
                AstraVisualGifts.sendGiftMessage(context: context, to: to, gift: gift, text: caption)
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

    /// Stores what an answer says about the account's own gifts and about the gifts worn as a status.
    private static func storeOwn(_ result: AstraStreakBot.VisualGiftsResult, context: AccountContext) {
        let accountPeerId = context.account.peerId
        if let mineReceived = result.mineReceived, mineReceived != AstraVisualGifts.mineReceived(accountPeerId: accountPeerId) {
            AstraVisualGifts.encode(mineReceived, key: AstraVisualGifts.mineReceivedKey(accountPeerId))
            AstraVisualGifts.changed()
        }
        if let mineMeta = result.mineMeta {
            let stored = Dictionary(uniqueKeysWithValues: mineMeta.map { ("\($0.key)", $0.value) })
            if stored != AstraVisualGifts.mineMeta(accountPeerId: accountPeerId) {
                AstraVisualGifts.encode(stored, key: AstraVisualGifts.mineMetaKey(accountPeerId))
                AstraVisualGifts.changed()
            }
        }
        if let worn = result.worn {
            let stored = Dictionary(uniqueKeysWithValues: worn.map { ("\($0.key)", $0.value) })
            if worn != AstraVisualGifts.worn(accountPeerId: accountPeerId) {
                AstraVisualGifts.encode(stored, key: AstraVisualGifts.wornKey(accountPeerId))
                AstraVisualGifts.changed()
            }
            AstraVisualGifts.applyWorn(context: context)
        }
        if let premiumLooks = result.premiumLooks {
            let _ = AstraPremiumLooks.update(premiumLooks, account: context.account).start()
        }
    }

    enum ChangeResult {
        case done
        /// Today's gifts are used up.
        case limit
        /// Six gifts are pinned already.
        case pinLimit
        case failed
    }

    /// Sends one change of the account's own gifts and stores the answer.
    private static func change(context: AccountContext, _ change: AstraStreakBot.VisualGiftsChange, completion: @escaping (ChangeResult, AstraStreakBot.VisualGiftsResult?) -> Void) {
        AstraStreakBot.visualGifts(accountPeerId: context.account.peerId, change: change, check: [], completion: { result in
            Queue.mainQueue().async {
                guard let result else {
                    completion(.failed, nil)
                    return
                }
                switch result.status {
                case 200:
                    AstraVisualGifts.storeOwn(result, context: context)
                    completion(.done, result)
                case 429:
                    completion(.limit, nil)
                case 409:
                    completion(.pinLimit, nil)
                default:
                    completion(.failed, nil)
                }
            }
        })
    }

    /// Changes what is set on one of the account's gifts at once on this device, then on the server.
    private static func updateMetaLocally(accountPeerId: EnginePeer.Id, entry: Entry, _ f: (inout AstraGiftMeta) -> Void) {
        if let received = entry.received {
            var list = AstraVisualGifts.mineReceived(accountPeerId: accountPeerId)
            if let index = list.firstIndex(where: { $0.id == received.id }) {
                var meta = list[index].meta ?? AstraGiftMeta()
                f(&meta)
                list[index].meta = meta
                AstraVisualGifts.encode(list, key: AstraVisualGifts.mineReceivedKey(accountPeerId))
            }
        } else {
            var all = AstraVisualGifts.mineMeta(accountPeerId: accountPeerId)
            var meta = all["\(entry.gift)"] ?? AstraGiftMeta()
            f(&meta)
            all["\(entry.gift)"] = meta
            AstraVisualGifts.encode(all, key: AstraVisualGifts.mineMetaKey(accountPeerId))
        }
        AstraVisualGifts.changed()
    }

    /// Pins a gift to the top of the account's profile, or unpins it.
    static func setPinned(context: AccountContext, entry: Entry, pinned: Bool, completion: @escaping (ChangeResult) -> Void) {
        let pinnedCount = AstraVisualGifts.entries(accountPeerId: context.account.peerId, peerId: context.account.peerId).filter { $0.meta.isPinned && $0.ref != entry.ref }.count
        if pinned && pinnedCount >= AstraVisualGifts.maxPinned {
            completion(.pinLimit)
            return
        }
        AstraVisualGifts.updateMetaLocally(accountPeerId: context.account.peerId, entry: entry, { meta in
            meta.pinnedAt = pinned ? Int32(Date().timeIntervalSince1970) : nil
        })
        var change = AstraStreakBot.VisualGiftsChange()
        change.meta = [(ref: entry.ref, pinned: pinned, hidden: nil)]
        AstraVisualGifts.change(context: context, change, completion: { result, _ in completion(result) })
    }

    /// Hides a gift from everyone but the account (it stays on the profile for the account), or shows it again.
    static func setHidden(context: AccountContext, entry: Entry, hidden: Bool, completion: @escaping (ChangeResult) -> Void) {
        AstraVisualGifts.updateMetaLocally(accountPeerId: context.account.peerId, entry: entry, { meta in
            meta.hidden = hidden ? true : nil
            if hidden {
                meta.pinnedAt = nil
            }
        })
        var change = AstraStreakBot.VisualGiftsChange()
        change.meta = [(ref: entry.ref, pinned: nil, hidden: hidden)]
        AstraVisualGifts.change(context: context, change, completion: { result, _ in completion(result) })
    }

    enum UpgradeResult {
        case upgraded(AstraUniqueLook)
        /// Telegram has no unique versions of this gift.
        case notUpgradable
        case failed
    }

    /// Upgrades a gift to a unique one: a model, a pattern and a backdrop picked from Telegram's list for the gift, each
    /// as often as on Telegram (by its rarity); the server numbers it.
    /// The admin's own pick of a unique look (model, pattern, backdrop, number), applied even to an upgraded gift.
    static func upgradeChosen(context: AccountContext, entry: Entry, model: String, pattern: String, backdrop: String, number: Int32?, completion: @escaping (UpgradeResult) -> Void) {
        var change = AstraStreakBot.VisualGiftsChange()
        change.upgrade = (ref: entry.ref, model: model, pattern: pattern, backdrop: backdrop)
        change.upgradeNumber = number
        AstraVisualGifts.change(context: context, change, completion: { result, answer in
            if case .done = result, let look = answer?.upgraded {
                AstraVisualGifts.updateMetaLocally(accountPeerId: context.account.peerId, entry: entry, { meta in
                    meta.unique = look
                })
                completion(.upgraded(look))
            } else {
                completion(.failed)
            }
        })
    }

    /// The account of AstraGram's admin (the streak bot's owner): may pick every part of an upgrade.
    public static func isAdmin(_ accountPeerId: EnginePeer.Id) -> Bool {
        return accountPeerId.namespace == Namespaces.Peer.CloudUser && accountPeerId.id._internalGetInt64Value() == 887825713
    }

    static func upgrade(context: AccountContext, entry: Entry, completion: @escaping (UpgradeResult) -> Void) {
        let _ = (context.engine.payments.getStarGiftUpgradeAttributes(giftId: entry.gift)
        |> take(1)
        |> deliverOnMainQueue).start(next: { attributes in
            let attributes = attributes ?? []
            // How often Telegram gives each: its chance in thousandths, or a share for the named rarities.
            func weight(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> Int32 {
                switch rarity {
                case let .permille(value):
                    return max(1, value)
                case .uncommon:
                    return 50
                case .rare:
                    return 20
                case .epic:
                    return 8
                case .legendary:
                    return 3
                }
            }
            func pick(_ type: StarGift.UniqueGift.Attribute.AttributeType) -> String? {
                var items: [(name: String, weight: Int32)] = []
                for attribute in attributes where attribute.attributeType == type {
                    switch attribute {
                    case let .model(name, _, rarity, crafted):
                        // A crafted model comes only from crafting, never from an upgrade.
                        if !crafted {
                            items.append((name, weight(rarity)))
                        }
                    case let .pattern(name, _, rarity):
                        items.append((name, weight(rarity)))
                    case let .backdrop(name, _, _, _, _, _, rarity):
                        items.append((name, weight(rarity)))
                    case .originalInfo:
                        break
                    }
                }
                let total = items.reduce(0) { $0 + Int($1.weight) }
                guard total > 0 else {
                    return nil
                }
                var roll = Int.random(in: 0 ..< total)
                for item in items {
                    roll -= Int(item.weight)
                    if roll < 0 {
                        return item.name
                    }
                }
                return items.last?.name
            }
            guard let model = pick(.model), let pattern = pick(.pattern), let backdrop = pick(.backdrop) else {
                completion(.notUpgradable)
                return
            }
            var change = AstraStreakBot.VisualGiftsChange()
            change.upgrade = (ref: entry.ref, model: model, pattern: pattern, backdrop: backdrop)
            AstraVisualGifts.change(context: context, change, completion: { result, answer in
                if case .done = result, let look = answer?.upgraded {
                    AstraVisualGifts.updateMetaLocally(accountPeerId: context.account.peerId, entry: entry, { meta in
                        meta.unique = look
                    })
                    completion(.upgraded(look))
                } else {
                    completion(.failed)
                }
            })
        })
    }

    /// Passes a gift on to `to`: it leaves the account's profile, with its upgrade, and a message goes to the chat.
    static func transfer(context: AccountContext, entry: Entry, to: EnginePeer.Id, text: String, anonymous: Bool, completion: @escaping (ChangeResult) -> Void) {
        let accountPeerId = context.account.peerId
        var change = AstraStreakBot.VisualGiftsChange()
        change.transfer = (ref: entry.ref, to: to.id._internalGetInt64Value(), text: text, anonymous: anonymous)
        AstraVisualGifts.change(context: context, change, completion: { result, answer in
            if case .done = result {
                if entry.received == nil {
                    // An own gift: the list without it (the server took it off already).
                    let ids = AstraVisualGifts.mine(accountPeerId: accountPeerId).filter { $0 != entry.gift }
                    UserDefaults.standard.set(ids.map { "\($0)" }, forKey: AstraVisualGifts.mineKey(accountPeerId))
                    AstraVisualGifts.changed()
                }
                AstraVisualGifts.sendGiftMessage(context: context, to: to, gift: entry.gift, text: text)
                AstraVisualGifts.refresh(context: context, sendMine: false, completion: { _ in })
            }
            completion(result)
        })
    }

    /// Wears a gift as the status AstraGram shows beside the account's name, or takes it off (nil).
    static func wear(context: AccountContext, entry: Entry?, completion: @escaping (ChangeResult) -> Void) {
        var change = AstraStreakBot.VisualGiftsChange()
        change.wear = .some(entry?.ref)
        AstraVisualGifts.change(context: context, change, completion: { result, _ in completion(result) })
    }

    /// The gift the account wears, if any.
    static func wornEntry(context: AccountContext) -> Entry? {
        let accountPeerId = context.account.peerId
        guard let worn = AstraVisualGifts.worn(accountPeerId: accountPeerId)[accountPeerId.id._internalGetInt64Value()] else {
            return nil
        }
        return AstraVisualGifts.entries(accountPeerId: accountPeerId, peerId: accountPeerId).first(where: { $0.ref == worn.ref })
    }

    /// The message a gift sends to the chat, as Telegram sends for a real gift: AstraGram draws it as a gift card, other
    /// apps show its text (with the caption).
    private static func sendGiftMessage(context: AccountContext, to: EnginePeer.Id, gift: Int64, text caption: String) {
        guard let item = AstraGiftMessage.gift(id: gift) else {
            return
        }
        let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
        var text = AstraGiftMessage.text(giftId: gift, title: item.title ?? (isRussian ? "подарок" : "gift"), isRussian: isRussian)
        if !caption.isEmpty {
            text += "\n\n" + caption
        }
        let _ = enqueueMessages(account: context.account, peerId: to, messages: [.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).startStandalone()
    }

    /// Telegram's unique-gift attributes of each of `giftIds` (cached by Telegram's own code).
    static func attributes(context: AccountContext, giftIds: Set<Int64>) -> Signal<[Int64: [StarGift.UniqueGift.Attribute]], NoError> {
        if giftIds.isEmpty {
            return .single([:])
        }
        return combineLatest(giftIds.map { id in
            context.engine.payments.getStarGiftUpgradeAttributes(giftId: id)
            |> take(1)
            |> map { (id, $0 ?? []) }
        })
        |> map { list -> [Int64: [StarGift.UniqueGift.Attribute]] in
            return Dictionary(list, uniquingKeysWith: { lhs, _ in lhs })
        }
    }

    /// The unique gift a visual gift was upgraded to, drawn as Telegram draws one; nil when Telegram's list no longer
    /// has its attributes.
    static func uniqueGift(gift: StarGift.Gift, look: AstraUniqueLook, attributes: [StarGift.UniqueGift.Attribute], ownerPeerId: EnginePeer.Id?) -> StarGift.UniqueGift? {
        var model: StarGift.UniqueGift.Attribute?
        var pattern: StarGift.UniqueGift.Attribute?
        var backdrop: StarGift.UniqueGift.Attribute?
        for attribute in attributes {
            switch attribute {
            case let .model(name, _, _, _) where name == look.model:
                model = attribute
            case let .pattern(name, _, _) where name == look.pattern:
                pattern = attribute
            case let .backdrop(name, _, _, _, _, _, _) where name == look.backdrop:
                backdrop = attribute
            default:
                break
            }
        }
        guard let model, let pattern, let backdrop else {
            return nil
        }
        // A stable ID of its own, never one of Telegram's.
        let id = Int64(bitPattern: UInt64(bitPattern: gift.id) &* 31 &+ UInt64(look.number)) | Int64.min
        return StarGift.UniqueGift(
            id: id,
            giftId: gift.id,
            title: gift.title ?? "",
            number: look.number,
            slug: "",
            owner: ownerPeerId.map { .peerId($0) } ?? .name(""),
            attributes: [model, pattern, backdrop],
            availability: StarGift.UniqueGift.Availability(issued: look.number, total: gift.availability?.total ?? max(look.number, 1)),
            giftAddress: nil,
            resellAmounts: nil,
            resellForTonOnly: false,
            releasedBy: nil,
            valueAmount: nil,
            valueCurrency: nil,
            valueUsdAmount: nil,
            flags: [],
            themePeerId: nil,
            peerColor: nil,
            hostPeerId: nil,
            minOfferStars: nil,
            craftChancePermille: nil
        )
    }

    /// The worn gifts of all the accounts on this device (each account learns the people in its own chats).
    private static var wornByAccount: [EnginePeer.Id: [Int64: AstraWornGift]] = [:]

    /// Shows the worn gifts beside the names: the unique ones with their backdrop, as Telegram shows a worn
    /// collectible; the others as their sticker.
    static func applyWorn(context: AccountContext) {
        let accountPeerId = context.account.peerId
        AstraVisualGifts.wornByAccount[accountPeerId] = AstraVisualGifts.worn(accountPeerId: accountPeerId)
        var all: [Int64: AstraWornGift] = [:]
        for (_, worn) in AstraVisualGifts.wornByAccount {
            all.merge(worn, uniquingKeysWith: { lhs, _ in lhs })
        }
        let uniqueIds = Set(all.values.filter { $0.unique != nil }.map { $0.gift })
        let catalog = context.engine.payments.cachedStarGifts()
        |> filter { $0 != nil }
        |> take(1)
        let _ = (combineLatest(catalog, AstraVisualGifts.attributes(context: context, giftIds: uniqueIds))
        |> take(1)
        |> mapToSignal { catalog, attributes -> Signal<Never, NoError> in
            var gifts: [Int64: StarGift.Gift] = [:]
            for gift in catalog ?? [] {
                if case let .generic(gift) = gift {
                    gifts[gift.id] = gift
                }
            }
            var statuses: [Int64: PeerEmojiStatus] = [:]
            for (user, worn) in all {
                guard let gift = gifts[worn.gift] else {
                    continue
                }
                if let look = worn.unique, let unique = AstraVisualGifts.uniqueGift(gift: gift, look: look, attributes: attributes[worn.gift] ?? [], ownerPeerId: nil) {
                    var modelFile: Int64?
                    var patternFile: Int64?
                    var colors: (Int32, Int32, Int32, Int32)?
                    for attribute in unique.attributes {
                        switch attribute {
                        case let .model(_, file, _, _):
                            modelFile = file.fileId.id
                        case let .pattern(_, file, _):
                            patternFile = file.fileId.id
                        case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _):
                            colors = (innerColor, outerColor, patternColor, textColor)
                        default:
                            break
                        }
                    }
                    if let modelFile, let patternFile, let colors {
                        statuses[user] = PeerEmojiStatus(content: .starGift(id: unique.id, fileId: modelFile, title: "\(unique.title) #\(unique.number)", slug: "", patternFileId: patternFile, innerColor: colors.0, outerColor: colors.1, patternColor: colors.2, textColor: colors.3), expirationDate: nil)
                        continue
                    }
                }
                statuses[user] = PeerEmojiStatus(content: .emoji(fileId: gift.file.fileId.id), expirationDate: nil)
            }
            return AstraWornGifts.update(statuses, account: context.account)
        }).start()
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
    private static var catalogDisposable: Disposable?

    static func start(context: AccountContext) {
        let peerId = context.account.peerId
        if AstraVisualGifts.catalogDisposable == nil {
            // The catalog for drawing gift messages in chats (AstraGiftMessage), kept as the app refreshes it.
            AstraVisualGifts.catalogDisposable = context.engine.payments.cachedStarGifts().start(next: { gifts in
                var result: [Int64: StarGift.Gift] = [:]
                for gift in gifts ?? [] {
                    if case let .generic(gift) = gift {
                        result[gift.id] = gift
                    }
                }
                if !result.isEmpty {
                    AstraGiftMessage.setCatalog(result)
                }
            })
        }
        if AstraVisualGifts.timers[peerId] != nil {
            AstraVisualGifts.refreshIfStale(context: context)
            return
        }
        // The gifts worn as a status, as last known, until the server answers.
        AstraVisualGifts.applyWorn(context: context)
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
        let account = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: accountPeerId))
        let _ = (combineLatest(AstraBadgeSync.candidates(context: context) |> take(1), account) |> deliverOnMainQueue).start(next: { check, account in
            let mine: [Int64]? = send ? AstraVisualGifts.mine(accountPeerId: accountPeerId) : nil
            // The account's Local Premium look goes along every time (off: taken off), so others see it.
            var premiumLook: [String: Any]?? = nil
            if case let .user(user)? = account {
                premiumLook = .some(AstraLocalPremium.sharedLook(account: user))
            }
            AstraStreakBot.visualGifts(accountPeerId: accountPeerId, set: mine, premiumLook: premiumLook, check: check, completion: { result in
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
                    var othersMeta: [String: [String: AstraGiftMeta]] = [:]
                    for (user, meta) in result.usersMeta where !meta.isEmpty {
                        othersMeta["\(user)"] = Dictionary(uniqueKeysWithValues: meta.map { ("\($0.key)", $0.value) })
                    }
                    if othersMeta != AstraVisualGifts.othersMeta(accountPeerId: accountPeerId) {
                        AstraVisualGifts.encode(othersMeta, key: AstraVisualGifts.othersMetaKey(accountPeerId))
                        AstraVisualGifts.changed()
                    }
                    AstraVisualGifts.storeOwn(result, context: context)
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
    static func giftId(of item: ProfileGiftsContext.State.StarGift) -> Int64 {
        switch item.gift {
        case let .generic(gift):
            return gift.id
        case let .unique(gift):
            return gift.giftId
        }
    }

    /// Kept in a synthetic item's collections, which no real gift has (Telegram's collection IDs are positive).
    static let marker: Int32 = Int32.min + 0x4153

    static func item(gift: StarGift.Gift, entry: Entry, fromPeer: EnginePeer?, unique: StarGift.UniqueGift? = nil) -> ProfileGiftsContext.State.StarGift {
        return ProfileGiftsContext.State.StarGift(
            gift: unique.map { .unique($0) } ?? .generic(gift),
            reference: nil,
            fromPeer: entry.received?.anonymous == true && entry.received?.from == 0 ? nil : fromPeer,
            date: entry.date,
            text: entry.received?.text,
            entities: nil,
            nameHidden: entry.received == nil || entry.received?.anonymous == true,
            savedToProfile: !entry.meta.isHidden,
            pinnedToTop: entry.meta.isPinned,
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
            number: unique?.number,
            isRefunded: false,
            canCraftAt: nil
        )
    }

    /// The entry a synthetic item of `peerId`'s profile was made from.
    public static func entry(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, item: ProfileGiftsContext.State.StarGift) -> Entry? {
        guard item.astraIsVisual else {
            return nil
        }
        let giftId: Int64
        switch item.gift {
        case let .generic(gift):
            giftId = gift.id
        case let .unique(gift):
            giftId = gift.giftId
        }
        let entries = AstraVisualGifts.entries(accountPeerId: accountPeerId, peerId: peerId).filter { $0.gift == giftId && $0.date == item.date }
        // A giver this device does not know (or an anonymous one) has no peer: such an item matches by gift and date.
        return entries.first(where: { entry in
            if let fromPeer = item.fromPeer {
                return entry.received?.from == fromPeer.id.id._internalGetInt64Value()
            }
            return true
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
    // Telegram's attributes of the upgraded gifts, to draw them as unique ones.
    let entriesWithAttributes = entries
    |> mapToSignal { entries, peers -> Signal<([AstraVisualGifts.Entry], [EnginePeer.Id: EnginePeer], [Int64: [StarGift.UniqueGift.Attribute]]), NoError> in
        let ids = Set(entries.filter { $0.meta.unique != nil }.map { $0.gift })
        return AstraVisualGifts.attributes(context: context, giftIds: ids)
        |> map { (entries, peers, $0) }
    }
    return combineLatest(state, entriesWithAttributes, catalog)
    |> map { state, entriesAndPeers, catalog -> ProfileGiftsContext.State in
        let (entries, peers, attributes) = entriesAndPeers
        let items = entries.compactMap { entry -> ProfileGiftsContext.State.StarGift? in
            guard let gift = catalog[entry.gift] else {
                return nil
            }
            let fromPeer = entry.received.flatMap { peers[EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value($0.from))] }
            let unique = entry.meta.unique.flatMap { AstraVisualGifts.uniqueGift(gift: gift, look: $0, attributes: attributes[entry.gift] ?? [], ownerPeerId: peerId) }
            return AstraVisualGifts.item(gift: gift, entry: entry, fromPeer: fromPeer, unique: unique)
        }
        if items.isEmpty {
            return state
        }
        // Pinned AstraGram gifts first (in the order they were pinned), then the owner's pinned Telegram gifts, then the
        // other AstraGram gifts, then the rest.
        let pinnedEntries = entries.enumerated().filter { $0.element.meta.isPinned }.sorted(by: { ($0.element.meta.pinnedAt ?? 0) < ($1.element.meta.pinnedAt ?? 0) })
        let pinnedItems = pinnedEntries.compactMap { pair in items.first(where: { $0.date == pair.element.date && $0.pinnedToTop && AstraVisualGifts.giftId(of: $0) == pair.element.gift }) }
        let otherItems = items.filter { !$0.pinnedToTop }
        func inserted(_ list: [ProfileGiftsContext.State.StarGift]) -> [ProfileGiftsContext.State.StarGift] {
            let pinned = list.prefix(while: { $0.pinnedToTop })
            return pinnedItems + Array(pinned) + otherItems + list.dropFirst(pinned.count)
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
