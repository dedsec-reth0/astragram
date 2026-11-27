import Foundation
import UIKit
import TelegramCore

/// "Keyboards": turn AstraGram's keyboard on, pick a theme, get more from the store or from a link.
public final class AstraKeyboardStoreController: UIViewController {
    private let isRussian: Bool
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let enableSwitch = UISwitch()
    private let installedStack = UIStackView()
    private let storeStack = UIStackView()
    private let storeStatus = UILabel()
    private var storeThemes: [AstraKeyboardTheme] = []

    public init(isRussian: Bool) {
        self.isRussian = isRussian
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .pageSheet
        if let sheet = self.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 32.0
        }
        self.overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        let ru = self.isRussian
        self.view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        self.scrollView.alwaysBounceVertical = true
        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.scrollView)
        self.stack.axis = .vertical
        self.stack.spacing = 14.0
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stack)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .bold)), for: .normal)
        close.tintColor = .white
        close.backgroundColor = UIColor(white: 1.0, alpha: 0.12)
        close.layer.cornerRadius = 16.0
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        close.accessibilityLabel = ru ? "Закрыть" : "Close"
        self.view.addSubview(close)

        NSLayoutConstraint.activate([
            self.scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.stack.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 28.0),
            self.stack.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 18.0),
            self.stack.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -18.0),
            self.stack.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -36.0),
            close.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 18.0),
            close.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -18.0),
            close.widthAnchor.constraint(equalToConstant: 32.0),
            close.heightAnchor.constraint(equalToConstant: 32.0)
        ])

        let title = UILabel()
        title.text = ru ? "Клавиатуры" : "Keyboards"
        title.font = UIFont.systemFont(ofSize: 34.0, weight: .heavy)
        title.textColor = .white
        self.stack.addArrangedSubview(title)

        // On/off
        let toggleRow = UIView()
        toggleRow.backgroundColor = UIColor(white: 1.0, alpha: 0.07)
        toggleRow.layer.cornerRadius = 18.0
        toggleRow.layer.cornerCurve = .continuous
        let toggleLabel = UILabel()
        toggleLabel.text = ru ? "Клавиатура AstraGram в чатах" : "AstraGram Keyboard in Chats"
        toggleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        toggleLabel.textColor = .white
        let toggleNote = UILabel()
        toggleNote.text = ru ? "Своя клавиатура с темами в поле сообщения. Кнопка 🌐 меняет язык, ⌨︎ на цифрах — обычная клавиатура iOS (эмодзи, диктовка)." : "A themed keyboard of its own in the message field. 🌐 switches the language; ⌨︎ on the numbers page goes back to the iOS keyboard (emoji, dictation)."
        toggleNote.font = UIFont.systemFont(ofSize: 13.0)
        toggleNote.textColor = UIColor(white: 1.0, alpha: 0.55)
        toggleNote.numberOfLines = 0
        self.enableSwitch.isOn = AstraGramSettings.current.customKeyboard
        self.enableSwitch.onTintColor = UIColor(red: 0.545, green: 0.36, blue: 0.965, alpha: 1.0)
        self.enableSwitch.addTarget(self, action: #selector(self.toggleChanged), for: .valueChanged)
        for view in [toggleLabel, toggleNote, self.enableSwitch] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toggleRow.addSubview(view)
        }
        NSLayoutConstraint.activate([
            toggleLabel.topAnchor.constraint(equalTo: toggleRow.topAnchor, constant: 14.0),
            toggleLabel.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor, constant: 16.0),
            toggleLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.enableSwitch.leadingAnchor, constant: -10.0),
            self.enableSwitch.centerYAnchor.constraint(equalTo: toggleLabel.centerYAnchor),
            self.enableSwitch.trailingAnchor.constraint(equalTo: toggleRow.trailingAnchor, constant: -16.0),
            toggleNote.topAnchor.constraint(equalTo: toggleLabel.bottomAnchor, constant: 6.0),
            toggleNote.leadingAnchor.constraint(equalTo: toggleRow.leadingAnchor, constant: 16.0),
            toggleNote.trailingAnchor.constraint(equalTo: toggleRow.trailingAnchor, constant: -16.0),
            toggleNote.bottomAnchor.constraint(equalTo: toggleRow.bottomAnchor, constant: -14.0)
        ])
        self.stack.addArrangedSubview(toggleRow)

        // Installed
        self.stack.addArrangedSubview(self.header(ru ? "Мои темы" : "My Themes"))
        self.installedStack.axis = .vertical
        self.installedStack.spacing = 14.0
        self.stack.addArrangedSubview(self.installedStack)

        // Store
        let storeHeader = UIStackView()
        storeHeader.axis = .horizontal
        storeHeader.addArrangedSubview(self.header(ru ? "Магазин" : "Store"))
        let link = UIButton(type: .system)
        link.setTitle(ru ? "Добавить по ссылке" : "Add from Link", for: .normal)
        link.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        link.tintColor = UIColor(red: 0.65, green: 0.55, blue: 1.0, alpha: 1.0)
        link.addTarget(self, action: #selector(self.addFromLinkPressed), for: .touchUpInside)
        storeHeader.addArrangedSubview(link)
        self.stack.setCustomSpacing(24.0, after: self.installedStack)
        self.stack.addArrangedSubview(storeHeader)
        self.storeStatus.font = UIFont.systemFont(ofSize: 14.0)
        self.storeStatus.textColor = UIColor(white: 1.0, alpha: 0.5)
        self.storeStatus.numberOfLines = 0
        self.storeStatus.text = ru ? "Загрузка…" : "Loading…"
        self.stack.addArrangedSubview(self.storeStatus)
        self.storeStack.axis = .vertical
        self.storeStack.spacing = 14.0
        self.stack.addArrangedSubview(self.storeStack)

        self.reloadInstalled()
        AstraKeyboardThemes.load(url: AstraKeyboardThemes.storeURL, completion: { [weak self] themes in
            guard let self else {
                return
            }
            self.storeThemes = themes
            self.reloadStore()
        })
    }

    private func header(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        label.textColor = UIColor(white: 1.0, alpha: 0.45)
        return label
    }

    private func reloadInstalled() {
        self.installedStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let selected = AstraGramSettings.current.keyboardThemeId
        let installedIds = Set(AstraKeyboardThemes.installed.map(\.id))
        for theme in AstraKeyboardThemes.all {
            let card = AstraKeyboardThemeCard(theme: theme, isRussian: self.isRussian, mode: theme.id == selected ? .selected : .apply, removable: installedIds.contains(theme.id) && !AstraKeyboardThemes.builtIn.contains(where: { $0.id == theme.id }))
            card.action = { [weak self] in
                UISelectionFeedbackGenerator().selectionChanged()
                AstraGramSettings.update {
                    $0.keyboardThemeId = theme.id
                    $0.customKeyboard = true
                }
                self?.enableSwitch.setOn(true, animated: true)
                self?.reloadInstalled()
            }
            card.remove = { [weak self] in
                AstraKeyboardThemes.remove(id: theme.id)
                if AstraGramSettings.current.keyboardThemeId == theme.id {
                    AstraGramSettings.update { $0.keyboardThemeId = AstraKeyboardThemes.builtIn[0].id }
                }
                self?.reloadInstalled()
                self?.reloadStore()
            }
            self.installedStack.addArrangedSubview(card)
        }
    }

    private func reloadStore() {
        let ru = self.isRussian
        self.storeStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let have = Set(AstraKeyboardThemes.all.map(\.id))
        let available = self.storeThemes.filter { !have.contains($0.id) }
        if self.storeThemes.isEmpty {
            self.storeStatus.text = ru ? "Магазин сейчас недоступен. Тему можно добавить по ссылке на её файл." : "The store is unavailable right now. A theme can be added from a link to its file."
        } else if available.isEmpty {
            self.storeStatus.text = ru ? "Все темы из магазина уже у вас." : "You have every theme from the store."
        } else {
            self.storeStatus.text = ru ? "Новые темы появляются здесь без обновления приложения." : "New themes show up here without an app update."
        }
        for theme in available {
            let card = AstraKeyboardThemeCard(theme: theme, isRussian: ru, mode: .install, removable: false)
            card.action = { [weak self] in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AstraKeyboardThemes.install(theme)
                AstraGramSettings.update {
                    $0.keyboardThemeId = theme.id
                    $0.customKeyboard = true
                }
                self?.enableSwitch.setOn(true, animated: true)
                self?.reloadInstalled()
                self?.reloadStore()
            }
            self.storeStack.addArrangedSubview(card)
        }
    }

    @objc private func toggleChanged() {
        let isOn = self.enableSwitch.isOn
        AstraGramSettings.update { $0.customKeyboard = isOn }
    }

    @objc private func addFromLinkPressed() {
        let ru = self.isRussian
        let alert = UIAlertController(title: ru ? "Тема по ссылке" : "Theme from Link", message: ru ? "Ссылка на файл темы (.json) — из магазина, с сайта или от друга." : "A link to a theme file (.json): from the store, a site or a friend.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://…"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.text = UIPasteboard.general.string.flatMap { $0.hasPrefix("http") ? $0 : nil }
        }
        alert.addAction(UIAlertAction(title: ru ? "Отмена" : "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: ru ? "Загрузить" : "Load", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: text) else {
                return
            }
            AstraKeyboardThemes.load(url: url, completion: { [weak self] themes in
                guard let self else {
                    return
                }
                if themes.isEmpty {
                    let failed = UIAlertController(title: nil, message: ru ? "По этой ссылке нет темы клавиатуры." : "There is no keyboard theme at this link.", preferredStyle: .alert)
                    failed.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(failed, animated: true)
                    return
                }
                for theme in themes {
                    AstraKeyboardThemes.install(theme)
                }
                AstraGramSettings.update {
                    $0.keyboardThemeId = themes[0].id
                    $0.customKeyboard = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.enableSwitch.setOn(true, animated: true)
                self.reloadInstalled()
                self.reloadStore()
            })
        }))
        self.present(alert, animated: true)
    }

    @objc private func closePressed() {
        self.dismiss(animated: true)
    }
}

