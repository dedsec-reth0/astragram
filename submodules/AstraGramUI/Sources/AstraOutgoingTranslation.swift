import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext

/// AstraGram: "Translate my messages" in chosen chats. What the user sends there is translated (by Telegram's
/// translation) into the language picked for that chat, and the translation is sent in its place.
public enum AstraOutgoingTranslation {
    private static let storageKey = "astragram.outgoingTranslation"

    /// The languages offered: a code Telegram's translation takes, and its name in Russian and English.
    public static let languages: [(code: String, ru: String, en: String)] = [
        ("en", "Английский", "English"),
        ("ru", "Русский", "Russian"),
        ("uk", "Украинский", "Ukrainian"),
        ("de", "Немецкий", "German"),
        ("fr", "Французский", "French"),
        ("es", "Испанский", "Spanish"),
        ("it", "Итальянский", "Italian"),
        ("pt", "Португальский", "Portuguese"),
        ("pl", "Польский", "Polish"),
        ("tr", "Турецкий", "Turkish"),
        ("ar", "Арабский", "Arabic"),
        ("zh", "Китайский", "Chinese"),
        ("ja", "Японский", "Japanese"),
        ("ko", "Корейский", "Korean"),
        ("hi", "Хинди", "Hindi"),
        ("kk", "Казахский", "Kazakh"),
        ("uz", "Узбекский", "Uzbek")
    ]

    private static func load() -> [String: String] {
        return (UserDefaults.standard.dictionary(forKey: AstraOutgoingTranslation.storageKey) as? [String: String]) ?? [:]
    }

    /// The language the user's messages in this chat are translated into (nil: not translated).
    public static func language(peerId: EnginePeer.Id) -> String? {
        return AstraOutgoingTranslation.load()["\(peerId.toInt64())"]
    }

    public static func setLanguage(_ code: String?, peerId: EnginePeer.Id) {
        var current = AstraOutgoingTranslation.load()
        current["\(peerId.toInt64())"] = code
        UserDefaults.standard.set(current, forKey: AstraOutgoingTranslation.storageKey)
    }

    public static func languageName(_ code: String, russian: Bool) -> String {
        guard let language = AstraOutgoingTranslation.languages.first(where: { $0.code == code }) else {
            return code
        }
        return russian ? language.ru : language.en
    }
}
