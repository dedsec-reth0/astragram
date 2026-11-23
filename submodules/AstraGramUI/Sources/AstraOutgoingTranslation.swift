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

    /// Picks the language for a chat (or turns translation off), in Telegram's own action sheet.
    public static func presentPicker(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void, completion: @escaping () -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let russian = presentationData.strings.baseLanguageCode.astraUsesRussianTexts
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let current = AstraOutgoingTranslation.language(peerId: peerId)
        var items: [ActionSheetItem] = [
            ActionSheetTextItem(title: russian ? "Перед отправкой ваше сообщение переводится на выбранный язык, и в чат уходит перевод." : "Before sending, your message is translated into the chosen language, and the translation is sent.")
        ]
        for language in AstraOutgoingTranslation.languages {
            items.append(ActionSheetCheckboxItem(title: russian ? language.ru : language.en, label: "", value: language.code == current, action: { [weak actionSheet] _ in
                actionSheet?.dismissAnimated()
                AstraOutgoingTranslation.setLanguage(language.code, peerId: peerId)
                completion()
            }))
        }
        var groups = [ActionSheetItemGroup(items: items)]
        if current != nil {
            groups.append(ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: russian ? "Не переводить" : "Don't Translate", color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    AstraOutgoingTranslation.setLanguage(nil, peerId: peerId)
                    completion()
                })
            ]))
        }
        groups.append(ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ]))
        actionSheet.setItemGroups(groups)
        present(actionSheet)
    }
}
