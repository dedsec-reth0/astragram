import Foundation
import Postbox

/// Marks a message that the server deleted but AyuGram kept in the chat ("Anti-delete").
public final class AyuDeletedMessageAttribute: Equatable, MessageAttribute {
    public let deletedAt: Int32

    public init(deletedAt: Int32) {
        self.deletedAt = deletedAt
    }

    required public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "d")
    }

    public static func ==(lhs: AyuDeletedMessageAttribute, rhs: AyuDeletedMessageAttribute) -> Bool {
        return lhs.deletedAt == rhs.deletedAt
    }
}

public extension Message {
    /// The time AyuGram saw this message deleted on the server, if it was kept in the chat.
    var ayuDeletedAt: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? AyuDeletedMessageAttribute {
                return attribute.deletedAt
            }
        }
        return nil
    }
}

public extension EngineMessage {
    var ayuDeletedAt: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? AyuDeletedMessageAttribute {
                return attribute.deletedAt
            }
        }
        return nil
    }
}
