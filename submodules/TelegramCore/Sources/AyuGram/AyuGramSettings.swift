import Foundation
import Postbox
import SwiftSignalKit

/// AyuGram client-side settings.
///
/// The values are read on network, Postbox and main queues (ghost mode is checked right before a request goes out),
/// so the current value lives in an `Atomic` and every read is a lock-protected copy. Changes are persisted to
/// `UserDefaults` as JSON and broadcast through `AyuGramSettings.signal`.
public struct AyuGramSettingsValues: Codable, Equatable {
    // MARK: Ghost mode
    /// Never report the account as online (`account.updateStatus(offline: true)` is sent instead).
    public var hideOnlineStatus: Bool
    /// Do not send read receipts for messages (`messages.readHistory` / `channels.readHistory` / `readDiscussion`).
    public var hideReadReceipts: Bool
    /// Do not report viewed stories (`stories.readStories`, `stories.incrementStoryViews`).
    public var hideStoryViews: Bool
    /// Do not send typing, recording and uploading activity (`messages.setTyping`).
    public var hideTyping: Bool
    /// Do not report listened voice/video messages and opened media (`readMessageContents`).
    public var hideMessageContentsRead: Bool
    /// Send a read receipt for a chat when you send a message into it, even while read receipts are hidden.
    public var markReadAfterSend: Bool

    // MARK: Anti-delete
    /// Save every message the server deletes into the local AyuGram database.
    public var saveDeletedMessages: Bool
    /// Keep messages deleted by other people in the chat, marked as deleted, instead of removing them.
    public var keepDeletedMessagesInChat: Bool
    /// Save previous versions of edited messages into the local AyuGram database.
    public var saveEditHistory: Bool
    /// Also save deleted messages of channels (can be a lot of data).
    public var saveDeletedInChannels: Bool
    /// Self-destructing and view-once photos, videos and voice messages stay viewable after you open them: the local
    /// self-destruct timer is not started. The sender still sees them as viewed (even in ghost mode).
    public var keepSelfDestructingMedia: Bool
    /// Send a read receipt for a chat when you react to a message or vote in a poll in it, even while read receipts are hidden.
    public var markReadAfterReaction: Bool
    /// Ghost mode: messages are sent as scheduled a few seconds ahead, so sending does not show the account online.
    public var sendViaSchedule: Bool
    /// Hide messages of blocked users in groups and channels.
    public var hideBlockedUsersMessages: Bool
    /// Allow copying, forwarding and saving the content of chats that forbid it.
    public var removeCopyRestrictions: Bool
    /// Allow screenshots of secret chats and self-destructing media without notifying the other side.
    public var allowScreenshots: Bool
    /// Hide the app from screenshots, screen recording and screen sharing.
    public var streamerMode: Bool
    /// Show the time of service messages.
    public var showServiceMessageTime: Bool
    /// Draw replies and quotes without the sender's colors and patterns.
    public var simpleReplies: Bool
    /// Hide recommendations of similar channels.
    public var hideSimilarChannels: Bool
    /// Hide unread counters on chat folder tabs.
    public var hideFolderCounters: Bool
    /// Hide the "All Chats" folder tab.
    public var hideAllChatsFolder: Bool
    /// Keep up to 100 recently used stickers.
    public var increaseRecentStickers: Bool
    /// Ask before sending any message.
    public var confirmMessageSend: Bool
    /// Show your own accounts as Premium on this device (client-side features only).
    public var localPremium: Bool
    /// Show the approximate registration date in profiles.
    public var showRegistrationDate: Bool
    /// Let message bubbles use more of the screen width.
    public var wideMessages: Bool
    /// Mark people writing to groups on behalf of a channel with 📢.
    public var channelBadge: Bool
    /// Check GitHub for a newer AyuGram build at launch.
    public var checkForUpdates: Bool
    /// Notifications without push: local notifications for messages that arrive in the background, and background app refresh.
    public var backgroundNotifications: Bool
    /// Stay connected in the background (plays silence so iOS does not suspend the app), so messages arrive and are notified at once. Uses more battery.
    public var keepAliveInBackground: Bool
    /// DEDSEC: notifications and sounds of all groups and channels are off (chats with their own exception still notify; new groups and channels are silent too).
    public var dedsecSilence: Bool
    /// Beta: the Liquid Glass+ look (gradient background, chat list as a floating card).
    public var liquidGlassBeta: Bool
    /// Look: round glass buttons with their labels under them in profiles.
    public var roundProfileButtons: Bool
    /// Look: the profile music as a capsule under the status, above the buttons.
    public var profileMusicCapsule: Bool
    /// Look: the Contacts tab in the tab bar.
    public var contactsTab: Bool
    /// Look: the Calls tab in the tab bar (Telegram's own "Show Calls Tab" switch mirrors it).
    public var callsTab: Bool
    /// Look: black, white and grays only, in the dark and the light appearance.
    public var monochrome: Bool
    /// Hide stickers sent by other people.
    public var hideStickersFromOthers: Bool
    /// Hide GIFs sent by other people.
    public var hideGifsFromOthers: Bool
    /// Message templates, "name = text": sending ";name" sends the text.
    public var messageTemplates: [String]
    /// Words that notify even in muted chats (case-insensitive).
    public var keywordAlerts: [String]
    /// OpenAI-compatible API base URL for the AI features.
    public var aiEndpoint: String
    /// API key for the AI features (stored on this device only).
    public var aiApiKey: String
    /// Model name for the AI features.
    public var aiModel: String

