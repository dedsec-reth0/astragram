import Foundation
import Postbox
import SwiftSignalKit

/// AstraGram: the Local Premium of other AstraGram users. Their app sends their look (emoji status, name and profile
/// colours) to the streak bot's server; this device shows them as Premium with that look. Everyone without AstraGram
/// sees them as Telegram does. What the server (Telegram's) sent is kept, so the look goes away cleanly when turned off.
public enum AstraPremiumLooks {
    public struct Look: Codable, Equatable {
        public var status: Int64?
        public var statusUntil: Int32?
        public var nameColor: Int32?
        public var backgroundEmoji: Int64?
        public var profileColor: Int32?
        public var profileBackgroundEmoji: Int64?

        public init(status: Int64?, statusUntil: Int32?, nameColor: Int32?, backgroundEmoji: Int64?, profileColor: Int32?, profileBackgroundEmoji: Int64?) {
            self.status = status
            self.statusUntil = statusUntil
            self.nameColor = nameColor
            self.backgroundEmoji = backgroundEmoji
            self.profileColor = profileColor
            self.profileBackgroundEmoji = profileBackgroundEmoji
        }
    }

    /// What Telegram last sent for a user with a look, to bring back when the look goes.
    private struct Real: Codable {
        var premium: Bool
        var status: PeerEmojiStatus?
        var nameColor: Int32?
        /// A collectible name colour, which `nameColor` (a preset) cannot hold. Optional, so older saved data decodes.
        var collectibleNameColor: PeerCollectibleColor?
        var backgroundEmoji: Int64?
        var profileColor: Int32?
        var profileBackgroundEmoji: Int64?
    }

    private struct Stored: Codable {
        /// The looks of every account's list together: what `applying()` dresses with.
        var looks: [String: Look]
        var real: [String: Real]
        /// Each account's own list (by account Telegram ID), as its last refresh got it. Each account asks only about
        /// the people in its own chats, so one account's answer must not drop another's. Nil in data saved before.
        var byAccount: [String: [String: Look]]?
    }

    private static let storageKey = "astragram.premiumLooks"
    private static let state = Atomic<Stored>(value: AstraPremiumLooks.load())

