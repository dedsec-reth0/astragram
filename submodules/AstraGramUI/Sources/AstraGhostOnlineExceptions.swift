import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Ghost mode had its own list of people who still saw the account online: the status was sent as usual, and the
/// account's Last Seen privacy was set to "Nobody, except the list". That made ghost mode depend on a privacy rule and
/// is removed: ghost mode never sends the online status again. This puts back what the list had changed.
public enum AstraGhostOnlineExceptions {
    private static let previousKindKey = "ayugram.ghostOnline.previousPrivacyKind"

    /// If the list had changed the account's Last Seen privacy, puts back the kind of rule that
    /// was set before (Everybody / My Contacts / Nobody).
    public static func restore(context: AccountContext) {
        guard let previousKind = UserDefaults.standard.string(forKey: AstraGhostOnlineExceptions.previousKindKey) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: AstraGhostOnlineExceptions.previousKindKey)
        let restored: SelectivePrivacySettings
        switch previousKind {
        case "everyone":
            restored = .enableEveryone(disableFor: [:])
        case "contacts":
            restored = .enableContacts(enableFor: [:], disableFor: [:], enableForPremium: false, enableForBots: false)
        default:
            restored = .disableEveryone(enableFor: [:], enableForCloseFriends: false, enableForPremium: false, enableForBots: false)
        }
        let _ = context.engine.privacy.updateSelectiveAccountPrivacySettings(type: .presence, settings: restored).start()
    }
}
