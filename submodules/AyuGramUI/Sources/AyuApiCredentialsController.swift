import Foundation
import UIKit
import BuildConfig

/// The screen where the user enters their own Telegram API ID and hash (from my.telegram.org). It is shown on the
/// first launch, before anything else starts, and from AyuGram settings to change them.
public final class AyuApiCredentialsController: UIViewController, UITextFieldDelegate {
    private let baseAppBundleId: String
    private let isInitialSetup: Bool
    private let completion: () -> Void
    private let isRussian: Bool

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let apiIdField = UITextField()
    private let apiHashField = UITextField()
    private let errorLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    public init(baseAppBundleId: String, isInitialSetup: Bool, completion: @escaping () -> Void) {
        self.baseAppBundleId = baseAppBundleId
        self.isInitialSetup = isInitialSetup
        self.completion = completion
        let language = Locale.preferredLanguages.first?.lowercased() ?? ""
        self.isRussian = language.hasPrefix("ru") || language.hasPrefix("uk") || language.hasPrefix("be")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func t(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground

        self.scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.keyboardDismissMode = .interactive
        self.view.addSubview(self.scrollView)

        self.stackView.axis = .vertical
        self.stackView.spacing = 14.0
        self.stackView.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView.addSubview(self.stackView)

        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.stackView.leadingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.leadingAnchor, constant: 24.0),
            self.stackView.trailingAnchor.constraint(equalTo: self.scrollView.frameLayoutGuide.trailingAnchor, constant: -24.0),
            self.stackView.topAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.topAnchor, constant: 64.0),
            self.stackView.bottomAnchor.constraint(equalTo: self.scrollView.contentLayoutGuide.bottomAnchor, constant: -32.0)
        ])

        let iconLabel = UILabel()
        iconLabel.text = "👻"
        iconLabel.font = UIFont.systemFont(ofSize: 64.0)
        iconLabel.textAlignment = .center
        self.stackView.addArrangedSubview(iconLabel)

        let titleLabel = UILabel()
        titleLabel.text = "AyuGram"
        titleLabel.font = UIFont.systemFont(ofSize: 28.0, weight: .bold)
        titleLabel.textAlignment = .center
        self.stackView.addArrangedSubview(titleLabel)

        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.font = UIFont.systemFont(ofSize: 15.0)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.text = self.t(
            "Для работы нужны ваши собственные API ID и API Hash. Получите их на my.telegram.org → API development tools (войдите своим номером, создайте приложение с любым названием) и вставьте сюда. Они хранятся только на этом устройстве.",
            "AyuGram needs your own API ID and API hash. Get them at my.telegram.org → API development tools (log in with your number, create an app with any name) and paste them here. They are stored on this device only."
        )
        self.stackView.addArrangedSubview(textLabel)

        let linkButton = UIButton(type: .system)
        linkButton.setTitle(self.t("Открыть my.telegram.org", "Open my.telegram.org"), for: .normal)
        linkButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
        linkButton.addTarget(self, action: #selector(self.openSitePressed), for: .touchUpInside)
        self.stackView.addArrangedSubview(linkButton)

        self.configure(field: self.apiIdField, placeholder: "API ID (1234567)", keyboardType: .numberPad)
        self.configure(field: self.apiHashField, placeholder: "API Hash (0123456789abcdef…)", keyboardType: .asciiCapable)

        self.errorLabel.numberOfLines = 0
        self.errorLabel.font = UIFont.systemFont(ofSize: 14.0)
        self.errorLabel.textColor = .systemRed
        self.errorLabel.textAlignment = .center
        self.errorLabel.isHidden = true
        self.stackView.addArrangedSubview(self.errorLabel)

        self.saveButton.setTitle(self.t("Сохранить и продолжить", "Save and Continue"), for: .normal)
        self.saveButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.saveButton.backgroundColor = .systemBlue
        self.saveButton.setTitleColor(.white, for: .normal)
        self.saveButton.layer.cornerRadius = 12.0
        self.saveButton.heightAnchor.constraint(equalToConstant: 50.0).isActive = true
        self.saveButton.addTarget(self, action: #selector(self.savePressed), for: .touchUpInside)
        self.stackView.addArrangedSubview(self.saveButton)

        if !self.isInitialSetup {
            let cancelButton = UIButton(type: .system)
            cancelButton.setTitle(self.t("Отмена", "Cancel"), for: .normal)
            cancelButton.addTarget(self, action: #selector(self.cancelPressed), for: .touchUpInside)
            self.stackView.addArrangedSubview(cancelButton)
        }
    }

    private func configure(field: UITextField, placeholder: String, keyboardType: UIKeyboardType) {
        field.placeholder = placeholder
        field.keyboardType = keyboardType
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemGroupedBackground
        field.layer.cornerRadius = 10.0
        field.font = UIFont.monospacedSystemFont(ofSize: 16.0, weight: .regular)
        field.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 12.0, height: 1.0))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 48.0).isActive = true
        field.delegate = self
        self.stackView.addArrangedSubview(field)
    }

    @objc private func openSitePressed() {
        if let url = URL(string: "https://my.telegram.org/apps") {
            UIApplication.shared.open(url)
        }
    }

    @objc private func cancelPressed() {
        self.dismiss(animated: true)
    }

    @objc private func savePressed() {
        let idText = (self.apiIdField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hashText = (self.apiHashField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiId = Int32(idText), apiId > 0 else {
            self.showError(self.t("API ID — это число, например 1234567.", "The API ID is a number, like 1234567."))
            return
        }
        guard BuildConfig.ayuStoreApiCredentials(apiId: apiId, apiHash: hashText, baseAppBundleId: self.baseAppBundleId) else {
            self.showError(self.t("API Hash — это 32 символа: цифры и буквы a–f.", "The API hash is 32 characters: digits and letters a–f."))
            return
        }
        self.view.endEditing(true)
        if self.isInitialSetup {
            self.completion()
        } else {
            let alert = UIAlertController(title: nil, message: self.t("Сохранено. Новые ключи начнут работать после перезапуска приложения.", "Saved. The new keys are used after the app restarts."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
                self?.dismiss(animated: true)
                self?.completion()
            }))
            self.present(alert, animated: true)
        }
    }

    private func showError(_ text: String) {
        self.errorLabel.text = text
        self.errorLabel.isHidden = false
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === self.apiIdField {
            self.apiHashField.becomeFirstResponder()
        } else {
            self.savePressed()
        }
        return true
    }
}