/// A theme: its keyboard drawn for real (not a picture), its name and author, and a button.
final class AstraKeyboardThemeCard: UIView {
    enum Mode {
        case selected
        case apply
        case install
    }

    var action: (() -> Void)?
    var remove: (() -> Void)?

    init(theme: AstraKeyboardTheme, isRussian ru: Bool, mode: Mode, removable: Bool) {
        super.init(frame: .zero)
        self.backgroundColor = UIColor(white: 1.0, alpha: 0.06)
        self.layer.cornerRadius = 24.0
        self.layer.cornerCurve = .continuous
        self.clipsToBounds = true
        if mode == .selected {
            self.layer.borderWidth = 2.5
            self.layer.borderColor = UIColor.white.cgColor
        }

        let preview = AstraKeyboardView(theme: theme, isPreview: true)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isUserInteractionEnabled = false
        preview.layer.cornerRadius = 16.0
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        self.addSubview(preview)

        let name = UILabel()
        name.text = theme.name
        name.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
        name.textColor = .white
        let author = UILabel()
        author.text = theme.author.map { (ru ? "от " : "by ") + $0 } ?? ""
        author.font = UIFont.systemFont(ofSize: 13.0)
        author.textColor = UIColor(white: 1.0, alpha: 0.5)

        let button = UIButton(type: .system)
        let title: String
        switch mode {
        case .selected: title = ru ? "Выбрана" : "In Use"
        case .apply: title = ru ? "Выбрать" : "Use"
        case .install: title = ru ? "Установить" : "Install"
        }
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15.0, weight: .bold)
        button.setTitleColor(mode == .selected ? .white : .black, for: .normal)
        button.backgroundColor = mode == .selected ? UIColor(white: 1.0, alpha: 0.15) : .white
        button.layer.cornerRadius = 17.0
        button.isEnabled = mode != .selected
        button.addTarget(self, action: #selector(self.buttonPressed), for: .touchUpInside)

        for view in [name, author, button] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(view)
        }
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: self.topAnchor, constant: 10.0),
            preview.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10.0),
            preview.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10.0),
            preview.heightAnchor.constraint(equalToConstant: 190.0),
            name.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 12.0),
            name.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16.0),
            author.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2.0),
            author.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16.0),
            author.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -14.0),
            button.centerYAnchor.constraint(equalTo: name.bottomAnchor, constant: 2.0),
            button.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -14.0),
            button.heightAnchor.constraint(equalToConstant: 34.0),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 104.0)
        ])
        if removable {
            let removeButton = UIButton(type: .system)
            removeButton.setImage(UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold)), for: .normal)
            removeButton.tintColor = UIColor(white: 1.0, alpha: 0.6)
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            removeButton.addTarget(self, action: #selector(self.removePressed), for: .touchUpInside)
            removeButton.accessibilityLabel = ru ? "Удалить тему" : "Remove Theme"
            self.addSubview(removeButton)
            NSLayoutConstraint.activate([
                removeButton.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                removeButton.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8.0),
                removeButton.widthAnchor.constraint(equalToConstant: 34.0),
                removeButton.heightAnchor.constraint(equalToConstant: 34.0)
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func buttonPressed() {
        self.action?()
    }

    @objc private func removePressed() {
        self.remove?()
    }
}
