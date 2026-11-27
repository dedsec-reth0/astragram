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
import AppBundle

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
    let openPage: (AstraGramSettingsPage) -> Void
    var showDescription: (String, String) -> Void = { _, _ in }

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
        openTool: @escaping (AstraGramSettingsButtonKind) -> Void,
        openPage: @escaping (AstraGramSettingsPage) -> Void
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
        self.openPage = openPage
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
    // The main page.
    case rootPrivacy
    case rootLook
    case rootExtras
    case rootAbout
    // The security page, in groups.
    case securityLock
    case securityInput
    case securityTelegram
    case backup

    /// The page of the AstraGram settings this section is on.
    var page: AstraGramSettingsPage {
        switch self {
        case .ghostMaster, .ghost, .ghostExtra:
            return .ghost
        case .antiDelete, .storage:
            return .history
        case .privacy, .dedsec:
            return .privacy
        case .security, .securityLock, .securityInput, .securityTelegram:
            return .security
        case .appearance, .view, .look, .extra:
            return .appearance
        case .chats, .filters, .media:
            return .chats
        case .notifications:
            return .notifications
        case .plugins, .tools, .translator:
            return .tools
        case .about, .backup, .onlineExceptions, .footerSection:
            return .about
        case .rootPrivacy, .rootLook, .rootExtras, .rootAbout:
            return .root
        }
    }
}

/// The AstraGram settings are a main page that lists the parts, as Telegram's own Settings do, and a page per part.
public enum AstraGramSettingsPage: Equatable {
    case root
    case ghost
    case history
    case privacy
    case security
    case appearance
    case chats
    case notifications
    case tools
    case about
}

/// What a row of the main page opens.
private enum AstraGramSettingsRootTarget: Equatable {
    case page(AstraGramSettingsPage)
    case streaks
    case giftShop
    case plugins
    case feedback
    case donate
}

