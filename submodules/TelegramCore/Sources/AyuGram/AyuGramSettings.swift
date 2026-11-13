import Foundation
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
    /// self-destruct timer is not started. Whether the sender learns that you opened them is decided by
    /// `hideMessageContentsRead`.
    public var keepSelfDestructingMedia: Bool

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

    public static func reset() {
        AyuGramSettings.update { value in
            value = .default
        }
    }
}
