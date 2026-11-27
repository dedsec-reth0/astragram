import Foundation
import UIKit
import TelegramCore

/// The keyboard look AstraGram asks iOS for (Settings → AstraGram → Appearance): iOS draws the keyboard itself, so an
/// app can choose only between its light and dark styles.
public enum AstraKeyboardStyle: Int, CaseIterable {
    case theme = 0
    case dark = 1
    case light = 2

    public func title(isRussian ru: Bool) -> String {
        switch self {
        case .theme: return ru ? "Как тема" : "Like Theme"
        case .dark: return ru ? "Тёмная" : "Dark"
        case .light: return ru ? "Светлая" : "Light"
        }
    }
}

/// "Effects and keyboard": cards with live previews of each screen effect, the amount, and the keyboard look.
/// Choices apply at once; the overlay behind the sheet shows them.
public final class AstraEffectsPickerController: UIViewController {
    private let isRussian: Bool
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var effectCards: [AstraScreenEffect: AstraEffectCardView] = [:]
    private var keyboardCards: [AstraKeyboardStyle: AstraKeyboardCardView] = [:]
    private let intensityControl = UISegmentedControl()

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

        // Title
        let title = UILabel()
        title.text = ru ? "Эффекты" : "Effects"
        title.font = UIFont.systemFont(ofSize: 34.0, weight: .heavy)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = ru ? "Падают в чатах, поверх сообщений, и не мешают нажатиям. В режиме энергосбережения отключаются сами." : "They drift over the messages in chats and never get in the way of taps. Low Power Mode pauses them."
        subtitle.font = UIFont.systemFont(ofSize: 15.0)
        subtitle.textColor = UIColor(white: 1.0, alpha: 0.6)
        subtitle.numberOfLines = 0
        self.stack.addArrangedSubview(title)
        self.stack.setCustomSpacing(6.0, after: title)
        self.stack.addArrangedSubview(subtitle)
        self.stack.setCustomSpacing(20.0, after: subtitle)

        // Effect cards, two per row.
        let effects = AstraScreenEffect.allCases
        var index = 0
        while index < effects.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 12.0
            row.distribution = .fillEqually
            for effect in effects[index ..< min(index + 2, effects.count)] {
                let card = AstraEffectCardView(effect: effect, isRussian: ru)
                card.addTarget(self, action: #selector(self.effectCardPressed(_:)), for: .touchUpInside)
                self.effectCards[effect] = card
                row.addArrangedSubview(card)
            }
            row.heightAnchor.constraint(equalToConstant: 156.0).isActive = true
            self.stack.addArrangedSubview(row)
            index += 2
        }

        // Amount
        let amountHeader = self.sectionHeader(ru ? "Сколько" : "Amount")
        self.stack.setCustomSpacing(26.0, after: self.stack.arrangedSubviews.last!)
        self.stack.addArrangedSubview(amountHeader)
        for (i, name) in (ru ? ["Тихо", "Средне", "Много"] : ["Light", "Medium", "Heavy"]).enumerated() {
            self.intensityControl.insertSegment(withTitle: name, at: i, animated: false)
        }
        self.intensityControl.selectedSegmentTintColor = UIColor(white: 1.0, alpha: 0.22)
        self.intensityControl.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 15.0, weight: .semibold)], for: .normal)
        self.intensityControl.addTarget(self, action: #selector(self.intensityChanged), for: .valueChanged)
        self.intensityControl.heightAnchor.constraint(equalToConstant: 40.0).isActive = true
        self.stack.addArrangedSubview(self.intensityControl)

        self.updateSelection(animated: false)
    }

    private func sectionHeader(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        label.textColor = UIColor(white: 1.0, alpha: 0.45)
        return label
    }

    private func updateSelection(animated: Bool) {
        let settings = AstraGramSettings.current
        for (effect, card) in self.effectCards {
            card.setSelected(effect.rawValue == settings.screenEffect, animated: animated)
        }
        for (style, card) in self.keyboardCards {
            card.setSelected(style.rawValue == settings.keyboardStyle, animated: animated)
        }
        self.intensityControl.selectedSegmentIndex = max(0, min(2, settings.screenEffectIntensity))
        self.intensityControl.isEnabled = settings.screenEffect != AstraScreenEffect.off.rawValue
        self.intensityControl.alpha = self.intensityControl.isEnabled ? 1.0 : 0.4
    }

    @objc private func effectCardPressed(_ sender: AstraEffectCardView) {
        UISelectionFeedbackGenerator().selectionChanged()
        if sender.effect == .custom {
            // The user's own effect opens its designer; it is turned on from there.
            let designer = AstraCustomEffectController(isRussian: self.isRussian)
            designer.onApply = { [weak self] in
                self?.effectCards[.custom]?.refreshPreview()
                self?.updateSelection(animated: true)
            }
            self.present(designer, animated: true)
            return
        }
        AstraGramSettings.update { $0.screenEffect = sender.effect.rawValue }
        self.updateSelection(animated: true)
    }

    @objc private func keyboardCardPressed(_ sender: AstraKeyboardCardView) {
        UISelectionFeedbackGenerator().selectionChanged()
        AstraGramSettings.update { $0.keyboardStyle = sender.style.rawValue }
        self.updateSelection(animated: true)
    }

    @objc private func intensityChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
        let value = self.intensityControl.selectedSegmentIndex
        AstraGramSettings.update { $0.screenEffectIntensity = value }
    }

    @objc private func closePressed() {
        self.dismiss(animated: true)
    }
}