    // MARK: Appearance and chats
    /// Text shown next to the time of a deleted message.
    public var deletedMark: String
    /// Text shown instead of "edited" next to the time of an edited message (empty: the standard text).
    public var editedMark: String
    /// Show seconds in message timestamps.
    public var showMessageSeconds: Bool
    /// Show the numeric ID of users, groups and channels in their profile.
    public var showPeerId: Bool
    /// Hide sponsored messages in channels.
    public var hideSponsoredMessages: Bool
    /// Hide the stories row above the chat list.
    public var hideStoriesInChatList: Bool
    /// Ask before sending a sticker or GIF (protects from accidental taps).
    public var confirmStickerSend: Bool
    /// Haptic feedback for AyuGram actions and settings.
    public var hapticFeedback: Bool

    // MARK: Message filters
    public var messageFiltersEnabled: Bool
    /// Messages whose text contains one of these (case-insensitive) or matches one of these regular expressions
    /// (entries written as `/pattern/`) are hidden from chat histories.
    public var messageFilters: [String]

    public static let `default` = AyuGramSettingsValues(
        hideOnlineStatus: false,
        hideReadReceipts: false,
        hideStoryViews: false,
        hideTyping: false,
        hideMessageContentsRead: false,
        markReadAfterSend: true,
        saveDeletedMessages: true,
        keepDeletedMessagesInChat: true,
        saveEditHistory: true,
        saveDeletedInChannels: true,
        keepSelfDestructingMedia: true,
        markReadAfterReaction: true,
        sendViaSchedule: false,
        hideBlockedUsersMessages: false,
        removeCopyRestrictions: true,
        allowScreenshots: true,
        streamerMode: false,
        showServiceMessageTime: false,
        simpleReplies: false,
        hideSimilarChannels: false,
        hideFolderCounters: false,
        hideAllChatsFolder: false,
        increaseRecentStickers: true,
        confirmMessageSend: false,
        localPremium: false,
        showRegistrationDate: true,
        wideMessages: false,
        channelBadge: true,
        checkForUpdates: true,
        backgroundNotifications: true,
        keepAliveInBackground: true,
        dedsecSilence: false,
        liquidGlassBeta: false,
        roundProfileButtons: false,
        profileMusicCapsule: false,
        contactsTab: true,
        callsTab: true,
        monochrome: false,
        hideStickersFromOthers: false,
        hideGifsFromOthers: false,
        messageTemplates: [],
        keywordAlerts: [],
        aiEndpoint: "https://api.openai.com/v1",
        aiApiKey: "",
        aiModel: "gpt-4o-mini",
        deletedMark: "🧹",
        editedMark: "",
        showMessageSeconds: false,
        showPeerId: true,
        hideSponsoredMessages: false,
        hideStoriesInChatList: false,
        confirmStickerSend: false,
        hapticFeedback: true,
        messageFiltersEnabled: false,
        messageFilters: []
    )

