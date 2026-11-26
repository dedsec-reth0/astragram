import Foundation
import Postbox
import SwiftSignalKit
import Security

/// AstraGram client-side settings.
///
/// The values are read on network, Postbox and main queues (ghost mode is checked right before a request goes out),
/// so the current value lives in an `Atomic` and every read is a lock-protected copy. Changes are persisted to
/// `UserDefaults` as JSON and broadcast through `AstraGramSettings.signal`.
public struct AstraGramSettingsValues: Codable, Equatable {
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
    /// Save every message the server deletes into the local AstraGram database.
    public var saveDeletedMessages: Bool
    /// Keep messages deleted by other people in the chat, marked as deleted, instead of removing them.
    public var keepDeletedMessagesInChat: Bool
    /// Save previous versions of edited messages into the local AstraGram database.
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
    /// Mark people writing to groups on behalf of a channel with a ◆ before the name.
    public var channelBadge: Bool
    /// Check GitHub for a newer AstraGram build at launch.
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
    /// Stored under a new name (1.0.31): on for everyone once, as in the concept, whatever the old switch said.
    public var musicCapsule: Bool
    /// Look: the Contacts tab in the tab bar.
    public var contactsTab: Bool
    /// Look: the Calls tab in the tab bar (Telegram's own "Show Calls Tab" switch mirrors it).
    public var callsTab: Bool
    /// Look: black, white and grays only, in the dark and the light appearance.
    public var monochrome: Bool
    /// Security: cover the screen while the app is not active, so the app switcher shows nothing of it.
    public var hideInAppSwitcher: Bool
    /// Security: only the system keyboard may be used in the app.
    public var blockThirdPartyKeyboards: Bool
    /// Security: AstraGram's settings open after Face ID.
    public var biometricForAstraGram: Bool
    /// Security: the chats that open after Face ID.
    public var lockedChats: [Int64]
    /// Security: confirm before opening a link that looks dangerous.
    public var warnSuspiciousLinks: Bool
    /// Security: cut tracking parameters from links before they open.
    public var stripLinkTrackers: Bool
    /// Security: what the app copies leaves the clipboard in a minute.
    public var clipboardExpire: Bool
    /// Security: what the app copies is not handed to other devices.
    public var clipboardLocalOnly: Bool
    /// Security: the AI host the user agreed to send text to.
    public var aiConsentEndpoint: String
    /// Look: with Monochrome, chats get a plain black or white background instead of the chosen one.
    public var monochromePlainBackground: Bool
    /// The AstraGram mark in the account's name, so other AstraGram users see a badge beside it (see `AstraBadge`).
    public var astraBadge: Bool
    /// Whether the user has been asked about the AstraGram badge.
    public var astraBadgeAsked: Bool
    /// The streak bot (огонёк for people without AstraGram): its username and the address of its server.
    public var streakBotUsername: String
    public var streakBotURL: String
    /// Look: the material of glass panels and buttons (0 Telegram's own, 1 clear, 2 matte).
    public var glassMaterial: Int
    /// Look: buttons answer a press with a spring, the chat list highlights a row as a rounded plate.
    public var springPresses: Bool
    /// The "AstraGram" ribbon on AstraGram's free gifts (off: they look like any gift).
    public var showAstraGiftRibbon: Bool
    /// No share button beside channel posts and forwarded messages (sharing stays in the message menu).
    public var hideShareButton: Bool = false
    /// An empty private chat shows no greeting sticker.
    public var disableGreetingSticker: Bool = false
    /// Scrolling a chat hides the keyboard.
    public var hideKeyboardOnScroll: Bool = false
    /// A mention chosen at the start of a message is followed by a comma ("@name, ").
    public var commaAfterMention: Bool = false
    /// No "send as" button in groups (shown again while another identity is chosen).
    public var hideSendAsPeer: Bool = false
    /// Typed markdown (**bold**, __italic__, `code`…) is sent as it is, not turned into formatting.
    public var disableMarkdown: Bool = false
    /// What a double tap on a message does: 0 the quick reaction (Telegram's), 1 reply, 2 copy, 3 forward,
    /// 4 save to Saved Messages, 5 edit (own messages; reply to others), 6 nothing.
    public var doubleTapAction: Int = 0
    /// Poll percentages show before voting (unless the poll hides them until it closes).
    public var showPollResultsBeforeVoting: Bool = false
    /// Stickers and big emoji have no time under them (reactions still show).
    public var hideStickerTime: Bool = false
    /// Size of stickers in chats, in percent of Telegram's.
    public var stickerSizePercent: Int = 100
    /// Letters buried under stacks of combining marks ("zalgo") are drawn with at most two.
    public var filterZalgo: Bool = false
    /// Reactions under messages are not drawn in private chats, groups, channels.
    public var hideReactionsPrivate: Bool = false
    public var hideReactionsGroups: Bool = false
    public var hideReactionsChannels: Bool = false
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
    /// Haptic feedback for AstraGram actions and settings.
    public var hapticFeedback: Bool

