import Foundation
import Postbox
import SwiftSignalKit

/// Messages hidden on this device with "Hide message" in the message menu. Kept in the app's own defaults.
public enum AyuHiddenMessages {
    private static let defaultsKey = "ayugram.hiddenMessages.v1"
    private static let ids = Atomic<Set<String>>(value: Set(UserDefaults.standard.stringArray(forKey: AyuHiddenMessages.defaultsKey) ?? []))

    private static func key(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64()):\(id.namespace):\(id.id)"
    }

    public static func contains(_ id: MessageId) -> Bool {
        let key = AyuHiddenMessages.key(id)
        return AyuHiddenMessages.ids.with { $0.contains(key) }
    }

    public static var count: Int {
        return AyuHiddenMessages.ids.with { $0.count }
    }

    fileprivate static func add(_ id: MessageId) {
        let updated = AyuHiddenMessages.ids.modify { current in
            var current = current
            current.insert(AyuHiddenMessages.key(id))
            return current
        }
        UserDefaults.standard.set(Array(updated), forKey: AyuHiddenMessages.defaultsKey)
    }

    /// Shows every hidden message again (they reappear when their chats are next updated or reopened).
    public static func removeAll() {
        let _ = AyuHiddenMessages.ids.swap(Set())
        UserDefaults.standard.removeObject(forKey: AyuHiddenMessages.defaultsKey)
    }
}

/// AyuGram's message menu actions that need TelegramCore internals.
public enum AyuMessageActions {
    /// "Read until here": marks the chat read up to `index`, and sends the read receipt even in ghost mode.
    public static func readUntil(account: Account, index: MessageIndex) -> Signal<Void, NoError> {
        guard let stateManager = account.stateManager else {
            return .complete()
        }
        return _internal_applyMaxReadIndexInteractively(postbox: account.postbox, stateManager: stateManager, index: index)
        |> afterCompleted {
            if AyuGramSettings.current.hideReadReceipts {
                AyuGhostMode.pushReadStateOnce(account: account, peerId: index.id.peerId)
            }
        }
    }

    /// "Hide message": hides the message on this device only.
    public static func hideLocally(account: Account, id: MessageId) -> Signal<Void, NoError> {
        AyuHiddenMessages.add(id)
        // Rewriting the message unchanged makes open chats rebuild their history, which now leaves it out.
        return account.postbox.transaction { transaction -> Void in
            transaction.updateMessage(id, update: { currentMessage in
                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: currentMessage.attributes, media: currentMessage.media))
            })
        }
    }
}
