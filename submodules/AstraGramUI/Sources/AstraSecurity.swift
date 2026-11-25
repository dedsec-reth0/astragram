import Foundation
import UIKit
import LocalAuthentication
import SwiftSignalKit
import TelegramCore
import AccountContext

/// AstraGram security: Face ID (or the device passcode) for what the user chose to protect.
public enum AstraBiometrics {
    /// Whether the device has any way to authenticate its owner (a passcode, with or without Face ID).
    public static var isAvailable: Bool {
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Asks the owner of the device to authenticate; `completion` is called on the main queue.
    /// A device with no passcode cannot ask anything: the answer is then yes, or what is locked could never be opened.
    public static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            DispatchQueue.main.async {
                completion(true)
            }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        })
    }
}

/// AstraGram security: the chats that open only after Face ID. A chat stays open until the app goes to the background.
public enum AstraChatLock {
    private static var unlocked = Set<Int64>()
    /// AstraGram's own settings, when they are behind Face ID too.
    public static var settingsUnlocked: Bool = false

    public static func isLocked(_ peerId: Int64) -> Bool {
        return AstraGramSettings.current.lockedChats.contains(peerId)
    }

    public static func needsAuthentication(_ peerId: Int64) -> Bool {
        return AstraChatLock.isLocked(peerId) && !AstraChatLock.unlocked.contains(peerId)
    }

    public static func markUnlocked(_ peerId: Int64) {
        AstraChatLock.unlocked.insert(peerId)
    }

    /// Whether a locked chat or the locked settings were opened since the last relock.
    static var hasUnlocked: Bool {
        return !AstraChatLock.unlocked.isEmpty || AstraChatLock.settingsUnlocked
    }

    public static func relock() {
        AstraChatLock.unlocked.removeAll()
        AstraChatLock.settingsUnlocked = false
    }

    /// Whether anything of this chat (its messages, media, notifications, bookmarks) may be shown right now.
    public static func canShow(_ peerId: Int64) -> Bool {
        return !AstraChatLock.needsAuthentication(peerId)
    }

    private static var isRussian: Bool {
        return (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("ru")
    }

    /// The one check every view of a locked chat goes through (opening it from any screen, a topic of it, a long-press
    /// preview): the view is covered at once, and opened in full only after Face ID. A preview stays covered (no Face ID
    /// sheet from a long press); a full view that is not unlocked is closed with `close`.
    public static func protect(view: UIView, peerId: Int64, isPreview: Bool, close: @escaping () -> Void) {
        guard AstraChatLock.needsAuthentication(peerId) else {
            return
        }
        let cover = UIView(frame: view.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "🔒\n" + (AstraChatLock.isRussian ? "Защищённый чат" : "Locked chat")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(label)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: cover.centerXAnchor), label.centerYAnchor.constraint(equalTo: cover.centerYAnchor)])
        view.addSubview(cover)
        if isPreview {
            return
        }
        AstraBiometrics.authenticate(reason: AstraChatLock.isRussian ? "Открыть защищённый чат" : "Open the locked chat", completion: { success in
            if success {
                AstraChatLock.markUnlocked(peerId)
                cover.removeFromSuperview()
            } else {
                close()
            }
        })
    }
}

private final class AstraLockCoverTarget: NSObject {
    @objc func tapped() {
        AstraSecurityRuntime.reauthenticate()
    }
}

/// AstraGram security: what runs for the whole life of the app. Started once, at launch.
public enum AstraSecurityRuntime {
    private static var isStarted = false
    private static var lastHandledPasteboardChange: Int = -1
    private static let coverTag = 0x4153_5452
    private static let lockTag = 0x4153_4C4B
    /// A locked chat or the settings were open when the app left the screen: they stay covered until Face ID.
    private static var pendingReauth = false
    private static var isAuthenticating = false
    /// Face ID is asked by itself once per return; after a failed try only a tap on the cover asks again (the Face ID
    /// sheet itself makes the app inactive and active again, which would otherwise ask in a loop).
    private static var autoPrompt = true