    public init(
        hideOnlineStatus: Bool,
        hideReadReceipts: Bool,
        hideStoryViews: Bool,
        hideTyping: Bool,
        hideMessageContentsRead: Bool,
        markReadAfterSend: Bool,
        saveDeletedMessages: Bool,
        keepDeletedMessagesInChat: Bool,
        saveEditHistory: Bool,
        saveDeletedInChannels: Bool,
        keepSelfDestructingMedia: Bool,
        markReadAfterReaction: Bool,
        sendViaSchedule: Bool,
        hideBlockedUsersMessages: Bool,
        removeCopyRestrictions: Bool,
        allowScreenshots: Bool,
        streamerMode: Bool,
        showServiceMessageTime: Bool,
        simpleReplies: Bool,
        hideSimilarChannels: Bool,
        hideFolderCounters: Bool,
        hideAllChatsFolder: Bool,
        increaseRecentStickers: Bool,
        confirmMessageSend: Bool,
        localPremium: Bool,
        showRegistrationDate: Bool,
        wideMessages: Bool,
        channelBadge: Bool,
        checkForUpdates: Bool,
        backgroundNotifications: Bool,
        keepAliveInBackground: Bool,
        dedsecSilence: Bool,
        liquidGlassBeta: Bool,
        roundProfileButtons: Bool,
        profileMusicCapsule: Bool,
        contactsTab: Bool,
        callsTab: Bool,
        monochrome: Bool,
        hideStickersFromOthers: Bool,
        hideGifsFromOthers: Bool,
        messageTemplates: [String],
        keywordAlerts: [String],
        aiEndpoint: String,
        aiApiKey: String,
        aiModel: String,
        deletedMark: String,
        editedMark: String,
        showMessageSeconds: Bool,
        showPeerId: Bool,
        hideSponsoredMessages: Bool,
        hideStoriesInChatList: Bool,
        confirmStickerSend: Bool,
        hapticFeedback: Bool,
        messageFiltersEnabled: Bool,
        messageFilters: [String]
    ) {
        self.hideOnlineStatus = hideOnlineStatus
        self.hideReadReceipts = hideReadReceipts
        self.hideStoryViews = hideStoryViews
        self.hideTyping = hideTyping
        self.hideMessageContentsRead = hideMessageContentsRead
        self.markReadAfterSend = markReadAfterSend
        self.saveDeletedMessages = saveDeletedMessages
        self.keepDeletedMessagesInChat = keepDeletedMessagesInChat
        self.saveEditHistory = saveEditHistory
        self.saveDeletedInChannels = saveDeletedInChannels
        self.keepSelfDestructingMedia = keepSelfDestructingMedia
        self.markReadAfterReaction = markReadAfterReaction
        self.sendViaSchedule = sendViaSchedule
        self.hideBlockedUsersMessages = hideBlockedUsersMessages
        self.removeCopyRestrictions = removeCopyRestrictions
        self.allowScreenshots = allowScreenshots
        self.streamerMode = streamerMode
        self.showServiceMessageTime = showServiceMessageTime
        self.simpleReplies = simpleReplies
        self.hideSimilarChannels = hideSimilarChannels
        self.hideFolderCounters = hideFolderCounters
        self.hideAllChatsFolder = hideAllChatsFolder
        self.increaseRecentStickers = increaseRecentStickers
        self.confirmMessageSend = confirmMessageSend
        self.localPremium = localPremium
        self.showRegistrationDate = showRegistrationDate
        self.wideMessages = wideMessages
        self.channelBadge = channelBadge
        self.checkForUpdates = checkForUpdates
        self.backgroundNotifications = backgroundNotifications
        self.keepAliveInBackground = keepAliveInBackground
        self.dedsecSilence = dedsecSilence
        self.liquidGlassBeta = liquidGlassBeta
        self.roundProfileButtons = roundProfileButtons
        self.profileMusicCapsule = profileMusicCapsule
        self.contactsTab = contactsTab
        self.callsTab = callsTab
        self.monochrome = monochrome
        self.hideStickersFromOthers = hideStickersFromOthers
        self.hideGifsFromOthers = hideGifsFromOthers
        self.messageTemplates = messageTemplates
        self.keywordAlerts = keywordAlerts
        self.aiEndpoint = aiEndpoint
        self.aiApiKey = aiApiKey
        self.aiModel = aiModel
        self.deletedMark = deletedMark
        self.editedMark = editedMark
        self.showMessageSeconds = showMessageSeconds
        self.showPeerId = showPeerId
        self.hideSponsoredMessages = hideSponsoredMessages
        self.hideStoriesInChatList = hideStoriesInChatList
        self.confirmStickerSend = confirmStickerSend
        self.hapticFeedback = hapticFeedback
        self.messageFiltersEnabled = messageFiltersEnabled
        self.messageFilters = messageFilters
    }