/// The icons of the main page, drawn the way Telegram draws its settings icons: a white glyph on a colored rounded
/// square with the same light gradient on top.
enum AstraGramSettingsIcons {
    static func render(glyph: UIImage?, color: UIColor) -> UIImage? {
        let size = CGSize(width: 30.0, height: 30.0)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let bounds = CGRect(origin: CGPoint(), size: size)
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: 8.0)
            path.addClip()
            color.setFill()
            path.fill()
            UIImage(bundleImageName: "Item List/Icons/Gradient")?.draw(in: bounds, blendMode: .plusLighter, alpha: 1.0)
            UIImage(bundleImageName: "Item List/Icons/Backdrop")?.draw(in: bounds, blendMode: .overlay, alpha: 1.0)
            if let glyph {
                let tinted = glyph.withTintColor(.white, renderingMode: .alwaysOriginal)
                let glyphSize = glyph.size
                tinted.draw(in: CGRect(x: floor((size.width - glyphSize.width) / 2.0), y: floor((size.height - glyphSize.height) / 2.0), width: glyphSize.width, height: glyphSize.height))
            }
        }
    }

    static func bundled(_ name: String, _ color: UIColor) -> UIImage? {
        return render(glyph: UIImage(bundleImageName: "Item List/Icons/\(name)"), color: color)
    }

    static func symbol(_ name: String, _ color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 16.0, weight: .semibold)
        return render(glyph: UIImage(systemName: name, withConfiguration: configuration), color: color)
    }

    // Telegram's settings palette.
    static let ghost = bundled("NoForward", UIColor(rgb: 0x5E5CE6))
    static let history = bundled("Delete", UIColor(rgb: 0xFF9F0A))
    static let privacy = bundled("Privacy", UIColor(rgb: 0x8E8E93))
    static let security = bundled("FaceId", UIColor(rgb: 0x34C759))
    static let appearance = bundled("Brush", UIColor(rgb: 0x32ADE6))
    static let chats = bundled("Chat", UIColor(rgb: 0x0A84FF))
    static let notifications = bundled("Notifications", UIColor(rgb: 0xFF453A))
    static let streaks = symbol("flame.fill", UIColor(rgb: 0xFF6A00))
    static let giftShop = symbol("gift.fill", UIColor(rgb: 0xFF2D55))
    static let tools = bundled("AITools", UIColor(rgb: 0xAF52DE))
    static let plugins = bundled("Bot", UIColor(rgb: 0x00C7BE))
    static let about = bundled("Settings", UIColor(rgb: 0x8E8E93))
    static let feedback = symbol("ladybug.fill", UIColor(rgb: 0xFF9500))
    static let donate = symbol("heart.fill", UIColor(rgb: 0xFF2D55))
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
    // A row of the main page: an icon, a title and a value, opening a page or a tool.
    case rootRow(id: Int32, section: AstraGramSettingsSection, icon: UIImage?, title: String, label: String, target: AstraGramSettingsRootTarget)

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
        case .appearanceHeader, .deletedMark, .editedMark, .showSeconds, .showPeerId, .haptics, .openAppearance, .appearanceFooter:
            return AstraGramSettingsSection.appearance.rawValue
        case .hideSponsored, .hideStoriesInList, .confirmSticker:
            return AstraGramSettingsSection.chats.rawValue
        case .filtersHeader, .filters:
            return AstraGramSettingsSection.filters.rawValue
        case .translatorHeader, .translator, .translatorFooter:
            return AstraGramSettingsSection.translator.rawValue
        case .aboutHeader:
            return AstraGramSettingsSection.about.rawValue
        case .reset, .version:
            return AstraGramSettingsSection.footerSection.rawValue
        case let .flag(_, section, _, _, _, _), let .header(_, section, _), let .footer(_, section, _), let .button(_, section, _, _, _), let .rootRow(_, section, _, _, _, _):
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
        case let .flag(id, _, _, _, _, _), let .header(id, _, _), let .footer(id, _, _), let .button(id, _, _, _, _), let .rootRow(id, _, _, _, _, _):
            return id
        }
    }

    // The list must be sorted by `<` (ItemListControllerNode diffs it that way and asserts it in debug builds), but newer
    // options got ids out of display order. So `<` follows the display order below; an id missing from it goes last.
    private static let displayOrder: [Int32: Int] = {
        let ids: [Int32] = [
            0, 1, 2, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
            20, 21, 22, 23, 24, 25, 26, 30, 31, 32, 33, 34, 35, 36, 37, 3, 4, 5,
            40, 41, 42, 43, 44, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 45, 46, 47,
            60, 61, 62, 63, 64, 65, 73, 74, 75, 76, 77, 78, 66, 67, 68, 69, 100, 101, 102, 103, 104, 70, 71, 72,
            80, 81, 82, 85, 105, 106, 90, 91, 92,
            130, 139, 134, 133, 131, 132, 135, 136, 137, 138, 140, 141,
            110, 184, 185, 111, 121, 112, 113, 114, 115, 119, 120, 122, 123, 124, 116, 117, 118, 199, 200
        ]
        var order: [Int32: Int] = [:]
        for (index, id) in ids.enumerated() {
            order[id] = index
        }
        return order
    }()

    /// The row's title, for the long-press description.
    fileprivate var astraRowTitle: String? {
        switch self {
        case let .ghostMaster(title, _), let .hideOnline(title, _), let .hideRead(title, _), let .hideStories(title, _), let .hideTyping(title, _), let .hideContents(title, _), let .markReadAfterSend(title, _, _), let .saveDeleted(title, _), let .keepInChat(title, _), let .saveInChannels(title, _, _), let .saveEdits(title, _), let .keepSelfDestructing(title, _), let .deletedMessages(title, _), let .showSeconds(title, _), let .showPeerId(title, _), let .hideSponsored(title, _), let .hideStoriesInList(title, _), let .confirmSticker(title, _), let .haptics(title, _), let .filters(title, _), let .translator(title):
            return title
        case let .flag(_, _, title, _, _, _), let .button(_, _, title, _, _), let .rootRow(_, _, _, title, _, _):
            return title
        default:
            return nil
        }
    }

    private var displayIndex: Int {
        return AstraGramSettingsEntry.displayOrder[self.stableId] ?? (100000 + Int(self.stableId))
    }

    static func <(lhs: AstraGramSettingsEntry, rhs: AstraGramSettingsEntry) -> Bool {
        return lhs.displayIndex < rhs.displayIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AstraGramSettingsArguments
        let section = self.section
        // AstraGram: a long press on a row explains the setting.
        let astraTitleAndDescription: (String, String)? = AstraStrings(presentationData.strings).featureDescription(self.stableId).map { (self.astraRowTitle ?? "", $0) }
        let astraLongTap: (() -> Void)? = astraTitleAndDescription.map { titleAndDescription in
            return { arguments.showDescription(titleAndDescription.0, titleAndDescription.1) }
        }

        func toggle(_ title: String, _ value: Bool, enabled: Bool = true, _ apply: @escaping (inout AstraGramSettingsValues, Bool) -> Void) -> ListViewItem {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: section, style: .blocks, updated: { value in
                AstraHaptics.toggle()
                arguments.update { settings in
                    apply(&settings, value)
                }
            }, longTapAction: astraLongTap)
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
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                arguments.openDeletedMessages()
            })
        case let .storageSize(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, longTapAction: astraLongTap, action: nil)
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
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                arguments.openLinked(.appearance)
            })
        case let .filters(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                arguments.openFilters()
            })
        case let .translator(title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
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
        case let .rootRow(_, _, icon, title, label, target):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                switch target {
                case let .page(page):
                    arguments.openPage(page)
                case .streaks:
                    arguments.openTool(.streaks)
                case .giftShop:
                    arguments.openTool(.giftShop)
                case .plugins:
                    arguments.openPlugins()
                case .feedback:
                    arguments.openTool(.feedback)
                case .donate:
                    arguments.openTool(.donate)
                }
            })
        case let .button(_, _, title, label, kind):
            switch kind {
            case .plugins:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                    arguments.openPlugins()
                })
            case .ai, .templates, .keywordAlerts, .bookmarks, .lockedChats, .securityCheck, .telegramPrivacy, .streaks, .giftShop, .feedback, .donate:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                    arguments.openTool(kind)
                })
            case .backupExport, .backupImport, .restartApp, .clearBadge:
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                    arguments.openTool(kind)
                })
            case .checkUpdates:
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                    arguments.checkUpdates()
                })
            case .apiCredentials:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                    arguments.openApiCredentials()
                })
            case .glassMaterial, .doubleTapAction, .stickerSize, .videoSeek, .chatListTitle:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, longTapAction: astraLongTap, action: {
                    arguments.openTool(kind)
                })
            case .screenEffects, .keyboards:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, longTapAction: astraLongTap, action: {
                    arguments.openTool(kind)
                })
            case .unhideMessages:
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, longTapAction: astraLongTap, action: {
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
    case doubleTapAction
    case stickerSize
    case screenEffects
    case keyboards
    case videoSeek
    case chatListTitle
    case lockedChats
    case securityCheck
    case telegramPrivacy
    case clearBadge
    case streaks
    case giftShop
    case feedback
    case donate
}

