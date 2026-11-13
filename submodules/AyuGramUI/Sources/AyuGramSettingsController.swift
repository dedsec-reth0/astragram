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

/// Sections of Telegram's own settings that the AyuGram screen links to.
public enum AyuLinkedTelegramSettings {
    case appearance
    case language
}

/// A shared haptic generator for AyuGram controls; honours the "Haptic feedback" setting.
public enum AyuHaptics {
    private static let feedback = HapticFeedback()

    public static func toggle() {
        if AyuGramSettings.current.hapticFeedback {
            AyuHaptics.feedback.impact(.light)
        }
    }

    public static func success() {
        if AyuGramSettings.current.hapticFeedback {
            AyuHaptics.feedback.success()
        }
    }

    public static func warning() {
        if AyuGramSettings.current.hapticFeedback {
            AyuHaptics.feedback.warning()
        }
    }
}

private final class AyuGramSettingsArguments {
    let update: ((inout AyuGramSettingsValues) -> Void) -> Void
    let openDeletedMessages: () -> Void
    let openFilters: () -> Void
    let openLinked: (AyuLinkedTelegramSettings) -> Void
    let clearHistory: () -> Void
    let reset: () -> Void

    init(
        update: @escaping ((inout AyuGramSettingsValues) -> Void) -> Void,
        openDeletedMessages: @escaping () -> Void,
        openFilters: @escaping () -> Void,
        openLinked: @escaping (AyuLinkedTelegramSettings) -> Void,
        clearHistory: @escaping () -> Void,
        reset: @escaping () -> Void
    ) {
        self.update = update
        self.openDeletedMessages = openDeletedMessages
        self.openFilters = openFilters
        self.openLinked = openLinked
        self.clearHistory = clearHistory
        self.reset = reset
    }
}

private enum AyuGramSettingsSection: Int32 {
    case ghostMaster
    case ghost
    case antiDelete
    case storage
    case appearance
    case filters
    case translator
    case about
}

private enum AyuGramSettingsEntry: ItemListNodeEntry {
    case ghostHeader(String)
    case ghostMaster(String, Bool)
    case ghostMasterFooter(String)

    case hideOnline(String, Bool)
    case hideRead(String, Bool)
    case hideStories(String, Bool)
    case hideTyping(String, Bool)
    case hideContents(String, Bool)
    case markReadAfterSend(String, Bool, enabled: Bool)
    case ghostFooter(String)

    case antiDeleteHeader(String)
    case saveDeleted(String, Bool)
    case keepInChat(String, Bool)
    case saveInChannels(String, Bool, enabled: Bool)
    case saveEdits(String, Bool)
    case antiDeleteFooter(String)

    case deletedMessages(String, String)
    case storageSize(String, String)
    case clearHistory(String)

    case appearanceHeader(String)
    case deletedMark(String, String)
    case editedMark(String, String, String)
    case showSeconds(String, Bool)
    case showPeerId(String, Bool)
    case hideSponsored(String, Bool)
    case hideStoriesInList(String, Bool)
    case confirmSticker(String, Bool)
    case haptics(String, Bool)
    case openAppearance(String)
    case appearanceFooter(String)

    case filtersHeader(String)
    case filters(String, String)

    case translatorHeader(String)
    case translator(String)
    case translatorFooter(String)