    // Every key is optional so that settings saved by an older build keep working after a field is added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = AyuGramSettingsValues.default
        self.hideOnlineStatus = try container.decodeIfPresent(Bool.self, forKey: .hideOnlineStatus) ?? d.hideOnlineStatus
        self.hideReadReceipts = try container.decodeIfPresent(Bool.self, forKey: .hideReadReceipts) ?? d.hideReadReceipts
        self.hideStoryViews = try container.decodeIfPresent(Bool.self, forKey: .hideStoryViews) ?? d.hideStoryViews
        self.hideTyping = try container.decodeIfPresent(Bool.self, forKey: .hideTyping) ?? d.hideTyping
        self.hideMessageContentsRead = try container.decodeIfPresent(Bool.self, forKey: .hideMessageContentsRead) ?? d.hideMessageContentsRead
        self.markReadAfterSend = try container.decodeIfPresent(Bool.self, forKey: .markReadAfterSend) ?? d.markReadAfterSend
        self.saveDeletedMessages = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedMessages) ?? d.saveDeletedMessages
        self.keepDeletedMessagesInChat = try container.decodeIfPresent(Bool.self, forKey: .keepDeletedMessagesInChat) ?? d.keepDeletedMessagesInChat
        self.saveEditHistory = try container.decodeIfPresent(Bool.self, forKey: .saveEditHistory) ?? d.saveEditHistory
        self.saveDeletedInChannels = try container.decodeIfPresent(Bool.self, forKey: .saveDeletedInChannels) ?? d.saveDeletedInChannels
        self.keepSelfDestructingMedia = try container.decodeIfPresent(Bool.self, forKey: .keepSelfDestructingMedia) ?? d.keepSelfDestructingMedia
        self.markReadAfterReaction = try container.decodeIfPresent(Bool.self, forKey: .markReadAfterReaction) ?? d.markReadAfterReaction
        self.sendViaSchedule = try container.decodeIfPresent(Bool.self, forKey: .sendViaSchedule) ?? d.sendViaSchedule
        self.hideBlockedUsersMessages = try container.decodeIfPresent(Bool.self, forKey: .hideBlockedUsersMessages) ?? d.hideBlockedUsersMessages
        self.removeCopyRestrictions = try container.decodeIfPresent(Bool.self, forKey: .removeCopyRestrictions) ?? d.removeCopyRestrictions
        self.allowScreenshots = try container.decodeIfPresent(Bool.self, forKey: .allowScreenshots) ?? d.allowScreenshots
        self.streamerMode = try container.decodeIfPresent(Bool.self, forKey: .streamerMode) ?? d.streamerMode
        self.showServiceMessageTime = try container.decodeIfPresent(Bool.self, forKey: .showServiceMessageTime) ?? d.showServiceMessageTime
        self.simpleReplies = try container.decodeIfPresent(Bool.self, forKey: .simpleReplies) ?? d.simpleReplies
        self.hideSimilarChannels = try container.decodeIfPresent(Bool.self, forKey: .hideSimilarChannels) ?? d.hideSimilarChannels
        self.hideFolderCounters = try container.decodeIfPresent(Bool.self, forKey: .hideFolderCounters) ?? d.hideFolderCounters
        self.hideAllChatsFolder = try container.decodeIfPresent(Bool.self, forKey: .hideAllChatsFolder) ?? d.hideAllChatsFolder
        self.increaseRecentStickers = try container.decodeIfPresent(Bool.self, forKey: .increaseRecentStickers) ?? d.increaseRecentStickers
        self.confirmMessageSend = try container.decodeIfPresent(Bool.self, forKey: .confirmMessageSend) ?? d.confirmMessageSend
        self.localPremium = try container.decodeIfPresent(Bool.self, forKey: .localPremium) ?? d.localPremium
        self.showRegistrationDate = try container.decodeIfPresent(Bool.self, forKey: .showRegistrationDate) ?? d.showRegistrationDate
        self.wideMessages = try container.decodeIfPresent(Bool.self, forKey: .wideMessages) ?? d.wideMessages
        self.channelBadge = try container.decodeIfPresent(Bool.self, forKey: .channelBadge) ?? d.channelBadge
        self.checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? d.checkForUpdates
        self.backgroundNotifications = try container.decodeIfPresent(Bool.self, forKey: .backgroundNotifications) ?? d.backgroundNotifications
        self.keepAliveInBackground = try container.decodeIfPresent(Bool.self, forKey: .keepAliveInBackground) ?? d.keepAliveInBackground
        self.dedsecSilence = try container.decodeIfPresent(Bool.self, forKey: .dedsecSilence) ?? d.dedsecSilence
        self.liquidGlassBeta = try container.decodeIfPresent(Bool.self, forKey: .liquidGlassBeta) ?? d.liquidGlassBeta
        self.roundProfileButtons = try container.decodeIfPresent(Bool.self, forKey: .roundProfileButtons) ?? (try container.decodeIfPresent(Bool.self, forKey: .liquidGlassBeta) ?? d.roundProfileButtons)
        self.profileMusicCapsule = try container.decodeIfPresent(Bool.self, forKey: .profileMusicCapsule) ?? (try container.decodeIfPresent(Bool.self, forKey: .liquidGlassBeta) ?? d.profileMusicCapsule)
        self.contactsTab = try container.decodeIfPresent(Bool.self, forKey: .contactsTab) ?? d.contactsTab
        self.callsTab = try container.decodeIfPresent(Bool.self, forKey: .callsTab) ?? d.callsTab
        self.monochrome = try container.decodeIfPresent(Bool.self, forKey: .monochrome) ?? d.monochrome
        self.hideStickersFromOthers = try container.decodeIfPresent(Bool.self, forKey: .hideStickersFromOthers) ?? d.hideStickersFromOthers
        self.hideGifsFromOthers = try container.decodeIfPresent(Bool.self, forKey: .hideGifsFromOthers) ?? d.hideGifsFromOthers
        self.messageTemplates = try container.decodeIfPresent([String].self, forKey: .messageTemplates) ?? d.messageTemplates
        self.keywordAlerts = try container.decodeIfPresent([String].self, forKey: .keywordAlerts) ?? d.keywordAlerts
        self.aiEndpoint = try container.decodeIfPresent(String.self, forKey: .aiEndpoint) ?? d.aiEndpoint
        self.aiApiKey = try container.decodeIfPresent(String.self, forKey: .aiApiKey) ?? d.aiApiKey
        self.aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        self.deletedMark = try container.decodeIfPresent(String.self, forKey: .deletedMark) ?? d.deletedMark
        self.editedMark = try container.decodeIfPresent(String.self, forKey: .editedMark) ?? d.editedMark
        self.showMessageSeconds = try container.decodeIfPresent(Bool.self, forKey: .showMessageSeconds) ?? d.showMessageSeconds
        self.showPeerId = try container.decodeIfPresent(Bool.self, forKey: .showPeerId) ?? d.showPeerId
        self.hideSponsoredMessages = try container.decodeIfPresent(Bool.self, forKey: .hideSponsoredMessages) ?? d.hideSponsoredMessages
        self.hideStoriesInChatList = try container.decodeIfPresent(Bool.self, forKey: .hideStoriesInChatList) ?? d.hideStoriesInChatList
        self.confirmStickerSend = try container.decodeIfPresent(Bool.self, forKey: .confirmStickerSend) ?? d.confirmStickerSend
        self.hapticFeedback = try container.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? d.hapticFeedback
        self.messageFiltersEnabled = try container.decodeIfPresent(Bool.self, forKey: .messageFiltersEnabled) ?? d.messageFiltersEnabled
        self.messageFilters = try container.decodeIfPresent([String].self, forKey: .messageFilters) ?? d.messageFilters
    }

    /// Ghost mode as one switch: on when every part of it is on.
    public var isGhostModeFullyEnabled: Bool {
        return self.hideOnlineStatus && self.hideReadReceipts && self.hideStoryViews && self.hideTyping && self.hideMessageContentsRead
    }

    public var isGhostModePartiallyEnabled: Bool {
        return self.hideOnlineStatus || self.hideReadReceipts || self.hideStoryViews || self.hideTyping || self.hideMessageContentsRead
    }

    public mutating func setGhostMode(_ enabled: Bool) {
        self.hideOnlineStatus = enabled
        self.hideReadReceipts = enabled
        self.hideStoryViews = enabled
        self.hideTyping = enabled
        self.hideMessageContentsRead = enabled
    }
}

