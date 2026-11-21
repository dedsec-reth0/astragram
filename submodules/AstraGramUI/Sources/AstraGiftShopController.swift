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

    init(context: AccountContext) {
        self.context = context
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
        self.title = self.text("Магазин подарков", "Gift Shop")
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: self.text("Отмена", "Cancel"), style: .plain, target: self, action: #selector(self.cancelPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.text("Готово", "Done"), style: .done, target: self, action: #selector(self.donePressed))

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
        if isSelected {
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
                isSelected: isSelected,
                mode: .select,
                action: { [weak self] in
                    self?.toggle(gift.id)
                }
            ),
            size: size
        )
        return cell
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

/// Opens the gift shop over the app.
public func astraOpenGiftShop(context: AccountContext) {
    guard let top = astraTopViewController() else {
        return
    }
    let navigation = UINavigationController(rootViewController: AstraGiftShopController(context: context))
    navigation.modalPresentationStyle = .pageSheet
    top.present(navigation, animated: true)
}
