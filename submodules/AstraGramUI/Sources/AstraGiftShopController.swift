import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ComponentFlow
import GiftItemComponent
import UndoUI

/// AstraGram: the gift shop. Every gift Telegram sells (sold-out ones included) in a grid; the chosen ones go on the
/// user's profile as visual gifts (`AstraVisualGifts`): nothing is bought, and only AstraGram shows them.
final class AstraGiftShopController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let context: AccountContext
    private let presentationData: PresentationData
    private let isRussian: Bool
    private var gifts: [StarGift.Gift] = []
    private var selected: [Int64]
    private var disposable: Disposable?
    private var collectionView: UICollectionView!
    private let headerLabel = UILabel()
    private let emptyLabel = UILabel()
    /// Giving a gift to this person instead of choosing the account's own.
    private let giftTo: EnginePeer?

    init(context: AccountContext, giftTo: EnginePeer? = nil) {
        self.context = context
        self.giftTo = giftTo
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.isRussian = self.presentationData.strings.baseLanguageCode.astraUsesRussianTexts
        self.selected = AstraVisualGifts.mine(accountPeerId: context.account.peerId)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable?.dispose()
    }

    private func text(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let theme = self.presentationData.theme
        self.view.backgroundColor = theme.list.blocksBackgroundColor
        self.title = self.giftTo == nil ? self.text("Магазин подарков", "Gift Shop") : self.text("Подарить", "Give a Gift")
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.text("Отмена", "Cancel"), style: .plain, target: self, action: #selector(self.cancelPressed))
        if self.giftTo == nil {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.text("Готово", "Done"), style: .done, target: self, action: #selector(self.donePressed))
        }

        self.headerLabel.numberOfLines = 0
        self.headerLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.headerLabel.textColor = theme.list.freeTextColor
        self.headerLabel.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.headerLabel)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10.0
        layout.minimumLineSpacing = 10.0
        layout.sectionInset = UIEdgeInsets(top: 8.0, left: 16.0, bottom: 24.0, right: 16.0)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.backgroundColor = .clear
        self.collectionView.alwaysBounceVertical = true
        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.collectionView.register(AstraGiftShopCell.self, forCellWithReuseIdentifier: "gift")
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.collectionView)

        self.emptyLabel.text = self.text("Загружаю подарки…", "Loading gifts…")
        self.emptyLabel.textColor = theme.list.freeTextColor
        self.emptyLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.emptyLabel)

        NSLayoutConstraint.activate([
            self.headerLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 10.0),
            self.headerLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 20.0),
            self.headerLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -20.0),
            self.collectionView.topAnchor.constraint(equalTo: self.headerLabel.bottomAnchor, constant: 6.0),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.emptyLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.emptyLabel.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
        ])
        self.updateHeader()

        // The catalog is kept on the device and refreshed by the app every hour; this asks for a fresh copy as well.
        let _ = self.context.engine.payments.keepStarGiftsUpdated().start()
        self.disposable = (self.context.engine.payments.cachedStarGifts()
        |> deliverOnMainQueue).start(next: { [weak self] gifts in
            guard let self, let gifts else {
                return
            }
            var result: [StarGift.Gift] = []
            for gift in gifts {
                if case let .generic(gift) = gift {
                    result.append(gift)
                }
            }
            self.gifts = result
            self.emptyLabel.isHidden = !result.isEmpty
            if result.isEmpty {
                self.emptyLabel.text = self.text("Каталог подарков пуст", "No gifts in the catalog")
            }
            self.collectionView.reloadData()
        })
    }

    private func updateHeader() {
        if let giftTo = self.giftTo {
            let name = giftTo.compactDisplayTitle
            self.headerLabel.text = self.text(
                "Выберите подарок для \(name). Это бесплатно: подарок появится в профиле \(name) с пометкой «AstraGram» и вашим именем, и увидят его только пользователи AstraGram. \(name) может его убрать.",
                "Choose a gift for \(name). It's free: the gift shows on \(name)'s profile with an \"AstraGram\" ribbon and your name, and only AstraGram users see it. \(name) can take it off."
            )
            return
        }
        self.headerLabel.text = self.text(
            "Выбрано: \(self.selected.count) из \(AstraVisualGifts.maxGifts). Подарки не покупаются: они появятся в вашем профиле с пометкой «AstraGram», и увидят их только пользователи AstraGram.",
            "Chosen: \(self.selected.count) of \(AstraVisualGifts.maxGifts). Gifts are not bought: they show on your profile with an \"AstraGram\" ribbon, and only AstraGram users see them."
        )
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.gifts.count
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - 32.0 - 20.0) / 3.0)
        return CGSize(width: max(60.0, width), height: 154.0)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "gift", for: indexPath) as! AstraGiftShopCell
        let gift = self.gifts[indexPath.item]
        let isSelected = self.selected.contains(gift.id)
        let isSoldOut = gift.soldOut != nil || gift.availability?.remains == 0
        var ribbon: GiftItemComponent.Ribbon?
        if isSelected && self.giftTo == nil {
            ribbon = GiftItemComponent.Ribbon(text: "AstraGram", color: .purple)
        } else if isSoldOut {
            ribbon = GiftItemComponent.Ribbon(text: self.text("распродан", "sold out"), color: .red)
        } else if let availability = gift.availability {
            ribbon = GiftItemComponent.Ribbon(text: self.text("1 из \(availability.total)", "1 of \(availability.total)"), color: .blue)
        }
        let size = self.collectionView(collectionView, layout: collectionView.collectionViewLayout, sizeForItemAt: indexPath)
        cell.update(
            component: GiftItemComponent(
                context: self.context,
                style: .glass,
                theme: self.presentationData.theme,
                strings: self.presentationData.strings,
                peer: nil,
                subject: .starGift(gift: gift, price: "# \(gift.price)"),
                ribbon: ribbon,
                isSelected: self.giftTo == nil && isSelected,
                mode: self.giftTo == nil ? .select : .generic,
                action: { [weak self] in
                    guard let self else {
                        return
                    }
                    if self.giftTo != nil {
                        self.give(gift)
                    } else {
                        self.toggle(gift.id)
                    }
                }
            ),
            size: size
        )
        return cell
    }

    private func give(_ gift: StarGift.Gift) {
        guard let giftTo = self.giftTo else {
            return
        }
        let context = self.context
        let isRussian = self.isRussian
        let name = giftTo.compactDisplayTitle
        let title = gift.title ?? self.text("подарок", "gift")
        let give = { [weak self] (caption: String, anonymous: Bool) in
            AstraVisualGifts.give(context: context, to: giftTo.id, gift: gift.id, text: caption, anonymous: anonymous, completion: { result in
                let text: String
                switch result {
                case .given:
                    AstraHaptics.success()
                    text = isRussian ? "Подарок для \(name) уже в профиле: его видят пользователи AstraGram" : "The gift is on \(name)'s profile: AstraGram users see it"
                    self?.dismiss(animated: true)
                case .limit:
                    text = isRussian ? "На сегодня подарки закончились: можно дарить до 20 в день" : "No more gifts today: up to 20 a day"
                case .failed:
                    text = isRussian ? "Не получилось подарить. Проверьте интернет и попробуйте ещё раз" : "Couldn't give the gift. Check the connection and try again"
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root, blockInteraction: false, completion: {})
            })
        }
        let linked = AstraStreakBot.isLinked(accountPeerId: context.account.peerId)
        astraAskCaption(
            title: self.text("Подарить «\(title)»?", "Give \"\(title)\"?"),
            message: linked
                ? self.text("Подарок бесплатный и визуальный: он появится в профиле \(name) с пометкой «AstraGram», видят его только пользователи AstraGram. Анонимно — ваше имя увидит только \(name). В чат с \(name) уйдёт сообщение о подарке.", "The gift is free and visual: it shows on \(name)'s profile with an \"AstraGram\" ribbon, and only AstraGram users see it. Anonymously — only \(name) sees your name. A message about the gift goes to your chat with \(name).")
                : self.text("Подарок бесплатный и визуальный: он появится в профиле \(name) с пометкой «AstraGram». Для этого AstraGram подключит бота огоньков @\(AstraStreakBot.username) (без сообщений в его чат): серверу уходят ваш Telegram ID, ID \(name), номер подарка и подпись. В чат с \(name) уйдёт сообщение о подарке.", "The gift is free and visual: it shows on \(name)'s profile with an \"AstraGram\" ribbon. For this AstraGram connects the streak bot @\(AstraStreakBot.username) (with no message in its chat): the server gets your Telegram ID, \(name)'s ID, the gift number and the caption."),
            isRussian: isRussian,
            done: { caption, anonymous in
                if linked {
                    give(caption, anonymous)
                } else {
                    AstraStreakBot.linkSilently(context: context, completion: { _ in
                        // The server may take a moment to know the new token: the gift goes a moment later.
                        Queue.mainQueue().after(5.0, {
                            give(caption, anonymous)
                        })
                    })
                }
            }
        )
    }

    private func toggle(_ id: Int64) {
        if let index = self.selected.firstIndex(of: id) {
            self.selected.remove(at: index)
        } else {
            if self.selected.count >= AstraVisualGifts.maxGifts {
                return
            }
            self.selected.append(id)
        }
        AstraHaptics.success()
        self.updateHeader()
        if let index = self.gifts.firstIndex(where: { $0.id == id }) {
            self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
        }
    }

    @objc private func cancelPressed() {
        self.dismiss(animated: true)
    }

    @objc private func donePressed() {
        let context = self.context
        let isRussian = self.isRussian
        let ids = self.selected
        let save = {
            AstraVisualGifts.setMine(context: context, ids: ids, completion: { sent in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let text: String
                if ids.isEmpty {
                    text = isRussian ? "Подарки убраны из профиля" : "Gifts removed from your profile"
                } else if sent {
                    text = isRussian ? "Подарки в профиле: \(ids.count). Их видят пользователи AstraGram" : "Gifts on your profile: \(ids.count). AstraGram users see them"
                } else {
                    text = isRussian ? "Подарки сохранены на этом устройстве. Другие увидят их, когда подключится бот огоньков" : "Saved on this device. Others see them once the streak bot is connected"
                }
                context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root, blockInteraction: false, completion: {})
            })
            self.dismiss(animated: true)
        }
        if AstraStreakBot.isLinked(accountPeerId: context.account.peerId) || ids.isEmpty {
            save()
            return
        }
        // Others see the gifts through the streak bot's server: it is connected once, after saying what it gets.
        let alert = UIAlertController(
            title: self.text("Показать подарки другим?", "Show the gifts to others?"),
            message: self.text(
                "Чтобы другие пользователи AstraGram видели ваши подарки, AstraGram подключит бота огоньков @\(AstraStreakBot.username) (без сообщений в его чат). Серверу уходят ваш Telegram ID и номера выбранных подарков; он отдаёт их только приложениям AstraGram тех, у кого вы есть в чатах.",
                "For other AstraGram users to see your gifts, AstraGram connects the streak bot @\(AstraStreakBot.username) (with no message in its chat). The server gets your Telegram ID and the chosen gift numbers, and gives them only to the AstraGram apps of people who have you in their chats."
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: self.text("Только у себя", "Only Here"), style: .cancel, handler: { _ in
            save()
        }))
        alert.addAction(UIAlertAction(title: self.text("Показывать", "Show"), style: .default, handler: { _ in
            AstraStreakBot.linkSilently(context: context, completion: { _ in
                // The server may take a moment to know the new token: the list goes a moment later.
                Queue.mainQueue().after(5.0, {
                    save()
                })
            })
        }))
        self.present(alert, animated: true)
    }
}

