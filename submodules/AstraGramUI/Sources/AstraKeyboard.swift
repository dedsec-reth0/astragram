import Foundation
import UIKit
import TelegramCore

// MARK: - Theme

/// A keyboard theme: colors, key shape, font and an optional background picture. Built-in themes ship with the app;
/// more are installed from the AstraGram keyboard store or from any link to a theme file (the same JSON).
public struct AstraKeyboardTheme: Codable, Equatable {
    public var id: String
    public var name: String
    public var author: String?
    /// One to three colors, top to bottom ("#RRGGBB" or "#RRGGBBAA").
    public var background: [String]
    /// A picture under the keys, drawn to fill (http/https).
    public var backgroundImage: String?
    public var key: String
    public var keyText: String
    public var special: String
    public var specialText: String?
    public var accent: String
    public var accentText: String?
    public var keyBorder: String?
    /// The color the key letters glow in (neon themes).
    public var glow: String?
    public var cornerRadius: Double?
    public var shadow: Bool?
    /// "default", "rounded", "mono" or "serif".
    public var font: String?
    public var pressed: String?

    var resolvedFont: (CGFloat, UIFont.Weight) -> UIFont {
        let design: UIFontDescriptor.SystemDesign
        switch self.font {
        case "rounded": design = .rounded
        case "mono": design = .monospaced
        case "serif": design = .serif
        default: design = .default
        }
        return { size, weight in
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            if let descriptor = base.fontDescriptor.withDesign(design) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return base
        }
    }
}

extension UIColor {
    /// "#RRGGBB" or "#RRGGBBAA"; nil for anything else.
    convenience init?(astraHex: String?) {
        guard var hex = astraHex?.trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        let hasAlpha = hex.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xff) / 255.0
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xff) / 255.0
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xff) / 255.0
        let a = hasAlpha ? CGFloat(value & 0xff) / 255.0 : 1.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