public final class AyuGramSettings {
    private static let defaultsKey = "ayugram.settings.v1"

    private static let state: Atomic<AyuGramSettingsValues> = Atomic(value: AyuGramSettings.load())
    private static let promise: ValuePromise<AyuGramSettingsValues> = ValuePromise(AyuGramSettings.state.with { $0 }, ignoreRepeated: true)

    /// The settings live in the app group's defaults, so the app extensions (the notification service extension
    /// applies deletions while the app is not running) see the same values as the app.
    private static let defaults: UserDefaults = {
        if let bundleId = Bundle.main.bundleIdentifier {
            var baseAppBundleId = bundleId
            if Bundle.main.bundlePath.hasSuffix(".appex"), let lastDotRange = bundleId.range(of: ".", options: [.backwards]) {
                baseAppBundleId = String(bundleId[..<lastDotRange.lowerBound])
            }
            if let defaults = UserDefaults(suiteName: "group.\(baseAppBundleId)") {
                return defaults
            }
        }
        return UserDefaults.standard
    }()

    private static func load() -> AyuGramSettingsValues {
        // Settings saved by builds that kept them in the app's own defaults are picked up once.
        guard let data = AyuGramSettings.defaults.data(forKey: AyuGramSettings.defaultsKey) ?? UserDefaults.standard.data(forKey: AyuGramSettings.defaultsKey) else {
            return .default
        }
        if let value = try? JSONDecoder().decode(AyuGramSettingsValues.self, from: data) {
            return value
        }
        return .default
    }