    // MARK: Message filters
    public var messageFiltersEnabled: Bool
    /// Messages whose text contains one of these (case-insensitive) or matches one of these regular expressions
    /// (entries written as `/pattern/`) are hidden from chat histories.
    public var messageFilters: [String]

    public static let `default` = AstraGramSettingsValues(
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
        sendViaSchedule: true,
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
        musicCapsule: true,
        contactsTab: true,
        callsTab: true,
        monochrome: false,
        hideInAppSwitcher: false,
        blockThirdPartyKeyboards: false,
        biometricForAstraGram: false,
        lockedChats: [],
        warnSuspiciousLinks: true,
        stripLinkTrackers: true,
        clipboardExpire: false,
        clipboardLocalOnly: false,
        aiConsentEndpoint: "",
        monochromePlainBackground: false,
        astraBadge: false,
        astraBadgeAsked: false,
        streakBotUsername: "",
        streakBotURL: "",
        glassMaterial: 0,
        springPresses: false,
        showAstraGiftRibbon: false,
        hideStickersFromOthers: false,
        hideGifsFromOthers: false,
        messageTemplates: [],
        keywordAlerts: [],
        aiEndpoint: "https://api.openai.com/v1",
        aiApiKey: "",
        aiModel: "gpt-4o-mini",
        deletedMark: "⌫",
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
        musicCapsule: Bool,
        contactsTab: Bool,
        callsTab: Bool,
        monochrome: Bool,
        hideInAppSwitcher: Bool,
        blockThirdPartyKeyboards: Bool,
        biometricForAstraGram: Bool,
        lockedChats: [Int64],
        warnSuspiciousLinks: Bool,
        stripLinkTrackers: Bool,
        clipboardExpire: Bool,
        clipboardLocalOnly: Bool,
        aiConsentEndpoint: String,
        monochromePlainBackground: Bool,
        astraBadge: Bool,
        astraBadgeAsked: Bool,
        streakBotUsername: String,
        streakBotURL: String,
        glassMaterial: Int,
        springPresses: Bool,
        showAstraGiftRibbon: Bool,
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
        self.musicCapsule = musicCapsule
        self.contactsTab = contactsTab
        self.callsTab = callsTab
        self.monochrome = monochrome
        self.hideInAppSwitcher = hideInAppSwitcher
        self.blockThirdPartyKeyboards = blockThirdPartyKeyboards
        self.biometricForAstraGram = biometricForAstraGram
        self.lockedChats = lockedChats
        self.warnSuspiciousLinks = warnSuspiciousLinks
        self.stripLinkTrackers = stripLinkTrackers
        self.clipboardExpire = clipboardExpire
        self.clipboardLocalOnly = clipboardLocalOnly
        self.aiConsentEndpoint = aiConsentEndpoint
        self.monochromePlainBackground = monochromePlainBackground
        self.astraBadge = astraBadge
        self.astraBadgeAsked = astraBadgeAsked
        self.streakBotUsername = streakBotUsername
        self.streakBotURL = streakBotURL
        self.glassMaterial = glassMaterial
        self.springPresses = springPresses
        self.showAstraGiftRibbon = showAstraGiftRibbon
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
        let d = AstraGramSettingsValues.default
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
        self.musicCapsule = try container.decodeIfPresent(Bool.self, forKey: .musicCapsule) ?? d.musicCapsule
        self.contactsTab = try container.decodeIfPresent(Bool.self, forKey: .contactsTab) ?? d.contactsTab
        self.callsTab = try container.decodeIfPresent(Bool.self, forKey: .callsTab) ?? d.callsTab
        self.monochrome = try container.decodeIfPresent(Bool.self, forKey: .monochrome) ?? d.monochrome
        self.hideInAppSwitcher = try container.decodeIfPresent(Bool.self, forKey: .hideInAppSwitcher) ?? d.hideInAppSwitcher
        self.blockThirdPartyKeyboards = try container.decodeIfPresent(Bool.self, forKey: .blockThirdPartyKeyboards) ?? d.blockThirdPartyKeyboards
        self.biometricForAstraGram = try container.decodeIfPresent(Bool.self, forKey: .biometricForAstraGram) ?? d.biometricForAstraGram
        self.lockedChats = try container.decodeIfPresent([Int64].self, forKey: .lockedChats) ?? d.lockedChats
        self.warnSuspiciousLinks = try container.decodeIfPresent(Bool.self, forKey: .warnSuspiciousLinks) ?? d.warnSuspiciousLinks
        self.stripLinkTrackers = try container.decodeIfPresent(Bool.self, forKey: .stripLinkTrackers) ?? d.stripLinkTrackers
        self.clipboardExpire = try container.decodeIfPresent(Bool.self, forKey: .clipboardExpire) ?? d.clipboardExpire
        self.clipboardLocalOnly = try container.decodeIfPresent(Bool.self, forKey: .clipboardLocalOnly) ?? d.clipboardLocalOnly
        self.aiConsentEndpoint = try container.decodeIfPresent(String.self, forKey: .aiConsentEndpoint) ?? d.aiConsentEndpoint
        self.monochromePlainBackground = try container.decodeIfPresent(Bool.self, forKey: .monochromePlainBackground) ?? d.monochromePlainBackground
        self.astraBadge = try container.decodeIfPresent(Bool.self, forKey: .astraBadge) ?? d.astraBadge
        self.astraBadgeAsked = try container.decodeIfPresent(Bool.self, forKey: .astraBadgeAsked) ?? d.astraBadgeAsked
        self.streakBotUsername = try container.decodeIfPresent(String.self, forKey: .streakBotUsername) ?? d.streakBotUsername
        self.streakBotURL = try container.decodeIfPresent(String.self, forKey: .streakBotURL) ?? d.streakBotURL
        self.glassMaterial = try container.decodeIfPresent(Int.self, forKey: .glassMaterial) ?? d.glassMaterial
        self.springPresses = try container.decodeIfPresent(Bool.self, forKey: .springPresses) ?? d.springPresses
        self.showAstraGiftRibbon = try container.decodeIfPresent(Bool.self, forKey: .showAstraGiftRibbon) ?? d.showAstraGiftRibbon
        self.hideShareButton = try container.decodeIfPresent(Bool.self, forKey: .hideShareButton) ?? d.hideShareButton
        self.disableGreetingSticker = try container.decodeIfPresent(Bool.self, forKey: .disableGreetingSticker) ?? d.disableGreetingSticker
        self.hideKeyboardOnScroll = try container.decodeIfPresent(Bool.self, forKey: .hideKeyboardOnScroll) ?? d.hideKeyboardOnScroll
        self.commaAfterMention = try container.decodeIfPresent(Bool.self, forKey: .commaAfterMention) ?? d.commaAfterMention
        self.hideSendAsPeer = try container.decodeIfPresent(Bool.self, forKey: .hideSendAsPeer) ?? d.hideSendAsPeer
        self.disableMarkdown = try container.decodeIfPresent(Bool.self, forKey: .disableMarkdown) ?? d.disableMarkdown
        self.doubleTapAction = try container.decodeIfPresent(Int.self, forKey: .doubleTapAction) ?? d.doubleTapAction
        self.showPollResultsBeforeVoting = try container.decodeIfPresent(Bool.self, forKey: .showPollResultsBeforeVoting) ?? d.showPollResultsBeforeVoting
        self.hideStickerTime = try container.decodeIfPresent(Bool.self, forKey: .hideStickerTime) ?? d.hideStickerTime
        self.stickerSizePercent = try container.decodeIfPresent(Int.self, forKey: .stickerSizePercent) ?? d.stickerSizePercent
        self.filterZalgo = try container.decodeIfPresent(Bool.self, forKey: .filterZalgo) ?? d.filterZalgo
        self.hideReactionsPrivate = try container.decodeIfPresent(Bool.self, forKey: .hideReactionsPrivate) ?? d.hideReactionsPrivate
        self.hideReactionsGroups = try container.decodeIfPresent(Bool.self, forKey: .hideReactionsGroups) ?? d.hideReactionsGroups
        self.hideReactionsChannels = try container.decodeIfPresent(Bool.self, forKey: .hideReactionsChannels) ?? d.hideReactionsChannels
        self.hideStickersFromOthers = try container.decodeIfPresent(Bool.self, forKey: .hideStickersFromOthers) ?? d.hideStickersFromOthers
        self.hideGifsFromOthers = try container.decodeIfPresent(Bool.self, forKey: .hideGifsFromOthers) ?? d.hideGifsFromOthers
        self.messageTemplates = try container.decodeIfPresent([String].self, forKey: .messageTemplates) ?? d.messageTemplates
        self.keywordAlerts = try container.decodeIfPresent([String].self, forKey: .keywordAlerts) ?? d.keywordAlerts
        self.aiEndpoint = try container.decodeIfPresent(String.self, forKey: .aiEndpoint) ?? d.aiEndpoint
        self.aiApiKey = try container.decodeIfPresent(String.self, forKey: .aiApiKey) ?? d.aiApiKey
        self.aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? d.aiModel
        // The mark was a broom emoji by default; whoever kept that default gets the new sign.
        let storedDeletedMark = try container.decodeIfPresent(String.self, forKey: .deletedMark) ?? d.deletedMark
        self.deletedMark = storedDeletedMark == "\u{1F9F9}" ? d.deletedMark : storedDeletedMark
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

/// AstraGram: the AI key lives in the Keychain (this device only, readable after the first unlock), not with the other
/// settings in the app group's defaults.
private enum AstraSecretStore {
    private static let service = "org.astragram.ai"
    private static let account = "apiKey"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AstraSecretStore.service,
            kSecAttrAccount as String: AstraSecretStore.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AstraSecretStore.service,
            kSecAttrAccount as String: AstraSecretStore.account
        ]
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        // Updated in place, added only when missing: deleting first lost the old key whenever the add then failed.
        let data = value.data(using: .utf8) ?? Data()
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            return false
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// An item kept only so the lock can be detected: with no AI key there is no item to fail on, and the Keychain
    /// reports a missing item as "not found" even while it is locked.
    private static let probeAccount = "lockProbe"

    /// Saves the probe item once (while the device is unlocked), so later launches before the first unlock see it fail.
    static func ensureProbe() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AstraSecretStore.service,
            kSecAttrAccount as String: AstraSecretStore.probeAccount
        ]
        guard SecItemCopyMatching(query as CFDictionary, nil) == errSecItemNotFound else {
            return
        }
        var attributes = query
        attributes[kSecValueData as String] = Data([1])
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    /// True while the Keychain cannot be read at all: before the first unlock after a reboot, when the app group's
    /// defaults are not readable either and read back as empty.
    static func isLocked() -> Bool {
        for account in [AstraSecretStore.probeAccount, AstraSecretStore.account] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: AstraSecretStore.service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecInteractionNotAllowed {
                return true
            }
        }
        return false
    }
}

