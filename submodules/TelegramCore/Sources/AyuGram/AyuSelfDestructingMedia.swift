import Foundation
import Postbox

/// Keeps self-destructing and view-once media of cloud chats viewable after it is opened.
///
/// Telegram expires such media locally: opening it starts the countdown of its `AutoclearTimeoutMessageAttribute`
/// (for view-once media the countdown ends immediately), and `managedAutoremoveMessageOperations` then replaces the
/// media with `TelegramMediaExpiredContent`. Whether the server (and so the sender) learns that the media was opened
/// is a separate request, which ghost mode suppresses. With this option the local countdown is never started, so the
/// media stays in the chat and can be opened again, and nothing changes for the sender beyond what ghost mode allows.
///
/// Secret chats are not affected: their messages are deleted on both sides by the secret chat protocol.
enum AyuSelfDestructingMedia {
    static func keepsMedia(of message: Message) -> Bool {
        if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        if !message.flags.contains(.Incoming) {
            return false
        }
        return AyuGramSettings.current.keepSelfDestructingMedia
    }

    /// Whether `message` is self-destructing or view-once media. Opening it is reported to the sender even in ghost
    /// mode, so for them it looks viewed as usual while AyuGram keeps it on this device.
    static func isSelfDestructing(_ message: Message) -> Bool {
        return message.containsSecretMedia
    }

    /// The attributes with the self-destruct countdown of `message` stopped (the timeout itself is kept, so the media is
    /// still shown and opened as self-destructing).
    static func attributesWithoutCountdown(_ attributes: [MessageAttribute]) -> [MessageAttribute] {
        return attributes.map { attribute -> MessageAttribute in
            if let attribute = attribute as? AutoclearTimeoutMessageAttribute, attribute.countdownBeginTime != nil {
                return AutoclearTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: nil)
            }
            return attribute
        }
    }
}