    /// Reads the settings again from storage (an app extension calls this, since the app may have changed them since
    /// the extension process started).
    public static func reload() {
        let value = AyuGramSettings.load()
        let _ = AyuGramSettings.state.swap(value)
        AyuGramSettings.promise.set(value)
    }

    /// The current settings. Safe to call from any queue.
    public static var current: AyuGramSettingsValues {
        return AyuGramSettings.state.with { $0 }
    }

    /// The current settings, followed by every change.
    public static var signal: Signal<AyuGramSettingsValues, NoError> {
        return AyuGramSettings.promise.get()
    }

    /// Changes the settings, stores them and notifies observers. Safe to call from any queue.
    public static func update(_ f: (inout AyuGramSettingsValues) -> Void) {
        let updated = AyuGramSettings.state.modify { current in
            var current = current
            f(&current)
            return current
        }
        if let data = try? JSONEncoder().encode(updated) {
            AyuGramSettings.defaults.set(data, forKey: AyuGramSettings.defaultsKey)
        }
        AyuGramSettings.promise.set(updated)
    }

    /// Replaces the settings with values encoded as JSON (keys left out keep their default values). Used by the
    /// automated UI tests, which pass the settings to test in a launch argument. Returns false for invalid JSON.
    @discardableResult
    public static func replace(withJSON data: Data) -> Bool {
        guard let value = try? JSONDecoder().decode(AyuGramSettingsValues.self, from: data) else {
            return false
        }
        AyuGramSettings.update { current in
            current = value
        }
        return true
    }

    public static func reset() {
        AyuGramSettings.update { value in
            value = .default
        }
    }
}

/// How many recent stickers are kept ("Up to 100 recent stickers"; Telegram keeps 20).
var ayuRecentStickersLimit: Int {
    return AyuGramSettings.current.increaseRecentStickers ? 100 : 20
}

/// "Local Premium": the accounts logged in on this device are shown as Premium here. Only the client is affected:
/// features the server checks keep working as for a regular account.
public enum AyuLocalPremium {
    private static let accountPeerIds = Atomic<Set<PeerId>>(value: Set())

    static func registerAccount(_ peerId: PeerId) {
        let _ = AyuLocalPremium.accountPeerIds.modify { current in
            var current = current
            current.insert(peerId)
            return current
        }
    }

    public static func applies(to peerId: PeerId) -> Bool {
        guard AyuGramSettings.current.localPremium else {
            return false
        }
        return AyuLocalPremium.accountPeerIds.with { $0.contains(peerId) }
    }
}
