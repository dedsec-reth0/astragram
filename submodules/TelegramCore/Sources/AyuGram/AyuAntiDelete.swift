import Foundation
import Postbox

/// Applies a deletion the notification service extension received while the app was not running, through
/// anti-delete like any received deletion. Returns the ids that were actually deleted.
public func ayuApplyReceivedDeletionInExtension(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) -> [MessageId] {
    AyuGramSettings.reload()
    let remaining = AyuAntiDelete.interceptReceivedDeletion(transaction: transaction, mediaBox: mediaBox, ids: ids)
    if !remaining.isEmpty {
        _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: remaining, deleteMedia: true)
    }
    return remaining
}

/// Anti-delete and edit history: the hooks the update replay and the history confirmation call.
///
/// Only deletions that come from the server pass through here (updates, getDifference, history fills that found a
/// stored message gone). Deleting messages yourself (`deleteMessagesInteractively`) does not, so your own deletions
/// still delete.
enum AyuAntiDelete {
    private static func shouldHandle(_ message: Message, settings: AyuGramSettingsValues) -> Bool {
        guard message.id.namespace == Namespaces.Message.Cloud else {
            return false
        }
        // "Also in channels" covers broadcast channels only; supergroups are chats.
        if !settings.saveDeletedInChannels, let channel = message.peers[message.id.peerId] as? TelegramChannel, case .broadcast = channel.info {
            return false
        }
        return true
    }

    /// Whether the message is kept in the chat as deleted. Such a message no longer exists on the server, so history
    /// synchronization must not treat it as a stored message the server lost.
    static func isKept(transaction: Transaction, id: MessageId) -> Bool {
        return transaction.getMessage(id)?.ayuDeletedAt != nil
    }

    /// For history validation, which found `id` gone on the server: keeps it in the chat as deleted when anti-delete
    /// wants that (or already did), and marks it validated at `channelPts` so validation does not ask again. Returns
    /// false when the message must be deleted as usual.
    static func keepOnValidation(transaction: Transaction, mediaBox: MediaBox, id: MessageId, channelPts: Int32?) -> Bool {
        if !AyuAntiDelete.interceptReceivedDeletion(transaction: transaction, mediaBox: mediaBox, ids: [id]).isEmpty {
            return false
        }
        guard transaction.getMessage(id) != nil else {
            return true
        }
        if let channelPts = channelPts {
            transaction.updateMessage(id, update: { currentMessage in
                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                var attributes = currentMessage.attributes.filter { !($0 is ChannelMessageStateVersionAttribute) }
                attributes.append(ChannelMessageStateVersionAttribute(pts: channelPts))
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
            })
        }
        return true
    }

    private static func isService(_ message: Message) -> Bool {
        return message.media.contains(where: { $0 is TelegramMediaAction })
    }

    /// Saves the messages about to be deleted and, when "keep in chat" is on, marks them deleted instead of
    /// deleting them. Returns the ids that must still be deleted.
    static func interceptReceivedDeletion(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) -> [MessageId] {
        let settings = AyuGramSettings.current
        if !settings.saveDeletedMessages && !settings.keepDeletedMessagesInChat {
            return ids
        }
        let now = Int32(Date().timeIntervalSince1970)
        var snapshots: [AyuMessageSnapshot] = []
        var remaining: [MessageId] = []
        for id in ids {
            guard let message = transaction.getMessage(id), AyuAntiDelete.shouldHandle(message, settings: settings) else {
                remaining.append(id)
                continue
            }
            if message.ayuDeletedAt != nil {
                // Already kept as deleted: a repeated deletion of it changes nothing.
                continue
            }
            if settings.saveDeletedMessages {
                snapshots.append(AyuMessageSnapshot(message: message))
            }
            if settings.keepDeletedMessagesInChat && !AyuAntiDelete.isService(message) {
                transaction.updateMessage(id, update: { currentMessage in
                    let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                    var attributes = currentMessage.attributes
                    attributes.append(AyuDeletedMessageAttribute(deletedAt: now))
                    // The server no longer has it: it is no longer pinned, and no unseen mention or reaction badge leads
                    // to it.
                    var tags = currentMessage.tags
                    tags.remove(.unseenPersonalMessage)
                    tags.remove(.unseenReaction)
                    tags.remove(.unseenPollVote)
                    tags.remove(.pinned)
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                })
            } else {
                remaining.append(id)
            }
        }
        if !snapshots.isEmpty {
            AyuMessageStore.forMediaBoxBasePath(mediaBox.basePath).saveDeleted(snapshots, deletedAt: now)
        }
        return remaining
    }

    /// Saves messages that are deleted anyway (a history fill found them gone on the server), without keeping them.
    static func saveBeforeDeletion(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
        let settings = AyuGramSettings.current
        if !settings.saveDeletedMessages {
            return
        }
        var snapshots: [AyuMessageSnapshot] = []
        for id in ids {
            if let message = transaction.getMessage(id), AyuAntiDelete.shouldHandle(message, settings: settings), message.ayuDeletedAt == nil {
                snapshots.append(AyuMessageSnapshot(message: message))
            }
        }
        if !snapshots.isEmpty {
            AyuMessageStore.forMediaBoxBasePath(mediaBox.basePath).saveDeleted(snapshots, deletedAt: Int32(Date().timeIntervalSince1970))
        }
    }

    /// Saves the current version of a message the server is about to replace with an edit.
    static func recordEdit(transaction: Transaction, mediaBox: MediaBox, id: MessageId, updated: StoreMessage) {
        let settings = AyuGramSettings.current
        guard settings.saveEditHistory, id.namespace == Namespaces.Message.Cloud, let previous = transaction.getMessage(id) else {
            return
        }
        var updatedEditDate: Int32?
        for attribute in updated.attributes {
            if let attribute = attribute as? EditedMessageAttribute {
                updatedEditDate = attribute.date
            }
        }
        var previousEditDate: Int32?
        for attribute in previous.attributes {
            if let attribute = attribute as? EditedMessageAttribute {
                previousEditDate = attribute.date
            }
        }
        // Edit updates also carry view counters, reply markup and reactions: only a new edit date with changed
        // text or media is an edit worth a version.
        guard let editDate = updatedEditDate, editDate != previousEditDate else {
            return
        }
        let previousMediaIds = previous.media.compactMap { $0.id }
        let updatedMediaIds = updated.media.compactMap { $0.id }
        if previous.text == updated.text && previousMediaIds == updatedMediaIds {
            return
        }
        AyuMessageStore.forMediaBoxBasePath(mediaBox.basePath).saveEdit(previous: AyuMessageSnapshot(message: previous), replacedAt: editDate)
    }
}
