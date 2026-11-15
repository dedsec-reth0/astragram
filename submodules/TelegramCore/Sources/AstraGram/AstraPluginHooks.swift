import Foundation
import Postbox
import SwiftSignalKit

/// What a plugin decided about an outgoing message.
public enum AstraPluginOutgoingResult {
    /// Send this text instead.
    case send(String)
    /// Do not send the message (a command that did its work).
    case drop
}

/// Hooks through which AstraGram plugins (run by AstraGramUI's plugin manager) see and change messages. TelegramCore only
/// calls them; the app sets them at launch. They may be called on any queue.
public enum AstraPluginHooks {
    private static let outgoingHook = Atomic<((String, PeerId) -> AstraPluginOutgoingResult?)?>(value: nil)
    private static let hideHook = Atomic<((Message) -> Bool)?>(value: nil)

    /// Called for the text of every outgoing message; nil leaves the message as it is.
    public static func setOutgoingHook(_ hook: ((String, PeerId) -> AstraPluginOutgoingResult?)?) {
        let _ = AstraPluginHooks.outgoingHook.swap(hook)
    }

    /// Called for every incoming message shown in a chat; true hides it.
    public static func setHideHook(_ hook: ((Message) -> Bool)?) {
        let _ = AstraPluginHooks.hideHook.swap(hook)
    }

    static func shouldHide(_ message: Message) -> Bool {
        guard let hook = AstraPluginHooks.hideHook.with({ $0 }) else {
            return false
        }
        return hook(message)
    }

    /// Message templates: ";name" is replaced with the template's text.
    static func templateText(_ text: String) -> String? {
        guard text.hasPrefix(";") else {
            return nil
        }
        let name = text.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
        if name.isEmpty {
            return nil
        }
        for entry in AstraGramSettings.current.messageTemplates {
            guard let separator = entry.range(of: "=") else {
                continue
            }
            let entryName = entry[..<separator.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            if entryName == name {
                // "\n" in a template stands for a line break.
                return entry[separator.upperBound...].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\n", with: "\n")
            }
        }
        return nil
    }

    /// Applies the templates and plugins to messages about to be sent.
    static func transformOutgoing(_ messages: [EnqueueMessage], peerId: PeerId) -> [EnqueueMessage] {
        let templateHook: (String, PeerId) -> AstraPluginOutgoingResult? = { text, _ in
            if let templateText = AstraPluginHooks.templateText(text) {
                return AstraPluginOutgoingResult.send(templateText)
            }
            return nil
        }
        let pluginHook = AstraPluginHooks.outgoingHook.with({ $0 })
        let hook: (String, PeerId) -> AstraPluginOutgoingResult? = { text, peerId in
            if let result = templateHook(text, peerId) {
                return result
            }
            return pluginHook?(text, peerId)
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