    private static func load() -> Stored {
        if let data = UserDefaults.standard.data(forKey: AstraPremiumLooks.storageKey), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return stored
        }
        return Stored(looks: [:], real: [:], byAccount: [:])
    }

    private static func save(_ stored: Stored) {
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: AstraPremiumLooks.storageKey)
        }
    }

    private static func real(_ user: TelegramUser) -> Real {
        var nameColor: Int32?
        var collectibleNameColor: PeerCollectibleColor?
        switch user.nameColor {
        case let .preset(color)?:
            nameColor = color.rawValue
        case let .collectible(color)?:
            collectibleNameColor = color
        case nil:
            break
        }
        return Real(premium: user.flags.contains(.isPremium), status: user.emojiStatus, nameColor: nameColor, collectibleNameColor: collectibleNameColor, backgroundEmoji: user.backgroundEmojiId, profileColor: user.profileColor?.rawValue, profileBackgroundEmoji: user.profileBackgroundEmojiId)
    }

    private static func dressed(_ user: TelegramUser, look: Look) -> TelegramUser {
        var user = user
        if !user.flags.contains(.isPremium) {
            var flags = user.flags
            flags.insert(.isPremium)
            user = user.withUpdatedFlags(flags)
        }
        if let status = look.status {
            let expired = look.statusUntil.map { $0 < Int32(Date().timeIntervalSince1970) } ?? false
            if !expired {
                user = user.withUpdatedEmojiStatus(PeerEmojiStatus(content: .emoji(fileId: status), expirationDate: look.statusUntil))
            }
        }
        if let nameColor = look.nameColor {
            user = user.withUpdatedNameColor(.preset(PeerNameColor(rawValue: nameColor)))
        }
        if look.backgroundEmoji != nil {
            user = user.withUpdatedBackgroundEmojiId(look.backgroundEmoji)
        }
        if let profileColor = look.profileColor {
            user = user.withUpdatedProfileColor(PeerNameColor(rawValue: profileColor))
        }
        if look.profileBackgroundEmoji != nil {
            user = user.withUpdatedProfileBackgroundEmojiId(look.profileBackgroundEmoji)
        }
        return user
    }

    private static func undressed(_ user: TelegramUser, real: Real) -> TelegramUser {
        var flags = user.flags
        if real.premium {
            flags.insert(.isPremium)
        } else {
            flags.remove(.isPremium)
        }
        let user = user.withUpdatedFlags(flags).withUpdatedEmojiStatus(real.status).withUpdatedBackgroundEmojiId(real.backgroundEmoji).withUpdatedProfileColor(real.profileColor.map { PeerNameColor(rawValue: $0) }).withUpdatedProfileBackgroundEmojiId(real.profileBackgroundEmoji)
        // Set even when Telegram sent none: otherwise the look's colour would stay on a user who has no colour.
        let nameColor: PeerColor?
        if let collectible = real.collectibleNameColor {
            nameColor = .collectible(collectible)
        } else {
            nameColor = real.nameColor.map { .preset(PeerNameColor(rawValue: $0)) }
        }
        return AstraPremiumLooks.withNameColor(user, nameColor)
    }

    /// `withUpdatedNameColor` takes no nil, so the user is built with the colour (or none) here.
    private static func withNameColor(_ user: TelegramUser, _ nameColor: PeerColor?) -> TelegramUser {
        return TelegramUser(id: user.id, accessHash: user.accessHash, firstName: user.firstName, lastName: user.lastName, username: user.username, phone: user.phone, photo: user.photo, botInfo: user.botInfo, restrictionInfo: user.restrictionInfo, flags: user.flags, emojiStatus: user.emojiStatus, usernames: user.usernames, storiesHidden: user.storiesHidden, nameColor: nameColor, backgroundEmojiId: user.backgroundEmojiId, profileColor: user.profileColor, profileBackgroundEmojiId: user.profileBackgroundEmojiId, subscriberCount: user.subscriberCount, verificationIconFileId: user.verificationIconFileId, linkedCommunityId: user.linkedCommunityId)
    }

    /// Whether the Telegram ID `key` is an account logged in on this device.
    private static func isAccount(_ key: Int64) -> Bool {
        return AstraLocalPremium.isAccount(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(key)))
    }

    /// `user` as AstraGram shows it: with their Local Premium look (Telegram's own values kept aside).
    static func applying(_ user: TelegramUser) -> TelegramUser {
        // An account of this device shows its own Local Premium (AstraLocalPremium). Another account's refresh,
        // which has this one in its chats, must not dress it: it would then pass for real Premium here.
        if AstraLocalPremium.isAccount(user.id) {
            return user
        }
        let key = "\(user.id.id._internalGetInt64Value())"
        guard let look = AstraPremiumLooks.state.with({ $0.looks[key] }) else {
            return user
        }
        let result = AstraPremiumLooks.dressed(user, look: look)
        if !result.isEqual(user) {
            // Fresh from Telegram: what it says is kept for when the look goes.
            let kept = AstraPremiumLooks.state.modify { current in
                var current = current
                current.real[key] = AstraPremiumLooks.real(user)
                return current
            }
            AstraPremiumLooks.save(kept)
        }
        return result
    }

    /// Replaces the looks `account` knows of with `looks` (by Telegram ID) and redraws the users in `account`'s
    /// storage whose look changed. The accounts of this device are left out: their own Local Premium already shows.
    /// The other accounts' lists are kept: each account asks only about the people in its own chats.
    public static func update(_ looks: [Int64: Look], account: Account) -> Signal<Never, NoError> {
        let accountId = account.peerId.id._internalGetInt64Value()
        let accountKey = "\(accountId)"
        let new = Dictionary(uniqueKeysWithValues: looks.filter { $0.key != accountId && !AstraPremiumLooks.isAccount($0.key) }.map { ("\($0.key)", $0.value) })
        var previousLooks: [String: Look] = [:]
        var realBefore: [String: Real] = [:]
        var allLooks: [String: Look] = [:]
        let updated = AstraPremiumLooks.state.modify { current in
            var current = current
            // Data saved before the lists were kept per account: the one list is taken as this account's.
            var byAccount = current.byAccount ?? [accountKey: current.looks]
            previousLooks = byAccount[accountKey] ?? [:]
            realBefore = current.real
            byAccount[accountKey] = new
            var looks: [String: Look] = [:]
            for (_, list) in byAccount {
                for (key, look) in list {
                    looks[key] = look
                }
            }
            for (key, look) in new {
                looks[key] = look
            }
            allLooks = looks
            current.byAccount = byAccount
            current.looks = looks
            current.real = current.real.filter { looks[$0.key] != nil }
            return current
        }
        AstraPremiumLooks.save(updated)
        let (previous, real, union) = (previousLooks, realBefore, allLooks)
        var changedIds = Set(new.keys).union(previous.keys).filter { previous[$0] != new[$0] }
        changedIds.formUnion(new.keys)
        return account.postbox.transaction { transaction -> Void in
            var peers: [Peer] = []
            for key in changedIds {
                guard let id = Int64(key), let user = transaction.getPeer(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))) as? TelegramUser else {
                    continue
                }
                if union[key] != nil {
                    // `updatePeersCustom` dresses it, keeping what Telegram sent. A user dressed before is fed back
                    // with Telegram's own values, so `applying()` does not record the old look as the real one.
                    peers.append(real[key].map { AstraPremiumLooks.undressed(user, real: $0) } ?? user)
                } else if previous[key] != nil, let kept = real[key] {
                    peers.append(AstraPremiumLooks.undressed(user, real: kept))
                }
            }
            if !peers.isEmpty {
                updatePeersCustom(transaction: transaction, peers: peers, update: { _, updated in updated })
            }
        }
        |> ignoreValues
    }
}
