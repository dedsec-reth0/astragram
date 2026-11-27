import Foundation
import UIKit
import TelegramCore

/// "Your own effect": any emoji or characters fall (or rise) in chats; size, speed, wind and spin are the user's.
/// A big live preview follows every change.
final class AstraCustomEffectController: UIViewController, UITextFieldDelegate {
    private let isRussian: Bool
    private let preview = UIView()
    private let previewGradient = CAGradientLayer()
    private let emitter = CAEmitterLayer()
    private let symbolsField = UITextField()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private static let presets: [String] = ["❄️", "🌸", "🍁", "💜", "⭐️", "✨", "🎃", "🎄", "🔥", "💸", "🦋", "🫧", "❤️‍🔥", "🍀", "👻", "🌙"]

    /// Called after "Use in Chats" closed the screen.
    var onApply: (() -> Void)?

    init(isRussian: Bool) {
        self.isRussian = isRussian
        super.init(nibName: nil, bundle: nil)
        self.overrideUserInterfaceStyle = .dark
        self.modalPresentationStyle = .pageSheet
        if let sheet = self.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 32.0
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let ru = self.isRussian
        let settings = AstraGramSettings.current
        self.view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)

        // Preview, pinned on top.
        self.preview.layer.cornerRadius = 28.0
        self.preview.layer.cornerCurve = .continuous
        self.preview.clipsToBounds = true
        self.previewGradient.colors = [UIColor(red: 0.12, green: 0.11, blue: 0.29, alpha: 1.0).cgColor, UIColor(red: 0.3, green: 0.13, blue: 0.45, alpha: 1.0).cgColor]
        self.preview.layer.addSublayer(self.previewGradient)
        self.preview.layer.addSublayer(self.emitter)
        // Two fake message bubbles, so the effect is seen over a chat.
        for (index, text) in [(ru ? "Смотри, как красиво ✨" : "Look how pretty ✨"), (ru ? "Это мой эффект!" : "That's my effect!")].enumerated() {
            let bubble = UILabel()
            bubble.text = "  \(text)  "
            bubble.font = UIFont.systemFont(ofSize: 15.0)
            bubble.textColor = .white
            bubble.backgroundColor = index == 0 ? UIColor(white: 1.0, alpha: 0.16) : UIColor(red: 0.49, green: 0.3, blue: 0.95, alpha: 1.0)
            bubble.layer.cornerRadius = 16.0
            bubble.clipsToBounds = true
            bubble.tag = 100 + index
            self.preview.addSubview(bubble)
        }
        self.preview.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.preview)

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.keyboardDismissMode = .onDrag
        self.view.addSubview(self.scrollView)
        self.stack.axis = .vertical
        self.stack.spacing = 12.0
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stack)

        NSLayoutConstraint.activate([
            self.preview.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 24.0),
            self.preview.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16.0),
            self.preview.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16.0),
            self.preview.heightAnchor.constraint(equalToConstant: 250.0),
            self.scrollView.topAnchor.constraint(equalTo: self.preview.bottomAnchor, constant: 8.0),
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.stack.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 12.0),
            self.stack.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 18.0),
            self.stack.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -18.0),
            self.stack.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -36.0)
        ])

        // Symbols
        self.stack.addArrangedSubview(self.header(ru ? "Что падает (до 3 эмодзи или символов)" : "What falls (up to 3 emoji or characters)"))
        self.symbolsField.text = settings.customEffectSymbols
        self.symbolsField.font = UIFont.systemFont(ofSize: 30.0)
        self.symbolsField.textAlignment = .center
        self.symbolsField.textColor = .white
        self.symbolsField.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.symbolsField.layer.cornerRadius = 16.0
        self.symbolsField.delegate = self
        self.symbolsField.returnKeyType = .done
        self.symbolsField.addTarget(self, action: #selector(self.symbolsChanged), for: .editingChanged)
        self.symbolsField.heightAnchor.constraint(equalToConstant: 56.0).isActive = true
        self.stack.addArrangedSubview(self.symbolsField)

        let presets = UIScrollView()
        presets.showsHorizontalScrollIndicator = false
        let presetRow = UIStackView()
        presetRow.axis = .horizontal
        presetRow.spacing = 8.0
        presetRow.translatesAutoresizingMaskIntoConstraints = false
        presets.addSubview(presetRow)
        for symbol in AstraCustomEffectController.presets {
            let button = UIButton(type: .system)
            button.setTitle(symbol, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 26.0)
            button.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            button.layer.cornerRadius = 22.0
            button.widthAnchor.constraint(equalToConstant: 44.0).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
            button.addTarget(self, action: #selector(self.presetPressed(_:)), for: .touchUpInside)
            presetRow.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([
            presetRow.topAnchor.constraint(equalTo: presets.contentLayoutGuide.topAnchor),
            presetRow.leadingAnchor.constraint(equalTo: presets.contentLayoutGuide.leadingAnchor),
            presetRow.trailingAnchor.constraint(equalTo: presets.contentLayoutGuide.trailingAnchor),
            presetRow.bottomAnchor.constraint(equalTo: presets.contentLayoutGuide.bottomAnchor),
            presetRow.heightAnchor.constraint(equalTo: presets.frameLayoutGuide.heightAnchor)
        ])
        presets.heightAnchor.constraint(equalToConstant: 44.0).isActive = true
        self.stack.addArrangedSubview(presets)
        self.stack.setCustomSpacing(22.0, after: presets)

        // Sliders
        self.addSlider(title: ru ? "Размер" : "Size", min: 30, max: 300, value: settings.customEffectSize, tag: 1)
        self.addSlider(title: ru ? "Скорость" : "Speed", min: 20, max: 300, value: settings.customEffectSpeed, tag: 2)
        self.addSlider(title: ru ? "Ветер ←  → " : "Wind ←  →", min: -100, max: 100, value: settings.customEffectWind, tag: 3)
        self.addSwitch(title: ru ? "Летят вверх" : "Float Up", value: settings.customEffectRise, tag: 4)
        self.addSwitch(title: ru ? "Вращаются" : "Spin", value: settings.customEffectSpin, tag: 5)

        let apply = UIButton(type: .system)
        apply.setTitle(ru ? "Включить в чатах" : "Use in Chats", for: .normal)
        apply.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .bold)
        apply.setTitleColor(.black, for: .normal)
        apply.backgroundColor = .white
        apply.layer.cornerRadius = 25.0
        apply.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        apply.addTarget(self, action: #selector(self.applyPressed), for: .touchUpInside)
        self.stack.setCustomSpacing(24.0, after: self.stack.arrangedSubviews.last!)
        self.stack.addArrangedSubview(apply)

        self.title = ru ? "Свой эффект" : "Custom Effect"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.previewGradient.frame = self.preview.bounds
        self.emitter.frame = self.preview.bounds
        CATransaction.commit()
        if let first = self.preview.viewWithTag(100), let second = self.preview.viewWithTag(101) {
            let size1 = first.sizeThatFits(CGSize(width: 260.0, height: 32.0))
            first.frame = CGRect(x: 14.0, y: self.preview.bounds.height - 96.0, width: size1.width, height: 34.0)
            let size2 = second.sizeThatFits(CGSize(width: 260.0, height: 32.0))
            second.frame = CGRect(x: self.preview.bounds.width - size2.width - 14.0, y: self.preview.bounds.height - 52.0, width: size2.width, height: 34.0)
        }
        if self.emitter.emitterCells == nil {
            self.refreshPreview()
        }
    }

    private func refreshPreview() {
        let size = self.preview.bounds.size
        guard size.width > 1.0 else {
            return
        }
        astraConfigureEmitter(self.emitter, effect: .custom, size: size, density: 1.4, particleScale: 1.0)
        self.emitter.beginTime = CACurrentMediaTime() - 4.0
    }

    private func header(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text.uppercased()
        label.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
        label.textColor = UIColor(white: 1.0, alpha: 0.45)
        label.numberOfLines = 0
        return label
    }

    private func addSlider(title: String, min: Int, max: Int, value: Int, tag: Int) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12.0
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
        label.textColor = .white
        label.widthAnchor.constraint(equalToConstant: 104.0).isActive = true
        let slider = UISlider()
        slider.minimumValue = Float(min)
        slider.maximumValue = Float(max)
        slider.value = Float(value)
        slider.tag = tag
        slider.minimumTrackTintColor = UIColor(red: 0.65, green: 0.55, blue: 1.0, alpha: 1.0)
        slider.addTarget(self, action: #selector(self.sliderChanged(_:)), for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(slider)
        self.stack.addArrangedSubview(row)
    }

    private func addSwitch(title: String, value: Bool, tag: Int) {
        let row = UIStackView()
        row.axis = .horizontal
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
        label.textColor = .white
        let toggle = UISwitch()
        toggle.isOn = value
        toggle.tag = tag
        toggle.onTintColor = UIColor(red: 0.545, green: 0.36, blue: 0.965, alpha: 1.0)
        toggle.addTarget(self, action: #selector(self.switchChanged(_:)), for: .valueChanged)
        row.addArrangedSubview(label)
        row.addArrangedSubview(toggle)
        self.stack.addArrangedSubview(row)
    }

    @objc private func symbolsChanged() {
        let symbols = astraCustomEffectSymbols(self.symbolsField.text ?? "").joined()
        AstraGramSettings.update { $0.customEffectSymbols = symbols }
        self.refreshPreview()
    }

    @objc private func presetPressed(_ sender: UIButton) {
        guard let symbol = sender.title(for: .normal) else {
            return
        }
        UISelectionFeedbackGenerator().selectionChanged()
        var current = astraCustomEffectSymbols(self.symbolsField.text ?? "")
        if current == ["❄️"] && symbol != "❄️" {
            current = []
        }
        if let index = current.firstIndex(of: symbol) {
            current.remove(at: index)
        } else {
            current.append(symbol)
            if current.count > 3 {
                current.removeFirst()
            }
        }
        self.symbolsField.text = current.joined()
        self.symbolsChanged()
    }

    @objc private func sliderChanged(_ slider: UISlider) {
        let value = Int(slider.value.rounded())
        AstraGramSettings.update { settings in
            switch slider.tag {
            case 1: settings.customEffectSize = value
            case 2: settings.customEffectSpeed = value
            default: settings.customEffectWind = value
            }
        }
        self.refreshPreview()
    }

    @objc private func switchChanged(_ toggle: UISwitch) {
        AstraGramSettings.update { settings in
            if toggle.tag == 4 {
                settings.customEffectRise = toggle.isOn
            } else {
                settings.customEffectSpin = toggle.isOn
            }
        }
        self.refreshPreview()
    }

    @objc private func applyPressed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AstraGramSettings.update { $0.screenEffect = AstraScreenEffect.custom.rawValue }
        let onApply = self.onApply
        self.dismiss(animated: true, completion: {
            onApply?()
        })
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
