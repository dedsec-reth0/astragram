import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// AstraGram: the AstraGram badge, kept in step with the "AstraGram badge" switch, and the question whether to show it.
///
/// Telegram drops invisible characters from names, so the mark the first versions put in the name never reached anyone.
/// The badge now goes through the streak bot's server: with the switch on, AstraGram connects the bot (as for a
/// streak), tells the server, and gets back everyone who shows the badge, at launch and every half hour. A mark an
/// older version left in the account's name is taken out.
public enum AstraBadgeSync {
    private static var disposables: [EnginePeer.Id: Disposable] = [:]
    private static var timers: [EnginePeer.Id: SwiftSignalKit.Timer] = [:]
    /// The bot is connected for the badge at most once per account in a session.
    private static var linkTried = Set<EnginePeer.Id>()
    /// The old name mark is taken out at most once per account in a session.
    private static var nameCleaned = Set<EnginePeer.Id>()
    private static var didAsk = false
    private static let refreshInterval: Double = 30.0 * 60.0

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
        var isFirst = true
        AstraBadgeSync.disposables[peerId] = (enabled
        |> deliverOnMainQueue).start(next: { enabled in
            let wasFirst = isFirst
            isFirst = false
            AstraBadgeSync.timers[peerId]?.invalidate()
            AstraBadgeSync.timers[peerId] = nil
            if enabled {
                // A little after launch, so the bot lookup does not compete with the first chat list load.
                AstraBadgeSync.timers[peerId] = SwiftSignalKit.Timer(timeout: 3.0, repeat: false, completion: {
                    AstraBadgeSync.refresh(context: context)
                    let timer = SwiftSignalKit.Timer(timeout: AstraBadgeSync.refreshInterval, repeat: true, completion: {
                        AstraBadgeSync.refresh(context: context)
                    }, queue: Queue.mainQueue())
                    AstraBadgeSync.timers[peerId] = timer
                    timer.start()
                }, queue: Queue.mainQueue())
                AstraBadgeSync.timers[peerId]?.start()
            } else {
                AstraBadge.setUsers([], accountPeerId: peerId)
                // Switched off now: the server forgets the badge (it was never on if off at launch).
                if !wasFirst {
                    AstraStreakBot.badge(accountPeerId: peerId, show: false, completion: { _ in })
                }
            }
        })
        AstraBadgeSync.cleanOldNameMark(context: context)
        AstraVisualGifts.start(context: context)

