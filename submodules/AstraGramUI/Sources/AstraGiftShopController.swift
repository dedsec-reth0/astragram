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
        let give = { [weak self] in
            AstraVisualGifts.give(context: context, to: giftTo.id, gift: gift.id, completion: { result in
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
        let alert = UIAlertController(
            title: self.text("Подарить «\(title)»?", "Give \"\(title)\"?"),
            message: linked
                ? self.text("Подарок бесплатный и визуальный: он появится в профиле \(name) с пометкой «AstraGram» и вашим именем, видят его только пользователи AstraGram. В чат с \(name) уйдёт сообщение о подарке.", "The gift is free and visual: it shows on \(name)'s profile with an \"AstraGram\" ribbon and your name, and only AstraGram users see it. A message about the gift goes to your chat with \(name).")
                : self.text("Подарок бесплатный и визуальный: он появится в профиле \(name) с пометкой «AstraGram» и вашим именем. Для этого AstraGram подключит бота огоньков @\(AstraStreakBot.username) (в его чат уйдёт одно сообщение «/start»): серверу уходят ваш Telegram ID, ID \(name) и номер подарка. В чат с \(name) уйдёт сообщение о подарке.", "The gift is free and visual: it shows on \(name)'s profile with an \"AstraGram\" ribbon and your name. For this AstraGram connects the streak bot @\(AstraStreakBot.username) (one \"/start\" goes to its chat): the server gets your Telegram ID, \(name)'s ID and the gift number."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: self.text("Отмена", "Cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: self.text("Подарить", "Give"), style: .default, handler: { _ in
            if linked {
                give()
            } else {
                AstraStreakBot.linkSilently(context: context, completion: { _ in
                    // The bot learns the token from "/start": the gift goes a moment later.
                    Queue.mainQueue().after(5.0, {
                        give()
                    })
                })
            }
        }))
        self.present(alert, animated: true)
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
                "Чтобы другие пользователи AstraGram видели ваши подарки, AstraGram подключит бота огоньков @\(AstraStreakBot.username) (в его чат уйдёт одно сообщение «/start»). Серверу уходят ваш Telegram ID и номера выбранных подарков; он отдаёт их только приложениям AstraGram тех, у кого вы есть в чатах.",
                "For other AstraGram users to see your gifts, AstraGram connects the streak bot @\(AstraStreakBot.username) (one \"/start\" goes to its chat). The server gets your Telegram ID and the chosen gift numbers, and gives them only to the AstraGram apps of people who have you in their chats."
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: self.text("Только у себя", "Only Here"), style: .cancel, handler: { _ in
            save()
        }))
        alert.addAction(UIAlertAction(title: self.text("Показывать", "Show"), style: .default, handler: { _ in
            AstraStreakBot.linkSilently(context: context, completion: { _ in
                // The bot learns the token from "/start": the list goes a moment later.
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

/// The action of a visual gift's screen: take it off one's own profile, or give a gift to the profile's owner.
public func astraVisualGiftAction(context: AccountContext, peerId: EnginePeer.Id, item: ProfileGiftsContext.State.StarGift) -> (title: String, action: () -> Void)? {
    let isRussian = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.astraUsesRussianTexts
    let accountPeerId = context.account.peerId
    if peerId == accountPeerId {
        guard let entry = AstraVisualGifts.entry(accountPeerId: accountPeerId, peerId: peerId, item: item) else {
            return nil
        }
        return (title: isRussian ? "Убрать из профиля" : "Remove from Profile", action: {
            if let received = entry.received {
                AstraVisualGifts.hideReceived(context: context, id: received.id, completion: { _ in })
            } else {
                AstraVisualGifts.removeMine(context: context, gift: entry.gift)
            }
        })
    }
    guard peerId.namespace == Namespaces.Peer.CloudUser else {
        return nil
    }
    return (title: isRussian ? "Подарить бесплатно" : "Give a Free Gift", action: {
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
    })
}
