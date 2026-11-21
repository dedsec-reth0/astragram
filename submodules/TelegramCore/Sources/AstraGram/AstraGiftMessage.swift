import Foundation
import Postbox
import SwiftSignalKit

/// AstraGram: the chat message of a visual gift (AstraGram's gift shop). The giver's app sends a plain text message
/// with the gift's ID hidden in invisible characters; AstraGram draws such a message as Telegram's gift card, other
/// apps show the text.
public enum AstraGiftMessage {
    /// Around the gift ID; other characters than a streak restore's mark, so the two never mix.
    private static let mark: [Unicode.Scalar] = ["\u{2064}", "\u{2062}", "\u{2063}"]
    private static let digits: [Unicode.Scalar] = ["\u{200B}", "\u{200C}", "\u{2060}", "\u{2061}"]

    /// Telegram's gift catalog by ID, as the app last loaded it (AstraGramUI keeps it filled).
    private static let catalog = Atomic<[Int64: StarGift.Gift]>(value: [:])

    public static func setCatalog(_ gifts: [Int64: StarGift.Gift]) {
        let _ = AstraGiftMessage.catalog.swap(gifts)
    }

    public static func gift(id: Int64) -> StarGift.Gift? {
        return AstraGiftMessage.catalog.with { $0[id] }
    }

    public static func text(giftId: Int64, title: String, isRussian: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: AstraGiftMessage.mark)
        var value = UInt64(bitPattern: giftId)
        var encoded: [Unicode.Scalar] = []
        repeat {
            encoded.insert(AstraGiftMessage.digits[Int(value % 4)], at: 0)
            value /= 4
        } while value > 0
        scalars.append(contentsOf: encoded)
        scalars.append(contentsOf: AstraGiftMessage.mark)
        let hidden = String(scalars)
        if isRussian {
            return "🎁 Дарю тебе «\(title)» в AstraGram\(hidden)\nПодарок виден в профиле в AstraGram"
        } else {
            return "🎁 A gift for you in AstraGram: \"\(title)\"\(hidden)\nThe gift shows on the profile in AstraGram"
        }
    }

    /// The gift ID a message text carries, if it is a visual gift message.
    public static func giftId(in text: String) -> Int64? {
        let scalars = Array(text.unicodeScalars)
        let mark = AstraGiftMessage.mark
        var index = 0
        while index + mark.count <= scalars.count {
            if Array(scalars[index ..< index + mark.count]) == mark {
                var position = index + mark.count
                var value: UInt64 = 0
                var count = 0
                while position < scalars.count, let digit = AstraGiftMessage.digits.firstIndex(of: scalars[position]) {
                    value = value &* 4 &+ UInt64(digit)
                    count += 1
                    position += 1
                    if count > 32 {
                        return nil
                    }
                }
                if count > 0 && position + mark.count <= scalars.count && Array(scalars[position ..< position + mark.count]) == mark {
                    return Int64(bitPattern: value)
                }
            }
            index += 1
        }
        return nil
    }

    /// A visual gift message as a gift action (for drawing it as a gift card); nil for any other message.
    public static func displayed(_ message: Message) -> Message? {
        guard message.media.isEmpty, !message.text.isEmpty, let id = AstraGiftMessage.giftId(in: message.text), let gift = AstraGiftMessage.gift(id: id) else {
            return nil
        }
        let isRussian = Locale.preferredLanguages.first.map { $0.hasPrefix("ru") || $0.hasPrefix("uk") || $0.hasPrefix("be") } ?? true
        // Shown on the card in place of Telegram's "add it to your profile, make it collectible": a visual gift is
        // already on the profile and has nothing to convert or upgrade.
        let note = isRussian ? "Бесплатный подарок AstraGram: он уже в профиле, его видят пользователи AstraGram" : "A free AstraGram gift: it is on the profile already, and AstraGram users see it"
        let action = TelegramMediaAction(action: .starGift(
            gift: .generic(gift),
            convertStars: nil,
            text: note,
            entities: nil,
            nameHidden: false,
            savedToProfile: true,
            converted: false,
            upgraded: false,
            canUpgrade: false,
            upgradeStars: nil,
            isRefunded: false,
            isPrepaidUpgrade: false,
            upgradeMessageId: nil,
            peerId: nil,
            senderId: nil,
            savedId: nil,
            prepaidUpgradeHash: nil,
            giftMessageId: nil,
            upgradeSeparate: false,
            isAuctionAcquired: false,
            toPeerId: nil,
            number: nil
        ))
        let _ = AstraGiftMessage.displayedIds.modify { ids in
            var ids = ids
            ids.insert(message.id)
            return ids
        }
        return message.withUpdatedText("").withUpdatedMedia([action])
    }

    private static let displayedIds = Atomic<Set<MessageId>>(value: Set())

    /// Whether a message drawn as a gift card is a visual gift message (its tap opens AstraGram's gift screen).
    public static func isDisplayedGiftMessage(_ id: MessageId) -> Bool {
        return AstraGiftMessage.displayedIds.with { $0.contains(id) }
    }

    /// Whether a message is a visual gift message (drawn as a gift card).
    public static func isGiftMessage(_ message: Message) -> Bool {
        return message.media.isEmpty && AstraGiftMessage.giftId(in: message.text) != nil
    }
}