        if !AstraGramSettings.current.astraBadgeAsked && !AstraBadgeSync.didAsk {
            AstraBadgeSync.didAsk = true
            let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
            Queue.mainQueue().after(2.0, {
                AstraBadgeSync.ask(isRussian: isRussian)
            })
        }
    }

    /// Who to ask the server about: the people in the chat list (archive included) and the contacts. The server answers
    /// only for the IDs it is asked about, so nobody gets the whole list.
    static func candidates(context: AccountContext) -> Signal<[Int64], NoError> {
        let peerId = context.account.peerId
        return combineLatest(
            context.engine.messages.chatList(group: .root, count: 400) |> take(1),
            context.engine.messages.chatList(group: .archive, count: 200) |> take(1),
            context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))
        )
        |> map { chatList, archive, contacts -> [Int64] in
            var ids = Set<Int64>()
            for item in chatList.items + archive.items {
                let id = item.renderedPeer.peerId
                if id.namespace == Namespaces.Peer.CloudUser {
                    ids.insert(id.id._internalGetInt64Value())
                }
            }
            for peer in contacts.peers {
                ids.insert(peer.id.id._internalGetInt64Value())
            }
            ids.remove(peerId.id._internalGetInt64Value())
            return Array(ids.prefix(1000))
        }
    }

    private static func refresh(context: AccountContext) {
        let peerId = context.account.peerId
        guard AstraGramSettings.current.astraBadge, AstraStreakBot.isAvailable else {
            return
        }
        let _ = (AstraBadgeSync.candidates(context: context) |> deliverOnMainQueue).start(next: { check in
        AstraStreakBot.badge(accountPeerId: peerId, show: true, check: check, completion: { result in
            Queue.mainQueue().async {
                guard AstraGramSettings.current.astraBadge else {
                    return
                }
                switch result {
                case let .users(ids):
                    AstraBadge.setUsers(ids.union([peerId.id._internalGetInt64Value()]), accountPeerId: peerId)
                case .notLinked:
                    // Connected once per session; the server learns the token when the bot gets "/start", so the
                    // list is asked again a little later.
                    if AstraBadgeSync.linkTried.contains(peerId) {
                        return
                    }
                    AstraBadgeSync.linkTried.insert(peerId)
                    AstraStreakBot.linkSilently(context: context, completion: { linked in
                        if linked {
                            Queue.mainQueue().after(15.0, {
                                AstraBadgeSync.refresh(context: context)
                            })
                        }
                    })
                case .failed:
                    break
                }
            }
        })
        })
    }

    /// Takes the invisible mark an older AstraGram put in the account's name out of it.
    private static func cleanOldNameMark(context: AccountContext) {
        let peerId = context.account.peerId
        if AstraBadgeSync.nameCleaned.contains(peerId) {
            return
        }
        AstraBadgeSync.nameCleaned.insert(peerId)
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard case let .user(user)? = peer else {
                return
            }
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            if !AstraBadge.contains(firstName) && !AstraBadge.contains(lastName) {
                return
            }
            let updatedFirstName = AstraBadge.removing(from: firstName)
            if updatedFirstName.isEmpty {
                return
            }
            let _ = context.engine.accountData.updateAccountPeerName(firstName: updatedFirstName, lastName: AstraBadge.removing(from: lastName)).startStandalone()
        })
    }

    /// Turns the badge off and takes the mark out of this account's name now, whatever this session sent before.
    /// `completion` gets whether there was a mark to take out.
    public static func clearName(context: AccountContext, completion: @escaping (Bool) -> Void) {
        let peerId = context.account.peerId
        AstraGramSettings.update { $0.astraBadgeAsked = true; $0.astraBadge = false }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard case let .user(user)? = peer else {
                completion(false)
                return
            }
            let firstName = user.firstName ?? ""
            let lastName = user.lastName ?? ""
            if !AstraBadge.contains(firstName) && !AstraBadge.contains(lastName) {
                completion(false)
                return
            }
            let _ = context.engine.accountData.updateAccountPeerName(firstName: AstraBadge.removing(from: firstName), lastName: AstraBadge.removing(from: lastName)).startStandalone()
            completion(true)
        })
    }

    private static func ask(isRussian: Bool) {
        guard let top = astraTopViewController() else {
            // Asked at the next launch instead.
            AstraBadgeSync.didAsk = false
            return
        }
        let title = isRussian ? "Значок AstraGram" : "AstraGram Badge"
        let message = isRussian
            ? "Другие пользователи AstraGram увидят рядом с вашим именем значок AstraGram, а вы — у них.\n\nДля этого AstraGram подключит бота огоньков AstraGram (в его чат уйдёт одно сообщение «/start») и сообщит его серверу ваш Telegram ID. Сервер отдаёт список ID со значком только приложениям AstraGram, у которых значок тоже включён. Ваше имя не меняется.\n\nЗначок ничего не подтверждает: не доверяйте человеку только из-за него.\n\nИзменить можно в настройках AstraGram → «Оформление»."
            : "Other AstraGram users will see an AstraGram badge beside your name, and you beside theirs.\n\nFor this AstraGram connects the AstraGram streak bot (one \"/start\" message goes to its chat) and tells its server your Telegram ID. The server gives the list of IDs with the badge only to AstraGram apps that show the badge too. Your name is not changed.\n\nThe badge proves nothing: do not trust someone because of it alone.\n\nYou can change this in AstraGram settings → Look."
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
