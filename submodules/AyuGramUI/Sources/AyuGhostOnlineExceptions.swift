import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Ghost mode had its own list of people who still saw the account online: the status was sent as usual, and the
/// account's Last Seen privacy was set to "Nobody, except the list". That made ghost mode depend on a privacy rule and
/// is removed: ghost mode never sends the online status again. This puts back what the list had changed.
public enum AyuGhostOnlineExceptions {
    private static let previousKindKey = "ayugram.ghostOnline.previousPrivacyKind"

    /// Empties the list and, if the list had changed the account's Last Seen privacy, puts back the kind of rule that
    /// was set before (Everybody / My Contacts / Nobody).
    public static func restore(context: AccountContext) {
        if !AyuGramSettings.current.ghostOnlineExceptions.isEmpty {
            AyuGramSettings.update { $0.ghostOnlineExceptions = [] }
        }
        guard let previousKind = UserDefaults.standard.string(forKey: AyuGhostOnlineExceptions.previousKindKey) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: AyuGhostOnlineExceptions.previousKindKey)
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
