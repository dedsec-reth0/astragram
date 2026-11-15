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

private final class AstraMessageFiltersArguments {
    let update: ((inout AstraGramSettingsValues) -> Void) -> Void
    let updateDraft: (String) -> Void
    let add: () -> Void
    let select: (Int) -> Void

    init(update: @escaping ((inout AstraGramSettingsValues) -> Void) -> Void, updateDraft: @escaping (String) -> Void, add: @escaping () -> Void, select: @escaping (Int) -> Void) {
        self.update = update
        self.updateDraft = updateDraft
        self.add = add
        self.select = select
    }
}

private enum AstraMessageFiltersEntry: ItemListNodeEntry {
    case enabled(String, Bool)
    case draft(String, String)
    case add(String, Bool)
    case filter(index: Int, text: String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .enabled:
            return 0
        case .draft, .add:
            return 1
        case .filter, .footer:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case .enabled: return 0
        case .draft: return 2
        case .add: return 3
        case let .filter(index, _): return 100 + index
        case .footer: return 100000
        }
    }

    static func <(lhs: AstraMessageFiltersEntry, rhs: AstraMessageFiltersEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraMessageFiltersArguments
        switch self {
        case let .enabled(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                AstraHaptics.toggle()
                arguments.update { $0.messageFiltersEnabled = value }
            })
        case let .draft(text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .done, sectionId: self.section, textUpdated: { text in
                arguments.updateDraft(text)
            }, action: {
                arguments.add()
            })
        case let .add(title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .filter(index, text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.select(index)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func astraMessageFiltersController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let draft = ValuePromise<String>("", ignoreRepeated: true)
    let draftValue = Atomic<String>(value: "")

    let arguments = AstraMessageFiltersArguments(
        update: { f in
            AstraGramSettings.update(f)
        },
        updateDraft: { text in
            let _ = draftValue.swap(text)
            draft.set(text)
        },
        add: {
            let text = draftValue.with { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return
            }
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AstraStrings(presentationData.strings)
            if !AstraMessageFilterMatcher.isValid(text) {
                AstraHaptics.warning()
                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.invalidRegex, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
                return
            }
            AstraGramSettings.update { settings in
                if !settings.messageFilters.contains(text) {
                    settings.messageFilters.append(text)
                }
                settings.messageFiltersEnabled = true
            }
            AstraHaptics.success()
            let _ = draftValue.swap("")
            draft.set("")
        },
        select: { index in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let actionSheet = ActionSheetController(presentationData: presentationData)
            actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Delete, color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    AstraGramSettings.update { settings in
                        if index >= 0 && index < settings.messageFilters.count {
                            settings.messageFilters.remove(at: index)
                        }
                    }
                })
            ]), ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])])
            presentControllerImpl?(actionSheet)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        AstraGramSettings.signal,
        draft.get()
    )
    |> map { presentationData, settings, draftText -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        var entries: [AstraMessageFiltersEntry] = []
        entries.append(.enabled(strings.filtersEnabled, settings.messageFiltersEnabled))
        entries.append(.draft(draftText, strings.filterPlaceholder))
        entries.append(.add(strings.addFilter, !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        for (index, filter) in settings.messageFilters.enumerated() {
            entries.append(.filter(index: index, text: filter))
        }
        entries.append(.footer(strings.filtersFooter))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.filters), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