public enum AstraKeyboardThemes {
    /// Themes that come with the app.
    public static let builtIn: [AstraKeyboardTheme] = [
        AstraKeyboardTheme(id: "astra", name: "AstraGram", author: "AstraGram", background: ["#1a1033", "#0c1a3a"], backgroundImage: nil, key: "#ffffff1f", keyText: "#ffffff", special: "#ffffff12", specialText: "#ffffffcc", accent: "#8b5cf6", accentText: "#ffffff", keyBorder: "#ffffff22", glow: nil, cornerRadius: 9, shadow: false, font: "rounded", pressed: "#8b5cf666"),
        AstraKeyboardTheme(id: "neon", name: "Neon", author: "AstraGram", background: ["#05050a"], backgroundImage: nil, key: "#00000000", keyText: "#5ff7ff", special: "#00000000", specialText: "#ff4fd8", accent: "#ff4fd833", accentText: "#ff4fd8", keyBorder: "#5ff7ff88", glow: "#5ff7ff", cornerRadius: 8, shadow: false, font: "rounded", pressed: "#5ff7ff33"),
        AstraKeyboardTheme(id: "sakura", name: "Sakura", author: "AstraGram", background: ["#ffd6e5", "#f7a8c4"], backgroundImage: nil, key: "#ffffffd9", keyText: "#7a2848", special: "#ffffff80", specialText: "#7a2848", accent: "#e0457b", accentText: "#ffffff", keyBorder: nil, glow: nil, cornerRadius: 12, shadow: true, font: "rounded", pressed: "#ffb3cc"),
        AstraKeyboardTheme(id: "ocean", name: "Ocean", author: "AstraGram", background: ["#0b3d5c", "#1b7fa6", "#3ec1d3"], backgroundImage: nil, key: "#ffffff2e", keyText: "#ffffff", special: "#00000026", specialText: "#e6fbff", accent: "#ffffff", accentText: "#0b3d5c", keyBorder: "#ffffff33", glow: nil, cornerRadius: 10, shadow: false, font: "default", pressed: "#ffffff55"),
        AstraKeyboardTheme(id: "matrix", name: "Matrix", author: "AstraGram", background: ["#000000", "#001a08"], backgroundImage: nil, key: "#00ff4114", keyText: "#33ff66", special: "#00ff410a", specialText: "#1fcc4f", accent: "#00ff41", accentText: "#000000", keyBorder: "#00ff4155", glow: "#00ff41", cornerRadius: 3, shadow: false, font: "mono", pressed: "#00ff4144"),
        AstraKeyboardTheme(id: "gold", name: "Gold", author: "AstraGram", background: ["#0d0b07", "#1f1a10"], backgroundImage: nil, key: "#ffffff0d", keyText: "#f2cf75", special: "#ffffff08", specialText: "#c9a24a", accent: "#d4a740", accentText: "#1a1408", keyBorder: "#d4a74066", glow: nil, cornerRadius: 7, shadow: false, font: "serif", pressed: "#d4a74044"),
        AstraKeyboardTheme(id: "candy", name: "Candy", author: "AstraGram", background: ["#a1c4fd", "#c2e9fb", "#fbc2eb"], backgroundImage: nil, key: "#ffffffcc", keyText: "#5b3fa0", special: "#ffffff73", specialText: "#5b3fa0", accent: "#ff7eb3", accentText: "#ffffff", keyBorder: nil, glow: nil, cornerRadius: 14, shadow: true, font: "rounded", pressed: "#ffffff"),
        AstraKeyboardTheme(id: "graphite", name: "Graphite", author: "AstraGram", background: ["#1c1c1e"], backgroundImage: nil, key: "#3a3a3c", keyText: "#ffffff", special: "#2c2c2e", specialText: "#ffffff", accent: "#0a84ff", accentText: "#ffffff", keyBorder: nil, glow: nil, cornerRadius: 6, shadow: true, font: "default", pressed: "#5a5a5e"),
        AstraKeyboardTheme(id: "paper", name: "Paper", author: "AstraGram", background: ["#d1d3d9"], backgroundImage: nil, key: "#ffffff", keyText: "#111111", special: "#adb1bb", specialText: "#111111", accent: "#007aff", accentText: "#ffffff", keyBorder: nil, glow: nil, cornerRadius: 6, shadow: true, font: "default", pressed: "#e5e5ea"),
        AstraKeyboardTheme(id: "sunset", name: "Sunset", author: "AstraGram", background: ["#2b1055", "#d53369", "#ffb347"], backgroundImage: nil, key: "#ffffff26", keyText: "#ffffff", special: "#00000026", specialText: "#fff1e0", accent: "#ffffff", accentText: "#d53369", keyBorder: "#ffffff30", glow: nil, cornerRadius: 11, shadow: false, font: "rounded", pressed: "#ffffff50")
    ]

    /// Where the store's list of themes lives (on the AstraGram site).
    public static let storeURL = URL(string: "https://dedsec-reth0.github.io/astragram/keyboards.json")!

    private static let installedKey = "astragram.keyboardThemes.installed"