    public static func start() {
        if AstraSecurityRuntime.isStarted {
            return
        }
        AstraSecurityRuntime.isStarted = true

        let center = NotificationCenter.default
        // Locked chats and settings are locked again once the app has left the screen.
        let _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { _ in
            // A locked chat (or the settings) still on screen is covered now, so the next person to open the app sees
            // nothing of it before Face ID.
            if AstraChatLock.hasUnlocked {
                AstraSecurityRuntime.pendingReauth = true
                AstraSecurityRuntime.autoPrompt = true
                AstraSecurityRuntime.setLockCoverVisible(true)
            }
            AstraChatLock.relock()
        })
        // The app switcher shows a picture of the app taken when it stops being active: the cover is on it.
        for name in [UIApplication.willResignActiveNotification, UIScene.willDeactivateNotification] {
            let _ = center.addObserver(forName: name, object: nil, queue: .main, using: { _ in
                AstraSecurityRuntime.setCoverVisible(true)
            })
        }
        for name in [UIApplication.didBecomeActiveNotification, UIScene.didActivateNotification] {
            let _ = center.addObserver(forName: name, object: nil, queue: .main, using: { _ in
                AstraSecurityRuntime.setCoverVisible(false)
                if AstraSecurityRuntime.pendingReauth && AstraSecurityRuntime.autoPrompt {
                    AstraSecurityRuntime.reauthenticate()
                }
            })
        }
        let _ = center.addObserver(forName: UIPasteboard.changedNotification, object: nil, queue: .main, using: { _ in
            AstraSecurityRuntime.pasteboardChanged()
        })
    }

    fileprivate static func reauthenticate() {
        guard AstraSecurityRuntime.pendingReauth, !AstraSecurityRuntime.isAuthenticating else {
            return
        }
        AstraSecurityRuntime.isAuthenticating = true
        AstraSecurityRuntime.autoPrompt = false
        let isRussian = (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("ru")
        AstraBiometrics.authenticate(reason: isRussian ? "Разблокировать чат" : "Unlock the chat", completion: { success in
            AstraSecurityRuntime.isAuthenticating = false
            if success {
                AstraSecurityRuntime.pendingReauth = false
                AstraSecurityRuntime.setLockCoverVisible(false)
            }
        })
    }

    private static let lockTarget = AstraLockCoverTarget()

    private static func setLockCoverVisible(_ visible: Bool) {
        for window in AstraSecurityRuntime.windows {
            let existing = window.viewWithTag(AstraSecurityRuntime.lockTag)
            if visible {
                if let existing {
                    window.bringSubviewToFront(existing)
                    continue
                }
                let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
                cover.tag = AstraSecurityRuntime.lockTag
                cover.frame = window.bounds
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let isRussian = (Locale.preferredLanguages.first ?? "").lowercased().hasPrefix("ru")
                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34.0, weight: .semibold)), for: .normal)
                button.setTitle(isRussian ? "  Нажмите, чтобы разблокировать" : "  Tap to unlock", for: .normal)
                button.tintColor = .white
                button.frame = cover.bounds
                button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                button.addTarget(AstraSecurityRuntime.lockTarget, action: #selector(AstraLockCoverTarget.tapped), for: .touchUpInside)
                cover.contentView.addSubview(button)
                window.addSubview(cover)
            } else if let existing {
                existing.removeFromSuperview()
            }
        }
    }

    private static var windows: [UIWindow] {
        var result: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                result.append(contentsOf: windowScene.windows)
            }
        }
        return result
    }

    private static func setCoverVisible(_ visible: Bool) {
        for window in AstraSecurityRuntime.windows {
            let existing = window.viewWithTag(AstraSecurityRuntime.coverTag)
            if visible && AstraGramSettings.current.hideInAppSwitcher {
                if existing != nil {
                    continue
                }
                let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
                cover.tag = AstraSecurityRuntime.coverTag
                cover.frame = window.bounds
                cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                cover.isUserInteractionEnabled = false
                let iconView = UIImageView(image: UIImage(named: "BlueIcon"))
                iconView.frame = CGRect(x: floor((window.bounds.width - 84.0) / 2.0), y: floor((window.bounds.height - 84.0) / 2.0), width: 84.0, height: 84.0)
                iconView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
                iconView.layer.cornerRadius = 19.0
                iconView.layer.cornerCurve = .continuous
                iconView.clipsToBounds = true
                cover.contentView.addSubview(iconView)
                window.addSubview(cover)
            } else if let existing = existing {
                existing.removeFromSuperview()
            }
        }
    }

    /// What the app has just copied gets an expiration date and stays on this device, as the settings ask.
    private static func pasteboardChanged() {
        let settings = AstraGramSettings.current
        guard settings.clipboardExpire || settings.clipboardLocalOnly else {
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        let pasteboard = UIPasteboard.general
        if pasteboard.changeCount == AstraSecurityRuntime.lastHandledPasteboardChange {
            return
        }
        let items = pasteboard.items
        if items.isEmpty {
            return
        }
        var options: [UIPasteboard.OptionsKey: Any] = [:]
        if settings.clipboardExpire {
            options[.expirationDate] = Date().addingTimeInterval(60.0)
        }
        if settings.clipboardLocalOnly {
            options[.localOnly] = true
        }
        pasteboard.setItems(items, options: options)
        AstraSecurityRuntime.lastHandledPasteboardChange = pasteboard.changeCount
    }

    /// Signs of a jailbreak: with one, other software on the device can read what the app stores.
    public static var deviceLooksJailbroken: Bool {
        let paths = [
            "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app", "/var/jb",
            "/private/var/lib/apt", "/Library/MobileSubstrate/MobileSubstrate.dylib", "/usr/lib/TweakInject"
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        return false
    }
}

/// The view controller on top of everything, to present an alert from code that has no screen of its own.
func astraTopViewController() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
        guard let windowScene = scene as? UIWindowScene, scene.activationState == .foregroundActive else {
            continue
        }
        let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        var presenter = window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        if let presenter = presenter {
            return presenter
        }
    }
    return nil
}