/// A card: a gradient, a live preview of the effect, its name, and a ring when chosen.
final class AstraEffectCardView: UIControl {
    let effect: AstraScreenEffect
    private let gradient = CAGradientLayer()
    private let emitter = CAEmitterLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let check = UIImageView()
    private var configuredSize: CGSize = .zero

    private let isRussianValue: Bool

    init(effect: AstraScreenEffect, isRussian: Bool) {
        self.effect = effect
        self.isRussianValue = isRussian
        super.init(frame: .zero)
        self.layer.cornerRadius = 24.0
        self.layer.cornerCurve = .continuous
        self.clipsToBounds = true

        self.gradient.colors = effect.cardColors.map { $0.cgColor }
        self.gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradient.endPoint = CGPoint(x: 0.6, y: 1.0)
        self.layer.addSublayer(self.gradient)
        self.layer.addSublayer(self.emitter)

        self.titleLabel.text = effect.title(isRussian: isRussian)
        self.titleLabel.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
        self.titleLabel.textColor = .white
        self.subtitleLabel.text = effect.subtitle(isRussian: isRussian)
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.check.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22.0, weight: .semibold))
        self.check.tintColor = .white
        for view in [self.titleLabel, self.subtitleLabel, self.check] as [UIView] {
            view.isUserInteractionEnabled = false
            self.addSubview(view)
        }
        if effect == .off {
            let icon = UIImageView(image: UIImage(systemName: "nosign", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34.0, weight: .light)))
            icon.tintColor = UIColor(white: 1.0, alpha: 0.35)
            icon.isUserInteractionEnabled = false
            icon.tag = 1
            self.addSubview(icon)
        }
        self.isAccessibilityElement = true
        self.accessibilityLabel = effect.title(isRussian: isRussian)
        self.accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Redraws the card's effect (the custom one changes with its settings).
    func refreshPreview() {
        self.configuredSize = .zero
        self.subtitleLabel.text = self.effect.subtitle(isRussian: self.isRussianValue)
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = self.bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradient.frame = self.bounds
        self.emitter.frame = self.bounds
        CATransaction.commit()
        if self.configuredSize != size {
            self.configuredSize = size
            // The phone screen's density, by area, at two thirds the size: a card shows a few, not a blizzard.
            let density = Float(max(0.35, (size.width * size.height) / (390.0 * 844.0) * 5.0))
            astraConfigureEmitter(self.emitter, effect: self.effect, size: size, density: density, particleScale: 0.7)
            self.emitter.beginTime = CACurrentMediaTime() - CFTimeInterval(size.height / 25.0)
        }
        self.titleLabel.frame = CGRect(x: 14.0, y: size.height - 50.0, width: size.width - 28.0, height: 24.0)
        self.subtitleLabel.frame = CGRect(x: 14.0, y: size.height - 27.0, width: size.width - 28.0, height: 16.0)
        self.check.frame = CGRect(x: size.width - 36.0, y: 12.0, width: 24.0, height: 24.0)
        if let icon = self.viewWithTag(1) {
            icon.frame = CGRect(x: (size.width - 40.0) / 2.0, y: (size.height - 40.0) / 2.0 - 16.0, width: 40.0, height: 40.0)
        }
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let update = {
            self.layer.borderWidth = selected ? 2.5 : 0.0
            self.layer.borderColor = UIColor.white.cgColor
            self.check.alpha = selected ? 1.0 : 0.0
            self.check.transform = selected ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [.beginFromCurrentState], animations: update)
        } else {
            update()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.25, delay: 0.0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            })
        }
    }
}

