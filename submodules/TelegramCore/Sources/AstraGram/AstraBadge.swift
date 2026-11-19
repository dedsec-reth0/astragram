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

    private static let usersKey = "astragram.badge.users"

    /// The Telegram IDs of the users who show the badge, as the server last gave them; kept for the next launch.
    private static let users = Atomic<Set<Int64>>(value: {
        let stored = UserDefaults.standard.array(forKey: AstraBadge.usersKey) as? [NSNumber] ?? []
        return Set(stored.map { $0.int64Value })
    }())

    /// Replaces the list of users who show the badge (an empty list hides every badge).
    public static func setUsers(_ ids: Set<Int64>) {
        let changed = AstraBadge.users.with { $0 != ids }
        if !changed {
            return
        }
        let _ = AstraBadge.users.swap(ids)
        UserDefaults.standard.set(ids.map { NSNumber(value: $0) }, forKey: AstraBadge.usersKey)
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
