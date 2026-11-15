import Foundation
import Postbox
import SwiftSignalKit

/// Messages hidden on this device with "Hide message" in the message menu. Kept in the app's own defaults.
public enum AstraHiddenMessages {
    private static let defaultsKey = "ayugram.hiddenMessages.v1"
    private static let ids = Atomic<Set<String>>(value: Set(UserDefaults.standard.stringArray(forKey: AstraHiddenMessages.defaultsKey) ?? []))

    private static func key(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
    }

    public static func contains(_ id: MessageId) -> Bool {
        let key = AstraHiddenMessages.key(id)
        return AstraHiddenMessages.ids.with { $0.contains(key) }
    }

    public static var count: Int {
        return AstraHiddenMessages.ids.with { $0.count }
    }

    fileprivate static func add(_ id: MessageId) {
        let updated = AstraHiddenMessages.ids.modify { current in
            var current = current
            current.insert(AstraHiddenMessages.key(id))
            return current
        }
        UserDefaults.standard.set(Array(updated), forKey: AstraHiddenMessages.defaultsKey)
    }

    /// Shows every hidden message again (they reappear when their chats are next updated or reopened).
    public static func removeAll() {
        let _ = AstraHiddenMessages.ids.swap(Set())
        UserDefaults.standard.removeObject(forKey: AstraHiddenMessages.defaultsKey)
    }
}

/// AstraGram's message menu actions that need TelegramCore internals.
public enum AstraMessageActions {
    /// "Read until here": marks the chat read up to `index`, and sends the read receipt even in ghost mode.
    public static func readUntil(account: Account, index: MessageIndex) -> Signal<Void, NoError> {
        guard let stateManager = account.stateManager else {
            return .complete()
        }
        return _internal_applyMaxReadIndexInteractively(postbox: account.postbox, stateManager: stateManager, index: index)
        |> afterCompleted {
            if AstraGramSettings.current.hideReadReceipts {
                AstraGhostMode.pushReadStateOnce(account: account, peerId: index.id.peerId)
            }
        }
    }

    /// "Hide message": hides the message on this device only.
    public static func hideLocally(account: Account, id: MessageId) -> Signal<Void, NoError> {
        AstraHiddenMessages.add(id)
        // Rewriting the message unchanged makes open chats rebuild their history, which now leaves it out.
        return account.postbox.transaction { transaction -> Void in
            transaction.updateMessage(id, update: { currentMessage in
                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: currentMessage.attributes, media: currentMessage.media))
            })
        }
    }

    /// "Burn now": expires a kept self-destructing or view-once media right away, as Telegram would have.
    public static func expireSelfDestructingMedia(account: Account, id: MessageId) -> Signal<Void, NoError> {
        return account.postbox.transaction { transaction -> Void in
            transaction.updateMessage(id, update: { currentMessage in
                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                var updatedMedia = currentMessage.media
                for i in 0 ..< updatedMedia.count {
                    if updatedMedia[i] is TelegramMediaImage {
                        updatedMedia[i] = TelegramMediaExpiredContent(data: .image)
                    } else if let file = updatedMedia[i] as? TelegramMediaFile {
                        if file.isInstantVideo {
                            updatedMedia[i] = TelegramMediaExpiredContent(data: .videoMessage)
                        } else if file.isVoice {
                            updatedMedia[i] = TelegramMediaExpiredContent(data: .voiceMessage)
                        } else {
                            updatedMedia[i] = TelegramMediaExpiredContent(data: .file)
                        }
                    }
                }
                let updatedAttributes = currentMessage.attributes.filter { !($0 is AutoclearTimeoutMessageAttribute) }
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
            })
        }
    }

    /// The newest `limit` messages of a chat, oldest first (for chat export, statistics and AI summaries).
    public static func recentMessages(account: Account, peerId: PeerId, limit: Int) -> Signal<[Message], NoError> {
        return account.postbox.transaction { transaction -> [Message] in
            var messages: [Message] = []
            transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: limit, { message in
                messages.append(message)
                return messages.count < limit
            })
            return messages.sorted(by: { $0.index < $1.index })
        }
    }
}
