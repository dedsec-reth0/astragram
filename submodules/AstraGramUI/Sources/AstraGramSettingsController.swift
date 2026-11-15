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
import BuildConfig
import UniformTypeIdentifiers

/// Sections of Telegram's own settings that the AstraGram screen links to.
public enum AstraLinkedTelegramSettings {
    case appearance
    case language
    case privacy
}

/// A shared haptic generator for AstraGram controls; honours the "Haptic feedback" setting.
public enum AstraHaptics {
    private static let feedback = HapticFeedback()

    public static func toggle() {
        if AstraGramSettings.current.hapticFeedback {
            AstraHaptics.feedback.impact(.light)
        }
    }

    public static func success() {
        if AstraGramSettings.current.hapticFeedback {
            AstraHaptics.feedback.success()
        }
    }

    public static func warning() {
        if AstraGramSettings.current.hapticFeedback {
            AstraHaptics.feedback.warning()
        }
    }
}

private final class AstraGramSettingsArguments {
    let update: ((inout AstraGramSettingsValues) -> Void) -> Void
    let openDeletedMessages: () -> Void
    let openFilters: () -> Void
    let openLinked: (AstraLinkedTelegramSettings) -> Void
    let clearHistory: () -> Void
    let reset: () -> Void
    let openPlugins: () -> Void
    let unhideMessages: () -> Void
    let openApiCredentials: () -> Void
    let checkUpdates: () -> Void
    let openTool: (AstraGramSettingsButtonKind) -> Void

    init(
        update: @escaping ((inout AstraGramSettingsValues) -> Void) -> Void,
        openDeletedMessages: @escaping () -> Void,
        openFilters: @escaping () -> Void,
        openLinked: @escaping (AstraLinkedTelegramSettings) -> Void,
        clearHistory: @escaping () -> Void,
        reset: @escaping () -> Void,
        openPlugins: @escaping () -> Void,
        unhideMessages: @escaping () -> Void,
        openApiCredentials: @escaping () -> Void,
        checkUpdates: @escaping () -> Void,
        openTool: @escaping (AstraGramSettingsButtonKind) -> Void
    ) {
        self.update = update
        self.openDeletedMessages = openDeletedMessages
        self.openFilters = openFilters
        self.openLinked = openLinked
        self.clearHistory = clearHistory
        self.reset = reset
        self.openPlugins = openPlugins
        self.unhideMessages = unhideMessages
        self.openApiCredentials = openApiCredentials
        self.checkUpdates = checkUpdates
        self.openTool = openTool
    }
}

private enum AstraGramSettingsSection: Int32 {
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
    case view
    case notifications
    case dedsec
    case look
    case onlineExceptions
    case media
    case tools
    case security
    case footerSection
}

private enum AstraGramSettingsEntry: ItemListNodeEntry {
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
    case flag(id: Int32, section: AstraGramSettingsSection, title: String, value: Bool, enabled: Bool, keyPath: WritableKeyPath<AstraGramSettingsValues, Bool>)
    case header(id: Int32, section: AstraGramSettingsSection, text: String)
    case footer(id: Int32, section: AstraGramSettingsSection, text: String)
    case button(id: Int32, section: AstraGramSettingsSection, title: String, label: String, kind: AstraGramSettingsButtonKind)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostMaster, .ghostMasterFooter:
            return AstraGramSettingsSection.ghostMaster.rawValue
        case .hideOnline, .hideRead, .hideStories, .hideTyping, .hideContents, .markReadAfterSend, .ghostFooter:
            return AstraGramSettingsSection.ghost.rawValue
        case .antiDeleteHeader, .saveDeleted, .keepInChat, .saveInChannels, .saveEdits, .keepSelfDestructing, .antiDeleteFooter:
            return AstraGramSettingsSection.antiDelete.rawValue
        case .deletedMessages, .storageSize, .clearHistory:
            return AstraGramSettingsSection.storage.rawValue
        case .appearanceHeader, .deletedMark, .editedMark, .showSeconds, .showPeerId, .hideSponsored, .hideStoriesInList, .confirmSticker, .haptics, .openAppearance, .appearanceFooter:
            return AstraGramSettingsSection.appearance.rawValue
        case .filtersHeader, .filters:
            return AstraGramSettingsSection.filters.rawValue
        case .translatorHeader, .translator, .translatorFooter:
            return AstraGramSettingsSection.translator.rawValue
        case .aboutHeader:
            return AstraGramSettingsSection.about.rawValue
        case .reset, .version:
            return AstraGramSettingsSection.footerSection.rawValue
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
        case .reset: return 199
        case .version: return 200
        case let .flag(id, _, _, _, _, _), let .header(id, _, _), let .footer(id, _, _), let .button(id, _, _, _, _):
            return id
        }
    }

    static func <(lhs: AstraGramSettingsEntry, rhs: AstraGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraGramSettingsArguments
        let section = self.section

        func toggle(_ title: String, _ value: Bool, enabled: Bool = true, _ apply: @escaping (inout AstraGramSettingsValues, Bool) -> Void) -> ListViewItem {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: section, style: .blocks, updated: { value in
                AstraHaptics.toggle()
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
            case .ai, .templates, .keywordAlerts, .bookmarks, .lockedChats, .securityCheck, .telegramPrivacy:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                    arguments.openTool(kind)
                })
            case .backupExport, .backupImport, .restartApp:
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                    arguments.openTool(kind)
                })
            case .checkUpdates:
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                    arguments.checkUpdates()
                })
            case .apiCredentials:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, action: {
                    arguments.openApiCredentials()
                })
            case .glassMaterial:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, action: {
                    arguments.openTool(kind)
                })
            case .unhideMessages:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, action: {
                    arguments.unhideMessages()
                })
            }
        }
    }
}