public final class AstraGramSettings {
    private static let defaultsKey = "ayugram.settings.v1"

    /// The AI key last read from or written to the Keychain: it is written only when it changes, so an extension
    /// (which has no access to the app's Keychain item) never wipes it.
    private static let storedApiKey = Atomic<String?>(value: nil)

    /// The settings as stored in the defaults: without the AI key, which goes to the Keychain.
    private static func encodeForStorage(_ value: AstraGramSettingsValues) -> Data? {
        let key = value.aiApiKey
        var stripped = value
        if AstraGramSettings.storedApiKey.with({ $0 }) != key {
            // Marked as stored only once the write worked, so a failed write is retried by the next update. Until
            // then the key stays in the defaults (as load() does), and a later load() moves it to the Keychain.
            if AstraSecretStore.write(key) {
                let _ = AstraGramSettings.storedApiKey.swap(key)
                stripped.aiApiKey = ""
            }
        } else {
            stripped.aiApiKey = ""
        }
        return try? JSONEncoder().encode(stripped)
    }

    /// The defaults with the AI key from the Keychain: without it the first update() saw an empty key that differs
    /// from the unknown stored one and deleted the Keychain item (after a reinstall the Keychain keeps the key while
    /// the app group's defaults are gone).
    private static func defaultWithStoredKey() -> AstraGramSettingsValues {
        var value = AstraGramSettingsValues.default
        let key = AstraSecretStore.read() ?? ""
        let _ = AstraGramSettings.storedApiKey.swap(key)
        value.aiApiKey = key
        return value
    }

