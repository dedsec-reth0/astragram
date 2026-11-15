import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI

// MARK: - A list of strings (templates, keyword alerts)

private final class AstraStringListArguments {
    let updateDraft: (String) -> Void
    let add: () -> Void
    let select: (Int) -> Void

    init(updateDraft: @escaping (String) -> Void, add: @escaping () -> Void, select: @escaping (Int) -> Void) {
        self.updateDraft = updateDraft
        self.add = add
        self.select = select
    }
}

private enum AstraStringListEntry: ItemListNodeEntry {
    case draft(String, String)
    case add(String, Bool)
    case value(index: Int, text: String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .draft, .add:
            return 0
        case .value, .footer:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .draft: return 0
        case .add: return 1
        case let .value(index, _): return 100 + index
        case .footer: return 1000000
        }
    }

    static func <(lhs: AstraStringListEntry, rhs: AstraStringListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraStringListArguments
        switch self {
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
        case let .value(index, text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.select(index)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Edits a list of strings in the AstraGram settings (message templates, keyword alerts).
public func astraStringListController(context: AccountContext, title: String, placeholder: String, footer: String, keyPath: WritableKeyPath<AstraGramSettingsValues, [String]>, validate: @escaping (String) -> Bool = { _ in true }) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let draft = ValuePromise<String>("", ignoreRepeated: true)
    let draftValue = Atomic<String>(value: "")

    let arguments = AstraStringListArguments(
        updateDraft: { text in
            let _ = draftValue.swap(text)
            draft.set(text)
        },
        add: {
            let text = draftValue.with { $0 }.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return
            }
            if !validate(text) {
                AstraHaptics.warning()
                return
            }
            AstraGramSettings.update { settings in
                if !settings[keyPath: keyPath].contains(text) {
                    settings[keyPath: keyPath].append(text)
                }
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
                        if index >= 0 && index < settings[keyPath: keyPath].count {
                            settings[keyPath: keyPath].remove(at: index)
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

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, AstraGramSettings.signal, draft.get())
    |> map { presentationData, settings, draftText -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        var entries: [AstraStringListEntry] = []
        entries.append(.draft(draftText, placeholder))
        entries.append(.add(strings.listAdd, !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        for (index, item) in settings[keyPath: keyPath].enumerated() {
            entries.append(.value(index: index, text: item))
        }
        entries.append(.footer(footer))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - AI settings

private final class AstraAIArguments {
    let update: ((inout AstraGramSettingsValues) -> Void) -> Void
    let test: () -> Void

    init(update: @escaping ((inout AstraGramSettingsValues) -> Void) -> Void, test: @escaping () -> Void) {
        self.update = update
        self.test = test
    }
}

private enum AstraAIEntry: ItemListNodeEntry {
    case header(String)
    case endpoint(String, String)
    case apiKey(String, String)
    case model(String, String)
    case test(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .endpoint, .apiKey, .model:
            return 0
        case .test, .footer:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .header: return 0
        case .endpoint: return 1
        case .apiKey: return 2
        case .model: return 3
        case .test: return 4
        case .footer: return 5
        }
    }

    static func <(lhs: AstraAIEntry, rhs: AstraAIEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraAIArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .endpoint(title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: "https://api.openai.com/v1", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { text in
                arguments.update { $0.aiEndpoint = text }
            }, action: {})
        case let .apiKey(title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: "sk-…", type: .password, sectionId: self.section, textUpdated: { text in
                arguments.update { $0.aiApiKey = text }
            }, action: {})
        case let .model(title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: "gpt-4o-mini", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { text in
                arguments.update { $0.aiModel = text }
            }, action: {})
        case let .test(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.test()
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// AstraGram → AI: the API used by the AI actions in the message menu.
public func astraAIController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let arguments = AstraAIArguments(update: { f in
        AstraGramSettings.update(f)
    }, test: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let strings = AstraStrings(presentationData.strings)
        AstraAI.complete(system: "You are a test. Answer with one short sentence.", user: strings.isRussian ? "Скажи, что всё работает." : "Say that everything works.", completion: { result in
            let text: String
            switch result {
            case let .success(answer):
                text = "✅ " + answer
            case let .failure(error):
                text = AstraAI.describe(error, isRussian: strings.isRussian)
            }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        })
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, AstraGramSettings.signal |> map { settings -> [String] in
        return [settings.aiEndpoint, settings.aiApiKey, settings.aiModel]
    } |> distinctUntilChanged)
    |> map { presentationData, values -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        let entries: [AstraAIEntry] = [
            .header(strings.aiHeader),
            .endpoint("URL", values[0]),
            .apiKey(strings.aiKey, values[1]),
            .model(strings.aiModel, values[2]),
            .test(strings.aiTest),
            .footer(strings.aiFooter)
        ]
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("AI"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: - Bookmarks

private final class AstraBookmarksArguments {
    let open: (AstraBookmark) -> Void
    let remove: (AstraBookmark) -> Void
    let clear: () -> Void

    init(open: @escaping (AstraBookmark) -> Void, remove: @escaping (AstraBookmark) -> Void, clear: @escaping () -> Void) {
        self.open = open
        self.remove = remove
        self.clear = clear
    }
}

private enum AstraBookmarksEntry: ItemListNodeEntry {
    case bookmark(index: Int, AstraBookmark, String)
    case empty(String)
    case clear(String)

    var section: ItemListSectionId {
        switch self {
        case .bookmark, .empty:
            return 0
        case .clear:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case let .bookmark(index, _, _): return 10 + index
        case .empty: return 0
        case .clear: return 1000000
        }
    }

    static func <(lhs: AstraBookmarksEntry, rhs: AstraBookmarksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraBookmarksArguments
        switch self {
        case let .bookmark(_, bookmark, dateText):
            let preview = bookmark.text.isEmpty ? "📎" : String(bookmark.text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: preview, label: bookmark.chatTitle + " · " + dateText, labelStyle: .detailText, sectionId: self.section, style: .blocks, action: {
                arguments.open(bookmark)
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .clear(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        }
    }
}

/// AstraGram → Bookmarks: messages bookmarked from the message menu, on this device.
public func astraBookmarksController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?

    let arguments = AstraBookmarksArguments(open: { bookmark in
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: bookmark.engineMessageId.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer = peer, let navigationController = navigationControllerImpl?() else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(bookmark.engineMessageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
        })
    }, remove: { bookmark in
        AstraBookmarks.remove(id: bookmark.engineMessageId)
    }, clear: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let strings = AstraStrings(presentationData.strings)
        presentControllerImpl?(textAlertController(context: context, title: nil, text: strings.bookmarksClearConfirm, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: strings.bookmarksClear, action: {
                AstraBookmarks.replaceAll([])
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, AstraBookmarks.signal)
    |> map { presentationData, bookmarks -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        var entries: [AstraBookmarksEntry] = []
        if bookmarks.isEmpty {
            entries.append(.empty(strings.bookmarksEmpty))
        } else {
            for (index, bookmark) in bookmarks.enumerated() {
                entries.append(.bookmark(index: index, bookmark, formatter.string(from: Date(timeIntervalSince1970: Double(bookmark.date)))))
            }
            entries.append(.clear(strings.bookmarksClear))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.bookmarks), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    return controller
}

// MARK: - Backup

/// AstraGram settings, templates, keyword alerts, bookmarks and plugins in one JSON file.
public enum AstraBackup {
    public static func exportData() -> Data? {
        var object: [String: Any] = ["format": "ayugram-ios-backup", "version": 1]
        if let settingsData = try? JSONEncoder().encode(AstraGramSettings.current), let settings = try? JSONSerialization.jsonObject(with: settingsData) {
            object["settings"] = settings
        }
        if let bookmarksData = try? JSONEncoder().encode(AstraBookmarks.all), let bookmarks = try? JSONSerialization.jsonObject(with: bookmarksData) {
            object["bookmarks"] = bookmarks
        }
        object["plugins"] = AstraPluginManager.shared.exportSources()
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    /// Restores a backup. Returns false when the data is not an AstraGram backup.
    public static func importData(_ data: Data) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], object["format"] as? String == "ayugram-ios-backup" else {
            return false
        }
        // JSONSerialization raises an Objective-C exception (which `try?` does not catch) for a value that is not an
        // object or an array: the types are checked first.
        if let settings = object["settings"] as? [String: Any], let settingsData = try? JSONSerialization.data(withJSONObject: settings) {
            AstraGramSettings.replace(withJSON: settingsData)
        }
        if let bookmarks = object["bookmarks"] as? [Any], let bookmarksData = try? JSONSerialization.data(withJSONObject: bookmarks), let decoded = try? JSONDecoder().decode([AstraBookmark].self, from: bookmarksData) {
            AstraBookmarks.replaceAll(decoded)
        }
        if let plugins = object["plugins"] as? [String] {
            for source in plugins {
                AstraPluginManager.shared.install(source: source)
            }
        }
        return true
    }
}