private func formatFileSize(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
}

/// The main page: one row per part, grouped like Telegram's Settings.
private func astraGramSettingsRootEntries(strings: AstraStrings, settings: AstraGramSettingsValues, statistics: AstraMessageStoreStatistics?) -> [AstraGramSettingsEntry] {
    var entries: [AstraGramSettingsEntry] = []
    let ghostLabel = settings.isGhostModeFullyEnabled ? strings.valueOn : (settings.isGhostModePartiallyEnabled ? strings.valuePartial : strings.valueOff)
    let deletedLabel = statistics.flatMap { $0.deletedCount > 0 ? "\($0.deletedCount)" : nil } ?? ""
    let pluginCount = AstraPluginManager.shared.enabledCount

    entries.append(.rootRow(id: 1000, section: .rootPrivacy, icon: AstraGramSettingsIcons.ghost, title: strings.pageGhost, label: ghostLabel, target: .page(.ghost)))
    entries.append(.rootRow(id: 1001, section: .rootPrivacy, icon: AstraGramSettingsIcons.history, title: strings.pageHistory, label: deletedLabel, target: .page(.history)))
    entries.append(.rootRow(id: 1002, section: .rootPrivacy, icon: AstraGramSettingsIcons.privacy, title: strings.pagePrivacy, label: "", target: .page(.privacy)))
    entries.append(.rootRow(id: 1003, section: .rootPrivacy, icon: AstraGramSettingsIcons.security, title: strings.pageSecurity, label: "", target: .page(.security)))

    entries.append(.rootRow(id: 1010, section: .rootLook, icon: AstraGramSettingsIcons.appearance, title: strings.pageAppearance, label: "", target: .page(.appearance)))
    entries.append(.rootRow(id: 1011, section: .rootLook, icon: AstraGramSettingsIcons.chats, title: strings.pageChats, label: "", target: .page(.chats)))
    entries.append(.rootRow(id: 1012, section: .rootLook, icon: AstraGramSettingsIcons.notifications, title: strings.pageNotifications, label: settings.backgroundNotifications ? strings.valueOn : strings.valueOff, target: .page(.notifications)))

    entries.append(.rootRow(id: 1020, section: .rootExtras, icon: AstraGramSettingsIcons.streaks, title: strings.pageStreaks, label: "", target: .streaks))
    entries.append(.rootRow(id: 1021, section: .rootExtras, icon: AstraGramSettingsIcons.giftShop, title: strings.pageGiftShop, label: "", target: .giftShop))
    entries.append(.rootRow(id: 1022, section: .rootExtras, icon: AstraGramSettingsIcons.tools, title: strings.pageTools, label: "", target: .page(.tools)))
    entries.append(.rootRow(id: 1023, section: .rootExtras, icon: AstraGramSettingsIcons.plugins, title: strings.plugins, label: pluginCount > 0 ? "\(pluginCount)" : "", target: .plugins))

    entries.append(.rootRow(id: 1030, section: .rootAbout, icon: AstraGramSettingsIcons.feedback, title: strings.pageFeedback, label: "", target: .feedback))
    entries.append(.rootRow(id: 1032, section: .rootAbout, icon: AstraGramSettingsIcons.donate, title: strings.pageDonate, label: "", target: .donate))
    entries.append(.rootRow(id: 1033, section: .rootAbout, icon: AstraGramSettingsIcons.about, title: strings.pageAbout, label: "", target: .page(.about)))
    entries.append(.footer(id: 1039, section: .rootAbout, text: strings.rootFooter))
    return entries
}