    /// Set while the settings could not be read because the device has not been unlocked since it started: the
    /// defaults then stand in memory only, and update() does not save them over the real settings. Cleared by the
    /// reload once protected data becomes available.
    private static let loadFailed = Atomic<Bool>(value: false)

    /// Reloads the settings when protected data becomes available after a launch before the first unlock. Observed by
    /// the notification's name, since TelegramCore does not import UIKit.
    private static let protectedDataObserver: NSObjectProtocol = NotificationCenter.default.addObserver(forName: NSNotification.Name("UIApplicationProtectedDataDidBecomeAvailable"), object: nil, queue: nil, using: { _ in
        if AstraGramSettings.loadFailed.with({ $0 }) {
            AstraGramSettings.reload()
        }
    })

    private static let state: Atomic<AstraGramSettingsValues> = Atomic(value: AstraGramSettings.load())
    private static let promise: ValuePromise<AstraGramSettingsValues> = ValuePromise(AstraGramSettings.state.with { $0 }, ignoreRepeated: true)

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

    private static func load() -> AstraGramSettingsValues {
        // Settings saved by builds that kept them in the app's own defaults are picked up once.
        guard let data = AstraGramSettings.defaults.data(forKey: AstraGramSettings.defaultsKey) ?? UserDefaults.standard.data(forKey: AstraGramSettings.defaultsKey) else {
            // Before the first unlock the defaults read as empty although settings exist: not "no settings".
            if AstraSecretStore.isLocked() {
                let _ = AstraGramSettings.loadFailed.swap(true)
                let _ = AstraGramSettings.protectedDataObserver
            } else {
                let _ = AstraGramSettings.loadFailed.swap(false)
                AstraSecretStore.ensureProbe()
            }
            return AstraGramSettings.defaultWithStoredKey()
        }
        let _ = AstraGramSettings.loadFailed.swap(false)
        AstraSecretStore.ensureProbe()
        if var value = try? JSONDecoder().decode(AstraGramSettingsValues.self, from: data) {
            if !value.aiApiKey.isEmpty {
                // Saved by a build that kept the key in the defaults: it moves to the Keychain.
                if AstraSecretStore.write(value.aiApiKey) {
                    let _ = AstraGramSettings.storedApiKey.swap(value.aiApiKey)
                    var stripped = value
                    stripped.aiApiKey = ""
                    if let strippedData = try? JSONEncoder().encode(stripped) {
                        AstraGramSettings.defaults.set(strippedData, forKey: AstraGramSettings.defaultsKey)
                        UserDefaults.standard.removeObject(forKey: AstraGramSettings.defaultsKey)
                    }
                }
            } else {
                let key = AstraSecretStore.read() ?? ""
                let _ = AstraGramSettings.storedApiKey.swap(key)
                value.aiApiKey = key
            }
            // "Send via schedule" is on by default since 1.0.11: without it ghost mode shows the account online after
            // every message. Turned on once for settings saved before; the user can turn it off again.
            let sendViaScheduleMigrationKey = "astragram.migration.sendViaScheduleOn"
            if !AstraGramSettings.defaults.bool(forKey: sendViaScheduleMigrationKey) {
                value.sendViaSchedule = true
                if let migratedData = AstraGramSettings.encodeForStorage(value) {
                    AstraGramSettings.defaults.set(migratedData, forKey: AstraGramSettings.defaultsKey)
                }
                AstraGramSettings.defaults.set(true, forKey: sendViaScheduleMigrationKey)
            }
            return value
        }
        return AstraGramSettings.defaultWithStoredKey()
    }

