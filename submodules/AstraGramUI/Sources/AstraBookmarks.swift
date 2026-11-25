import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

/// A message saved to AstraGram's local bookmarks.
public struct AstraBookmark: Codable, Equatable {
    public let peerId: Int64
    public let namespace: Int32
    public let messageId: Int32
    public let chatTitle: String
    public let text: String
    public let date: Int32
    public let savedAt: Int32

    public var engineMessageId: EngineMessage.Id {
        return EngineMessage.Id(peerId: EnginePeer.Id(self.peerId), namespace: self.namespace, id: self.messageId)
    }
}

/// Local bookmarks: messages saved on this device only (unlike Saved Messages, nothing is sent to the server).
public enum AstraBookmarks {
    private static let defaultsKey = "ayugram.bookmarks.v1"
    private static let promise = ValuePromise<[AstraBookmark]>(AstraBookmarks.load(), ignoreRepeated: true)

    /// The bookmarks (message texts and chat titles) are kept in a file of their own, not in the app's preferences: the
    /// file is left out of iPhone backups (iCloud, a computer) and is readable only after the first unlock.
    private static var fileURL: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("astragram", isDirectory: true) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory.appendingPathComponent("bookmarks.json")
    }

    private static func load() -> [AstraBookmark] {
        if let url = AstraBookmarks.fileURL, let data = try? Data(contentsOf: url) {
            return (try? JSONDecoder().decode([AstraBookmark].self, from: data)) ?? []
        }
        // Bookmarks of earlier versions, in the preferences: moved to the file once.
        guard let data = UserDefaults.standard.data(forKey: AstraBookmarks.defaultsKey) else {
            return []
        }
        let bookmarks = (try? JSONDecoder().decode([AstraBookmark].self, from: data)) ?? []
        if AstraBookmarks.write(bookmarks) {
            UserDefaults.standard.removeObject(forKey: AstraBookmarks.defaultsKey)
        }
        return bookmarks
    }

    @discardableResult
    private static func write(_ bookmarks: [AstraBookmark]) -> Bool {
        guard var url = AstraBookmarks.fileURL, let data = try? JSONEncoder().encode(bookmarks) else {
            return false
        }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private static func save(_ bookmarks: [AstraBookmark]) {
        AstraBookmarks.write(bookmarks)
        AstraBookmarks.promise.set(bookmarks)
    }

    public static var all: [AstraBookmark] {
        return AstraBookmarks.load()
    }

    public static var signal: Signal<[AstraBookmark], NoError> {
        return AstraBookmarks.promise.get()
    }

    public static func contains(_ id: EngineMessage.Id) -> Bool {
        return AstraBookmarks.load().contains(where: { $0.engineMessageId == id })
    }

    public static func add(id: EngineMessage.Id, chatTitle: String, text: String, date: Int32) {
        var bookmarks = AstraBookmarks.load().filter { $0.engineMessageId != id }
        bookmarks.insert(AstraBookmark(peerId: id.peerId.toInt64(), namespace: id.namespace, messageId: id.id, chatTitle: chatTitle, text: text, date: date, savedAt: Int32(Date().timeIntervalSince1970)), at: 0)
        AstraBookmarks.save(bookmarks)
    }

    public static func remove(id: EngineMessage.Id) {
        AstraBookmarks.save(AstraBookmarks.load().filter { $0.engineMessageId != id })
    }

    public static func replaceAll(_ bookmarks: [AstraBookmark]) {
        AstraBookmarks.save(bookmarks)
    }
}