    /// Themes installed from the store or a link (built-in ones are always there).
    public static var installed: [AstraKeyboardTheme] {
        get {
            guard let data = UserDefaults.standard.data(forKey: installedKey), let themes = try? JSONDecoder().decode([AstraKeyboardTheme].self, from: data) else {
                return []
            }
            return themes
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: installedKey)
            }
        }
    }

    public static var all: [AstraKeyboardTheme] {
        return builtIn + installed.filter { theme in !builtIn.contains(where: { $0.id == theme.id }) }
    }

    public static func theme(id: String) -> AstraKeyboardTheme {
        return all.first(where: { $0.id == id }) ?? builtIn[0]
    }

    public static func install(_ theme: AstraKeyboardTheme) {
        var list = installed.filter { $0.id != theme.id }
        list.append(theme)
        installed = list
    }

    public static func remove(id: String) {
        installed = installed.filter { $0.id != id }
    }

    /// A theme file is one theme object or a list of them (`{"themes": [...]}` or `[...]`).
    public static func parse(_ data: Data) -> [AstraKeyboardTheme] {
        let decoder = JSONDecoder()
        if let one = try? decoder.decode(AstraKeyboardTheme.self, from: data) {
            return [one].filter(isValid)
        }
        if let list = try? decoder.decode([AstraKeyboardTheme].self, from: data) {
            return list.filter(isValid)
        }
        struct Wrapper: Codable { var themes: [AstraKeyboardTheme] }
        if let wrapper = try? decoder.decode(Wrapper.self, from: data) {
            return wrapper.themes.filter(isValid)
        }
        return []
    }

    private static func isValid(_ theme: AstraKeyboardTheme) -> Bool {
        return !theme.id.isEmpty && theme.id.count <= 64 && !theme.name.isEmpty && !theme.background.isEmpty && UIColor(astraHex: theme.background[0]) != nil && UIColor(astraHex: theme.keyText) != nil
    }

    /// Loads themes from `url` (the store list or a theme file someone shared).
    public static func load(url: URL, completion: @escaping ([AstraKeyboardTheme]) -> Void) {
        guard url.scheme == "https" || url.scheme == "http" else {
            completion([])
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0)
        request.setValue("AstraGram", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            let themes = data.flatMap { $0.count < 512 * 1024 ? parse($0) : nil } ?? []
            DispatchQueue.main.async {
                completion(themes)
            }
        }).resume()
    }

    private static var imageCache: [String: UIImage] = [:]

    /// A theme's background picture, kept in memory and in Caches after the first download.
    static func backgroundImage(_ urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let image = imageCache[urlString] {
            completion(image)
            return
        }
        guard let url = URL(string: urlString), url.scheme == "https" else {
            completion(nil)
            return
        }
        let cacheFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("astra-keyboard-\(abs(urlString.hashValue)).img")
        if let data = try? Data(contentsOf: cacheFile), let image = UIImage(data: data) {
            imageCache[urlString] = image
            completion(image)
            return
        }
        URLSession.shared.dataTask(with: url, completionHandler: { data, _, _ in
            var image: UIImage?
            if let data, data.count < 8 * 1024 * 1024, let decoded = UIImage(data: data) {
                image = decoded
                try? data.write(to: cacheFile)
            }
            DispatchQueue.main.async {
                if let image {
                    imageCache[urlString] = image
                }
                completion(image)
            }
        }).resume()
    }
}

// MARK: - Languages

/// A letter layout of AstraGram's keyboard: three rows of letters (the third between shift and delete).
public struct AstraKeyboardLanguage {
    public let id: String
    public let name: String
    public let short: String
    public let rows: [String]
    public let space: String