    /// Reads the settings again from storage (an app extension calls this, since the app may have changed them since
    /// the extension process started).
    public static func reload() {
        let value = AstraGramSettings.load()
        let _ = AstraGramSettings.state.swap(value)
        AstraGramSettings.promise.set(value)
    }

    /// The current settings. Safe to call from any queue.
    public static var current: AstraGramSettingsValues {
        return AstraGramSettings.state.with { $0 }
    }

    /// The current settings, followed by every change.
    public static var signal: Signal<AstraGramSettingsValues, NoError> {
        return AstraGramSettings.promise.get()
    }

    /// Changes the settings, stores them and notifies observers. Safe to call from any queue.
    public static func update(_ f: (inout AstraGramSettingsValues) -> Void) {
        let updated = AstraGramSettings.state.modify { current in
            var current = current
            f(&current)
            return current
        }
        // Not saved while the stored settings could not be read: the defaults in memory would replace them for good.
        if !AstraGramSettings.loadFailed.with({ $0 }), let data = AstraGramSettings.encodeForStorage(updated) {
            AstraGramSettings.defaults.set(data, forKey: AstraGramSettings.defaultsKey)
        }
        AstraGramSettings.promise.set(updated)
    }

    /// Replaces the settings with values encoded as JSON (keys left out keep their default values). Used by the
    /// automated UI tests, which pass the settings to test in a launch argument. Returns false for invalid JSON.
    /// `adjusting` gets the settings being replaced and the decoded ones, and changes the decoded ones before they are
    /// stored: one update, so no observer ever sees the file's values before the adjustment (a backup's server address
    /// would otherwise receive the streak-bot token in between).
    @discardableResult
    public static func replace(withJSON data: Data, adjusting: (AstraGramSettingsValues, inout AstraGramSettingsValues) -> Void = { _, _ in }) -> Bool {
        guard var value = try? JSONDecoder().decode(AstraGramSettingsValues.self, from: data) else {
            return false
        }
        AstraGramSettings.update { current in
            adjusting(current, &value)
            current = value
        }
        return true
    }

