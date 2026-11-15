import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// AstraGram: keeps the AstraGram mark in the account's name in step with the "AstraGram badge" switch, and asks once
/// whether to show it (the mark changes the account's name, so it is not added without asking).
public enum AstraBadgeSync {
    private static var disposables: [EnginePeer.Id: Disposable] = [:]
    /// What was last sent for an account in this session: a name the server changes back is not sent again and again.
    private static var lastSent: [EnginePeer.Id: Bool] = [:]
    private static var didAsk = false

    public static func start(context: AccountContext) {
        let peerId = context.account.peerId
        if AstraBadgeSync.disposables[peerId] != nil {
            return
        }
        let enabled = AstraGramSettings.signal
        |> map { settings -> Bool in
            return settings.astraBadge
        }
        |> distinctUntilChanged
        let peer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        AstraBadgeSync.disposables[peerId] = (combineLatest(enabled, peer)
        |> deliverOnMainQueue).start(next: { enabled, peer in
            guard case let .user(user)? = peer else {
                return
            }
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            let hasMark = AstraBadge.contains(firstName) || AstraBadge.contains(lastName)
            if hasMark == enabled || AstraBadgeSync.lastSent[peerId] == enabled {
                return
            }
            let updatedFirstName: String
            let updatedLastName: String
            if enabled {
                if firstName.count + AstraBadge.marker.unicodeScalars.count > AstraBadge.maxNameLength || firstName.isEmpty {
                    return
                }
                updatedFirstName = AstraBadge.adding(to: firstName)
                updatedLastName = lastName
            } else {
                updatedFirstName = AstraBadge.removing(from: firstName)
                updatedLastName = AstraBadge.removing(from: lastName)
            }
            AstraBadgeSync.lastSent[peerId] = enabled
            let _ = context.engine.accountData.updateAccountPeerName(firstName: updatedFirstName, lastName: updatedLastName).startStandalone()
        })

        if !AstraGramSettings.current.astraBadgeAsked && !AstraBadgeSync.didAsk {
            AstraBadgeSync.didAsk = true
            let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.lowercased().hasPrefix("ru")
            Queue.mainQueue().after(2.0, {
                AstraBadgeSync.ask(isRussian: isRussian)
            })
        }
    }

    private static func ask(isRussian: Bool) {
        guard let top = astraTopViewController() else {
            // Asked at the next launch instead.
            AstraBadgeSync.didAsk = false
            return
        }
        let title = isRussian ? "Значок AstraGram" : "AstraGram Badge"
        let message = isRussian
            ? "Другие пользователи AstraGram увидят рядом с вашим именем значок AstraGram, а вы — у них.\n\nДля этого в конец вашего имени добавляются два невидимых символа. В обычном Telegram имя выглядит как прежде, но через API эти символы может прочитать кто угодно.\n\nИзменить можно в настройках AstraGram → «Оформление»."
            : "Other AstraGram users will see an AstraGram badge beside your name, and you beside theirs.\n\nTo do this, two invisible characters are added to the end of your name. In regular Telegram your name looks the same, but anyone can read these characters through the API.\n\nYou can change this in AstraGram settings → Look."
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: isRussian ? "Не показывать" : "Don't Show", style: .cancel, handler: { _ in
            AstraGramSettings.update { $0.astraBadgeAsked = true; $0.astraBadge = false }
        }))
        alert.addAction(UIAlertAction(title: isRussian ? "Показывать" : "Show", style: .default, handler: { _ in
            AstraGramSettings.update { $0.astraBadgeAsked = true; $0.astraBadge = true }
        }))
        top.present(alert, animated: true)
    }
}
