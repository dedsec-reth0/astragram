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
    let openPlugins: () -> Void
    let unhideMessages: () -> Void

    init(
        update: @escaping ((inout AyuGramSettingsValues) -> Void) -> Void,
        openDeletedMessages: @escaping () -> Void,
        openFilters: @escaping () -> Void,
        openLinked: @escaping (AyuLinkedTelegramSettings) -> Void,
        clearHistory: @escaping () -> Void,
        reset: @escaping () -> Void,
        openPlugins: @escaping () -> Void,
        unhideMessages: @escaping () -> Void
    ) {
        self.update = update
        self.openDeletedMessages = openDeletedMessages
        self.openFilters = openFilters
        self.openLinked = openLinked
        self.clearHistory = clearHistory
        self.reset = reset
        self.openPlugins = openPlugins
        self.unhideMessages = unhideMessages
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
    case ghostExtra
    case privacy
    case chats
    case plugins
    case extra
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
    case keepSelfDestructing(String, Bool)
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

    // A switch bound to a setting, a section header or footer, and a button (newer options use these generic cases).
    case flag(id: Int32, section: AyuGramSettingsSection, title: String, value: Bool, enabled: Bool, keyPath: WritableKeyPath<AyuGramSettingsValues, Bool>)
    case header(id: Int32, section: AyuGramSettingsSection, text: String)
    case footer(id: Int32, section: AyuGramSettingsSection, text: String)
    case button(id: Int32, section: AyuGramSettingsSection, title: String, label: String, kind: AyuGramSettingsButtonKind)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMaster, .ghostMasterFooter:
            return AyuGramSettingsSection.ghostMaster.rawValue
        case .hideOnline, .hideRead, .hideStories, .hideTyping, .hideContents, .markReadAfterSend, .ghostFooter:
            return AyuGramSettingsSection.ghost.rawValue
        case .antiDeleteHeader, .saveDeleted, .keepInChat, .saveInChannels, .saveEdits, .keepSelfDestructing, .antiDeleteFooter:
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
        case let .flag(_, section, _, _, _, _), let .header(_, section, _), let .footer(_, section, _), let .button(_, section, _, _, _):
            return section.rawValue
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
        case .keepSelfDestructing: return 25
        case .antiDeleteFooter: return 26
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
        case let .flag(id, _, _, _, _, _), let .header(id, _, _), let .footer(id, _, _), let .button(id, _, _, _, _):
            return id
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
        case let .keepSelfDestructing(title, value):
            return toggle(title, value) { $0.keepSelfDestructingMedia = $1 }
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
        case let .flag(_, _, title, value, enabled, keyPath):
            return toggle(title, value, enabled: enabled) { settings, value in
                settings[keyPath: keyPath] = value
            }
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .button(_, _, title, label, kind):
            switch kind {
            case .plugins:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                    arguments.openPlugins()
                })
            case .unhideMessages:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, action: {
                    arguments.unhideMessages()
                })
            }
        }
    }
}

private enum AyuGramSettingsButtonKind: Equatable {
    case plugins
    case unhideMessages
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
    entries.append(.ghostMasterFooter(strings.ghostFooter + " " + strings.ghostButtonHint))

    entries.append(.hideOnline(strings.hideOnline, settings.hideOnlineStatus))
    entries.append(.hideRead(strings.hideRead, settings.hideReadReceipts))
    entries.append(.hideStories(strings.hideStories, settings.hideStoryViews))
    entries.append(.hideTyping(strings.hideTyping, settings.hideTyping))
    entries.append(.hideContents(strings.hideContents, settings.hideMessageContentsRead))
    entries.append(.markReadAfterSend(strings.markReadAfterSend, settings.markReadAfterSend, enabled: settings.hideReadReceipts))
    entries.append(.ghostFooter(strings.markReadAfterSendFooter))

    entries.append(.flag(id: 17, section: .ghostExtra, title: strings.markReadAfterReaction, value: settings.markReadAfterReaction, enabled: settings.hideReadReceipts, keyPath: \.markReadAfterReaction))
    entries.append(.flag(id: 18, section: .ghostExtra, title: strings.sendViaSchedule, value: settings.sendViaSchedule, enabled: settings.hideOnlineStatus, keyPath: \.sendViaSchedule))
    entries.append(.footer(id: 19, section: .ghostExtra, text: strings.sendViaScheduleFooter))

