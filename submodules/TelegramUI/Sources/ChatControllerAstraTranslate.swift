import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import AttachmentUI
import TranslateUI
import AstraGramUI

/// AstraGram: the attachment menu's "Translate" tab: which language the user's own messages go out in, and which
/// language the others' messages in this chat are shown in. Telegram's own list look, in the attachment sheet.
final class AstraTranslateAttachmentScreen: ItemListController, AttachmentContainable {
    var requestAttachmentMenuExpansion: () -> Void = {}
    var updateNavigationStack: (@escaping ([AttachmentContainable]) -> ([AttachmentContainable], AttachmentMediaPickerContext?)) -> Void = { _ in }
    var updateTabBarAlpha: (CGFloat, ContainedViewLayoutTransition) -> Void = { _, _ in }
    var updateTabBarVisibility: (Bool, ContainedViewLayoutTransition) -> Void = { _, _ in }
    var cancelPanGesture: () -> Void = {}
    var isContainerPanning: () -> Bool = { return false }
    var isContainerExpanded: () -> Bool = { return false }
    var parentController: () -> ViewController? = { return nil }
    var isMinimized: Bool = false
    var mediaPickerContext: AttachmentMediaPickerContext? {
        return nil
    }
}

private enum AstraTranslateMode: Int {
    case mine
    case theirs
}

private final class AstraTranslateArguments {
    let selectMode: (AstraTranslateMode) -> Void
    let selectLanguage: (String?) -> Void

    init(selectMode: @escaping (AstraTranslateMode) -> Void, selectLanguage: @escaping (String?) -> Void) {
        self.selectMode = selectMode
        self.selectLanguage = selectLanguage
    }
}

private enum AstraTranslateEntry: ItemListNodeEntry {
    case modeHeader(String)
    case mode(AstraTranslateMode, String, String, Bool)
    case modeFooter(String)
    case languageHeader(String)
    case off(String, Bool)
    case language(Int, String, String, Bool)

    var section: ItemListSectionId {
        switch self {
        case .modeHeader, .mode, .modeFooter:
            return 0
        case .languageHeader, .off, .language:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .modeHeader: return 0
        case let .mode(mode, _, _, _): return 1 + mode.rawValue
        case .modeFooter: return 9
        case .languageHeader: return 10
        case .off: return 11
        case let .language(index, _, _, _): return 100 + index
        }
    }

    static func ==(lhs: AstraTranslateEntry, rhs: AstraTranslateEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.modeHeader(a), .modeHeader(b)), let (.modeFooter(a), .modeFooter(b)), let (.languageHeader(a), .languageHeader(b)):
            return a == b
        case let (.mode(a1, a2, a3, a4), .mode(b1, b2, b3, b4)):
            return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case let (.off(a1, a2), .off(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.language(a1, a2, a3, a4), .language(b1, b2, b3, b4)):
            return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        default:
            return false
        }
    }

    static func <(lhs: AstraTranslateEntry, rhs: AstraTranslateEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraTranslateArguments
        switch self {
        case let .modeHeader(text), let .languageHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .mode(mode, title, value, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, subtitle: value, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectMode(mode)
            })
        case let .modeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .off(title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectLanguage(nil)
            })
        case let .language(_, code, title, selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.selectLanguage(code)
            })
        }
    }
}

extension ChatControllerImpl {
    func astraTranslateAttachmentScreen() -> AstraTranslateAttachmentScreen? {
        guard let peerId = self.chatLocation.peerId else {
            return nil
        }
        let context = self.context
        let mode = ValuePromise<AstraTranslateMode>(.mine, ignoreRepeated: true)
        let modeValue = Atomic<AstraTranslateMode>(value: .mine)
        let changed = ValuePromise<Int>(0, ignoreRepeated: false)
        let changes = Atomic<Int>(value: 0)
        var dismissImpl: (() -> Void)?
        // The settings are this chat's own: its name stands under the title.
        let chatTitle = self.presentationInterfaceState.renderedPeer?.chatMainPeer.flatMap { EnginePeer($0).compactDisplayTitle } ?? ""

        let arguments = AstraTranslateArguments(selectMode: { value in
            let _ = modeValue.swap(value)
            mode.set(value)
        }, selectLanguage: { code in
            switch modeValue.with({ $0 }) {
            case .mine:
                AstraOutgoingTranslation.setLanguage(code, peerId: peerId)
            case .theirs:
                AstraIncomingTranslation.setLanguage(code, peerId: peerId)
            }
            changed.set(changes.modify { $0 + 1 })
        })

        let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, mode.get(), changed.get())
        |> map { presentationData, currentMode, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let russian = presentationData.strings.baseLanguageCode.astraUsesRussianTexts
            let locale = Locale(identifier: normalizeTranslationLanguage(presentationData.strings.baseLanguageCode))
            func name(_ code: String?) -> String {
                guard let code else {
                    return russian ? "Не переводить" : "Off"
                }
                return (locale.localizedString(forLanguageCode: code) ?? code).capitalized(with: locale)
            }
            let mine = AstraOutgoingTranslation.language(peerId: peerId)
            let theirs = AstraIncomingTranslation.language(peerId: peerId)
            let current = currentMode == .mine ? mine : theirs

            var entries: [AstraTranslateEntry] = []
            entries.append(.modeHeader(russian ? "ЧТО ПЕРЕВОДИТЬ В ЭТОМ ЧАТЕ" : "TRANSLATE IN THIS CHAT"))
            entries.append(.mode(.mine, russian ? "Мои сообщения" : "My Messages", name(mine), currentMode == .mine))
            entries.append(.mode(.theirs, russian ? "Сообщения собеседника" : "Their Messages", name(theirs), currentMode == .theirs))
            entries.append(.modeFooter(currentMode == .mine
                ? (russian ? "Перед отправкой ваше сообщение переводится на выбранный язык, и в чат уходит перевод." : "Your message is translated into this language before it is sent, and the translation goes to the chat.")
                : (russian ? "Сообщения собеседника в этом чате показываются переведёнными на выбранный язык." : "The other side's messages in this chat are shown translated into this language.")))
            entries.append(.languageHeader(russian ? "ЯЗЫК" : "LANGUAGE"))
            entries.append(.off(name(nil), current == nil))
            var languages = supportedTranslationLanguages.map { ($0, name($0)) }
            languages.sort { $0.1.localizedCompare($1.1) == .orderedAscending }
            for (index, language) in languages.enumerated() {
                entries.append(.language(index, language.0, language.1, language.0 == current))
            }

            let close = ItemListNavigationButton(content: .icon(.close), style: .regular, enabled: true, action: {
                dismissImpl?()
            })
            let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: chatTitle.isEmpty ? .text(russian ? "Перевод" : "Translation") : .textWithSubtitle(russian ? "Перевод" : "Translation", (russian ? "только для чата «" : "this chat only: «") + chatTitle + "»"), leftNavigationButton: close, rightNavigationButton: nil, backNavigationButton: nil)
            let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
            return (controllerState, (listState, arguments))
        }

        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = AstraTranslateAttachmentScreen(presentationData: ItemListPresentationData(presentationData), updatedPresentationData: context.sharedContext.presentationData |> map { ItemListPresentationData($0) }, state: signal, tabBarItem: nil)
        dismissImpl = { [weak self] in
            self?.attachmentController?.dismiss(animated: true)
        }
        return controller
    }
}
