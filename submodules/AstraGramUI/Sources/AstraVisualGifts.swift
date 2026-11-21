import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// AstraGram: visual gifts. In the gift shop a user puts any of Telegram's gifts on their profile without buying it.
/// The gifts are drawn only in AstraGram, with an "AstraGram" ribbon so nobody takes them for bought ones: on the
/// user's own profile at once, and on other AstraGram users' profiles through the streak bot's server, which hands an
/// app the lists of the people in its own chats and contacts only (as with the AstraGram badge).
public enum AstraVisualGifts {
    /// The most gifts one profile shows (the server keeps as many).
    public static let maxGifts = 100

    private static let refreshInterval: Double = 30.0 * 60.0
    private static var timers: [EnginePeer.Id: SwiftSignalKit.Timer] = [:]
    private static let changedPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    private static var revision = 0

    private static func mineKey(_ accountPeerId: EnginePeer.Id) -> String {
        return "astra.visualGifts.mine.\(accountPeerId.toInt64())"
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

    /// The account's own gifts, in the order they were put on.
    public static func mine(accountPeerId: EnginePeer.Id) -> [Int64] {
        let stored = UserDefaults.standard.stringArray(forKey: AstraVisualGifts.mineKey(accountPeerId)) ?? []
        return stored.compactMap { Int64($0) }
    }

    /// The other people's gifts this account last got from the server, by their Telegram ID.
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

    private static func changed() {
        AstraVisualGifts.revision += 1
        AstraVisualGifts.changedPromise.set(AstraVisualGifts.revision)
    }

    /// The visual gifts of `peerId` as this account sees them (the account's own when it is the account itself).
    public static func gifts(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> [Int64] {
        if peerId == accountPeerId {
            return AstraVisualGifts.mine(accountPeerId: accountPeerId)
        }
        guard peerId.namespace == Namespaces.Peer.CloudUser else {
            return []
        }
        return AstraVisualGifts.others(accountPeerId: accountPeerId)[peerId.id._internalGetInt64Value()] ?? []
    }

    public static func hasGifts(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> Bool {
        return !AstraVisualGifts.gifts(accountPeerId: accountPeerId, peerId: peerId).isEmpty
    }

    public static func giftsSignal(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id) -> Signal<[Int64], NoError> {
        return AstraVisualGifts.changedPromise.get()
        |> map { _ -> [Int64] in
            return AstraVisualGifts.gifts(accountPeerId: accountPeerId, peerId: peerId)
        }
        |> distinctUntilChanged
    }

    /// Puts `ids` on the account's profile (replacing what was there) and sends them to the server.
    static func setMine(context: AccountContext, ids: [Int64], completion: @escaping (Bool) -> Void) {
        let accountPeerId = context.account.peerId
        var seen = Set<Int64>()
        let unique = Array(ids.filter { seen.insert($0).inserted }.prefix(AstraVisualGifts.maxGifts))
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

    /// Keeps the other people's gifts up to date while the app runs: at launch and every half hour, when the streak bot
    /// is connected (the shop connects it; it is never connected only for this).
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
                    guard let result = result else {
                        completion(false)
                        return
                    }
                    var stored: [String: [String]] = [:]
                    for (user, gifts) in result.users where !gifts.isEmpty {
                        stored["\(user)"] = gifts.map { "\($0)" }
                    }
                    let previous = AstraVisualGifts.others(accountPeerId: accountPeerId)
                    if previous != result.users.filter({ !$0.value.isEmpty }) {
                        UserDefaults.standard.set(stored, forKey: AstraVisualGifts.othersKey(accountPeerId))
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
    /// A gift AstraGram's gift shop put on a profile: not bought, drawn only in AstraGram.
    var astraIsVisual: Bool {
        return self.reference == nil && self.date == 0 && self.fromPeer == nil && self.text == AstraVisualGifts.marker
    }
}

extension AstraVisualGifts {
    /// Kept in the synthetic item's text, which nothing shows for an item without a sender.
    static let marker = "\u{2063}astragram-visual\u{2063}"

    static func item(gift: StarGift.Gift) -> ProfileGiftsContext.State.StarGift {
        return ProfileGiftsContext.State.StarGift(
            gift: .generic(gift),
            reference: nil,
            fromPeer: nil,
            date: 0,
            text: AstraVisualGifts.marker,
            entities: nil,
            nameHidden: true,
            savedToProfile: true,
            pinnedToTop: false,
            convertStars: nil,
            canUpgrade: false,
            canExportDate: nil,
            upgradeStars: nil,
            transferStars: nil,
            canTransferDate: nil,
            canResaleDate: nil,
            collectionIds: nil,
            prepaidUpgradeHash: nil,
            upgradeSeparate: false,
            dropOriginalDetailsStars: nil,
            number: nil,
            isRefunded: false,
            canCraftAt: nil
        )
    }
}

/// A profile's gifts with its visual gifts first, before the real ones (in the "All" view only).
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
    return combineLatest(state, AstraVisualGifts.giftsSignal(accountPeerId: context.account.peerId, peerId: peerId), catalog)
    |> map { state, ids, catalog -> ProfileGiftsContext.State in
        let items = ids.compactMap { catalog[$0] }.map(AstraVisualGifts.item(gift:))
        if items.isEmpty {
            return state
        }
        var state = state
        // First, before the real gifts.
        state.gifts = items + state.gifts
        if state.filter == .All {
            state.filteredGifts = items + state.filteredGifts
        }
        state.count = (state.count ?? 0) + Int32(items.count)
        return state
    }
}