    case aboutHeader(String)
    case reset(String)
    case version(String)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMaster, .ghostMasterFooter:
            return AyuGramSettingsSection.ghostMaster.rawValue
        case .hideOnline, .hideRead, .hideStories, .hideTyping, .hideContents, .markReadAfterSend, .ghostFooter:
            return AyuGramSettingsSection.ghost.rawValue
        case .antiDeleteHeader, .saveDeleted, .keepInChat, .saveInChannels, .saveEdits, .antiDeleteFooter:
            return AyuGramSettingsSection.antiDelete.rawValue
        case .deletedMessages, .storageSize, .clearHistory:
            return AyuGramSettingsSection.storage.rawValue
        case .appearanceHeader, .deletedMark, .editedMark, .showSeconds, .showPeerId, .hideSponsored, .hideStoriesInList, .confirmSticker, .haptics, .openAppearance, .appearanceFooter:
            return AyuGramSettingsSection.appearance.rawValue
        case .filtersHeader, .filters:
            return AyuGramSettingsSection.filters.rawValue
        case .translatorHeader, .translator, .translatorFooter:
            return AyuGramSettingsSection.translator.rawValue
        case .aboutHeader, .reset, .version:
            return AyuGramSettingsSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader: return 0
        case .ghostMaster: return 1
        case .ghostMasterFooter: return 2
        case .hideOnline: return 10
        case .hideRead: return 11
        case .hideStories: return 12
        case .hideTyping: return 13
        case .hideContents: return 14
        case .markReadAfterSend: return 15
        case .ghostFooter: return 16
        case .antiDeleteHeader: return 20
        case .saveDeleted: return 21
        case .keepInChat: return 22
        case .saveInChannels: return 23
        case .saveEdits: return 24
        case .antiDeleteFooter: return 25
        case .deletedMessages: return 30
        case .storageSize: return 31
        case .clearHistory: return 32
        case .appearanceHeader: return 40
        case .deletedMark: return 41
        case .editedMark: return 42
        case .showSeconds: return 43
        case .showPeerId: return 44
        case .hideSponsored: return 45
        case .hideStoriesInList: return 46
        case .confirmSticker: return 47
        case .haptics: return 48
        case .openAppearance: return 49
        case .appearanceFooter: return 50
        case .filtersHeader: return 60
        case .filters: return 61
        case .translatorHeader: return 70
        case .translator: return 71
        case .translatorFooter: return 72
        case .aboutHeader: return 80
        case .reset: return 81
        case .version: return 82
        }
    }

    static func <(lhs: AyuGramSettingsEntry, rhs: AyuGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuGramSettingsArguments
        let section = self.section

        func toggle(_ title: String, _ value: Bool, enabled: Bool = true, _ apply: @escaping (inout AyuGramSettingsValues, Bool) -> Void) -> ListViewItem {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: section, style: .blocks, updated: { value in
                AyuHaptics.toggle()
                arguments.update { settings in
                    apply(&settings, value)
                }
            })
        }

        switch self {
        case let .ghostHeader(text), let .antiDeleteHeader(text), let .appearanceHeader(text), let .filtersHeader(text), let .translatorHeader(text), let .aboutHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .ghostMasterFooter(text), let .ghostFooter(text), let .antiDeleteFooter(text), let .appearanceFooter(text), let .translatorFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .ghostMaster(title, value):
            return toggle(title, value) { settings, value in
                settings.setGhostMode(value)
            }
        case let .hideOnline(title, value):
            return toggle(title, value) { $0.hideOnlineStatus = $1 }
        case let .hideRead(title, value):
            return toggle(title, value) { $0.hideReadReceipts = $1 }
        case let .hideStories(title, value):
            return toggle(title, value) { $0.hideStoryViews = $1 }
        case let .hideTyping(title, value):
            return toggle(title, value) { $0.hideTyping = $1 }
        case let .hideContents(title, value):
            return toggle(title, value) { $0.hideMessageContentsRead = $1 }
        case let .markReadAfterSend(title, value, enabled):
            return toggle(title, value, enabled: enabled) { $0.markReadAfterSend = $1 }
        case let .saveDeleted(title, value):
            return toggle(title, value) { $0.saveDeletedMessages = $1 }
        case let .keepInChat(title, value):
            return toggle(title, value) { $0.keepDeletedMessagesInChat = $1 }
        case let .saveInChannels(title, value, enabled):
            return toggle(title, value, enabled: enabled) { $0.saveDeletedInChannels = $1 }
        case let .saveEdits(title, value):
            return toggle(title, value) { $0.saveEditHistory = $1 }
        case let .deletedMessages(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
        case let .storageSize(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .clearHistory(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.clearHistory()
            })
        case let .deletedMark(title, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: "", type: .regular(capitalization: false, autocorrection: false), alignment: .right, maxLength: 24, sectionId: section, textUpdated: { text in
                arguments.update { $0.deletedMark = text }
            }, action: {})
        case let .editedMark(title, value, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title), text: value, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), alignment: .right, maxLength: 24, sectionId: section, textUpdated: { text in
                arguments.update { $0.editedMark = text }
            }, action: {})
        case let .showSeconds(title, value):
            return toggle(title, value) { $0.showMessageSeconds = $1 }
        case let .showPeerId(title, value):
            return toggle(title, value) { $0.showPeerId = $1 }
        case let .hideSponsored(title, value):
            return toggle(title, value) { $0.hideSponsoredMessages = $1 }
        case let .hideStoriesInList(title, value):
            return toggle(title, value) { $0.hideStoriesInChatList = $1 }
        case let .confirmSticker(title, value):
            return toggle(title, value) { $0.confirmStickerSend = $1 }
        case let .haptics(title, value):
            return toggle(title, value) { $0.hapticFeedback = $1 }
        case let .openAppearance(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: {
                arguments.openLinked(.appearance)
            })
        case let .filters(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                arguments.openFilters()
            })
        case let .translator(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: {
                arguments.openLinked(.language)
            })
        case let .reset(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: section, style: .blocks, action: {
                arguments.reset()
            })
        case let .version(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private func formatFileSize(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
}

private func ayuGramSettingsEntries(strings: AyuStrings, settings: AyuGramSettingsValues, statistics: AyuMessageStoreStatistics?) -> [AyuGramSettingsEntry] {
    var entries: [AyuGramSettingsEntry] = []

    entries.append(.ghostHeader(strings.ghostHeader))
    entries.append(.ghostMaster(strings.ghostMode, settings.isGhostModeFullyEnabled))
    entries.append(.ghostMasterFooter(strings.ghostFooter))

    entries.append(.hideOnline(strings.hideOnline, settings.hideOnlineStatus))
    entries.append(.hideRead(strings.hideRead, settings.hideReadReceipts))
    entries.append(.hideStories(strings.hideStories, settings.hideStoryViews))
    entries.append(.hideTyping(strings.hideTyping, settings.hideTyping))
    entries.append(.hideContents(strings.hideContents, settings.hideMessageContentsRead))
    entries.append(.markReadAfterSend(strings.markReadAfterSend, settings.markReadAfterSend, enabled: settings.hideReadReceipts))
    entries.append(.ghostFooter(strings.markReadAfterSendFooter))

    entries.append(.antiDeleteHeader(strings.antiDeleteHeader))
    entries.append(.saveDeleted(strings.saveDeleted, settings.saveDeletedMessages))
    entries.append(.keepInChat(strings.keepDeletedInChat, settings.keepDeletedMessagesInChat))
    entries.append(.saveInChannels(strings.saveInChannels, settings.saveDeletedInChannels, enabled: settings.saveDeletedMessages || settings.keepDeletedMessagesInChat))
    entries.append(.saveEdits(strings.saveEdits, settings.saveEditHistory))
    entries.append(.antiDeleteFooter(strings.antiDeleteFooter))

    entries.append(.deletedMessages(strings.deletedMessages, statistics.flatMap { "\($0.deletedCount)" } ?? ""))
    entries.append(.storageSize(strings.storageUsage, statistics.flatMap { formatFileSize($0.fileSize) } ?? ""))
    entries.append(.clearHistory(strings.clearHistory))

    entries.append(.appearanceHeader(strings.appearanceHeader))
    entries.append(.deletedMark(strings.deletedMark, settings.deletedMark))
    entries.append(.editedMark(strings.editedMark, settings.editedMark, strings.editedMarkPlaceholder))
    entries.append(.showSeconds(strings.showSeconds, settings.showMessageSeconds))
    entries.append(.showPeerId(strings.showPeerId, settings.showPeerId))
    entries.append(.hideSponsored(strings.hideSponsored, settings.hideSponsoredMessages))
    entries.append(.hideStoriesInList(strings.hideStoriesInList, settings.hideStoriesInChatList))
    entries.append(.confirmSticker(strings.confirmSticker, settings.confirmStickerSend))
    entries.append(.haptics(strings.haptics, settings.hapticFeedback))
    entries.append(.openAppearance(strings.openAppearance))
    entries.append(.appearanceFooter(strings.appearanceFooter))

    entries.append(.filtersHeader(strings.filtersHeader))
    entries.append(.filters(strings.filters, settings.messageFiltersEnabled ? "\(settings.messageFilters.count)" : ""))

    entries.append(.translatorHeader(strings.translatorHeader))
    entries.append(.translator(strings.translatorSettings))
    entries.append(.translatorFooter(strings.translatorFooter))

    entries.append(.aboutHeader(strings.aboutHeader))
    entries.append(.reset(strings.resetSettings))
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    entries.append(.version("AyuGram for iOS \(version) (\(build))"))

    return entries
}

/// The "AyuGram" section of Settings.
public func ayuGramSettingsController(context: AccountContext, makeLinked: @escaping (AyuLinkedTelegramSettings) -> ViewController) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?

    let store = AyuMessageStore.forAccount(context.account)

    let arguments = AyuGramSettingsArguments(
        update: { f in
            AyuGramSettings.update(f)
        },
        openDeletedMessages: {
            pushControllerImpl?(ayuDeletedChatsController(context: context))
        },
        openFilters: {
            pushControllerImpl?(ayuMessageFiltersController(context: context))
        },
        openLinked: { section in
            pushControllerImpl?(makeLinked(section))
        },
        clearHistory: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AyuStrings(presentationData.strings)
            let actionSheet = ActionSheetController(presentationData: presentationData)
            actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: strings.clearHistoryConfirm),
                ActionSheetButtonItem(title: strings.clearHistory, color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    store.clearAll()
                    AyuHaptics.success()
                    presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.clearHistoryDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
                })
            ]), ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])])
            presentControllerImpl?(actionSheet)
        },
        reset: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AyuStrings(presentationData.strings)
            AyuGramSettings.reset()
            AyuHaptics.success()
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.resetDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
        }
    )

    let statistics: Signal<AyuMessageStoreStatistics?, NoError> = .single(nil) |> then(store.statistics() |> map(Optional.init))

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        AyuGramSettings.signal,
        statistics
    )
    |> map { presentationData, settings, statistics -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AyuStrings(presentationData.strings)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: ayuGramSettingsEntries(strings: strings, settings: settings, statistics: statistics), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