private func astraGramSettingsEntries(page: AstraGramSettingsPage, strings: AstraStrings, settings: AstraGramSettingsValues, statistics: AstraMessageStoreStatistics?) -> [AstraGramSettingsEntry] {
    if page == .root {
        return astraGramSettingsRootEntries(strings: strings, settings: settings, statistics: statistics)
    }
    // A part's page: the rows of its sections. The Plugins and Streaks rows are on the main page.
    return astraGramAllSettingsEntries(strings: strings, settings: settings, statistics: statistics).filter { entry in
        if case let .button(_, _, _, _, kind) = entry, kind == .streaks || kind == .plugins {
            return false
        }
        // A header that only repeats the page's title is left out, as Telegram's own pages do.
        switch entry {
        case .ghostHeader:
            return false
        case let .header(id, _, _) where id == 130 || id == 66 || id == 73:
            return false
        case let .footer(id, _, _) where id == 75:
            return false
        case .aboutHeader:
            return false
        default:
            break
        }
        guard let section = AstraGramSettingsSection(rawValue: entry.section) else {
            return false
        }
        return section.page == page
    }.sorted(by: <)
}

private func astraGramAllSettingsEntries(strings: AstraStrings, settings: AstraGramSettingsValues, statistics: AstraMessageStoreStatistics?) -> [AstraGramSettingsEntry] {
    var entries: [AstraGramSettingsEntry] = []

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
    entries.append(.button(id: 150, section: .chats, title: strings.doubleTapAction, label: strings.doubleTapActionNames[max(0, min(strings.doubleTapActionNames.count - 1, settings.doubleTapAction))], kind: .doubleTapAction))
    entries.append(.flag(id: 151, section: .chats, title: strings.hideShareButton, value: settings.hideShareButton, enabled: true, keyPath: \.hideShareButton))
    entries.append(.flag(id: 152, section: .chats, title: strings.hideKeyboardOnScroll, value: settings.hideKeyboardOnScroll, enabled: true, keyPath: \.hideKeyboardOnScroll))
    entries.append(.flag(id: 153, section: .chats, title: strings.commaAfterMention, value: settings.commaAfterMention, enabled: true, keyPath: \.commaAfterMention))
    entries.append(.flag(id: 154, section: .chats, title: strings.disableMarkdown, value: settings.disableMarkdown, enabled: true, keyPath: \.disableMarkdown))
    entries.append(.flag(id: 155, section: .chats, title: strings.hideSendAsPeer, value: settings.hideSendAsPeer, enabled: true, keyPath: \.hideSendAsPeer))
    entries.append(.flag(id: 156, section: .chats, title: strings.disableGreetingSticker, value: settings.disableGreetingSticker, enabled: true, keyPath: \.disableGreetingSticker))
    entries.append(.flag(id: 157, section: .chats, title: strings.showPollResultsBeforeVoting, value: settings.showPollResultsBeforeVoting, enabled: true, keyPath: \.showPollResultsBeforeVoting))
    entries.append(.button(id: 158, section: .chats, title: strings.stickerSize, label: "\(max(50, min(150, settings.stickerSizePercent)))%", kind: .stickerSize))
    entries.append(.flag(id: 159, section: .chats, title: strings.hideStickerTime, value: settings.hideStickerTime, enabled: true, keyPath: \.hideStickerTime))
    entries.append(.flag(id: 160, section: .chats, title: strings.filterZalgo, value: settings.filterZalgo, enabled: true, keyPath: \.filterZalgo))
    entries.append(.flag(id: 161, section: .chats, title: strings.hideReactionsPrivate, value: settings.hideReactionsPrivate, enabled: true, keyPath: \.hideReactionsPrivate))
    entries.append(.flag(id: 162, section: .chats, title: strings.hideReactionsGroups, value: settings.hideReactionsGroups, enabled: true, keyPath: \.hideReactionsGroups))
    entries.append(.flag(id: 163, section: .chats, title: strings.hideReactionsChannels, value: settings.hideReactionsChannels, enabled: true, keyPath: \.hideReactionsChannels))
    entries.append(.flag(id: 164, section: .chats, title: strings.removeBubbleTail, value: settings.removeBubbleTail, enabled: true, keyPath: \.removeBubbleTail))
    entries.append(.flag(id: 165, section: .chats, title: strings.exactNumbers, value: settings.exactNumbers, enabled: true, keyPath: \.exactNumbers))
    entries.append(.flag(id: 166, section: .chats, title: strings.hideComposeButton, value: settings.hideComposeButton, enabled: true, keyPath: \.hideComposeButton))
    entries.append(.flag(id: 167, section: .chats, title: strings.alwaysSendHD, value: settings.alwaysSendHD, enabled: true, keyPath: \.alwaysSendHD))
    entries.append(.flag(id: 168, section: .chats, title: strings.hideCameraTile, value: settings.hideCameraTile, enabled: true, keyPath: \.hideCameraTile))
    entries.append(.button(id: 169, section: .chats, title: strings.videoSeek, label: strings.seconds(settings.videoSeekSeconds), kind: .videoSeek))
    entries.append(.flag(id: 170, section: .chats, title: strings.inlineCalculator, value: settings.inlineCalculator, enabled: true, keyPath: \.inlineCalculator))
    entries.append(.flag(id: 171, section: .chats, title: strings.pauseMediaOnMinimize, value: settings.pauseMediaOnMinimize, enabled: true, keyPath: \.pauseMediaOnMinimize))
    entries.append(.flag(id: 172, section: .chats, title: strings.relativeLastSeen, value: settings.relativeLastSeen, enabled: true, keyPath: \.relativeLastSeen))
    entries.append(.flag(id: 174, section: .chats, title: strings.hideOwnPhone, value: settings.hideOwnPhone, enabled: true, keyPath: \.hideOwnPhone))
    entries.append(.flag(id: 176, section: .chats, title: strings.squareAvatars, value: settings.squareAvatars, enabled: true, keyPath: \.squareAvatars))
    entries.append(.flag(id: 175, section: .chats, title: strings.showDataCenter, value: settings.showDataCenter, enabled: true, keyPath: \.showDataCenter))
    entries.append(.flag(id: 178, section: .chats, title: strings.confirmVoiceSend, value: settings.confirmVoiceSend, enabled: true, keyPath: \.confirmVoiceSend))
    entries.append(.flag(id: 179, section: .chats, title: strings.dimDeletedMessages, value: settings.dimDeletedMessages, enabled: true, keyPath: \.dimDeletedMessages))
    entries.append(.flag(id: 180, section: .chats, title: strings.revealSpoilers, value: settings.revealSpoilers, enabled: true, keyPath: \.revealSpoilers))
    entries.append(.flag(id: 181, section: .chats, title: strings.sendSilentlyByDefault, value: settings.sendSilentlyByDefault, enabled: true, keyPath: \.sendSilentlyByDefault))
    entries.append(.flag(id: 182, section: .chats, title: strings.hidePremiumStatuses, value: settings.hidePremiumStatuses, enabled: true, keyPath: \.hidePremiumStatuses))
    entries.append(.flag(id: 183, section: .chats, title: strings.hideAppBadge, value: settings.hideAppBadge, enabled: true, keyPath: \.hideAppBadge))
    entries.append(.button(id: 173, section: .chats, title: strings.chatListTitle, label: settings.chatListTitle.isEmpty ? strings.chatListTitleDefault : settings.chatListTitle, kind: .chatListTitle))

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
    entries.append(.footer(id: 78, section: .extra, text: strings.localPremiumFooter))
    entries.append(.header(id: 66, section: .notifications, text: strings.notificationsHeader))
    entries.append(.flag(id: 67, section: .notifications, title: strings.backgroundNotifications, value: settings.backgroundNotifications, enabled: true, keyPath: \.backgroundNotifications))
    entries.append(.flag(id: 68, section: .notifications, title: strings.keepAliveInBackground, value: settings.keepAliveInBackground, enabled: settings.backgroundNotifications, keyPath: \.keepAliveInBackground))
    entries.append(.footer(id: 69, section: .notifications, text: strings.backgroundNotificationsFooter))

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
    entries.append(.button(id: 105, section: .backup, title: strings.backupExport, label: "", kind: .backupExport))
    entries.append(.button(id: 106, section: .backup, title: strings.backupImport, label: "", kind: .backupImport))

    // The look: every part has its own switch.
    entries.append(.header(id: 130, section: .security, text: strings.securityHeader))
    entries.append(.button(id: 139, section: .security, title: strings.securityCheck, label: "", kind: .securityCheck))
    entries.append(.button(id: 134, section: .securityLock, title: strings.lockedChats, label: settings.lockedChats.isEmpty ? strings.lockedChatsNone : "\(settings.lockedChats.count)", kind: .lockedChats))
    entries.append(.flag(id: 133, section: .securityLock, title: strings.biometricForAstraGram, value: settings.biometricForAstraGram, enabled: true, keyPath: \.biometricForAstraGram))
    entries.append(.flag(id: 131, section: .securityLock, title: strings.hideInAppSwitcher, value: settings.hideInAppSwitcher, enabled: true, keyPath: \.hideInAppSwitcher))
    entries.append(.flag(id: 132, section: .securityInput, title: strings.blockThirdPartyKeyboards, value: settings.blockThirdPartyKeyboards, enabled: true, keyPath: \.blockThirdPartyKeyboards))
    entries.append(.flag(id: 135, section: .securityInput, title: strings.warnSuspiciousLinks, value: settings.warnSuspiciousLinks, enabled: true, keyPath: \.warnSuspiciousLinks))
    entries.append(.flag(id: 136, section: .securityInput, title: strings.stripLinkTrackers, value: settings.stripLinkTrackers, enabled: true, keyPath: \.stripLinkTrackers))
    entries.append(.flag(id: 137, section: .securityInput, title: strings.clipboardExpire, value: settings.clipboardExpire, enabled: true, keyPath: \.clipboardExpire))
    entries.append(.flag(id: 138, section: .securityInput, title: strings.clipboardLocalOnly, value: settings.clipboardLocalOnly, enabled: true, keyPath: \.clipboardLocalOnly))
    entries.append(.button(id: 140, section: .securityTelegram, title: strings.telegramPrivacy, label: "", kind: .telegramPrivacy))
    entries.append(.footer(id: 141, section: .securityTelegram, text: strings.securityFooter))
    entries.append(.header(id: 110, section: .look, text: strings.lookHeader))
    entries.append(.flag(id: 111, section: .look, title: strings.monochrome, value: settings.monochrome, enabled: true, keyPath: \.monochrome))
    if settings.monochrome {
        entries.append(.flag(id: 121, section: .look, title: strings.monochromePlainBackground, value: settings.monochromePlainBackground, enabled: true, keyPath: \.monochromePlainBackground))
    }
    entries.append(.flag(id: 112, section: .look, title: strings.roundProfileButtons, value: settings.roundProfileButtons, enabled: true, keyPath: \.roundProfileButtons))
    entries.append(.flag(id: 113, section: .look, title: strings.profileMusicCapsule, value: settings.musicCapsule, enabled: true, keyPath: \.musicCapsule))
    entries.append(.flag(id: 114, section: .look, title: strings.contactsTab, value: settings.contactsTab, enabled: true, keyPath: \.contactsTab))
    entries.append(.flag(id: 115, section: .look, title: strings.callsTab, value: settings.callsTab, enabled: true, keyPath: \.callsTab))
    entries.append(.button(id: 184, section: .look, title: strings.screenEffects, label: (AstraScreenEffect(rawValue: settings.screenEffect) ?? .off).title(isRussian: strings.isRussian), kind: .screenEffects))
    entries.append(.button(id: 185, section: .look, title: strings.keyboardLook, label: settings.customKeyboard ? AstraKeyboardThemes.theme(id: settings.keyboardThemeId).name : (strings.isRussian ? "iOS" : "iOS"), kind: .keyboards))
    entries.append(.button(id: 119, section: .look, title: strings.glassMaterial, label: [strings.glassMaterialStandard, strings.glassMaterialClear, strings.glassMaterialMatte][max(0, min(2, settings.glassMaterial))], kind: .glassMaterial))
    entries.append(.flag(id: 120, section: .look, title: strings.springPresses, value: settings.springPresses, enabled: true, keyPath: \.springPresses))
    entries.append(.flag(id: 142, section: .look, title: strings.showAstraGiftRibbon, value: settings.showAstraGiftRibbon, enabled: true, keyPath: \.showAstraGiftRibbon))
    entries.append(.flag(id: 122, section: .look, title: strings.astraBadge, value: settings.astraBadge, enabled: true, keyPath: \.astraBadge))
    entries.append(.button(id: 123, section: .look, title: strings.astraBadgeClear, label: "", kind: .clearBadge))
    entries.append(.button(id: 124, section: .look, title: strings.streaks, label: "", kind: .streaks))
    entries.append(.footer(id: 116, section: .look, text: strings.lookFooter))
    entries.append(.button(id: 117, section: .onlineExceptions, title: strings.restartApp, label: "", kind: .restartApp))
    entries.append(.footer(id: 118, section: .onlineExceptions, text: strings.restartFooter))
    entries.append(.reset(strings.resetSettings))
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    // The version people see: one step per build after 103783 (as in astragram/ci/publish_release.py). The raw
    // CFBundleShortVersionString is now "13.2.<build>" (so AltStore sees each build as an update), which would just
    // repeat the build number here, so only the marketing version and the build number are shown.
    let astraBuildNumber = Int(build) ?? 0
    let astraMarketingVersion = astraBuildNumber > 103783 ? "1.0.\(astraBuildNumber - 103783)" : "1.0.0"
    entries.append(.version("AstraGram \(astraMarketingVersion) Alpha (\(build))"))

    return entries
}

