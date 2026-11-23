import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import TranslateUI
import TranslationLanguagesContextMenuContent
import AstraGramUI

/// AstraGram: "Translate my messages" in this chat, from the attachment menu's "Translate" tab: Telegram's own
/// context menu and its own list of translation languages.
extension ChatControllerImpl {
    func astraOpenTranslateMenu(sourceView: UIView, inAttachment attachmentController: ViewController?) {
        guard let peerId = self.chatLocation.peerId else {
            return
        }
        let presentationData = self.presentationData
        let russian = presentationData.strings.baseLanguageCode.astraUsesRussianTexts
        let current = AstraOutgoingTranslation.language(peerId: peerId)
        let interfaceLanguage = normalizeTranslationLanguage(presentationData.strings.baseLanguageCode)
        let locale = Locale(identifier: interfaceLanguage)
        func name(_ code: String) -> String {
            return (locale.localizedString(forLanguageCode: code) ?? code).capitalized(with: locale)
        }

        var items: [ContextMenuItem] = []
        let title = current.flatMap { (russian ? "Переводить на: " : "Translate to: ") + name($0) } ?? (russian ? "Переводить мои сообщения" : "Translate My Messages")
        items.append(.action(ContextMenuActionItem(text: title, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Translate"), color: theme.contextMenu.primaryColor)
        }, action: { [weak self] c, _ in
            guard let self else {
                return
            }
            var languages: [(String, String)] = []
            for code in supportedTranslationLanguages {
                languages.append((code, name(code)))
            }
            c?.pushItems(items: .single(ContextController.Items(content: .custom(TranslationLanguagesContextMenuContent(
                context: self.context,
                languages: languages,
                selectedLanguages: current.flatMap { Set([$0]) },
                back: { [weak c] in
                    c?.popItems()
                },
                selectLanguage: { [weak c] code in
                    c?.dismiss(completion: nil)
                    AstraOutgoingTranslation.setLanguage(code, peerId: peerId)
                }
            )))))
        })))
        if current != nil {
            items.append(.action(ContextMenuActionItem(text: russian ? "Не переводить" : "Don't Translate", textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Restrict"), color: theme.contextMenu.destructiveColor)
            }, action: { c, _ in
                c?.dismiss(completion: nil)
                AstraOutgoingTranslation.setLanguage(nil, peerId: peerId)
            })))
        }
        items.append(.separator)
        items.append(.action(ContextMenuActionItem(text: russian ? "Перед отправкой ваше сообщение переводится, и в чат уходит перевод." : "Your messages are translated before sending, and the translation is sent.", textLayout: .multiline, textFont: .small, icon: { _ in return nil }, action: { _, _ in })))

        let contextController = makeContextController(presentationData: presentationData, source: .reference(ChatControllerContextReferenceContentSource(controller: self, sourceView: sourceView, insets: .zero)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        if let attachmentController {
            attachmentController.presentInGlobalOverlay(contextController)
        } else {
            self.presentInGlobalOverlay(contextController)
        }
    }
}