/// A card with a drawn miniature keyboard in the style it chooses.
final class AstraKeyboardCardView: UIControl {
    let style: AstraKeyboardStyle
    private let keyboard = UIView()
    private let titleLabel = UILabel()
    private let check = UIImageView()

    init(style: AstraKeyboardStyle, isRussian: Bool) {
        self.style = style
        super.init(frame: .zero)
        self.layer.cornerRadius = 20.0
        self.layer.cornerCurve = .continuous
        self.backgroundColor = UIColor(white: 1.0, alpha: 0.07)
        self.clipsToBounds = true
        self.keyboard.isUserInteractionEnabled = false
        self.keyboard.layer.cornerRadius = 10.0
        self.keyboard.layer.cornerCurve = .continuous
        self.keyboard.clipsToBounds = true
        self.addSubview(self.keyboard)
        self.titleLabel.text = style.title(isRussian: isRussian)
        self.titleLabel.font = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.addSubview(self.titleLabel)
        self.check.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold))
        self.check.tintColor = .white
        self.check.isUserInteractionEnabled = false
        self.addSubview(self.check)
        self.isAccessibilityElement = true
        self.accessibilityLabel = style.title(isRussian: isRussian)
        self.accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = self.bounds.size
        let keyboardFrame = CGRect(x: 10.0, y: 12.0, width: size.width - 20.0, height: size.height - 48.0)
        self.keyboard.frame = keyboardFrame
        self.titleLabel.frame = CGRect(x: 4.0, y: size.height - 30.0, width: size.width - 8.0, height: 20.0)
        self.check.frame = CGRect(x: size.width - 26.0, y: 6.0, width: 20.0, height: 20.0)
        self.drawKeys(in: keyboardFrame.size)
    }

    private func drawKeys(in size: CGSize) {
        self.keyboard.subviews.forEach { $0.removeFromSuperview() }
        let dark: Bool
        switch self.style {
        case .dark: dark = true
        case .light: dark = false
        case .theme: dark = self.traitCollection.userInterfaceStyle != .light
        }
        // "Like theme" shows both halves: its card is split diagonally between the two looks.
        let split = self.style == .theme
        self.keyboard.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1.0) : UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1.0)
        let rows: [Int] = [7, 6, 5]
        let gap: CGFloat = 3.0
        let keyHeight = (size.height - gap * 5.0) / 4.0
        for (rowIndex, count) in rows.enumerated() {
            let keyWidth = (size.width - gap * CGFloat(8)) / 7.0
            let rowWidth = keyWidth * CGFloat(count) + gap * CGFloat(count - 1)
            let x0 = (size.width - rowWidth) / 2.0
            for i in 0 ..< count {
                let key = UIView(frame: CGRect(x: x0 + CGFloat(i) * (keyWidth + gap), y: gap + CGFloat(rowIndex) * (keyHeight + gap), width: keyWidth, height: keyHeight))
                key.layer.cornerRadius = 2.5
                let keyDark = split ? (key.frame.midX / size.width + key.frame.midY / size.height) > 1.0 : dark
                key.backgroundColor = keyDark ? UIColor(white: 0.42, alpha: 1.0) : .white
                self.keyboard.addSubview(key)
            }
        }
        let space = UIView(frame: CGRect(x: size.width * 0.22, y: gap + 3.0 * (keyHeight + gap), width: size.width * 0.56, height: keyHeight))
        space.layer.cornerRadius = 2.5
        space.backgroundColor = (split ? true : dark) ? UIColor(white: 0.42, alpha: 1.0) : .white
        self.keyboard.addSubview(space)
        if split {
            let mask = CAShapeLayer()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: size.width, y: 0.0))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0.0, y: size.height))
            path.close()
            mask.path = path.cgPath
            let darkHalf = CALayer()
            darkHalf.frame = CGRect(origin: .zero, size: size)
            darkHalf.backgroundColor = UIColor(white: 0.17, alpha: 1.0).cgColor
            darkHalf.mask = mask
            self.keyboard.backgroundColor = UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1.0)
            self.keyboard.layer.insertSublayer(darkHalf, at: 0)
        }
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let update = {
            self.layer.borderWidth = selected ? 2.0 : 0.0
            self.layer.borderColor = UIColor.white.cgColor
            self.check.alpha = selected ? 1.0 : 0.0
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: update)
        } else {
            update()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
            })
        }
    }
}
