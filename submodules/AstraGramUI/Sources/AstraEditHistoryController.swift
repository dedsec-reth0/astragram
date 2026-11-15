import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import Pasteboard

private final class AstraEditHistoryArguments {
    let copy: (String, [MessageTextEntity]) -> Void

    init(copy: @escaping (String, [MessageTextEntity]) -> Void) {
        self.copy = copy
    }
}

private enum AstraEditHistoryEntry: ItemListNodeEntry {
    /// `text` is the shown preview (with the media kind), `rawText` the message text that is copied.
    case version(index: Int, title: String, date: String, text: String, rawText: String, entities: [MessageTextEntity])
    case current(title: String, date: String, text: String, entities: [MessageTextEntity])
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .version:
            return 0
        case .current:
            return 1
        case .empty:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case let .version(index, _, _, _, _, _):
            return index
        case .current:
            return 100000
        case .empty:
            return 100001
        }
    }

    static func ==(lhs: AstraEditHistoryEntry, rhs: AstraEditHistoryEntry) -> Bool {
        switch lhs {
        case let .version(index, title, date, text, rawText, entities):
            if case let .version(rIndex, rTitle, rDate, rText, rRawText, rEntities) = rhs, index == rIndex, title == rTitle, date == rDate, text == rText, rawText == rRawText, entities == rEntities {
                return true
            }
            return false
        case let .current(title, date, text, entities):
            if case let .current(rTitle, rDate, rText, rEntities) = rhs, title == rTitle, date == rDate, text == rText, entities == rEntities {
                return true
            }
            return false
        case let .empty(text):
            if case let .empty(rText) = rhs, text == rText {
                return true
            }
            return false
        }
    }

    static func <(lhs: AstraEditHistoryEntry, rhs: AstraEditHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraEditHistoryArguments
        switch self {
        case let .version(_, title, date, text, rawText, entities):
            // The date goes into the title: a detail label and an additional detail label are drawn on the same line.
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title + " · " + date, label: text, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.copy(rawText, entities)
            })
        case let .current(title, date, text, entities):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title + " · " + date, label: text, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.copy(text, entities)
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        }
    }
}

/// Earlier versions of a message, oldest first, followed by the current one. Tapping a version copies its text.
public func astraEditHistoryController(context: AccountContext, message: EngineMessage) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let store = AstraMessageStore.forAccount(context.account)

    let arguments = AstraEditHistoryArguments(copy: { text, entities in
        guard !text.isEmpty else {
            return
        }
        storeMessageTextInPasteboard(text, entities: entities)
        AstraHaptics.success()
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: presentationData.strings.Conversation_TextCopied), elevatedLayout: false, action: { _ in return false }))
    })

    var currentEntities: [MessageTextEntity] = []
    var currentEditDate: Int32?
    for attribute in message.attributes {
        if let attribute = attribute as? TextEntitiesMessageAttribute {
            currentEntities = attribute.entities
        } else if let attribute = attribute as? EditedMessageAttribute {
            currentEditDate = attribute.date
        }
    }
    let currentText = message.text
    let currentDate = currentEditDate ?? message.timestamp
    let entitiesValue = currentEntities

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        store.editHistory(messageId: message.id)
    )
    |> map { presentationData, versions -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        var entries: [AstraEditHistoryEntry] = []
        for (index, version) in versions.enumerated() {
            let title = index == 0 ? strings.originalVersion : strings.versionN(index + 1)
            let text = astraPreviewText(text: version.text, mediaKind: version.mediaKind, fileName: nil, strings: strings)
            entries.append(.version(index: index, title: title, date: astraFormatDate(version.versionDate, withSeconds: true), text: text, rawText: version.text, entities: version.entities))
        }
        if versions.isEmpty {
            entries.append(.empty(strings.noEditHistory))
        }
        entries.append(.current(title: strings.currentVersion, date: astraFormatDate(currentDate, withSeconds: true), text: currentText, entities: entitiesValue))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.editHistory), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
