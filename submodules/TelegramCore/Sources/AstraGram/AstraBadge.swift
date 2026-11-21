import Foundation
import Postbox
import SwiftSignalKit

/// AstraGram: the mark of people who use AstraGram.
///
/// With "AstraGram badge" on, AstraGram tells the streak bot's server, and gets back the Telegram IDs of everyone who
/// has it on (`AstraBadgeSync` in AstraGramUI); the badge is drawn beside those users. The first versions put two
/// invisible characters (INVISIBLE SEPARATOR, INVISIBLE PLUS) at the end of the account's first name instead, but
/// Telegram drops them from names, so nobody saw the badge. A name that still has them counts too.
public enum AstraBadge {
    public static let marker = "\u{2063}\u{2064}"
    private static let markerScalars = Array("\u{2063}\u{2064}".unicodeScalars)

    /// Telegram's limit for a first name.
    public static let maxNameLength = 64

    public static func contains(_ string: String?) -> Bool {
        guard let string, !string.isEmpty else {
            return false
        }
        let scalars = Array(string.unicodeScalars)
        let count = AstraBadge.markerScalars.count
        if scalars.count < count {
            return false
        }
        for start in 0 ... (scalars.count - count) {
            if Array(scalars[start ..< start + count]) == AstraBadge.markerScalars {
                return true
            }
        }
        return false
    }

    public static func adding(to name: String) -> String {
        if AstraBadge.contains(name) {
            return name
        }
        return name + AstraBadge.marker
    }

    public static func removing(from name: String) -> String {
        var scalars = String.UnicodeScalarView()
        let all = Array(name.unicodeScalars)
        var i = 0
        let count = AstraBadge.markerScalars.count
        while i < all.count {
            if i + count <= all.count && Array(all[i ..< i + count]) == AstraBadge.markerScalars {
                i += count
                continue
            }
            scalars.append(all[i])
            i += 1
        }
        return String(scalars)
    }

    private static let usersKey = "astragram.badge.usersByAccount"

    /// The Telegram IDs of the users who show the badge, per account (each account asks the server about its own chats
    /// and contacts), as the server last gave them; kept for the next launch. A badge shows when any account has it.
    private static let usersByAccount = Atomic<[Int64: Set<Int64>]>(value: {
        var result: [Int64: Set<Int64>] = [:]
        if let stored = UserDefaults.standard.dictionary(forKey: AstraBadge.usersKey) as? [String: [NSNumber]] {
            for (account, ids) in stored {
                if let account = Int64(account) {
                    result[account] = Set(ids.map { $0.int64Value })
                }
            }
        }
        return result
    }())
    private static let users = Atomic<Set<Int64>>(value: AstraBadge.usersByAccount.with { Set($0.values.joined()) })

    /// Replaces an account's list of users who show the badge (an empty list hides the badges it gave).
    public static func setUsers(_ ids: Set<Int64>, accountPeerId: PeerId) {
        let account = accountPeerId.id._internalGetInt64Value()
        var changed = false
        let all = AstraBadge.usersByAccount.modify { current in
            var current = current
            if current[account] != ids {
                changed = true
                if ids.isEmpty {
                    current.removeValue(forKey: account)
                } else {
                    current[account] = ids
                }
            }
            return current
        }
        if !changed {
            return
        }
        let union = Set(all.values.joined())
        let _ = AstraBadge.users.swap(union)
        var stored: [String: [NSNumber]] = [:]
        for (account, ids) in all {
            stored["\(account)"] = ids.map { NSNumber(value: $0) }
        }
        UserDefaults.standard.set(stored, forKey: AstraBadge.usersKey)
        UserDefaults.standard.removeObject(forKey: "astragram.badge.users")
        AstraMarks.changed()
    }

    static func isAstraGramUser(_ peer: Peer) -> Bool {
        guard let user = peer as? TelegramUser, user.botInfo == nil else {
            return false
        }
        let id = user.id.id._internalGetInt64Value()
        if AstraBadge.users.with({ $0.contains(id) }) {
            return true
        }
        return AstraBadge.contains(user.firstName) || AstraBadge.contains(user.lastName)
    }
}

/// AstraGram: the marks drawn beside names that come from outside the peer itself (the AstraGram badge, the streak
/// count). They change without the peer changing, so lists that show them redraw when `revision` moves.
public enum AstraMarks {
    private static let revisionValue = Atomic<Int>(value: 0)
    private static let pipe = ValuePipe<Int>()

    public static var revision: Int {
        return AstraMarks.revisionValue.with { $0 }
    }

    /// Fires with the new revision whenever a mark changes.
    public static var updates: Signal<Int, NoError> {
        return AstraMarks.pipe.signal()
    }

    public static func changed() {
        let revision = AstraMarks.revisionValue.modify { $0 + 1 }
        AstraMarks.pipe.putNext(revision)
    }
}

public extension Peer {
    /// Whether this user has the AstraGram mark in their name (see `AstraBadge`).
    var astraUsesAstraGram: Bool {
        return AstraBadge.isAstraGramUser(self)
    }
}

public extension EnginePeer {
    /// Whether this user has the AstraGram mark in their name (see `AstraBadge`).
    var astraUsesAstraGram: Bool {
        return AstraBadge.isAstraGramUser(self._asPeer())
    }
}