/// The "AstraGram" section of Settings.
public func astraGramSettingsController(context: AccountContext, page: AstraGramSettingsPage = .root, makeLinked: @escaping (AstraLinkedTelegramSettings) -> ViewController) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?
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
            let actionSheet = ActionSheetController(presentationData: presentationData)
            actionSheet.setItemGroups([ActionSheetItemGroup(items: [
                ActionSheetTextItem(title: strings.resetConfirm),
                ActionSheetButtonItem(title: strings.resetSettings, color: .destructive, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                    AstraGramSettings.reset()
                    AstraHaptics.success()
                    presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: strings.resetDone, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
                })
            ]), ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])])
            presentControllerImpl?(actionSheet)
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
            case .chatListTitle:
                let alert = UIAlertController(title: strings.chatListTitle, message: strings.chatListTitleHint, preferredStyle: .alert)
                alert.addTextField { field in
                    field.text = AstraGramSettings.current.chatListTitle
                    field.placeholder = strings.chatListTitleDefault
                    field.clearButtonMode = .whileEditing
                }
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Cancel, style: .cancel))
                alert.addAction(UIAlertAction(title: presentationData.strings.Common_Done, style: .default, handler: { [weak alert] _ in
                    let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    AstraHaptics.toggle()
                    AstraGramSettings.update { $0.chatListTitle = String(text.prefix(32)) }
                }))
                presentNativeControllerImpl?(alert)
            case .videoSeek:
                let actionSheet = ActionSheetController(presentationData: presentationData)
                let current = AstraGramSettings.current.videoSeekSeconds
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [ActionSheetTextItem(title: strings.videoSeek)] + [5, 10, 15, 30].map { seconds in
                    return ActionSheetButtonItem(title: seconds == current ? "✓ " + strings.seconds(seconds) : strings.seconds(seconds), color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        AstraHaptics.toggle()
                        AstraGramSettings.update { $0.videoSeekSeconds = seconds }
                    })
                }), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet)
            case .screenEffects:
                presentNativeControllerImpl?(AstraEffectsPickerController(isRussian: strings.isRussian))
            case .keyboards:
                presentNativeControllerImpl?(AstraKeyboardStoreController(isRussian: strings.isRussian))
            case .stickerSize:
                let actionSheet = ActionSheetController(presentationData: presentationData)
                let current = AstraGramSettings.current.stickerSizePercent
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [ActionSheetTextItem(title: strings.stickerSize)] + [60, 80, 100, 120, 140].map { percent in
                    return ActionSheetButtonItem(title: percent == current ? "✓ \(percent)%" : "\(percent)%", color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        AstraHaptics.toggle()
                        AstraGramSettings.update { $0.stickerSizePercent = percent }
                    })
                }), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet)
            case .doubleTapAction:
                let actionSheet = ActionSheetController(presentationData: presentationData)
                let current = AstraGramSettings.current.doubleTapAction
                actionSheet.setItemGroups([ActionSheetItemGroup(items: [ActionSheetTextItem(title: strings.doubleTapAction)] + strings.doubleTapActionNames.enumerated().map { index, name in
                    return ActionSheetButtonItem(title: index == current ? "✓ " + name : name, color: .accent, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                        AstraHaptics.toggle()
                        AstraGramSettings.update { $0.doubleTapAction = index }
                    })
                }), ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                        actionSheet?.dismissAnimated()
                    })
                ])])
                presentControllerImpl?(actionSheet)
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
            case .streaks:
                pushControllerImpl?(astraStreaksListController(context: context))
            case .giftShop:
                astraOpenGiftShop(context: context)
            case .feedback:
                astraOpenFeedback(context: context, idea: false)
            case .donate:
                astraOpenDonation(context: context, navigationController: navigationControllerImpl?())
            case .clearBadge:
                AstraBadgeSync.clearName(context: context, completion: { removed in
                    let text = removed ? strings.astraBadgeCleared : strings.astraBadgeNothing
                    presentControllerImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }))
                })
            case .backupExport:
                guard let data = AstraBackup.exportData() else {
                    return
                }
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AstraGram-backup.json")
                try? data.write(to: url)
                let activityController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activityController.completionWithItemsHandler = { _, _, _, _ in
                    try? FileManager.default.removeItem(at: url)
                }
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
        },
        openPage: { page in
            pushControllerImpl?(astraGramSettingsController(context: context, page: page, makeLinked: makeLinked))
        }
    )
    arguments.showDescription = { title, text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ]))
    }

    let statistics: Signal<AstraMessageStoreStatistics?, NoError> = .single(nil) |> then(store.statistics() |> map(Optional.init))

    // The plugin list is part of the state, so the Plugins row's counter follows installs and switches made on the
    // Plugins screen.
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        AstraGramSettings.signal,
        statistics,
        AstraPluginManager.shared.plugins
    )
    |> map { presentationData, settings, statistics, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = AstraStrings(presentationData.strings)
        let title: String
        switch page {
        case .root:
            title = strings.title
        case .ghost:
            title = strings.pageGhost
        case .history:
            title = strings.pageHistory
        case .privacy:
            title = strings.pagePrivacy
        case .security:
            title = strings.pageSecurity
        case .appearance:
            title = strings.pageAppearance
        case .chats:
            title = strings.pageChats
        case .notifications:
            title = strings.pageNotifications
        case .tools:
            title = strings.pageTools
        case .about:
            title = strings.pageAbout
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: astraGramSettingsEntries(page: page, strings: strings, settings: settings, statistics: statistics), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
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
