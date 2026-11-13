import Foundation
import Postbox
import TelegramCore
import TelegramPresentationData

/// The ID of a peer in the form the Bot API and other clients show it.
public func ayuBotApiId(_ peerId: PeerId) -> Int64 {
    let rawId = peerId.id._internalGetInt64Value()
    if peerId.namespace == Namespaces.Peer.CloudChannel {
        return -(1000000000000 + rawId)
    } else if peerId.namespace == Namespaces.Peer.CloudGroup {
        return -rawId
    } else {
        return rawId
    }
}

/// The ID of the user who created a sticker or emoji pack, derived from the pack ID the way AyuGram does it.
public func ayuStickerPackOwnerId(_ packId: Int64) -> Int64 {
    var ownerId = packId >> 32
    if (packId >> 16) & 0xff == 0x3f {
        ownerId |= 0x80000000
    }
    if (packId >> 24) & 0xff != 0 {
        ownerId += 0x100000000
    }
    return ownerId
}

private func ayuFormatDate(_ timestamp: Int32) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))
}

private func ayuFormatSize(_ size: Int64) -> String {
    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}

/// The text of "Message details" in the message menu.
public func ayuMessageDetailsText(message: Message, strings: PresentationStrings) -> String {
    let ayuStrings = AyuStrings(strings)
    var lines: [String] = []
    lines.append("\(ayuStrings.detailsMessageId): \(message.id.id)")
    lines.append("\(ayuStrings.detailsChatId): \(ayuBotApiId(message.id.peerId))")
    if let author = message.author {
        lines.append("\(ayuStrings.detailsAuthorId): \(ayuBotApiId(author.id))")
    }
    lines.append("\(ayuStrings.detailsDate): \(ayuFormatDate(message.timestamp))")
    for attribute in message.attributes {
        if let attribute = attribute as? EditedMessageAttribute {
            lines.append("\(ayuStrings.detailsEdited): \(ayuFormatDate(attribute.date))")
        } else if let attribute = attribute as? ViewCountMessageAttribute {
            lines.append("\(ayuStrings.detailsViews): \(attribute.count)")
        } else if let attribute = attribute as? ForwardCountMessageAttribute {
            lines.append("\(ayuStrings.detailsForwards): \(attribute.count)")
        }
    }
    if let forwardInfo = message.forwardInfo {
        if let author = forwardInfo.author {
            lines.append("\(ayuStrings.detailsForwardedFrom): \(ayuBotApiId(author.id))")
        } else if let authorSignature = forwardInfo.authorSignature {
            lines.append("\(ayuStrings.detailsForwardedFrom): \(authorSignature)")
        }
        lines.append("\(ayuStrings.detailsOriginalDate): \(ayuFormatDate(forwardInfo.date))")
    }
    for media in message.media {
        if let file = media as? TelegramMediaFile {
            if let fileName = file.fileName {
                lines.append("\(ayuStrings.detailsFile): \(fileName)")
            }
            lines.append("MIME: \(file.mimeType)")
            if let size = file.size {
                lines.append("\(ayuStrings.detailsSize): \(ayuFormatSize(size))")
            }
            if let resource = file.resource as? CloudDocumentMediaResource {
                lines.append("DC: \(resource.datacenterId)")
            }
            for attribute in file.attributes {
                if case let .Sticker(displayText, packReference, _) = attribute {
                    if !displayText.isEmpty {
                        lines.append("Emoji: \(displayText)")
                    }
                    switch packReference {
                    case let .id(id, _):
                        lines.append("\(ayuStrings.detailsPackId): \(id)")
                        lines.append("\(ayuStrings.detailsPackOwner): \(ayuStickerPackOwnerId(id))")
                    case let .name(name):
                        lines.append("\(ayuStrings.detailsPack): t.me/addstickers/\(name)")
                    default:
                        break
                    }
                }
            }
        } else if let image = media as? TelegramMediaImage, let largest = image.representations.last {
            lines.append("\(ayuStrings.detailsPhoto): \(Int(largest.dimensions.width))×\(Int(largest.dimensions.height))")
        }
    }
    return lines.joined(separator: "\n")
}