private enum AstraGramSettingsButtonKind: Equatable {
    case plugins
    case unhideMessages
    case apiCredentials
    case checkUpdates
    case ai
    case templates
    case keywordAlerts
    case bookmarks
    case backupExport
    case backupImport
    case restartApp
    case glassMaterial
    case lockedChats
    case securityCheck
    case telegramPrivacy
}

private func formatFileSize(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
}

private func astraGramSettingsEntries(strings: AstraStrings, settings: AstraGramSettingsValues, statistics: AstraMessageStoreStatistics?) -> [AstraGramSettingsEntry] {
    var entries: [AstraGramSettingsEntry] = []

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

    entries.append(.header(id: 3, section: .dedsec, text: strings.dedsecHeader))
    entries.append(.flag(id: 4, section: .dedsec, title: strings.dedsecSilence, value: settings.dedsecSilence, enabled: true, keyPath: \.dedsecSilence))
    entries.append(.footer(id: 5, section: .dedsec, text: strings.dedsecFooter))

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
    let hiddenCount = AstraHiddenMessages.count
    entries.append(.button(id: 62, section: .filters, title: strings.unhideMessages, label: hiddenCount > 0 ? "\(hiddenCount)" : "", kind: .unhideMessages))

    entries.append(.header(id: 63, section: .view, text: strings.viewHeader))
    entries.append(.flag(id: 64, section: .view, title: strings.wideMessages, value: settings.wideMessages, enabled: true, keyPath: \.wideMessages))
    entries.append(.flag(id: 65, section: .view, title: strings.channelBadge, value: settings.channelBadge, enabled: true, keyPath: \.channelBadge))

    entries.append(.header(id: 73, section: .plugins, text: strings.plugins.uppercased()))
    entries.append(.button(id: 74, section: .plugins, title: strings.plugins, label: "\(AstraPluginManager.shared.enabledCount)", kind: .plugins))
    entries.append(.footer(id: 75, section: .plugins, text: strings.pluginsFooter))

    entries.append(.flag(id: 76, section: .extra, title: strings.showRegistrationDate, value: settings.showRegistrationDate, enabled: true, keyPath: \.showRegistrationDate))
    entries.append(.flag(id: 77, section: .extra, title: strings.localPremium, value: settings.localPremium, enabled: true, keyPath: \.localPremium))
    entries.append(.header(id: 66, section: .notifications, text: strings.notificationsHeader))
    entries.append(.flag(id: 67, section: .notifications, title: strings.backgroundNotifications, value: settings.backgroundNotifications, enabled: true, keyPath: \.backgroundNotifications))
    entries.append(.flag(id: 68, section: .notifications, title: strings.keepAliveInBackground, value: settings.keepAliveInBackground, enabled: settings.backgroundNotifications, keyPath: \.keepAliveInBackground))
    entries.append(.footer(id: 69, section: .notifications, text: strings.backgroundNotificationsFooter))
    entries.append(.footer(id: 78, section: .extra, text: strings.localPremiumFooter))

    entries.append(.translatorHeader(strings.translatorHeader))
    entries.append(.translator(strings.translatorSettings))
    entries.append(.translatorFooter(strings.translatorFooter))

    entries.append(.aboutHeader(strings.aboutHeader))
    entries.append(.button(id: 81, section: .about, title: strings.apiCredentials, label: "\(BuildConfig(baseAppBundleId: Bundle.main.bundleIdentifier ?? "").apiId)", kind: .apiCredentials))
    entries.append(.flag(id: 82, section: .about, title: strings.checkForUpdates, value: settings.checkForUpdates, enabled: true, keyPath: \.checkForUpdates))
    entries.append(.button(id: 85, section: .about, title: strings.checkUpdatesNow, label: "", kind: .checkUpdates))

    entries.append(.header(id: 90, section: .media, text: strings.mediaHeader))
    entries.append(.flag(id: 91, section: .media, title: strings.hideStickers, value: settings.hideStickersFromOthers, enabled: true, keyPath: \.hideStickersFromOthers))
    entries.append(.flag(id: 92, section: .media, title: strings.hideGifs, value: settings.hideGifsFromOthers, enabled: true, keyPath: \.hideGifsFromOthers))

    entries.append(.header(id: 100, section: .tools, text: strings.toolsHeader))
    entries.append(.button(id: 101, section: .tools, title: strings.aiSettings, label: AstraAI.hasOwnKey ? settings.aiModel : strings.aiFree, kind: .ai))
    entries.append(.button(id: 102, section: .tools, title: strings.templates, label: settings.messageTemplates.isEmpty ? "" : "\(settings.messageTemplates.count)", kind: .templates))
    entries.append(.button(id: 103, section: .tools, title: strings.keywordAlerts, label: settings.keywordAlerts.isEmpty ? "" : "\(settings.keywordAlerts.count)", kind: .keywordAlerts))
    entries.append(.button(id: 104, section: .tools, title: strings.bookmarks, label: "", kind: .bookmarks))
    entries.append(.button(id: 105, section: .tools, title: strings.backupExport, label: "", kind: .backupExport))
    entries.append(.button(id: 106, section: .tools, title: strings.backupImport, label: "", kind: .backupImport))

    // The look: every part has its own switch.
    entries.append(.header(id: 130, section: .security, text: strings.securityHeader))
    entries.append(.button(id: 139, section: .security, title: strings.securityCheck, label: "", kind: .securityCheck))
    entries.append(.button(id: 134, section: .security, title: strings.lockedChats, label: settings.lockedChats.isEmpty ? strings.lockedChatsNone : "\(settings.lockedChats.count)", kind: .lockedChats))
    entries.append(.flag(id: 133, section: .security, title: strings.biometricForAstraGram, value: settings.biometricForAstraGram, enabled: true, keyPath: \.biometricForAstraGram))
    entries.append(.flag(id: 131, section: .security, title: strings.hideInAppSwitcher, value: settings.hideInAppSwitcher, enabled: true, keyPath: \.hideInAppSwitcher))
    entries.append(.flag(id: 132, section: .security, title: strings.blockThirdPartyKeyboards, value: settings.blockThirdPartyKeyboards, enabled: true, keyPath: \.blockThirdPartyKeyboards))
    entries.append(.flag(id: 135, section: .security, title: strings.warnSuspiciousLinks, value: settings.warnSuspiciousLinks, enabled: true, keyPath: \.warnSuspiciousLinks))
    entries.append(.flag(id: 136, section: .security, title: strings.stripLinkTrackers, value: settings.stripLinkTrackers, enabled: true, keyPath: \.stripLinkTrackers))
    entries.append(.flag(id: 137, section: .security, title: strings.clipboardExpire, value: settings.clipboardExpire, enabled: true, keyPath: \.clipboardExpire))
    entries.append(.flag(id: 138, section: .security, title: strings.clipboardLocalOnly, value: settings.clipboardLocalOnly, enabled: true, keyPath: \.clipboardLocalOnly))
    entries.append(.button(id: 140, section: .security, title: strings.telegramPrivacy, label: "", kind: .telegramPrivacy))
    entries.append(.footer(id: 141, section: .security, text: strings.securityFooter))
    entries.append(.header(id: 110, section: .look, text: strings.lookHeader))
    entries.append(.flag(id: 111, section: .look, title: strings.monochrome, value: settings.monochrome, enabled: true, keyPath: \.monochrome))
    if settings.monochrome {
        entries.append(.flag(id: 121, section: .look, title: strings.monochromePlainBackground, value: settings.monochromePlainBackground, enabled: true, keyPath: \.monochromePlainBackground))
    }
    entries.append(.flag(id: 112, section: .look, title: strings.roundProfileButtons, value: settings.roundProfileButtons, enabled: true, keyPath: \.roundProfileButtons))
    entries.append(.flag(id: 113, section: .look, title: strings.profileMusicCapsule, value: settings.profileMusicCapsule, enabled: true, keyPath: \.profileMusicCapsule))
    entries.append(.flag(id: 114, section: .look, title: strings.contactsTab, value: settings.contactsTab, enabled: true, keyPath: \.contactsTab))
    entries.append(.flag(id: 115, section: .look, title: strings.callsTab, value: settings.callsTab, enabled: true, keyPath: \.callsTab))
    entries.append(.button(id: 119, section: .look, title: strings.glassMaterial, label: [strings.glassMaterialStandard, strings.glassMaterialClear, strings.glassMaterialMatte][max(0, min(2, settings.glassMaterial))], kind: .glassMaterial))
    entries.append(.flag(id: 120, section: .look, title: strings.springPresses, value: settings.springPresses, enabled: true, keyPath: \.springPresses))
    entries.append(.flag(id: 122, section: .look, title: strings.astraBadge, value: settings.astraBadge, enabled: true, keyPath: \.astraBadge))
    entries.append(.footer(id: 116, section: .look, text: strings.lookFooter))
    entries.append(.button(id: 117, section: .onlineExceptions, title: strings.restartApp, label: "", kind: .restartApp))
    entries.append(.footer(id: 118, section: .onlineExceptions, text: strings.restartFooter))
    entries.append(.reset(strings.resetSettings))
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    entries.append(.version("AstraGram 1.0 Alpha · \(version) (\(build))"))

    return entries
}

