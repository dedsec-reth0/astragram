import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import Photos
import DeviceAccess
import AccountContext

/// AstraGram: what became of saving self-destructing or view-once media to the device.
public enum AstraSaveOriginalResult {
    case photo
    case video
    /// Neither a photo nor a video (a voice message): a copy of the file to hand to the share sheet.
    case file(URL)
    /// No access to Photos. The request for access has already told the user.
    case accessDenied
    /// The media is gone from the server and is not complete on this device, or Photos did not take it.
    case failed
}

public struct AstraSaveOriginalStrings {
    public let isRussian: Bool

    public init(isRussian: Bool) {
        self.isRussian = isRussian
    }

    public var title: String {
        return self.isRussian ? "Сохранить оригинал" : "Save Original"
    }

    public var saving: String {
        return self.isRussian ? "Сохраняю оригинал…" : "Saving the original…"
    }

    /// The notice for `result`; none when the result speaks for itself.
    public func text(for result: AstraSaveOriginalResult) -> String? {
        switch result {
        case .photo:
            return self.isRussian ? "Фото сохранено в исходном качестве" : "Photo saved in its original quality"
        case .video:
            return self.isRussian ? "Видео сохранено в исходном качестве" : "Video saved in its original quality"
        case .failed:
            return self.isRussian ? "Не удалось сохранить: медиа больше недоступно" : "Could not save: the media is no longer available"
        case .file, .accessDenied:
            return nil
        }
    }
}

private enum AstraSaveOriginalKind {
    case photo
    case video
    case file
}

/// AstraGram: saves media exactly as Telegram delivered it, with no re-encoding: the largest version of a photo, the
/// file of a video. A photo or a video goes to Photos; anything else is copied to a temporary file for the share sheet.
///
/// Downloading the media is not what tells the sender it was opened (that is a separate request), so saving media
/// that has not been opened yet does not mark it as viewed.
public func astraSaveOriginal(context: AccountContext, userLocation: MediaResourceUserLocation, mediaReference: AnyMediaReference) -> Signal<AstraSaveOriginalResult, NoError> {
    var maybeResource: TelegramMediaResource?
    var kind: AstraSaveOriginalKind = .photo
    var fileName = "photo.jpg"
    var userContentType: MediaResourceUserContentType = .image
    if let image = mediaReference.media as? TelegramMediaImage {
        maybeResource = largestImageRepresentation(image.representations)?.resource
    } else if let file = mediaReference.media as? TelegramMediaFile {
        maybeResource = file.resource
        userContentType = MediaResourceUserContentType(file: file)
        let isVideo = file.isVideo || file.mimeType.hasPrefix("video/")
        kind = isVideo ? .video : .file
        if let name = file.fileName, !(name as NSString).pathExtension.isEmpty {
            fileName = (name as NSString).lastPathComponent
        } else if isVideo {
            fileName = "video.mp4"
        } else if file.isVoice {
            fileName = "voice.ogg"
        } else {
            fileName = "audio.mp3"
        }
    }
    guard let resource = maybeResource else {
        return .single(.failed)
    }
    let savedKind = kind
    let savedFileName = fileName

    let completePath: Signal<String?, NoError> = Signal { subscriber in
        let fetched = context.engine.resources.fetch(
            reference: mediaReference.resourceReference(resource),
            userLocation: userLocation,
            userContentType: userContentType
        ).start(error: { _ in
            subscriber.putNext(nil)
            subscriber.putCompletion()
        })
        let data = (context.engine.resources.data(resource: EngineMediaResource(resource))
        |> filter { data -> Bool in
            return data.isComplete
        }
        |> take(1)).start(next: { data in
            subscriber.putNext(data.path)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetched.dispose()
            data.dispose()
        }
    }

    return completePath
    |> timeout(10.0 * 60.0, queue: Queue.mainQueue(), alternate: .single(nil))
    |> take(1)
    |> deliverOnMainQueue
    |> mapToSignal { path -> Signal<AstraSaveOriginalResult, NoError> in
        guard let path = path else {
            return .single(.failed)
        }
        if case .file = savedKind {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(savedFileName)
            let _ = try? FileManager.default.removeItem(at: url)
            do {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: url)
            } catch {
                return .single(.failed)
            }
            return .single(.file(url))
        }
        return Signal { subscriber in
            DeviceAccess.authorizeAccess(to: .mediaLibrary(.save), presentationData: context.sharedContext.currentPresentationData.with { $0 }, present: { c, a in
                context.sharedContext.presentGlobalController(c, a)
            }, openSettings: context.sharedContext.applicationBindings.openSettings, { authorized in
                if !authorized {
                    subscriber.putNext(.accessDenied)
                    subscriber.putCompletion()
                    return
                }
                if case .photo = savedKind {
                    guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                        subscriber.putNext(.failed)
                        subscriber.putCompletion()
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: imageData, options: nil)
                    }, completionHandler: { success, _ in
                        subscriber.putNext(success ? .photo : .failed)
                        subscriber.putCompletion()
                    })
                } else {
                    // Photos tells a video by the extension of its file, which the stored media has none of.
                    let tempVideoPath = NSTemporaryDirectory() + "\(Int64.random(in: 0 ... Int64.max)).mp4"
                    guard let _ = try? FileManager.default.copyItem(atPath: path, toPath: tempVideoPath) else {
                        subscriber.putNext(.failed)
                        subscriber.putCompletion()
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        let _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: tempVideoPath))
                    }, completionHandler: { success, _ in
                        let _ = try? FileManager.default.removeItem(atPath: tempVideoPath)
                        subscriber.putNext(success ? .video : .failed)
                        subscriber.putCompletion()
                    })
                }
            })
            return EmptyDisposable
        }
    }
}
