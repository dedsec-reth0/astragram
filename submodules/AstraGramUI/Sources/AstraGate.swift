import Foundation
import UIKit
import SwiftSignalKit

/// AstraGram: a remote availability check at launch. The app asks the server whether it may run; if the server says
/// no, a screen covers everything and the app cannot be used until the server says yes again. The state is cached, so
/// turning off the network does not lift a block once it has been seen. The server is fixed here on purpose (not the
/// streak-bot setting), so the check cannot be redirected from settings.
public enum AstraGate {
    private static let statusURL = "https://astragram-streak-bot.dedsec-reth0.workers.dev/api/status"

    private static let blockedKey = "astragram.gate.blocked"
    private static let messageKey = "astragram.gate.message"
    private static let messageEnKey = "astragram.gate.messageEn"
    private static let urlKey = "astragram.gate.url"

    private static var started = false
    private static var window: UIWindow?
    private static var timer: SwiftSignalKit.Timer?

    private static var defaults: UserDefaults {
        return UserDefaults.standard
    }

    private static var isRussian: Bool {
        let language = Locale.preferredLanguages.first?.lowercased() ?? ""
        return language.hasPrefix("ru") || language.hasPrefix("uk") || language.hasPrefix("be")
    }

    public static func start() {
        if AstraGate.started {
            return
        }
        AstraGate.started = true
        if AstraGate.defaults.bool(forKey: AstraGate.blockedKey) {
            AstraGate.showIfNeeded()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            if AstraGate.defaults.bool(forKey: AstraGate.blockedKey) {
                AstraGate.showIfNeeded()
            }
            AstraGate.refresh()
        }
        let timer = SwiftSignalKit.Timer(timeout: 15.0 * 60.0, repeat: true, completion: {
            AstraGate.refresh()
        }, queue: Queue.mainQueue())
        AstraGate.timer = timer
        timer.start()
        AstraGate.refresh()
    }

    private static func refresh() {
        guard let url = URL(string: AstraGate.statusURL) else {
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 20.0)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200, let data = data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                // No answer: the cached state stands, so a block cannot be lifted by cutting the network.
                return
            }
            let blocked = (object["blocked"] as? Bool) ?? false
            DispatchQueue.main.async {
                if blocked {
                    AstraGate.defaults.set(true, forKey: AstraGate.blockedKey)
                    AstraGate.defaults.set((object["message"] as? String) ?? "", forKey: AstraGate.messageKey)
                    AstraGate.defaults.set((object["messageEn"] as? String) ?? "", forKey: AstraGate.messageEnKey)
                    AstraGate.defaults.set((object["url"] as? String) ?? "", forKey: AstraGate.urlKey)
                    AstraGate.showIfNeeded()
                } else {
                    AstraGate.defaults.set(false, forKey: AstraGate.blockedKey)
                    AstraGate.hide()
                }
            }
        }).resume()
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    private static func showIfNeeded() {
        if let window = AstraGate.window {
            window.isHidden = false
            window.makeKeyAndVisible()
            return
        }
        guard let scene = AstraGate.activeScene() else {
            // No scene yet; shown when the app becomes active.
            return
        }
        let message: String
        if AstraGate.isRussian {
            let stored = AstraGate.defaults.string(forKey: AstraGate.messageKey) ?? ""
            message = stored.isEmpty ? "Приложение больше недоступно.\nСледите за новостями." : stored
        } else {
            let stored = AstraGate.defaults.string(forKey: AstraGate.messageEnKey) ?? ""
            message = stored.isEmpty ? "This app is no longer available.\nWatch for news." : stored
        }
        let urlString = AstraGate.defaults.string(forKey: AstraGate.urlKey) ?? ""
        let window = UIWindow(windowScene: scene)
        // Above all app content. UIKit clamps app windows to 1e7 (below the keyboard window), which is fine here.
        window.windowLevel = UIWindow.Level(rawValue: 9_999_999.0)
        window.backgroundColor = .black
        window.rootViewController = AstraGateController(message: message, buttonURL: urlString, isRussian: AstraGate.isRussian)
        window.makeKeyAndVisible()
        AstraGate.window = window
    }

    private static func hide() {
        guard let window = AstraGate.window else {
            return
        }
        window.isHidden = true
        window.resignKey()
        AstraGate.window = nil
    }
}

private final class AstraGateController: UIViewController {
    private let message: String
    private let buttonURL: String
    private let isRussian: Bool

    init(message: String, buttonURL: String, isRussian: Bool) {
        self.message = message
        self.buttonURL = buttonURL
        self.isRussian = isRussian
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black

        let iconLabel = UILabel()
        iconLabel.text = "🚫"
        iconLabel.font = .systemFont(ofSize: 56.0)
        iconLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.text = self.message
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 18.0, weight: .medium)

        let stack = UIStackView(arrangedSubviews: [iconLabel, messageLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20.0
        stack.translatesAutoresizingMaskIntoConstraints = false

        if !self.buttonURL.isEmpty, URL(string: self.buttonURL) != nil {
            let button = UIButton(type: .system)
            button.setTitle(self.isRussian ? "Открыть новости" : "Open news", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17.0, weight: .semibold)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(red: 0.486, green: 0.302, blue: 1.0, alpha: 1.0)
            button.contentEdgeInsets = UIEdgeInsets(top: 12.0, left: 24.0, bottom: 12.0, right: 24.0)
            button.layer.cornerRadius = 12.0
            button.addTarget(self, action: #selector(self.openURL), for: .touchUpInside)
            stack.addArrangedSubview(button)
            stack.setCustomSpacing(32.0, after: messageLabel)
        }

        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.leadingAnchor, constant: 32.0),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: self.view.trailingAnchor, constant: -32.0)
        ])
    }

    @objc private func openURL() {
        guard let url = URL(string: self.buttonURL) else {
            return
        }
        UIApplication.shared.open(url)
    }
}
