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

/// Known (user ID, registration time) points; the date of other IDs is interpolated between them.
private let ayuRegistrationPoints: [(Int64, Double)] = [
    (1000000, 1380326400),
    (2768409, 1383264000),
    (7679610, 1388448000),
    (11538514, 1391212000),
    (15835244, 1392940000),
    (23646077, 1393459000),
    (38015510, 1393632000),
    (44634663, 1399334000),
    (46145305, 1400198000),
    (54845238, 1411257000),
    (63263518, 1414454000),
    (101260938, 1425600000),
    (111220210, 1429574000),
    (116812045, 1437696000),
    (122600695, 1437782000),
    (124872445, 1439856000),
    (130029930, 1441324000),
    (133909606, 1444176000),
    (157242073, 1446768000),
    (171295414, 1457481000),
    (181783990, 1460246000),
    (222021233, 1465344000),
    (225034354, 1466208000),
    (278941742, 1473465000),
    (285253072, 1476835000),
    (294851037, 1479600000),
    (328594461, 1482969000),
    (369669043, 1490918000),
    (400169472, 1501459000),
    (805158066, 1563208000),
    (1974255900, 1634000000),
    (5000000000, 1640995200),
    (6000000000, 1675209600),
    (7000000000, 1709251200),
    (8000000000, 1743465600)
]

/// The approximate registration month of a user, from the ID ("≈ 03.2016").
public func ayuApproximateRegistrationDate(userId: Int64) -> String? {
    guard userId > 0, let first = ayuRegistrationPoints.first, let last = ayuRegistrationPoints.last else {
        return nil
    }
    let timestamp: Double
    if userId <= first.0 {
        timestamp = first.1
    } else if userId >= last.0 {
        timestamp = last.1
    } else {
        var value = last.1
        for i in 1 ..< ayuRegistrationPoints.count where userId <= ayuRegistrationPoints[i].0 {
            let (lowerId, lowerTime) = ayuRegistrationPoints[i - 1]
            let (upperId, upperTime) = ayuRegistrationPoints[i]
            let fraction = Double(userId - lowerId) / Double(upperId - lowerId)
            value = lowerTime + (upperTime - lowerTime) * fraction
            break
        }
        timestamp = value
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM.yyyy"
    let text = formatter.string(from: Date(timeIntervalSince1970: timestamp))
    return userId >= last.0 ? "≥ \(text)" : "≈ \(text)"
}