private final class AstraGiftShopCell: UICollectionViewCell {
    private let item = ComponentView<Empty>()

    func update(component: GiftItemComponent, size: CGSize) {
        let itemSize = self.item.update(
            transition: .immediate,
            component: AnyComponent(component),
            environment: {},
            containerSize: size
        )
        if let view = self.item.view {
            if view.superview == nil {
                self.contentView.addSubview(view)
            }
            view.frame = CGRect(origin: CGPoint(x: floor((size.width - itemSize.width) / 2.0), y: 0.0), size: itemSize)
        }
    }
}

/// Opens the gift shop over the app: the account's own gifts, or a gift for `giftTo`.
public func astraOpenGiftShop(context: AccountContext, giftTo: EnginePeer? = nil) {
    guard let top = astraTopViewController() else {
        return
    }
    let navigation = UINavigationController(rootViewController: AstraGiftShopController(context: context, giftTo: giftTo))
    navigation.modalPresentationStyle = .pageSheet
    top.present(navigation, animated: true)
}

/// The action of a visual gift's screen: on one's own profile, a menu with what Telegram's own gifts can do (upgrade,
/// wear, pin, hide, pass on, remove); on someone else's, giving them a gift. `push` shows a screen (picking whom to pass
/// the gift to), `open` the gift's screen again (after an upgrade, to show what it became).
public struct AstraVisualGiftAction {
    public let title: String
    public let action: () -> Void
    /// The gift's screen offers wearing it (one's own gifts).
    public let wear: (() -> Void)?
    public let isWorn: Bool
    public let setHidden: ((Bool) -> Void)?
    /// The "…" menu of one's own gift: (title, icon, destructive, action).
    public var menu: [(title: String, icon: String, isDestructive: Bool, action: () -> Void)] = []
    /// A free upgrade, revealed with Telegram's upgrade animation: the gift's item as a unique one, or nil.
    public var upgrade: (() -> Signal<ProfileGiftsContext.State.StarGift?, NoError>)?
}