    public static let all: [AstraKeyboardLanguage] = [
        AstraKeyboardLanguage(id: "ru", name: "Русский", short: "RU", rows: ["йцукенгшщзх", "фывапролджэ", "ячсмитьбю"], space: "пробел"),
        AstraKeyboardLanguage(id: "en", name: "English", short: "EN", rows: ["qwertyuiop", "asdfghjkl", "zxcvbnm"], space: "space"),
        AstraKeyboardLanguage(id: "uk", name: "Українська", short: "UK", rows: ["йцукенгшщзхї", "фівапролджє", "ячсмитьбю"], space: "пробіл"),
        AstraKeyboardLanguage(id: "be", name: "Беларуская", short: "BE", rows: ["йцукенгшўзх", "фывапролджэ", "ячсмітьбю"], space: "прабел"),
        AstraKeyboardLanguage(id: "kk", name: "Қазақша", short: "KK", rows: ["әіңғүұқөһ", "йцукенгшщзх", "фывапролджэ", "ячсмитьбю"], space: "бос орын"),
        AstraKeyboardLanguage(id: "hy", name: "Հայերեն", short: "HY", rows: ["էթփձջւևրչճժ", "քոեռտըիօպխծ", "ասդֆգհյկլշ", "զղցվբնմ"], space: "բացատ"),
        AstraKeyboardLanguage(id: "ka", name: "ქართული", short: "KA", rows: ["ქწერტყუიოპ", "ასდფგჰჯკლ", "ზხცვბნმ"], space: "გამოტოვება"),
        AstraKeyboardLanguage(id: "de", name: "Deutsch", short: "DE", rows: ["qwertzuiopü", "asdfghjklöä", "yxcvbnmß"], space: "Leerzeichen"),
        AstraKeyboardLanguage(id: "fr", name: "Français", short: "FR", rows: ["azertyuiop", "qsdfghjklm", "wxcvbnéèà"], space: "espace"),
        AstraKeyboardLanguage(id: "es", name: "Español", short: "ES", rows: ["qwertyuiop", "asdfghjklñ", "zxcvbnmá"], space: "espacio"),
        AstraKeyboardLanguage(id: "it", name: "Italiano", short: "IT", rows: ["qwertyuiop", "asdfghjklè", "zxcvbnmàò"], space: "spazio"),
        AstraKeyboardLanguage(id: "pt", name: "Português", short: "PT", rows: ["qwertyuiop", "asdfghjklç", "zxcvbnmãé"], space: "espaço"),
        AstraKeyboardLanguage(id: "pl", name: "Polski", short: "PL", rows: ["qwertyuiop", "asdfghjklł", "zxcvbnmąęś"], space: "spacja"),
        AstraKeyboardLanguage(id: "tr", name: "Türkçe", short: "TR", rows: ["qwertyuıopğü", "asdfghjklşi", "zxcvbnmöç"], space: "boşluk"),
        AstraKeyboardLanguage(id: "az", name: "Azərbaycan", short: "AZ", rows: ["qüertyuiopöğ", "asdfghjklıə", "zxcvbnmçş"], space: "boşluq"),
        AstraKeyboardLanguage(id: "uz", name: "Oʻzbek", short: "UZ", rows: ["qwertyuiop", "asdfghjkl", "zxcvbnmʻ"], space: "boʻsh joy"),
        AstraKeyboardLanguage(id: "el", name: "Ελληνικά", short: "EL", rows: ["ςερτυθιοπ", "ασδφγηξκλ", "ζχψωβνμ"], space: "διάστημα"),
        AstraKeyboardLanguage(id: "he", name: "עברית", short: "HE", rows: ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"], space: "רווח"),
        AstraKeyboardLanguage(id: "ar", name: "العربية", short: "AR", rows: ["ضصثقفغعهخحج", "شسيبلاتنمكط", "ئءؤرىةوزظد"], space: "مسافة")
    ]

    public static func language(id: String) -> AstraKeyboardLanguage {
        return all.first(where: { $0.id == id }) ?? all[0]
    }
}

// MARK: - Keyboard

private enum AstraKeyKind: Equatable {
    case character(String)
    case shift
    case delete
    case space
    case returnKey
    case numbers
    case symbols
    case letters
    case language
    case systemKeyboard
}

private enum AstraKeyboardPage: Equatable {
    case letters
    case numbers
    case symbols
}

/// AstraGram's own keyboard for the chat input field, drawn in the chosen theme. It types into whatever text view
/// is first responder, as a system keyboard would.
public final class AstraKeyboardView: UIInputView, UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool {
        return true
    }

    /// Asked to hand over to the iOS keyboard (the keyboard key; it has emoji, dictation and other languages).
    public var switchToSystemKeyboard: (() -> Void)?

    private var theme: AstraKeyboardTheme
    private let isPreview: Bool
    private var page: AstraKeyboardPage = .letters
    private var languageIndex = 0
    private var languages: [AstraKeyboardLanguage] {
        let ids = AstraGramSettings.current.keyboardLanguages
        let list = ids.map { AstraKeyboardLanguage.language(id: $0) }
        return list.isEmpty ? [AstraKeyboardLanguage.all[0]] : list
    }
    private var language: AstraKeyboardLanguage {
        let languages = self.languages
        return languages[min(self.languageIndex, languages.count - 1)]
    }
    private var shifted = false
    private var capsLocked = false
    private var lastShiftTap: CFTimeInterval = 0.0

    private let backgroundGradient = CAGradientLayer()
    private let backgroundImageView = UIImageView()
    private var keyViews: [(AstraKeyKind, UIButton)] = []
    private let popup = UILabel()
    private var deleteTimer: Timer?

