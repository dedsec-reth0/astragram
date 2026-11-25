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

func astraFormatDate(_ timestamp: Int32, withSeconds: Bool = false) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = withSeconds ? .medium : .short
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

func astraPreviewText(text: String, mediaKind: AstraSavedMediaKind, fileName: String?, strings: AstraStrings) -> String {
    var parts: [String] = []
    if mediaKind != .none {
        if let fileName = fileName, !fileName.isEmpty {
            parts.append("\(strings.mediaKind(mediaKind)): \(fileName)")
        } else {
            parts.append(strings.mediaKind(mediaKind))
        }
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        parts.append(trimmed)
    }
    return parts.joined(separator: " · ")
}

// MARK: - Chats with deleted messages

private final class AstraDeletedChatsArguments {
    let openChat: (EnginePeer.Id?, String) -> Void

    init(openChat: @escaping (EnginePeer.Id?, String) -> Void) {
        self.openChat = openChat
    }
}

private enum AstraDeletedChatsEntryId: Hashable {
    case all
    case chat(Int64)
    case empty
}

private enum AstraDeletedChatsEntry: ItemListNodeEntry {
    case all(String, String)
    case chat(index: Int, peerId: EnginePeer.Id, title: String, label: String, detail: String)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .all:
            return 0
        case .chat, .empty:
            return 1
        }
    }

    var stableId: AstraDeletedChatsEntryId {
        switch self {
        case .all:
            return .all
        case let .chat(_, peerId, _, _, _):
            return .chat(peerId.toInt64())
        case .empty:
            return .empty
        }
    }

    static func ==(lhs: AstraDeletedChatsEntry, rhs: AstraDeletedChatsEntry) -> Bool {
        switch lhs {
        case let .all(a, b):
            if case let .all(c, d) = rhs, a == c, b == d {
                return true
            }
            return false
        case let .chat(index, peerId, title, label, detail):
            if case let .chat(rIndex, rPeerId, rTitle, rLabel, rDetail) = rhs, index == rIndex, peerId == rPeerId, title == rTitle, label == rLabel, detail == rDetail {
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

    static func <(lhs: AstraDeletedChatsEntry, rhs: AstraDeletedChatsEntry) -> Bool {
        return lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .all:
            return -1
        case let .chat(index, _, _, _, _):
            return index
        case .empty:
            return Int.max
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraDeletedChatsArguments
        switch self {
        case let .all(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, titleFont: .bold, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openChat(nil, title)
            })
        case let .chat(_, peerId, title, label, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, additionalDetailLabel: detail, sectionId: self.section, style: .blocks, action: {
                arguments.openChat(peerId, title)
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        }
    }
}

public func astraDeletedChatsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let store = AstraMessageStore.forAccount(context.account)

    let arguments = AstraDeletedChatsArguments(openChat: { peerId, title in
        pushControllerImpl?(astraDeletedMessagesController(context: context, peerId: peerId, title: title))
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        store.chatsWithDeletedMessages()
    )
    |> map { presentationData, chats -> (ItemListControllerState, (ItemListNodeState, Any)) in
        // AstraGram security: a chat locked with Face ID shows here only once it is unlocked (opened with Face ID).
        let chats = chats.filter { AstraChatLock.canShow($0.peerId.toInt64()) }
        let strings = AstraStrings(presentationData.strings)
        var entries: [AstraDeletedChatsEntry] = []
        if chats.isEmpty {
            entries.append(.empty(strings.noDeletedMessages))
        } else {
            let total = chats.reduce(0, { $0 + $1.count })
            entries.append(.all(strings.allChats, "\(total)"))
            for (index, chat) in chats.enumerated() {
                entries.append(.chat(index: index, peerId: chat.peerId, title: chat.title.isEmpty ? "\(chat.peerId.id._internalGetInt64Value())" : chat.title, label: "\(chat.count)", detail: astraFormatDate(chat.lastDeletedAt)))
            }
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.deletedMessages), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

// MARK: - Deleted messages of a chat

private final class AstraDeletedMessagesArguments {
    let select: (AstraDeletedMessageRecord) -> Void

    init(select: @escaping (AstraDeletedMessageRecord) -> Void) {
        self.select = select
    }
}

private enum AstraDeletedMessagesEntry: ItemListNodeEntry {
    case message(index: Int, record: AstraDeletedMessageRecord, title: String, label: String, detail: String)
    case empty(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int64 {
        switch self {
        case let .message(_, record, _, _, _):
            return record.rowId
        case .empty:
            return -1
        }
    }

    static func ==(lhs: AstraDeletedMessagesEntry, rhs: AstraDeletedMessagesEntry) -> Bool {
        switch lhs {
        case let .message(index, record, title, label, detail):
            if case let .message(rIndex, rRecord, rTitle, rLabel, rDetail) = rhs, index == rIndex, record == rRecord, title == rTitle, label == rLabel, detail == rDetail {
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

    static func <(lhs: AstraDeletedMessagesEntry, rhs: AstraDeletedMessagesEntry) -> Bool {
        return lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case let .message(index, _, _, _, _):
            return index
        case .empty:
            return Int.max
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraDeletedMessagesArguments
        switch self {
        case let .message(_, record, title, label, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail.isEmpty ? label : label + "\n" + detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.select(record)
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section, textAlignment: .center)
        }
    }
}

public func astraDeletedMessagesController(context: AccountContext, peerId: EnginePeer.Id?, title: String) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var openChatImpl: ((AstraDeletedMessageRecord) -> Void)?
    let store = AstraMessageStore.forAccount(context.account)

    let arguments = AstraDeletedMessagesArguments(select: { record in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let strings = AstraStrings(presentationData.strings)
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        let header = "\(strings.sentAt) \(astraFormatDate(record.timestamp, withSeconds: true))\n\(strings.deletedAt) \(astraFormatDate(record.deletedAt, withSeconds: true))"
        items.append(ActionSheetTextItem(title: header, parseMarkdown: false))
        if !record.text.isEmpty {
            items.append(ActionSheetButtonItem(title: strings.copyText, color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                storeMessageTextInPasteboard(record.text, entities: record.entities)
                AstraHaptics.success()
                presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .copy(text: presentationData.strings.Conversation_TextCopied), elevatedLayout: false, action: { _ in return false }))
            }))
        }
        items.append(ActionSheetButtonItem(title: strings.openInChat, color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            openChatImpl?(record)
        }))
        items.append(ActionSheetButtonItem(title: strings.removeFromHistory, color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            store.removeDeletedMessage(rowId: record.rowId)
        }))
        actionSheet.setItemGroups([ActionSheetItemGroup(items: items), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentControllerImpl?(actionSheet)
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        store.deletedMessages(peerId: peerId)
    )
    |> map { presentationData, records -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let records = records.filter { AstraChatLock.canShow($0.peerId.toInt64()) }
        let strings = AstraStrings(presentationData.strings)
        var entries: [AstraDeletedMessagesEntry] = []
        if records.isEmpty {
            entries.append(.empty(strings.noDeletedMessages))
        }
        for (index, record) in records.enumerated() {
            var rowTitle = record.isOutgoing ? strings.you : record.authorName
            if rowTitle.isEmpty {
                rowTitle = record.chatTitle
            }
            if peerId == nil, !record.chatTitle.isEmpty, record.chatTitle != rowTitle {
                rowTitle = "\(rowTitle) → \(record.chatTitle)"
            }
            let detail = astraPreviewText(text: record.text, mediaKind: record.mediaKind, fileName: record.fileName, strings: strings)
            entries.append(.message(index: index, record: record, title: rowTitle, label: astraFormatDate(record.deletedAt), detail: detail))
        }

        var rightButton: ItemListNavigationButton?
        if !records.isEmpty {
            rightButton = ItemListNavigationButton(content: .text(strings.clearChatHistory), style: .regular, enabled: true, action: {
                AstraHaptics.warning()
                // The saved messages cannot be restored: ask first.
                let actionSheet = ActionSheetController(presentationData: presentationData)
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                    ActionSheetTextItem(title: strings.clearDeletedConfirm),
                    ActionSheetButtonItem(title: strings.clearChatHistory, color: .destructive, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        store.clearDeletedMessages(peerId: peerId)
                        AstraHaptics.success()
                    })
                ]), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet)
            })
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    openChatImpl = { [weak controller] record in
        guard let navigationController = controller?.navigationController as? NavigationController else {
            return
        }
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: record.peerId))
        |> deliverOnMainQueue).start(next: { peer in
            guard let peer = peer else {
                return
            }
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(record.messageId), highlight: nil, timecode: nil, setupReply: false)))
        })
    }
    return controller
}