public func astraVisualGiftAction(context: AccountContext, peerId: EnginePeer.Id, item: ProfileGiftsContext.State.StarGift, push: @escaping (ViewController) -> Void = { _ in }, open: @escaping (ProfileGiftsContext.State.StarGift) -> Void = { _ in }) -> AstraVisualGiftAction? {
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    let accountPeerId = context.account.peerId
    if peerId == accountPeerId {
        guard let entry = AstraVisualGifts.entry(accountPeerId: accountPeerId, peerId: peerId, item: item) else {
            return nil
        }
        let isWorn = AstraVisualGifts.wornEntry(context: context)?.ref == entry.ref
        func text(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }
        // After the gift's screen has gone.
        let later: (@escaping () -> Void) -> () -> Void = { f in
            return {
                Queue.mainQueue().after(0.4, f)
            }
        }
        var action = AstraVisualGiftAction(title: entry.meta.unique == nil ? text("Улучшить бесплатно", "Upgrade for Free") : text("Готово", "Done"), action: {}, wear: later {
            astraWearVisualGift(context: context, entry: isWorn ? nil : entry)
        }, isWorn: isWorn, setHidden: { hidden in
            AstraVisualGifts.setHidden(context: context, entry: entry, hidden: hidden, completion: { result in
                if case .done = result {
                    astraToast(context: context, hidden ? text("Подарок скрыт: его видите только вы", "The gift is hidden: only you see it") : text("Подарок снова виден в профиле", "The gift shows on your profile again"))
                } else {
                    astraChangeFailed(context: context, result, isRussian: isRussian)
                }
            })
        })
        var menu: [(title: String, icon: String, isDestructive: Bool, action: () -> Void)] = []
        menu.append((isWorn ? text("Снять", "Take Off") : text("Носить", "Wear"), isWorn ? "Premium/Collectible/Unwear" : "Premium/Collectible/Wear", false, later {
            astraWearVisualGift(context: context, entry: isWorn ? nil : entry)
        }))
        if !entry.meta.isHidden {
            menu.append((entry.meta.isPinned ? text("Открепить", "Unpin") : text("Закрепить", "Pin"), entry.meta.isPinned ? "Chat/Context Menu/Unpin" : "Chat/Context Menu/Pin", false, later {
                AstraVisualGifts.setPinned(context: context, entry: entry, pinned: !entry.meta.isPinned, completion: { result in
                    astraChangeFailed(context: context, result, isRussian: isRussian)
                })
            }))
        }
        menu.append((entry.meta.isHidden ? text("Показать в профиле", "Show on Profile") : text("Скрыть из профиля", "Hide from Profile"), entry.meta.isHidden ? "Peer Info/ShowIcon" : "Peer Info/HideIcon", false, later {
            action.setHidden?(!entry.meta.isHidden)
        }))
        // The admin picks the upgrade's model, pattern, backdrop and number by hand.
        if AstraVisualGifts.isAdmin(accountPeerId) {
            menu.append((text("Улучшить с выбором (админ)", "Upgrade by Choice (Admin)"), "Chat/Context Menu/Edit", false, later {
                astraAdminUpgrade(context: context, entry: entry)
            }))
        }
        menu.append((text("Передать", "Transfer"), "Chat/Context Menu/Replace", false, later {
            astraTransferVisualGift(context: context, entry: entry, push: push)
        }))
        menu.append((text("Убрать навсегда", "Remove for Good"), "Chat/Context Menu/Delete", true, later {
            if let received = entry.received {
                AstraVisualGifts.hideReceived(context: context, id: received.id, completion: { _ in })
            } else {
                AstraVisualGifts.removeMine(context: context, gift: entry.gift)
            }
        }))
        action.menu = menu
        let fromPeer = item.fromPeer
        action.upgrade = {
            return Signal { subscriber in
                AstraVisualGifts.upgrade(context: context, entry: entry, completion: { result in
                    guard case let .upgraded(look) = result else {
                        if case .notUpgradable = result {
                            astraToast(context: context, text("У этого подарка в Telegram нет уникальных версий", "Telegram has no unique versions of this gift"))
                        } else {
                            astraToast(context: context, text("Не получилось улучшить. Проверьте интернет и попробуйте ещё раз", "Couldn't upgrade. Check the connection and try again"))
                        }
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    AstraHaptics.success()
                    let _ = (combineLatest(
                        context.engine.payments.cachedStarGifts() |> filter { $0 != nil } |> take(1),
                        AstraVisualGifts.attributes(context: context, giftIds: [entry.gift])
                    )
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { catalog, attributes in
                        var updated = entry
                        updated.meta.unique = look
                        for gift in catalog ?? [] {
                            if case let .generic(gift) = gift, gift.id == entry.gift, let unique = AstraVisualGifts.uniqueGift(gift: gift, look: look, attributes: attributes[entry.gift] ?? [], ownerPeerId: accountPeerId) {
                                subscriber.putNext(AstraVisualGifts.item(gift: gift, entry: updated, fromPeer: fromPeer, unique: unique))
                                subscriber.putCompletion()
                                return
                            }
                        }
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    })
                })
                return EmptyDisposable
            }
        }
        return action
    }
    guard peerId.namespace == Namespaces.Peer.CloudUser else {
        return nil
    }
    return AstraVisualGiftAction(title: isRussian ? "Подарить бесплатно" : "Give a Free Gift", action: {
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer else {
                return
            }
            // After the gift's screen has gone.
            Queue.mainQueue().after(0.4, {
                astraOpenGiftShop(context: context, giftTo: peer)
            })
        })
    }, wear: nil, isWorn: false, setHidden: nil)
}