    /// Back to the defaults, except what protects the user or cannot be typed again easily: the AI key, the chats
    /// locked with Face ID and Face ID for these settings.
    public static func reset() {
        AstraGramSettings.update { value in
            let aiApiKey = value.aiApiKey
            let lockedChats = value.lockedChats
            let biometricForAstraGram = value.biometricForAstraGram
            value = .default
            value.aiApiKey = aiApiKey
            value.lockedChats = lockedChats
            value.biometricForAstraGram = biometricForAstraGram
        }
    }
}

/// How many recent stickers are kept ("Up to 100 recent stickers"; Telegram keeps 20).
var astraRecentStickersLimit: Int {
    return AstraGramSettings.current.increaseRecentStickers ? 100 : 20
}

/// "Local Premium": the accounts logged in on this device are shown as Premium here. Only the client is affected:
/// features the server checks keep working as for a regular account.
public enum AstraLocalPremium {
    private static let accountPeerIds = Atomic<Set<PeerId>>(value: Set())

    static func registerAccount(_ peerId: PeerId) {
        let _ = AstraLocalPremium.accountPeerIds.modify { current in
            var current = current
            current.insert(peerId)
            return current
        }
    }

    /// Whether `peerId` is an account logged in on this device, whatever the Local Premium switch says.
    static func isAccount(_ peerId: PeerId) -> Bool {
        return AstraLocalPremium.accountPeerIds.with { $0.contains(peerId) }
    }

