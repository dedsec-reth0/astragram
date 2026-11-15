import Foundation
import Postbox
import SwiftSignalKit

/// AstraForward: forwarding from chats that forbid it. The server refuses to forward their messages, so with "Remove copy
/// restrictions" on, such a forward is sent as a copy instead: the text with its formatting, and photos, videos and
/// files downloaded and uploaded again.
enum AstraForward {
    private static func isProtected(_ message: Message, transaction: Transaction) -> Bool {
        if message.flags.contains(.CopyProtected) {
            return true
        }
        if let group = message.peers[message.id.peerId] as? TelegramGroup, group.flags.contains(.copyProtectionEnabled) {
            return true
        }
        if let channel = message.peers[message.id.peerId] as? TelegramChannel, channel.flags.contains(.copyProtectionEnabled) {
            return true
        }
        if let cachedUserData = transaction.getPeerCachedData(peerId: message.id.peerId) as? CachedUserData, cachedUserData.flags.contains(.copyProtectionEnabled) {
            return true
        }
        return false
    }

    /// Replaces forwards of protected messages with copies.
    static func prepare(account: Account, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError> {
        guard AstraGramSettings.current.removeCopyRestrictions, messages.contains(where: { message in
            if case .forward = message {
                return true
            }
            return false
        }) else {
            return .single(messages)
        }
        return account.postbox.transaction { transaction -> [(EnqueueMessage, Message?)] in
            return messages.map { message -> (EnqueueMessage, Message?) in
                if case let .forward(source, _, _, _, _) = message, let sourceMessage = transaction.getMessage(source), AstraForward.isProtected(sourceMessage, transaction: transaction) {
                    return (message, sourceMessage)
                }
                return (message, nil)
            }
        }
        |> mapToSignal { items -> Signal<[EnqueueMessage], NoError> in
            if !items.contains(where: { $0.1 != nil }) {
                return .single(messages)
            }
            let signals = items.map { message, sourceMessage -> Signal<EnqueueMessage?, NoError> in
                guard let sourceMessage = sourceMessage, case let .forward(_, threadId, _, attributes, correlationId) = message else {
                    return .single(message)
                }
                return AstraForward.copy(account: account, original: message, message: sourceMessage, threadId: threadId, attributes: attributes, correlationId: correlationId)
            }
            return combineLatest(signals)
            |> map { values -> [EnqueueMessage] in
                return values.compactMap { $0 }
            }
        }
    }

    /// A copy of `message`, or `original` (the forward itself, which the server refuses, so the message is shown as
    /// failed) when a copy cannot be made: the photo or file could not be downloaded, or there is nothing to copy.
    private static func copy(account: Account, original: EnqueueMessage, message: Message, threadId: Int64?, attributes: [MessageAttribute], correlationId: Int64?) -> Signal<EnqueueMessage?, NoError> {
        let groupingKey = message.groupingKey

        var mediaSignal: Signal<Media?, NoError> = .single(nil)
        var requiresDownload = false
        for media in message.media {
            if media is TelegramMediaImage || media is TelegramMediaFile {
                mediaSignal = AstraForward.localCopy(account: account, message: message, media: media)
                requiresDownload = true
                break
            } else if media is TelegramMediaMap || media is TelegramMediaContact || media is TelegramMediaDice {
                mediaSignal = .single(media)
                break
            }
        }
        let mediaRequired = requiresDownload

        // "Hide captions" of the forward options: the photo or file is sent without its text.
        var hideCaptions = false
        for attribute in attributes {
            if let attribute = attribute as? ForwardOptionsMessageAttribute, attribute.hideCaptions {
                hideCaptions = true
            }
        }
        let text = (hideCaptions && mediaRequired) ? "" : message.text

        var copiedAttributes = attributes.filter { !($0 is ForwardOptionsMessageAttribute) }
        if !text.isEmpty, let entities = message.attributes.first(where: { $0 is TextEntitiesMessageAttribute }) {
            copiedAttributes.append(entities)
        }

        return mediaSignal
        |> map { media -> EnqueueMessage? in
            if media == nil && (mediaRequired || text.isEmpty) {
                return original
            }
            return .message(text: text, attributes: copiedAttributes, inlineStickers: [:], mediaReference: media.flatMap { .standalone(media: $0) }, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: [])
        }
    }

    /// Downloads `resource` of `media` in `message` (it may already be cached).
    private static func download(account: Account, message: Message, media: Media, resource: TelegramMediaResource) -> Signal<Bool, NoError> {
        let reference = AnyMediaReference.message(message: MessageReference(message), media: media).resourceReference(resource)
        let fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .other, reference: reference)
        let completed = account.postbox.mediaBox.resourceData(resource)
        |> filter { $0.complete }
        |> take(1)
        |> map { _ -> Bool in
            return true
        }
        |> timeout(15.0 * 60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(false))
        return Signal { subscriber in
            // A failed download ends at once instead of waiting for the timeout.
            let fetchDisposable = fetch.start(error: { _ in
                subscriber.putNext(false)
                subscriber.putCompletion()
            })
            let completedDisposable = completed.start(next: { value in
                subscriber.putNext(value)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                completedDisposable.dispose()
            }
        }
    }

    /// A copy of a photo or file whose data lives in a local resource, so sending it uploads it again.
    private static func localCopy(account: Account, message: Message, media: Media) -> Signal<Media?, NoError> {
        let mediaBox = account.postbox.mediaBox
        if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
            return AstraForward.download(account: account, message: message, media: image, resource: largest.resource)
            |> map { success -> Media? in
                guard success else {
                    return nil
                }
                let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
                mediaBox.copyResourceData(from: largest.resource.id, to: resource.id, synchronous: true)
                return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            }
        } else if let file = media as? TelegramMediaFile {
            return AstraForward.download(account: account, message: message, media: file, resource: file.resource)
            |> map { success -> Media? in
                guard success else {
                    return nil
                }
                let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: file.size)
                mediaBox.copyResourceData(from: file.resource.id, to: resource.id, synchronous: true)
                return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
            }
        }
        return .single(nil)
    }
}