/// The admin's upgrade: one Telegram sheet after another (model, pattern, backdrop with their rarity), then the number.
private func astraAdminUpgrade(context: AccountContext, entry: AstraVisualGifts.Entry) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let russian = presentationData.strings.baseLanguageCode.astraUsesRussianTexts
    func present(_ controller: ViewController) {
        context.sharedContext.mainWindow?.present(controller, on: .root, blockInteraction: false, completion: {})
    }
    func rarityText(_ rarity: StarGift.UniqueGift.Attribute.Rarity) -> String {
        switch rarity {
        case let .permille(value):
            return String(format: "%.1f%%", Double(value) / 10.0)
        case .uncommon:
            return russian ? "необычный" : "uncommon"
        case .rare:
            return russian ? "редкий" : "rare"
        case .epic:
            return russian ? "эпический" : "epic"
        case .legendary:
            return russian ? "легендарный" : "legendary"
        }
    }
    func choose(_ title: String, _ items: [(String, String)], _ done: @escaping (String) -> Void) {
        let sheet = ActionSheetController(presentationData: presentationData)
        var buttons: [ActionSheetItem] = [ActionSheetTextItem(title: title)]
        for (name, rarity) in items {
            buttons.append(ActionSheetButtonItem(title: "\(name) · \(rarity)", color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                done(name)
            }))
        }
        sheet.setItemGroups([ActionSheetItemGroup(items: buttons), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })
        ])])
        present(sheet)
    }
    let _ = (context.engine.payments.getStarGiftUpgradeAttributes(giftId: entry.gift)
    |> take(1)
    |> deliverOnMainQueue).start(next: { attributes in
        var models: [(String, String)] = []
        var patterns: [(String, String)] = []
        var backdrops: [(String, String)] = []
        for attribute in attributes ?? [] {
            switch attribute {
            case let .model(name, _, rarity, crafted):
                if !crafted {
                    models.append((name, rarityText(rarity)))
                }
            case let .pattern(name, _, rarity):
                patterns.append((name, rarityText(rarity)))
            case let .backdrop(name, _, _, _, _, _, rarity):
                backdrops.append((name, rarityText(rarity)))
            case .originalInfo:
                break
            }
        }
        guard !models.isEmpty, !patterns.isEmpty, !backdrops.isEmpty else {
            astraToast(context: context, russian ? "У этого подарка в Telegram нет уникальных версий" : "Telegram has no unique versions of this gift")
            return
        }
        choose(russian ? "Модель" : "Model", models, { model in
            Queue.mainQueue().after(0.35, {
                choose(russian ? "Узор" : "Pattern", patterns, { pattern in
                    Queue.mainQueue().after(0.35, {
                        choose(russian ? "Фон" : "Backdrop", backdrops, { backdrop in
                            Queue.mainQueue().after(0.35, {
                                let alert = UIAlertController(title: russian ? "Номер подарка" : "Gift Number", message: russian ? "Пусто — следующий по счёту" : "Empty: the next one", preferredStyle: .alert)
                                alert.addTextField { field in
                                    field.keyboardType = .numberPad
                                    field.placeholder = "#"
                                }
                                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                                alert.addAction(UIAlertAction(title: russian ? "Улучшить" : "Upgrade", style: .default, handler: { [weak alert] _ in
                                    let number = alert?.textFields?.first?.text.flatMap { Int32($0) }.flatMap { $0 > 0 ? $0 : nil }
                                    AstraVisualGifts.upgradeChosen(context: context, entry: entry, model: model, pattern: pattern, backdrop: backdrop, number: number, completion: { result in
                                        if case let .upgraded(look) = result {
                                            AstraHaptics.success()
                                            astraToast(context: context, "\(look.model) · \(look.pattern) · \(look.backdrop) #\(look.number)")
                                        } else {
                                            astraToast(context: context, russian ? "Не получилось улучшить" : "Couldn't upgrade")
                                        }
                                    })
                                }))
                                astraTopViewController()?.present(alert, animated: true)
                            })
                        })
                    })
                })
            })
        })
    })
}

