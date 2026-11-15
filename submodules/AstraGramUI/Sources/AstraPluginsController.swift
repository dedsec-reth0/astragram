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

private final class AstraPluginsArguments {
    let installFromFile: () -> Void
    let installFromClipboard: () -> Void
    let setEnabled: (String, Bool) -> Void
    let remove: (String) -> Void

    init(installFromFile: @escaping () -> Void, installFromClipboard: @escaping () -> Void, setEnabled: @escaping (String, Bool) -> Void, remove: @escaping (String) -> Void) {
        self.installFromFile = installFromFile
        self.installFromClipboard = installFromClipboard
        self.setEnabled = setEnabled
        self.remove = remove
    }
}

private enum AstraPluginsEntry: ItemListNodeEntry {
    case installFromFile(String)
    case installFromClipboard(String)
    case installFooter(String)
    case empty(String)
    case pluginHeader(index: Int, text: String)
    case pluginSwitch(index: Int, id: String, title: String, value: Bool)
    case pluginInfo(index: Int, text: String)
    case pluginDelete(index: Int, id: String, title: String)

    var section: ItemListSectionId {
        switch self {
        case .installFromFile, .installFromClipboard, .installFooter:
            return 0
        case .empty:
            return 1
        case let .pluginHeader(index, _), let .pluginSwitch(index, _, _, _), let .pluginInfo(index, _), let .pluginDelete(index, _, _):
            return Int32(2 + index)
        }
    }

    var stableId: Int32 {
        switch self {
        case .installFromFile:
            return 0
        case .installFromClipboard:
            return 1
        case .installFooter:
            return 2
        case .empty:
            return 3
        case let .pluginHeader(index, _):
            return Int32(100 + index * 4)
        case let .pluginSwitch(index, _, _, _):
            return Int32(101 + index * 4)
        case let .pluginInfo(index, _):
            return Int32(102 + index * 4)
        case let .pluginDelete(index, _, _):
            return Int32(103 + index * 4)
        }
    }

    static func <(lhs: AstraPluginsEntry, rhs: AstraPluginsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraPluginsArguments
        let section = self.section
        switch self {
        case let .installFromFile(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.installFromFile()
            })
        case let .installFromClipboard(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.installFromClipboard()
            })
        case let .installFooter(text), let .empty(text), let .pluginInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .pluginHeader(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .pluginSwitch(_, id, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: { value in
                AstraHaptics.toggle()
                arguments.setEnabled(id, value)
            })
        case let .pluginDelete(_, id, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.remove(id)
            })
        }
    }
}

private final class AstraDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
    }
}

/// AstraGram → Plugins.
public func astraPluginsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeControllerImpl: ((UIViewController) -> Void)?
    final class DelegateHolder {
        var delegate: AstraDocumentPickerDelegate?
    }
    let pickerDelegate = DelegateHolder()

    let manager = AstraPluginManager.shared

    func install(source: String?) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let strings = AstraStrings(presentationData.strings)
        if let source = source, manager.install(source: source) != nil {
            AstraHaptics.success()
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.pluginsInstalledDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
        } else {
            presentControllerImpl?(textAlertController(context: context, title: nil, text: strings.pluginsInvalid, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        }
    }

    let arguments = AstraPluginsArguments(
        installFromFile: {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
            let delegate = AstraDocumentPickerDelegate(completion: { url in
                pickerDelegate.delegate = nil
                guard let url = url else {
                    return
                }
                let accessing = url.startAccessingSecurityScopedResource()
                let source = try? String(contentsOf: url, encoding: .utf8)
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
                install(source: source)
            })
            pickerDelegate.delegate = delegate
            picker.delegate = delegate
            presentNativeControllerImpl?(picker)
        },
        installFromClipboard: {
            install(source: UIPasteboard.general.string)
        },
        setEnabled: { id, enabled in
            manager.setEnabled(id: id, enabled: enabled)
        },
        remove: { id in
            manager.remove(id: id)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        manager.plugins
    )
    |> map { presentationData, plugins -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        var entries: [AstraPluginsEntry] = []
        entries.append(.installFromFile(strings.pluginsInstall))
        entries.append(.installFromClipboard(strings.pluginsInstallFromClipboard))
        entries.append(.installFooter(strings.pluginsFooter))
        if plugins.isEmpty {
            entries.append(.empty(strings.pluginsEmpty))
        }
        for (index, plugin) in plugins.enumerated() {
            var header = plugin.name
            if !plugin.version.isEmpty {
                header += " " + plugin.version
            }
            entries.append(.pluginHeader(index: index, text: header.uppercased()))
            entries.append(.pluginSwitch(index: index, id: plugin.id, title: plugin.name, value: plugin.isEnabled))
            var info: [String] = []
            if !plugin.author.isEmpty {
                info.append("@" + plugin.author)
            }
            if !plugin.description.isEmpty {
                info.append(plugin.description)
            }
            if let error = plugin.error {
                info.append(error)
            }
            if !info.isEmpty {
                entries.append(.pluginInfo(index: index, text: info.joined(separator: "\n")))
            }
            entries.append(.pluginDelete(index: index, id: plugin.id, title: strings.pluginsDelete))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.plugins), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentNativeControllerImpl = { [weak controller] c in
        var presenter = controller?.view.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        presenter?.present(c, animated: true)
    }
    return controller
}
