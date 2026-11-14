import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Ghost mode's own list of people who still see you online.
///
/// Telegram's servers decide who sees an online status, so the list is applied with the only tool there is: while ghost
/// mode hides the online status and the list is not empty, AyuGram sends the status as usual and sets the account's
/// Last Seen privacy to "Nobody, except the people of the list". When ghost mode is turned off or the list is emptied,
/// the kind of rule that was set before (Everybody / My Contacts / Nobody) is put back.
public enum AyuGhostOnlineExceptions {
    private static let previousKindKey = "ayugram.ghostOnline.previousPrivacyKind"

    private static func kind(of settings: SelectivePrivacySettings) -> String {
        switch settings {
        case .enableEveryone:
            return "everyone"
        case .enableContacts:
            return "contacts"
        case .disableEveryone:
            return "nobody"
        }
    }

    /// Applies the current settings to the account's Last Seen privacy.
    public static func apply(context: AccountContext) {
        let settings = AyuGramSettings.current
        let ids = settings.ghostOnlineExceptions.map { EnginePeer.Id($0) }
        if settings.hideOnlineStatus && !ids.isEmpty {
            let _ = (context.engine.privacy.requestAccountPrivacySettings()
            |> take(1)
            |> mapToSignal { privacySettings -> Signal<[EnginePeer.Id: EnginePeer?], NoError> in
                if UserDefaults.standard.string(forKey: AyuGhostOnlineExceptions.previousKindKey) == nil {
                    UserDefaults.standard.set(AyuGhostOnlineExceptions.kind(of: privacySettings.presence), forKey: AyuGhostOnlineExceptions.previousKindKey)
                }
                return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
            }
            |> mapToSignal { peers -> Signal<Void, NoError> in
                var enableFor: [EnginePeer.Id: SelectivePrivacyPeer] = [:]
                for (id, peer) in peers {
                    if let peer = peer {
                        enableFor[id] = SelectivePrivacyPeer(peer: peer, participantCount: nil)
                    }
                }
                if enableFor.isEmpty {
                    return .complete()
                }
                return context.engine.privacy.updateSelectiveAccountPrivacySettings(type: .presence, settings: .disableEveryone(enableFor: enableFor, enableForCloseFriends: false, enableForPremium: false, enableForBots: false))
            }).start()
        } else if let previousKind = UserDefaults.standard.string(forKey: AyuGhostOnlineExceptions.previousKindKey) {
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
}
