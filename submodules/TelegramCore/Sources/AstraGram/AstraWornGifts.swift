import Foundation
import Postbox
import SwiftSignalKit

/// AstraGram: visual gifts worn as a status. An AstraGram user can wear one of their AstraGram gifts beside their name;
/// other AstraGram apps learn it from the streak bot's server and show it in place of the user's Telegram emoji status,
/// on this device only. Everyone without AstraGram keeps seeing the user's own Telegram status, which the server never
/// gets. The status the server sends is kept (`realStatus`), so taking the gift off brings it back at once.
public enum AstraWornGifts {
    private struct Stored: Codable {
        var worn: [String: PeerEmojiStatus]
        /// The status the server last sent for each user wearing a gift (nil: none).
        var real: [String: StoredStatus]
    }

    private struct StoredStatus: Codable {
        var status: PeerEmojiStatus?
    }

    private static let storageKey = "astragram.wornGifts"

    private static let state = Atomic<Stored>(value: AstraWornGifts.load())

    private static func load() -> Stored {
        if let data = UserDefaults.standard.data(forKey: AstraWornGifts.storageKey), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return stored
        }
        return Stored(worn: [:], real: [:])
    }

    private static func save(_ stored: Stored) {
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: AstraWornGifts.storageKey)
        }
    }

    /// The status the user's gift shows as, when they wear one.
    public static func wornStatus(userId: Int64) -> PeerEmojiStatus? {
        return AstraWornGifts.state.with { $0.worn["\(userId)"] }
    }

    /// The user's own Telegram status (what people without AstraGram see), when they wear a gift: `.some(nil)` is no
    /// status; nil when they wear none or the server has not sent it yet.
    public static func realStatus(userId: Int64) -> PeerEmojiStatus?? {
        return AstraWornGifts.state.with { $0.real["\(userId)"].map { $0.status } }
    }

    /// `user` as AstraGram shows it: with their worn gift as the status (the server's status kept aside).
    static func applying(_ user: TelegramUser) -> TelegramUser {
        let key = "\(user.id.id._internalGetInt64Value())"
        guard let worn = AstraWornGifts.state.with({ $0.worn[key] }) else {
            return user
        }
        if user.emojiStatus != worn {
            let changed = AstraWornGifts.state.modify { current in
                var current = current
                current.real[key] = StoredStatus(status: user.emojiStatus)
                return current
            }
            AstraWornGifts.save(changed)
            return user.withUpdatedEmojiStatus(worn)
        }
        return user
    }

    /// Replaces the worn statuses this device knows of with `worn` (by Telegram ID), and redraws the users in
    /// `account`'s storage whose status changed.
    public static func update(_ worn: [Int64: PeerEmojiStatus], account: Account) -> Signal<Never, NoError> {
        let new = Dictionary(uniqueKeysWithValues: worn.map { ("\($0.key)", $0.value) })
        let (previous, real) = AstraWornGifts.state.with { ($0.worn, $0.real) }
        var changedIds = Set(new.keys).union(previous.keys).filter { previous[$0] != new[$0] }
        // The first time on an account: its storage may still hold statuses that were not applied yet.
        changedIds.formUnion(new.keys)
        let updated = AstraWornGifts.state.modify { current in
            var current = current
            current.worn = new
            current.real = current.real.filter { new[$0.key] != nil }
            return current
        }
        AstraWornGifts.save(updated)
        return account.postbox.transaction { transaction -> Void in
            var peers: [Peer] = []
            for key in changedIds {
                guard let id = Int64(key), let user = transaction.getPeer(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))) as? TelegramUser else {
                    continue
                }
                if let status = new[key] {
                    if user.emojiStatus != status {
                        // What the server sent, kept for when the gift is taken off.
                        let kept = AstraWornGifts.state.modify { current in
                            var current = current
                            current.real[key] = StoredStatus(status: user.emojiStatus)
                            return current
                        }
                        AstraWornGifts.save(kept)
                        peers.append(user.withUpdatedEmojiStatus(status))
                    }
                } else if previous[key] != nil, user.emojiStatus == previous[key] {
                    // Taken off: the status the server last sent comes back.
                    peers.append(user.withUpdatedEmojiStatus(real[key]?.status))
                }
            }
            if !peers.isEmpty {
                updatePeersCustom(transaction: transaction, peers: peers, update: { _, updated in updated })
            }
        }
        |> ignoreValues
    }
}
