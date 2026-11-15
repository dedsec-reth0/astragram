import Foundation

/// AstraGram security: what is checked about an external link before it opens.
public enum AstraLinkSafety {
    public enum Warning {
        /// The host is written in punycode or with non-ASCII letters: it may imitate another site.
        case lookalikeLetters
        /// The host is an IP address, not a site's name.
        case ipAddress
        /// The host has Telegram in its name without being Telegram's.
        case imitatesTelegram
        /// The link downloads a file that can install or run something.
        case dangerousFile
    }

    /// Query parameters that only track where a click came from.
    private static let trackers: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "ysclid", "twclid", "ttclid",
        "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_anon_id", "oly_enc_id",
        "s_cid", "li_fat_id", "_openstat", "rb_clickid", "wickedid", "srsltid"
    ]

    private static let telegramHosts: [String] = [
        "telegram.org", "t.me", "telegram.me", "telegram.dog", "telegra.ph", "telesco.pe", "tg.dev", "fragment.com",
        "tdesktop.com", "telegram.space", "contest.com", "graph.org"
    ]

    private static let dangerousExtensions: Set<String> = [
        "apk", "exe", "scr", "bat", "cmd", "msi", "pif", "vbs", "jar", "ps1", "lnk", "dmg", "pkg", "ipa",
        "mobileconfig", "deb", "sh", "hta", "reg"
    ]

    private static let lock = NSLock()
    private static var confirmed = Set<String>()

    private static func webComponents(_ string: String) -> URLComponents? {
        guard let components = URLComponents(string: string), let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        return components
    }

    /// The link without its tracking parameters; the link itself when it has none or is not a web link.
    public static func removingTrackers(_ string: String) -> String {
        guard var components = AstraLinkSafety.webComponents(string), let items = components.percentEncodedQueryItems, !items.isEmpty else {
            return string
        }
        let host = (components.host ?? "").lowercased()
        let isMediaHost = host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be") || host.hasSuffix("spotify.com")
        let filtered = items.filter { item -> Bool in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") || AstraLinkSafety.trackers.contains(name) {
                return false
            }
            // `si` is a share identifier on these hosts, and an ordinary parameter elsewhere.
            if name == "si" && isMediaHost {
                return false
            }
            return true
        }
        if filtered.count == items.count {
            return string
        }
        components.percentEncodedQueryItems = filtered.isEmpty ? nil : filtered
        return components.string ?? string
    }

    /// What is suspicious about the link, if anything.
    public static func warning(for string: String) -> Warning? {
        guard let components = AstraLinkSafety.webComponents(string), let rawHost = components.host, !rawHost.isEmpty else {
            return nil
        }
        let host = rawHost.lowercased()
        if host.contains("xn--") || host.unicodeScalars.contains(where: { !$0.isASCII }) {
            return .lookalikeLetters
        }
        if host.contains(":") {
            return .ipAddress
        }
        let parts = host.split(separator: ".")
        if parts.count == 4 && parts.allSatisfy({ part -> Bool in
            if let value = Int(part) {
                return value >= 0 && value <= 255
            }
            return false
        }) {
            return .ipAddress
        }
        let isTelegram = AstraLinkSafety.telegramHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        if !isTelegram {
            // Digits and letter pairs that read as other letters, as in te1egram or telegrarn.
            let normalized = host
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "1", with: "l")
                .replacingOccurrences(of: "0", with: "o")
                .replacingOccurrences(of: "rn", with: "m")
                .replacingOccurrences(of: "q", with: "g")
            if normalized.contains("telegram") || normalized.contains("telegrarn") {
                return .imitatesTelegram
            }
        }
        let pathExtension = (components.path as NSString).pathExtension.lowercased()
        if !pathExtension.isEmpty && AstraLinkSafety.dangerousExtensions.contains(pathExtension) {
            return .dangerousFile
        }
        return nil
    }

    /// The user has seen the warning for this link and chose to open it: the next opening of it is not asked about.
    public static func confirm(_ string: String) {
        AstraLinkSafety.lock.lock()
        AstraLinkSafety.confirmed.insert(string)
        AstraLinkSafety.lock.unlock()
    }

    /// Whether the link was just confirmed; a confirmation is good for one opening.
    public static func consumeConfirmation(_ string: String) -> Bool {
        AstraLinkSafety.lock.lock()
        defer {
            AstraLinkSafety.lock.unlock()
        }
        return AstraLinkSafety.confirmed.remove(string) != nil
    }
}
