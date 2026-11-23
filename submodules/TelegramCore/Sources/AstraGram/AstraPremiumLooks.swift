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
        var backgroundEmoji: Int64?
        var profileColor: Int32?
        var profileBackgroundEmoji: Int64?
    }

    private struct Stored: Codable {
        var looks: [String: Look]
        var real: [String: Real]
    }

    private static let storageKey = "astragram.premiumLooks"
    private static let state = Atomic<Stored>(value: AstraPremiumLooks.load())

    private static func load() -> Stored {
        if let data = UserDefaults.standard.data(forKey: AstraPremiumLooks.storageKey), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return stored
        }
        return Stored(looks: [:], real: [:])
    }

    private static func save(_ stored: Stored) {
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: AstraPremiumLooks.storageKey)
        }
    }

    private static func real(_ user: TelegramUser) -> Real {
        var nameColor: Int32?
        if case let .preset(color)? = user.nameColor {
            nameColor = color.rawValue
        }
        return Real(premium: user.flags.contains(.isPremium), status: user.emojiStatus, nameColor: nameColor, backgroundEmoji: user.backgroundEmojiId, profileColor: user.profileColor?.rawValue, profileBackgroundEmoji: user.profileBackgroundEmojiId)
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
        var user = user.withUpdatedFlags(flags).withUpdatedEmojiStatus(real.status).withUpdatedBackgroundEmojiId(real.backgroundEmoji).withUpdatedProfileColor(real.profileColor.map { PeerNameColor(rawValue: $0) }).withUpdatedProfileBackgroundEmojiId(real.profileBackgroundEmoji)
        if let nameColor = real.nameColor {
            user = user.withUpdatedNameColor(.preset(PeerNameColor(rawValue: nameColor)))
        }
        return user
    }

    /// `user` as AstraGram shows it: with their Local Premium look (Telegram's own values kept aside).
    static func applying(_ user: TelegramUser) -> TelegramUser {
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

    /// Replaces the looks this device knows of with `looks` (by Telegram ID) and redraws the users in `account`'s
    /// storage whose look changed. The account itself is left out: its own Local Premium already shows on it.
    public static func update(_ looks: [Int64: Look], account: Account) -> Signal<Never, NoError> {
        let accountId = account.peerId.id._internalGetInt64Value()
        let new = Dictionary(uniqueKeysWithValues: looks.filter { $0.key != accountId }.map { ("\($0.key)", $0.value) })
        let (previous, real) = AstraPremiumLooks.state.with { ($0.looks, $0.real) }
        var changedIds = Set(new.keys).union(previous.keys).filter { previous[$0] != new[$0] }
        changedIds.formUnion(new.keys)
        let updated = AstraPremiumLooks.state.modify { current in
            var current = current
            current.looks = new
            current.real = current.real.filter { new[$0.key] != nil }
            return current
        }
        AstraPremiumLooks.save(updated)
        return account.postbox.transaction { transaction -> Void in
            var peers: [Peer] = []
            for key in changedIds {
                guard let id = Int64(key), let user = transaction.getPeer(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))) as? TelegramUser else {
                    continue
                }
                if new[key] != nil {
                    // `updatePeersCustom` dresses it, keeping what Telegram sent.
                    peers.append(user)
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
