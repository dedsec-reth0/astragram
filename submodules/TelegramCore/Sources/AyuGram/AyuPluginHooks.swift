import Foundation
import Postbox
import SwiftSignalKit

/// What a plugin decided about an outgoing message.
public enum AyuPluginOutgoingResult {
    /// Send this text instead.
    case send(String)
    /// Do not send the message (a command that did its work).
    case drop
}

/// Hooks through which AyuGram plugins (run by AyuGramUI's plugin manager) see and change messages. TelegramCore only
/// calls them; the app sets them at launch. They may be called on any queue.
public enum AyuPluginHooks {
    private static let outgoingHook = Atomic<((String, PeerId) -> AyuPluginOutgoingResult?)?>(value: nil)
    private static let hideHook = Atomic<((Message) -> Bool)?>(value: nil)

    /// Called for the text of every outgoing message; nil leaves the message as it is.
    public static func setOutgoingHook(_ hook: ((String, PeerId) -> AyuPluginOutgoingResult?)?) {
        let _ = AyuPluginHooks.outgoingHook.swap(hook)
    }

    /// Called for every incoming message shown in a chat; true hides it.
    public static func setHideHook(_ hook: ((Message) -> Bool)?) {
        let _ = AyuPluginHooks.hideHook.swap(hook)
    }

    static func shouldHide(_ message: Message) -> Bool {
        guard let hook = AyuPluginHooks.hideHook.with({ $0 }) else {
            return false
        }
        return hook(message)
    }

    /// Applies the plugins to messages about to be sent.
    static func transformOutgoing(_ messages: [EnqueueMessage], peerId: PeerId) -> [EnqueueMessage] {
        guard let hook = AyuPluginHooks.outgoingHook.with({ $0 }) else {
            return messages
        }
        var result: [EnqueueMessage] = []
        for message in messages {
            if case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, !text.isEmpty {
                switch hook(text, peerId) {
                case .none:
                    result.append(message)
                case let .send(updatedText)?:
                    if updatedText == text {
                        result.append(message)
                    } else if updatedText.isEmpty && mediaReference == nil {
                        continue
                    } else {
                        // Formatting entities no longer match the changed text.
                        let updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
                        result.append(.message(text: updatedText, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets))
                    }
                case .drop?:
                    continue
                }
            } else {
                result.append(message)
            }
        }
        return result
    }
}
