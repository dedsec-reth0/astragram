import Foundation
import UIKit
import TelegramCore

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

    /// Picks the language for a chat (or turns translation off), from the top screen.
    public static func presentPicker(peerId: EnginePeer.Id, russian: Bool, completion: @escaping () -> Void) {
        guard let top = astraTopViewController() else {
            return
        }
        let sheet = UIAlertController(title: russian ? "Переводить мои сообщения" : "Translate My Messages", message: russian ? "Перед отправкой ваше сообщение переводится на выбранный язык, и в чат уходит перевод." : "Before sending, your message is translated into the chosen language, and the translation is sent.", preferredStyle: .actionSheet)
        let current = AstraOutgoingTranslation.language(peerId: peerId)
        for language in AstraOutgoingTranslation.languages {
            let title = (russian ? language.ru : language.en) + (language.code == current ? " ✓" : "")
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                AstraOutgoingTranslation.setLanguage(language.code, peerId: peerId)
                completion()
            }))
        }
        if current != nil {
            sheet.addAction(UIAlertAction(title: russian ? "Не переводить" : "Don't Translate", style: .destructive, handler: { _ in
                AstraOutgoingTranslation.setLanguage(nil, peerId: peerId)
                completion()
            }))
        }
        sheet.addAction(UIAlertAction(title: russian ? "Отмена" : "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1.0, height: 1.0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}