    public static func applies(to peerId: PeerId) -> Bool {
        guard AstraGramSettings.current.localPremium else {
            return false
        }
        return AstraLocalPremium.accountPeerIds.with { $0.contains(peerId) }
    }

    // MARK: The emoji status

    /// The server takes an emoji status only from real Premium, so with Local Premium the status picked is kept here,
    /// on this device, and shown in place of the one the server sends (`updatePeersCustom`). Others do not see it.
    private struct StoredEmojiStatus: Codable {
        let status: PeerEmojiStatus?
    }

    /// Per account, once read from the disk: nil = nothing picked locally; a status of nil = removed locally.
    private static let emojiStatuses = Atomic<[PeerId: StoredEmojiStatus?]>(value: [:])

    private static func emojiStatusKey(_ accountPeerId: PeerId) -> String {
        return "astragram.localPremium.emojiStatus.\(accountPeerId.toInt64())"
    }

    private static func loadedEmojiStatus(accountPeerId: PeerId) -> StoredEmojiStatus? {
        if let cached = AstraLocalPremium.emojiStatuses.with({ $0[accountPeerId] }) {
            return cached
        }
        var stored: StoredEmojiStatus?
        if let data = UserDefaults.standard.data(forKey: AstraLocalPremium.emojiStatusKey(accountPeerId)) {
            stored = try? JSONDecoder().decode(StoredEmojiStatus.self, from: data)
        }
        let _ = AstraLocalPremium.emojiStatuses.modify { current in
            var current = current
            current[accountPeerId] = .some(stored)
            return current
        }
        return stored
    }

    /// Whether `user` is an account of this device shown as Premium by Local Premium only.
    static func isLocalOnly(_ user: TelegramUser) -> Bool {
        return !user.flags.contains(.isPremium) && AstraLocalPremium.applies(to: user.id)
    }

