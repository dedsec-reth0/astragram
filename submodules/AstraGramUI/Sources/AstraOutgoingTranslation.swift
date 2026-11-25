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

    /// Whether the translator answered with a refusal ("I cannot translate this text…") instead of a translation, as it
    /// does for text it cannot make sense of. Such an answer must never be sent in place of the user's message. A text
    /// that itself says so is translated to the same words, so the original is checked too.
    public static func isRefusal(original: String, translated: String) -> Bool {
        let answer = translated.lowercased()
        let markers = ["cannot translate", "can't translate", "can’t translate", "unable to translate", "not able to translate", "gibberish", "random characters", "random string", "language i do not recognize", "language i don't recognize", "language i don’t recognize"]
        guard markers.contains(where: { answer.contains($0) }) else {
            return false
        }
        let source = original.lowercased()
        return !["translat", "gibberish", "random", "перев", "бессмысл"].contains(where: { source.contains($0) })
    }

    public static func languageName(_ code: String, russian: Bool) -> String {
        guard let language = AstraOutgoingTranslation.languages.first(where: { $0.code == code }) else {
            return code
        }
        return russian ? language.ru : language.en
    }
}