/// AstraGram → Security Check: what protects the account and the app now, as a text report.
public func astraSecurityReport(context: AccountContext, isRussian: Bool, completion: @escaping (String) -> Void) {
    let passcode: Signal<Bool, NoError> = context.sharedContext.accountManager.accessChallengeData()
    |> take(1)
    |> map { view -> Bool in
        return view.data.isLockable
    }
    let twoStep: Signal<Bool?, NoError> = context.engine.auth.twoStepVerificationConfiguration()
    |> map { configuration -> Bool? in
        switch configuration {
        case .set:
            return true
        case .notSet:
            return false
        }
    }
    |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single(nil))
    |> take(1)
    let privacy: Signal<AccountPrivacySettings?, NoError> = context.engine.privacy.requestAccountPrivacySettings()
    |> map { settings -> AccountPrivacySettings? in
        return settings
    }
    |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single(nil))
    |> take(1)
    // The context loads the list of sessions; it has to live until the list has arrived.
    let sessionsContext = context.engine.privacy.activeSessions()
    let sessions: Signal<Int?, NoError> = sessionsContext.state
    |> filter { state -> Bool in
        return !state.sessions.isEmpty
    }
    |> map { state -> Int? in
        return state.sessions.count
    }
    |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single(nil))
    |> take(1)

    let _ = (combineLatest(passcode, twoStep, privacy, sessions)
    |> take(1)
    |> deliverOnMainQueue).start(next: { passcode, twoStep, privacy, sessions in
        let _ = sessionsContext
        let settings = AstraGramSettings.current
        func t(_ ru: String, _ en: String) -> String {
            return isRussian ? ru : en
        }
        let unknown = t("не удалось узнать (нет сети?)", "could not be checked (no network?)")
        var good: [String] = []
        var attention: [String] = []
        func add(_ isGood: Bool, _ text: String) {
            if isGood {
                good.append("✓ " + text)
            } else {
                attention.append("! " + text)
            }
        }
        func who(_ value: SelectivePrivacySettings) -> (text: String, isEveryone: Bool) {
            switch value {
            case .enableEveryone:
                return (t("все", "everybody"), true)
            case .enableContacts:
                return (t("контакты", "contacts"), false)
            case .disableEveryone:
                return (t("никто", "nobody"), false)
            }
        }

        // The account
        if let twoStep = twoStep {
            add(twoStep, twoStep ? t("Облачный пароль включён.", "The cloud password is on.") : t("Облачный пароль не включён. Без него в аккаунт можно войти, перехватив код из SMS.", "The cloud password is off. Without it, whoever intercepts the SMS code can log in."))
        } else {
            attention.append("? " + t("Облачный пароль: ", "Cloud password: ") + unknown)
        }
        add(passcode, passcode ? t("Код-пароль приложения задан.", "The app passcode is set.") : t("Код-пароль приложения не задан: кто взял разблокированный телефон, тот читает переписку.", "The app passcode is not set: whoever holds the unlocked phone reads the chats."))
        if let sessions = sessions {
            add(sessions <= 1, t("Активных сеансов: \(sessions).", "Active sessions: \(sessions).") + (sessions > 1 ? " " + t("Проверьте, что все устройства ваши.", "Check that every device is yours.") : ""))
        } else {
            attention.append("? " + t("Активные сеансы: ", "Active sessions: ") + unknown)
        }
        if let privacy = privacy {
            let phone = who(privacy.phoneNumber)
            add(!phone.isEveryone, t("Номер телефона видят: ", "Phone number is seen by: ") + phone.text + ".")
            add(!privacy.phoneDiscoveryEnabled, privacy.phoneDiscoveryEnabled ? t("Найти вас по номеру может кто угодно.", "Anyone can find you by your number.") : t("Найти вас по номеру могут только контакты.", "Only contacts can find you by your number."))
            let peerToPeer = who(privacy.voiceCallsP2P)
            add(!peerToPeer.isEveryone, t("Прямое соединение в звонках (раскрывает IP-адрес): ", "Peer-to-peer in calls (reveals the IP address): ") + peerToPeer.text + ".")
            let invitations = who(privacy.groupInvitations)
            add(!invitations.isEveryone, t("Добавлять вас в группы могут: ", "You can be added to groups by: ") + invitations.text + ".")
        } else {
            attention.append("? " + t("Настройки приватности: ", "Privacy settings: ") + unknown)
        }

        // The app and the device
        add(AstraBiometrics.isAvailable, AstraBiometrics.isAvailable ? t("На устройстве задан код-пароль.", "The device has a passcode.") : t("На устройстве нет код-пароля: Face ID-защита AstraGram не работает.", "The device has no passcode: AstraGram's Face ID protection does not work."))
        add(!AstraSecurityRuntime.deviceLooksJailbroken, AstraSecurityRuntime.deviceLooksJailbroken ? t("Найдены признаки джейлбрейка: другие программы могут читать данные приложения.", "Signs of a jailbreak: other software may read the app's data.") : t("Признаков джейлбрейка нет.", "No signs of a jailbreak."))
        add(settings.blockThirdPartyKeyboards, settings.blockThirdPartyKeyboards ? t("Сторонние клавиатуры запрещены.", "Third-party keyboards are blocked.") : t("Сторонние клавиатуры разрешены: клавиатура видит всё, что вы набираете.", "Third-party keyboards are allowed: a keyboard sees everything you type."))
        add(settings.hideInAppSwitcher, settings.hideInAppSwitcher ? t("Экран скрыт в переключателе приложений.", "The screen is hidden in the app switcher.") : t("Экран виден в переключателе приложений.", "The screen is visible in the app switcher."))
        add(settings.warnSuspiciousLinks, settings.warnSuspiciousLinks ? t("Подозрительные ссылки открываются с предупреждением.", "Suspicious links open with a warning.") : t("Предупреждение о подозрительных ссылках выключено.", "The warning about suspicious links is off."))
        add(settings.stripLinkTrackers, settings.stripLinkTrackers ? t("Трекеры из ссылок убираются.", "Trackers are removed from links.") : t("Трекеры из ссылок не убираются.", "Trackers are not removed from links."))
        add(settings.clipboardExpire, settings.clipboardExpire ? t("Скопированное очищается через минуту.", "What is copied is cleared in a minute.") : t("Скопированное остаётся в буфере обмена.", "What is copied stays on the clipboard."))
        add(!settings.lockedChats.isEmpty, settings.lockedChats.isEmpty ? t("Нет чатов под Face ID.", "No chats are locked with Face ID.") : t("Чатов под Face ID: \(settings.lockedChats.count).", "Chats locked with Face ID: \(settings.lockedChats.count)."))

        var text = ""
        if !attention.isEmpty {
            text += t("СТОИТ ПОПРАВИТЬ", "WORTH FIXING") + "\n\n" + attention.joined(separator: "\n\n") + "\n\n\n"
        }
        text += t("В ПОРЯДКЕ", "IN ORDER") + "\n\n" + (good.isEmpty ? "—" : good.joined(separator: "\n\n"))
        text += "\n\n\n" + t("Пароль, код-пароль, сеансы и приватность меняются в Настройки → Конфиденциальность. Остальное — в Настройки → AstraGram → Безопасность.", "The password, the passcode, sessions and privacy are changed in Settings → Privacy and Security. The rest is in Settings → AstraGram → Security.")
        completion(text)
    })
}
