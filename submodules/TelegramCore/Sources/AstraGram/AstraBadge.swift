import Foundation
import Postbox

/// AstraGram: the mark of people who use AstraGram.
///
/// With "AstraGram badge" on, AstraGram adds two invisible characters (INVISIBLE SEPARATOR, INVISIBLE PLUS) to the end
/// of the account's first name. Other apps show the name as it was; AstraGram finds the characters in a user's name and
/// draws its badge beside it. There is no server: the name is the only place another AstraGram can see.
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

    static func isAstraGramUser(_ peer: Peer) -> Bool {
        guard let user = peer as? TelegramUser, user.botInfo == nil else {
            return false
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