/// The "AstraGram" section of Settings.
public func astraGramSettingsController(context: AccountContext, makeLinked: @escaping (AstraLinkedTelegramSettings) -> ViewController) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    var presentNativeControllerImpl: ((UIViewController) -> Void)?
    var topNativeControllerImpl: (() -> UIViewController?)?

    let store = AstraMessageStore.forAccount(context.account)

    let arguments = AstraGramSettingsArguments(
        update: { f in
            AstraGramSettings.update(f)
        },
        openDeletedMessages: {
            pushControllerImpl?(astraDeletedChatsController(context: context))
        },
        openFilters: {
            pushControllerImpl?(astraMessageFiltersController(context: context))
        },
        openLinked: { section in
            pushControllerImpl?(makeLinked(section))
        },
        clearHistory: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AstraStrings(presentationData.strings)
            let actionSheet = ActionSheetController(presentationData: presentationData)
            actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: strings.clearHistoryConfirm),
                ActionSheetButtonItem(title: strings.clearHistory, color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    store.clearAll()
                    AstraHaptics.success()
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
            let strings = AstraStrings(presentationData.strings)
            AstraGramSettings.reset()
            AstraHaptics.success()
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.resetDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
        },
        openPlugins: {
            pushControllerImpl?(astraPluginsController(context: context))
        },
        unhideMessages: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AstraStrings(presentationData.strings)
            AstraHiddenMessages.removeAll()
            AstraHaptics.success()
            presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.unhideMessagesDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
        },
        openApiCredentials: {
            presentNativeControllerImpl?(AstraApiCredentialsController(baseAppBundleId: Bundle.main.bundleIdentifier ?? "", isInitialSetup: false, completion: {}))
        },
        checkUpdates: {
            if let controller = topNativeControllerImpl?() {
                AstraUpdateChecker.checkNow(from: controller)
            }
        },
        openTool: { kind in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let strings = AstraStrings(presentationData.strings)
            switch kind {
            case .ai:
                pushControllerImpl?(astraAIController(context: context))
            case .templates:
                pushControllerImpl?(astraStringListController(context: context, title: strings.templates, placeholder: strings.templatePlaceholder, footer: strings.templatesFooter, keyPath: \.messageTemplates, validate: { $0.contains("=") }))
            case .keywordAlerts:
                pushControllerImpl?(astraStringListController(context: context, title: strings.keywordAlerts, placeholder: strings.keywordPlaceholder, footer: strings.keywordAlertsFooter, keyPath: \.keywordAlerts))
            case .bookmarks:
                pushControllerImpl?(astraBookmarksController(context: context))
            case .glassMaterial:
                AstraGramSettings.update { $0.glassMaterial = (max(0, $0.glassMaterial) + 1) % 3 }
            case .securityCheck:
                let resultController = AstraTextResultController(title: strings.securityCheck, isRussian: strings.isRussian, load: { completion in
                    astraSecurityReport(context: context, isRussian: strings.isRussian, completion: { text in
                        completion(.success(text))
                    })
                })
                presentNativeControllerImpl?(resultController.wrapped())
            case .telegramPrivacy:
                pushControllerImpl?(context.sharedContext.makePrivacyAndSecurityController(context: context))
            case .lockedChats:
                // Whoever holds the unlocked phone must not be able to take the lock off: the list opens after Face ID.
                AstraBiometrics.authenticate(reason: strings.lockedChatsReason, completion: { success in
                    guard success else {
                        return
                    }
                    let selected = Set(AstraGramSettings.current.lockedChats.map { EnginePeer.Id($0) })
                    let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
                        title: strings.lockedChats,
                        searchPlaceholder: presentationData.strings.Common_Search,
                        selectedChats: selected,
                        additionalCategories: nil,
                        chatListFilters: nil,
                        onlyUsers: false,
                        disableChannels: false,
                        disableBots: false
                    ))))
                    let _ = (controller.result
                    |> take(1)
                    |> deliverOnMainQueue).start(next: { [weak controller] result in
                        if case let .result(peerIds, _) = result {
                            var ids: [Int64] = []
                            for peerId in peerIds {
                                if case let .peer(id) = peerId {
                                    ids.append(id.toInt64())
                                }
                            }
                            AstraGramSettings.update { $0.lockedChats = ids }
                        }
                        controller?.dismiss()
                    })
                    pushControllerImpl?(controller)
                })
            case .restartApp:
                AstraAppRestart.perform(title: strings.restartNotificationTitle, text: strings.restartNotificationText)
            case .backupExport:
                guard let data = AstraBackup.exportData() else {
                    return
                }
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AstraGram-backup.json")
                try? data.write(to: url)
                let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                presentNativeControllerImpl?(activityController)
            case .backupImport:
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json, UTType.item], asCopy: true)
                let delegate = AstraBackupPickerDelegate(completion: { url in
                    guard let url = url, let data = try? Data(contentsOf: url) else {
                        return
                    }
                    let text = AstraBackup.importData(data) ? strings.backupDone : strings.backupInvalid
                    presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
                })
                AstraBackupPickerDelegate.current = delegate
                picker.delegate = delegate
                presentNativeControllerImpl?(picker)
            default:
                break
            }
        }
    )

    let statistics: Signal<AstraMessageStoreStatistics?, NoError> = .single(nil) |> then(store.statistics() |> map(Optional.init))

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        AstraGramSettings.signal,
        statistics
    )
    |> map { presentationData, settings, statistics -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(strings.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: astraGramSettingsEntries(strings: strings, settings: settings, statistics: statistics), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentNativeControllerImpl = { [weak controller] c in
        var presenter = controller?.view.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        // On iPad the share sheet is a popover: without an anchor UIKit raises an exception when it is presented.
        if let presenterView = presenter?.view, let popover = c.popoverPresentationController, popover.sourceView == nil {
            popover.sourceView = presenterView
            popover.sourceRect = CGRect(x: presenterView.bounds.midX, y: presenterView.bounds.midY, width: 1.0, height: 1.0)
            popover.permittedArrowDirections = []
        }
        presenter?.present(c, animated: true)
    }
    topNativeControllerImpl = { [weak controller] in
        var presenter = controller?.view.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
    return controller
}

private final class AstraBackupPickerDelegate: NSObject, UIDocumentPickerDelegate {
    static var current: AstraBackupPickerDelegate?
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
        AstraBackupPickerDelegate.current = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        AstraBackupPickerDelegate.current = nil
    }
}