    public init(theme: AstraKeyboardTheme, isPreview: Bool = false) {
        self.theme = theme
        self.isPreview = isPreview
        if let saved = UserDefaults.standard.string(forKey: "astragram.keyboard.language") {
            let ids = AstraGramSettings.current.keyboardLanguages
            self.languageIndex = ids.firstIndex(of: saved) ?? 0
        }
        super.init(frame: CGRect(x: 0.0, y: 0.0, width: 375.0, height: 262.0), inputViewStyle: .keyboard)
        self.allowsSelfSizing = true
        self.autoresizingMask = [.flexibleWidth]
        self.layer.addSublayer(self.backgroundGradient)
        self.backgroundImageView.contentMode = .scaleAspectFill
        self.backgroundImageView.clipsToBounds = true
        self.addSubview(self.backgroundImageView)
        self.popup.textAlignment = .center
        self.popup.clipsToBounds = true
        self.popup.isHidden = true
        self.addSubview(self.popup)
        self.applyTheme()
        self.rebuildKeys()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 262.0)
    }

    public func update(theme: AstraKeyboardTheme) {
        guard theme != self.theme else {
            return
        }
        self.theme = theme
        self.applyTheme()
        self.rebuildKeys()
    }

    private func applyTheme() {
        let colors = self.theme.background.compactMap { UIColor(astraHex: $0)?.cgColor }
        self.backgroundGradient.colors = colors.count == 1 ? [colors[0], colors[0]] : colors
        self.backgroundImageView.image = nil
        if let imageURL = self.theme.backgroundImage {
            let themeId = self.theme.id
            AstraKeyboardThemes.backgroundImage(imageURL, completion: { [weak self] image in
                guard let self, self.theme.id == themeId else {
                    return
                }
                self.backgroundImageView.image = image
            })
        }
        self.popup.font = self.theme.resolvedFont(26.0, .regular)
        self.popup.textColor = UIColor(astraHex: self.theme.keyText) ?? .white
        self.popup.backgroundColor = (UIColor(astraHex: self.theme.pressed) ?? UIColor(astraHex: self.theme.key) ?? .gray).withAlphaComponent(1.0)
        self.popup.layer.cornerRadius = 10.0
    }

    // MARK: Rows

    private func rows() -> [[AstraKeyKind]] {
        func chars(_ string: String) -> [AstraKeyKind] {
            return string.map { .character(String($0)) }
        }
        let globe: AstraKeyKind = self.languages.count > 1 ? .language : .systemKeyboard
        switch self.page {
        case .letters:
            var rows = self.language.rows.map(chars)
            let last = rows.removeLast()
            rows.append([.shift] + last + [.delete])
            rows.append([.numbers, globe, .space, .returnKey])
            return rows
        case .numbers:
            return [chars("1234567890"), chars("-/:;()₽&@\""), [.symbols] + chars(".,?!'") + [.delete], [.letters, .systemKeyboard, .space, .returnKey]]
        case .symbols:
            return [chars("[]{}#%^*+="), chars("_\\|~<>$€£•"), [.numbers] + chars(".,?!'") + [.delete], [.letters, .systemKeyboard, .space, .returnKey]]
        }
    }

    private func title(for kind: AstraKeyKind) -> (String?, String?) {
        switch kind {
        case let .character(c):
            return ((self.shifted || self.capsLocked) ? c.uppercased() : c, nil)
        case .shift: return (nil, self.capsLocked ? "capslock.fill" : (self.shifted ? "shift.fill" : "shift"))
        case .delete: return (nil, "delete.left")
        case .space: return (self.language.space, nil)
        case .returnKey: return (nil, "return")
        case .numbers: return ("123", nil)
        case .symbols: return ("#+=", nil)
        case .letters: return (String(self.language.rows[0].prefix(3)).uppercased(), nil)
        case .language: return (self.language.short, nil)
        case .systemKeyboard: return (nil, "keyboard")
        }
    }

    private func rebuildKeys() {
        for (_, button) in self.keyViews {
            button.removeFromSuperview()
        }
        self.keyViews = []
        let keyColor = UIColor(astraHex: self.theme.key) ?? .darkGray
        let keyText = UIColor(astraHex: self.theme.keyText) ?? .white
        let special = UIColor(astraHex: self.theme.special) ?? keyColor
        let specialText = UIColor(astraHex: self.theme.specialText) ?? keyText
        let accent = UIColor(astraHex: self.theme.accent) ?? .systemBlue
        let accentText = UIColor(astraHex: self.theme.accentText) ?? .white
        let border = UIColor(astraHex: self.theme.keyBorder)
        let glow = UIColor(astraHex: self.theme.glow)
        let font = self.theme.resolvedFont
        for row in self.rows() {
            for kind in row {
                let button = UIButton(type: .custom)
                let (text, symbol) = self.title(for: kind)
                var background = keyColor
                var foreground = keyText
                switch kind {
                case .character, .space:
                    break
                case .returnKey:
                    background = accent
                    foreground = accentText
                default:
                    background = special
                    foreground = specialText
                }
                if case .shift = kind, self.shifted || self.capsLocked {
                    background = keyColor
                    foreground = keyText
                }
                button.backgroundColor = background
                button.layer.cornerRadius = CGFloat(self.theme.cornerRadius ?? 6.0)
                button.layer.cornerCurve = .continuous
                if let border {
                    button.layer.borderWidth = 1.0
                    button.layer.borderColor = border.cgColor
                }
                if self.theme.shadow == true {
                    button.layer.shadowColor = UIColor.black.cgColor
                    button.layer.shadowOpacity = 0.3
                    button.layer.shadowRadius = 0.0
                    button.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
                }
                if let text {
                    button.setTitle(text, for: .normal)
                    button.setTitleColor(foreground, for: .normal)
                    if case .character = kind {
                        button.titleLabel?.font = font(23.0, .regular)
                    } else {
                        button.titleLabel?.font = font(16.0, .medium)
                    }
                    if let glow {
                        button.titleLabel?.layer.shadowColor = glow.cgColor
                        button.titleLabel?.layer.shadowRadius = 5.0
                        button.titleLabel?.layer.shadowOpacity = 0.9
                        button.titleLabel?.layer.shadowOffset = .zero
                    }
                } else if let symbol {
                    button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .medium)), for: .normal)
                    button.tintColor = foreground
                }
                button.isUserInteractionEnabled = !self.isPreview
                button.addTarget(self, action: #selector(self.keyDown(_:)), for: .touchDown)
                button.addTarget(self, action: #selector(self.keyUp(_:)), for: [.touchUpInside])
                button.addTarget(self, action: #selector(self.keyCancel(_:)), for: [.touchUpOutside, .touchCancel])
                button.accessibilityLabel = text ?? symbol
                if case .language = kind, !self.isPreview {
                    // Holding the globe goes to the iOS keyboard, as on the iOS keyboard itself.
                    button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.languageLongPress(_:))))
                }
                self.addSubview(button)
                self.keyViews.append((kind, button))
            }
        }
        self.bringSubviewToFront(self.popup)
        self.setNeedsLayout()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.backgroundGradient.frame = self.bounds
        CATransaction.commit()
        self.backgroundImageView.frame = self.bounds

        let rows = self.rows()
        let side: CGFloat = 3.0
        let gap: CGFloat = 6.0
        let rowGap: CGFloat = 11.0
        let top: CGFloat = 8.0
        let usable = self.bounds.height - self.safeAreaInsets.bottom - top - 4.0
        let rowCount = CGFloat(rows.count)
        let keyHeight = max(28.0, min(44.0, (usable - rowGap * (rowCount - 1.0)) / rowCount))
        let width = self.bounds.width
        let maxLetters = CGFloat(max(10, rows.map { $0.count }.max() ?? 10))
        let unit = (width - side * 2.0 - gap * (maxLetters - 1.0)) / maxLetters
        var index = 0
        for (rowIndex, row) in rows.enumerated() {
            let y = top + CGFloat(rowIndex) * (keyHeight + rowGap)
            // Widths: letters one unit; the bottom row's space takes what is left.
            var widths: [CGFloat] = row.map { kind in
                switch kind {
                case .character: return unit
                case .shift, .delete, .symbols: return unit * 1.35
                case .numbers, .letters: return unit * 1.6
                case .language, .systemKeyboard: return unit * 1.2
                case .returnKey: return unit * 2.2
                case .space: return 0.0
                }
            }
            if rowIndex == rows.count - 1 {
                let fixed = widths.reduce(0.0, +) + gap * CGFloat(row.count - 1)
                if let spaceIndex = row.firstIndex(of: .space) {
                    widths[spaceIndex] = max(unit * 3.0, width - side * 2.0 - fixed)
                }
            } else if rowIndex == rows.count - 2 {
                // The shift and delete keys sit at the edges; the letters are centered between them.
                let letters = row.filter { if case .character = $0 { return true } else { return false } }.count
                let lettersWidth = unit * CGFloat(letters) + gap * CGFloat(letters - 1)
                let edge = (width - side * 2.0 - lettersWidth - gap * 2.0) / 2.0
                for i in widths.indices where !({ if case .character = row[i] { return true } else { return false } }()) {
                    widths[i] = max(unit, edge)
                }
            }
            let total = widths.reduce(0.0, +) + gap * CGFloat(row.count - 1)
            var x = (width - total) / 2.0
            for (i, _) in row.enumerated() {
                let button = self.keyViews[index].1
                button.frame = CGRect(x: x, y: y, width: widths[i], height: keyHeight)
                x += widths[i] + gap
                index += 1
            }
        }
    }

    // MARK: Typing

    private func insert(_ text: String) {
        UIApplication.shared.sendAction(NSSelectorFromString("insertText:"), to: nil, from: text as NSString, for: nil)
    }

    private func deleteBackward() {
        UIApplication.shared.sendAction(NSSelectorFromString("deleteBackward"), to: nil, from: nil, for: nil)
    }

    private func kind(of button: UIButton) -> AstraKeyKind? {
        return self.keyViews.first(where: { $0.1 === button })?.0
    }

    @objc private func keyDown(_ button: UIButton) {
        UIDevice.current.playInputClick()
        let pressed = UIColor(astraHex: self.theme.pressed)
        if let pressed {
            button.layer.setValue(button.backgroundColor, forKey: "astraNormalColor")
            button.backgroundColor = pressed
        } else {
            button.alpha = 0.6
        }
        guard let kind = self.kind(of: button) else {
            return
        }
        switch kind {
        case let .character(c):
            self.popup.text = (self.shifted || self.capsLocked) ? c.uppercased() : c
            let frame = button.frame
            self.popup.frame = CGRect(x: frame.midX - max(frame.width + 12.0, 46.0) / 2.0, y: frame.minY - 52.0, width: max(frame.width + 12.0, 46.0), height: 50.0)
            self.popup.frame.origin.y = max(-30.0, self.popup.frame.origin.y)
            self.popup.isHidden = false
        case .delete:
            self.deleteBackward()
            self.deleteTimer?.invalidate()
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false, block: { [weak self] _ in
                self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true, block: { [weak self] _ in
                    self?.deleteBackward()
                    UIDevice.current.playInputClick()
                })
            })
        default:
            break
        }
    }

    @objc private func languageLongPress(_ recognizer: UILongPressGestureRecognizer) {
        if case .began = recognizer.state {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.switchToSystemKeyboard?()
        }
    }

    @objc private func keyCancel(_ button: UIButton) {
        self.restore(button)
    }

    private func restore(_ button: UIButton) {
        self.popup.isHidden = true
        self.deleteTimer?.invalidate()
        self.deleteTimer = nil
        if let normal = button.layer.value(forKey: "astraNormalColor") as? UIColor {
            button.backgroundColor = normal
        }
        button.alpha = 1.0
    }

    @objc private func keyUp(_ button: UIButton) {
        self.restore(button)
        guard let kind = self.kind(of: button) else {
            return
        }
        switch kind {
        case let .character(c):
            self.insert((self.shifted || self.capsLocked) ? c.uppercased() : c)
            if self.shifted && !self.capsLocked {
                self.shifted = false
                self.rebuildKeys()
            }
        case .space:
            self.insert(" ")
            if self.page != .letters {
                self.page = .letters
                self.rebuildKeys()
            }
        case .returnKey:
            self.insert("\n")
        case .delete:
            break
        case .shift:
            let now = CACurrentMediaTime()
            if now - self.lastShiftTap < 0.3 {
                self.capsLocked = true
                self.shifted = true
            } else if self.capsLocked {
                self.capsLocked = false
                self.shifted = false
            } else {
                self.shifted.toggle()
            }
            self.lastShiftTap = now
            self.rebuildKeys()
        case .numbers:
            self.page = .numbers
            self.rebuildKeys()
        case .symbols:
            self.page = .symbols
            self.rebuildKeys()
        case .letters:
            self.page = .letters
            self.rebuildKeys()
        case .language:
            self.languageIndex = (self.languageIndex + 1) % self.languages.count
            UserDefaults.standard.set(self.language.id, forKey: "astragram.keyboard.language")
            self.shifted = false
            self.capsLocked = false
            self.rebuildKeys()
        case .systemKeyboard:
            self.switchToSystemKeyboard?()
        }
    }
}
