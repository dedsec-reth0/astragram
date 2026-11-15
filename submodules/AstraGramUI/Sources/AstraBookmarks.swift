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

    private static func load() -> [AstraBookmark] {
        guard let data = UserDefaults.standard.data(forKey: AstraBookmarks.defaultsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([AstraBookmark].self, from: data)) ?? []
    }

    private static func save(_ bookmarks: [AstraBookmark]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: AstraBookmarks.defaultsKey)
        }
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