    entries.append(.antiDeleteHeader(strings.antiDeleteHeader))
    entries.append(.saveDeleted(strings.saveDeleted, settings.saveDeletedMessages))
    entries.append(.keepInChat(strings.keepDeletedInChat, settings.keepDeletedMessagesInChat))
    entries.append(.saveInChannels(strings.saveInChannels, settings.saveDeletedInChannels, enabled: settings.saveDeletedMessages || settings.keepDeletedMessagesInChat))
    entries.append(.saveEdits(strings.saveEdits, settings.saveEditHistory))
    entries.append(.keepSelfDestructing(strings.keepSelfDestructing, settings.keepSelfDestructingMedia))
    entries.append(.antiDeleteFooter(strings.antiDeleteFooter))

    entries.append(.deletedMessages(strings.deletedMessages, statistics.flatMap { "\($0.deletedCount)" } ?? ""))
    entries.append(.storageSize(strings.storageUsage, statistics.flatMap { formatFileSize($0.fileSize) } ?? ""))
    entries.append(.clearHistory(strings.clearHistory))

    entries.append(.header(id: 33, section: .privacy, text: strings.privacyHeader))
    entries.append(.flag(id: 34, section: .privacy, title: strings.removeCopyRestrictions, value: settings.removeCopyRestrictions, enabled: true, keyPath: \.removeCopyRestrictions))
    entries.append(.flag(id: 35, section: .privacy, title: strings.allowScreenshots, value: settings.allowScreenshots, enabled: true, keyPath: \.allowScreenshots))
    entries.append(.flag(id: 36, section: .privacy, title: strings.streamerMode, value: settings.streamerMode, enabled: true, keyPath: \.streamerMode))
    entries.append(.footer(id: 37, section: .privacy, text: strings.privacyFooter))

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

    entries.append(.header(id: 51, section: .chats, text: strings.chatsHeader))
    entries.append(.flag(id: 52, section: .chats, title: strings.hideBlocked, value: settings.hideBlockedUsersMessages, enabled: true, keyPath: \.hideBlockedUsersMessages))
    entries.append(.flag(id: 53, section: .chats, title: strings.hideSimilarChannels, value: settings.hideSimilarChannels, enabled: true, keyPath: \.hideSimilarChannels))
    entries.append(.flag(id: 54, section: .chats, title: strings.hideFolderCounters, value: settings.hideFolderCounters, enabled: true, keyPath: \.hideFolderCounters))
    entries.append(.flag(id: 55, section: .chats, title: strings.hideAllChatsFolder, value: settings.hideAllChatsFolder, enabled: true, keyPath: \.hideAllChatsFolder))
    entries.append(.flag(id: 56, section: .chats, title: strings.increaseRecentStickers, value: settings.increaseRecentStickers, enabled: true, keyPath: \.increaseRecentStickers))
    entries.append(.flag(id: 57, section: .chats, title: strings.showServiceTime, value: settings.showServiceMessageTime, enabled: true, keyPath: \.showServiceMessageTime))
    entries.append(.flag(id: 58, section: .chats, title: strings.simpleReplies, value: settings.simpleReplies, enabled: true, keyPath: \.simpleReplies))
    entries.append(.flag(id: 59, section: .chats, title: strings.confirmMessageSend, value: settings.confirmMessageSend, enabled: true, keyPath: \.confirmMessageSend))

    entries.append(.filtersHeader(strings.filtersHeader))
    entries.append(.filters(strings.filters, settings.messageFiltersEnabled ? "\(settings.messageFilters.count)" : ""))
    let hiddenCount = AyuHiddenMessages.count
    entries.append(.button(id: 62, section: .filters, title: strings.unhideMessages, label: hiddenCount > 0 ? "\(hiddenCount)" : "", kind: .unhideMessages))

    entries.append(.header(id: 73, section: .plugins, text: strings.plugins.uppercased()))
    entries.append(.button(id: 74, section: .plugins, title: strings.plugins, label: "\(AyuPluginManager.shared.enabledCount)", kind: .plugins))
    entries.append(.footer(id: 75, section: .plugins, text: strings.pluginsFooter))

    entries.append(.flag(id: 76, section: .extra, title: strings.showRegistrationDate, value: settings.showRegistrationDate, enabled: true, keyPath: \.showRegistrationDate))
    entries.append(.flag(id: 77, section: .extra, title: strings.localPremium, value: settings.localPremium, enabled: true, keyPath: \.localPremium))
    entries.append(.footer(id: 78, section: .extra, text: strings.localPremiumFooter))

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
        },
        openPlugins: {
            pushControllerImpl?(ayuPluginsController(context: context))
        },
        unhideMessages: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AyuStrings(presentationData.strings)
            AyuHiddenMessages.removeAll()
            AyuHaptics.success()
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.unhideMessagesDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
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