    /// Keeps `status` as the account's emoji status on this device.
    static func setEmojiStatus(_ status: PeerEmojiStatus?, accountPeerId: PeerId) {
        let stored = StoredEmojiStatus(status: status)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: AstraLocalPremium.emojiStatusKey(accountPeerId))
        }
        let _ = AstraLocalPremium.emojiStatuses.modify { current in
            var current = current
            current[accountPeerId] = .some(stored)
            return current
        }
    }

    /// `user` with the emoji status picked on this device, when Local Premium shows it as Premium.
    static func applyingEmojiStatus(_ user: TelegramUser) -> TelegramUser {
        guard AstraLocalPremium.isLocalOnly(user), let stored = AstraLocalPremium.loadedEmojiStatus(accountPeerId: user.id), stored.status != user.emojiStatus else {
            return user
        }
        return user.withUpdatedEmojiStatus(stored.status)
    }

    // MARK: The name and profile colors

    /// The server takes name and profile colors only from real Premium as well, so with Local Premium the colors picked
    /// are kept here and shown in place of the server's, on this device only.
    private struct StoredColors: Codable {
        var namePreset: Int32?
        var nameCollectible: PeerCollectibleColor?
        var backgroundEmojiId: Int64?
        var profileColor: Int32?
        var profileBackgroundEmojiId: Int64?

        var nameColor: PeerColor? {
            if let nameCollectible {
                return .collectible(nameCollectible)
            }
            return self.namePreset.map { .preset(PeerNameColor(rawValue: $0)) }
        }
    }

    private static let colors = Atomic<[PeerId: StoredColors?]>(value: [:])

    private static func colorsKey(_ accountPeerId: PeerId) -> String {
        return "astragram.localPremium.colors.\(accountPeerId.toInt64())"
    }

    private static func loadedColors(accountPeerId: PeerId) -> StoredColors? {
        if let cached = AstraLocalPremium.colors.with({ $0[accountPeerId] }) {
            return cached
        }
        var stored: StoredColors?
        if let data = UserDefaults.standard.data(forKey: AstraLocalPremium.colorsKey(accountPeerId)) {
            stored = try? JSONDecoder().decode(StoredColors.self, from: data)
        }
        let _ = AstraLocalPremium.colors.modify { current in
            var current = current
            current[accountPeerId] = .some(stored)
            return current
        }
        return stored
    }

    /// Keeps the colors picked as the account's name and profile colors on this device.
    static func setColors(nameColor: PeerColor, backgroundEmojiId: Int64?, profileColor: PeerNameColor?, profileBackgroundEmojiId: Int64?, accountPeerId: PeerId) {
        var stored = StoredColors()
        switch nameColor {
        case let .preset(color):
            stored.namePreset = color.rawValue
        case let .collectible(color):
            stored.nameCollectible = color
        }
        stored.backgroundEmojiId = backgroundEmojiId
        stored.profileColor = profileColor?.rawValue
        stored.profileBackgroundEmojiId = profileBackgroundEmojiId
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: AstraLocalPremium.colorsKey(accountPeerId))
        }
        let _ = AstraLocalPremium.colors.modify { current in
            var current = current
            current[accountPeerId] = .some(stored)
            return current
        }
    }

    /// The account's Local Premium look as other AstraGram apps get it (nil: Local Premium is off, or the account has
    /// real Premium and Telegram shows its look to everyone already). An emoji status of a gift is left out: worn
    /// gifts travel on their own.
    public static func sharedLook(account: TelegramUser) -> [String: Any]? {
        guard AstraLocalPremium.isLocalOnly(account) else {
            return nil
        }
        var look: [String: Any] = [:]
        if let status = AstraLocalPremium.loadedEmojiStatus(accountPeerId: account.id)?.status, case let .emoji(fileId) = status.content {
            look["status"] = "\(fileId)"
            if let until = status.expirationDate {
                look["statusUntil"] = NSNumber(value: until)
            }
        }
        if let colors = AstraLocalPremium.loadedColors(accountPeerId: account.id) {
            if let preset = colors.namePreset {
                look["nameColor"] = NSNumber(value: preset)
            }
            if let id = colors.backgroundEmojiId {
                look["backgroundEmoji"] = "\(id)"
            }
            if let profile = colors.profileColor {
                look["profileColor"] = NSNumber(value: profile)
            }
            if let id = colors.profileBackgroundEmojiId {
                look["profileBackgroundEmoji"] = "\(id)"
            }
        }
        return look
    }

    /// `user` with the emoji status and colors picked on this device, when Local Premium shows it as Premium.
    static func applyingLocal(_ user: TelegramUser) -> TelegramUser {
        var user = AstraLocalPremium.applyingEmojiStatus(user)
        guard AstraLocalPremium.isLocalOnly(user), let stored = AstraLocalPremium.loadedColors(accountPeerId: user.id) else {
            return user
        }
        if let nameColor = stored.nameColor, user.nameColor != nameColor {
            user = user.withUpdatedNameColor(nameColor)
        }
        if user.backgroundEmojiId != stored.backgroundEmojiId {
            user = user.withUpdatedBackgroundEmojiId(stored.backgroundEmojiId)
        }
        let profileColor = stored.profileColor.map { PeerNameColor(rawValue: $0) }
        if user.profileColor != profileColor {
            user = user.withUpdatedProfileColor(profileColor)
        }
        if user.profileBackgroundEmojiId != stored.profileBackgroundEmojiId {
            user = user.withUpdatedProfileBackgroundEmojiId(stored.profileBackgroundEmojiId)
        }
        return user
    }
}

public extension String {
    /// Whether AstraGram's own texts are shown in Russian for this language code: Russian, and also Ukrainian and
    /// Belarusian (AstraGram has no texts of its own in those, and Russian is closer than English).
    var astraUsesRussianTexts: Bool {
        let code = self.lowercased()
        return code.hasPrefix("ru") || code.hasPrefix("uk") || code.hasPrefix("be")
    }
}
