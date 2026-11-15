import Foundation
import UIKit

/// A sheet that runs a task (an AI request, text recognition, an export) and shows its text result, with Copy and
/// Share. Long results scroll, which an alert cannot do.
public final class AstraTextResultController: UIViewController {
    private let titleText: String
    private let isRussian: Bool
    private let load: (@escaping (Result<String, Error>) -> Void) -> Void

    private let textView = UITextView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var resultText: String?

    public init(title: String, isRussian: Bool, load: @escaping (@escaping (Result<String, Error>) -> Void) -> Void) {
        self.titleText = title
        self.isRussian = isRussian
        self.load = load
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Wraps the controller in a navigation controller, ready to present.
    public func wrapped() -> UIViewController {
        let navigationController = UINavigationController(rootViewController: self)
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        return navigationController
    }

    private func t(_ ru: String, _ en: String) -> String {
        return self.isRussian ? ru : en
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.title = self.titleText
        self.view.backgroundColor = .systemBackground
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(self.closePressed))
        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(self.sharePressed)),
            UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(self.copyPressed))
        ]
        self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }

        self.textView.translatesAutoresizingMaskIntoConstraints = false
        self.textView.isEditable = false
        self.textView.font = UIFont.preferredFont(forTextStyle: .body)
        self.textView.textContainerInset = UIEdgeInsets(top: 16.0, left: 12.0, bottom: 24.0, right: 12.0)
        self.view.addSubview(self.textView)
        self.activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.activityIndicator)
        NSLayoutConstraint.activate([
            self.textView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.textView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.textView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.textView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.activityIndicator.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.activityIndicator.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
        ])

        self.activityIndicator.startAnimating()
        self.load({ [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.activityIndicator.stopAnimating()
                switch result {
                case let .success(text):
                    self.resultText = text
                    self.textView.text = text.isEmpty ? self.t("Пусто", "Empty") : text
                    self.navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = !text.isEmpty }
                case let .failure(error):
                    self.textView.text = "⚠️ " + error.localizedDescription
                    self.textView.textColor = .systemRed
                }
            }
        })
    }

    @objc private func closePressed() {
        self.dismiss(animated: true)
    }

    @objc private func copyPressed() {
        guard let text = self.resultText else {
            return
        }
        UIPasteboard.general.string = text
        AstraHaptics.success()
        self.title = self.t("Скопировано", "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: { [weak self] in
            self?.title = self?.titleText
        })
    }

    @objc private func sharePressed() {
        guard let text = self.resultText else {
            return
        }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        controller.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItems?.first
        self.present(controller, animated: true)
    }
}

/// An error with a ready-made message for AstraTextResultController.
public struct AstraTextError: LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        return self.message
    }
}

/// Presents `controller` over the topmost controller of `window`.
public func astraPresentNative(_ controller: UIViewController, in window: UIWindow?) {
    var presenter = window?.rootViewController
    while let presented = presenter?.presentedViewController {
        presenter = presented
    }
    presenter?.present(controller, animated: true)
}