private func astraToast(context: AccountContext, _ text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), on: .root, blockInteraction: false, completion: {})
}

private func astraPresent(_ controller: UIViewController) {
    guard let top = astraTopViewController() else {
        return
    }
    // iOS 26 draws an action sheet with a source as a narrow popover even on an iPhone: a source only on an iPad.
    if UIDevice.current.userInterfaceIdiom == .pad, let popover = controller.popoverPresentationController {
        popover.sourceView = top.view
        popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60.0, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    top.present(controller, animated: true)
}

/// A failed change of a gift, said in a toast.
private func astraChangeFailed(context: AccountContext, _ result: AstraVisualGifts.ChangeResult, isRussian: Bool) {
    switch result {
    case .done:
        break
    case .limit:
        astraToast(context: context, isRussian ? "На сегодня подарки закончились: можно дарить до 20 в день" : "No more gifts today: up to 20 a day")
    case .pinLimit:
        astraToast(context: context, isRussian ? "Закрепить можно не больше \(AstraVisualGifts.maxPinned) подарков" : "You can pin up to \(AstraVisualGifts.maxPinned) gifts")
    case .failed:
        astraToast(context: context, isRussian ? "Не получилось. Проверьте интернет и попробуйте ещё раз" : "Couldn't do it. Check the connection and try again")
    }
}

private func astraWearVisualGift(context: AccountContext, entry: AstraVisualGifts.Entry?) {
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    AstraVisualGifts.wear(context: context, entry: entry, completion: { result in
        guard case .done = result else {
            astraChangeFailed(context: context, result, isRussian: isRussian)
            return
        }
        if entry == nil {
            astraToast(context: context, isRussian ? "Подарок снят" : "The gift is off")
            return
        }
        AstraHaptics.success()
        // What people without AstraGram see is the account's own Telegram status, set apart from the gift.
        let alert = UIAlertController(
            title: isRussian ? "Подарок надет" : "Gift On",
            message: isRussian
                ? "Пользователи AstraGram видят этот подарок рядом с вашим именем. Остальные видят ваш обычный статус Telegram — его можно выбрать отдельно: нажмите на статус рядом со своим именем в профиле или в списке чатов."
                : "AstraGram users see this gift beside your name. Everyone else sees your own Telegram status — pick it separately: tap the status beside your name on your profile or in the chat list.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        astraPresent(alert)
    })
}

/// Asks for a caption and whether to hide the giver's name, then calls `done`.
private func astraAskCaption(title: String, message: String, isRussian: Bool, done: @escaping (_ text: String, _ anonymous: Bool) -> Void) {
    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
    alert.addTextField { field in
        field.placeholder = isRussian ? "Подпись (необязательно)" : "Caption (optional)"
        field.autocapitalizationType = .sentences
    }
    let text = { () -> String in
        return String((alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(255))
    }
    alert.addAction(UIAlertAction(title: isRussian ? "От своего имени" : "With My Name", style: .default, handler: { _ in
        done(text(), false)
    }))
    alert.addAction(UIAlertAction(title: isRussian ? "Анонимно" : "Anonymously", style: .default, handler: { _ in
        done(text(), true)
    }))
    alert.addAction(UIAlertAction(title: isRussian ? "Отмена" : "Cancel", style: .cancel, handler: nil))
    astraPresent(alert)
}

private func astraTransferVisualGift(context: AccountContext, entry: AstraVisualGifts.Entry, push: @escaping (ViewController) -> Void) {
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyPrivateChats, .excludeBots, .excludeSavedMessages, .excludeSecretChats, .excludeRecent, .doNotSearchMessages], hasContactSelector: false, title: isRussian ? "Передать подарок" : "Transfer Gift"))
    controller.peerSelected = { [weak controller] peer, _ in
        controller?.dismiss()
        // A person, not a bot or Telegram's service account.
        guard case let .user(user) = peer, user.botInfo == nil, peer.id != context.account.peerId, peer.id.id._internalGetInt64Value() != 777000 else {
            return
        }
        let name = peer.compactDisplayTitle
        Queue.mainQueue().after(0.4, {
            astraAskCaption(
                title: isRussian ? "Передать подарок \(name)?" : "Transfer the gift to \(name)?",
                message: isRussian ? "Подарок уйдёт из вашего профиля в профиль \(name) вместе с улучшением. В чат с \(name) уйдёт сообщение о подарке." : "The gift leaves your profile for \(name)'s, with its upgrade. A message about it goes to your chat with \(name).",
                isRussian: isRussian,
                done: { text, anonymous in
                    AstraVisualGifts.transfer(context: context, entry: entry, to: peer.id, text: text, anonymous: anonymous, completion: { result in
                        if case .done = result {
                            AstraHaptics.success()
                            astraToast(context: context, isRussian ? "Подарок передан \(name)" : "The gift went to \(name)")
                        } else {
                            astraChangeFailed(context: context, result, isRussian: isRussian)
                        }
                    })
                }
            )
        })
    }
    push(controller)
}
