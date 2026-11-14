import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

/// A message saved to AyuGram's local bookmarks.
public struct AyuBookmark: Codable, Equatable {
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
public enum AyuBookmarks {
    private static let defaultsKey = "ayugram.bookmarks.v1"
    private static let promise = ValuePromise<[AyuBookmark]>(AyuBookmarks.load(), ignoreRepeated: true)

    private static func load() -> [AyuBookmark] {
        guard let data = UserDefaults.standard.data(forKey: AyuBookmarks.defaultsKey) else {
            return []
        }
        return (try? JSONDecoder().decode([AyuBookmark].self, from: data)) ?? []
    }

    private static func save(_ bookmarks: [AyuBookmark]) {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: AyuBookmarks.defaultsKey)
        }
        AyuBookmarks.promise.set(bookmarks)
    }

    public static var all: [AyuBookmark] {
        return AyuBookmarks.load()
    }

    public static var signal: Signal<[AyuBookmark], NoError> {
        return AyuBookmarks.promise.get()
    }

    public static func contains(_ id: EngineMessage.Id) -> Bool {
        return AyuBookmarks.load().contains(where: { $0.engineMessageId == id })
    }

    public static func add(id: EngineMessage.Id, chatTitle: String, text: String, date: Int32) {
        var bookmarks = AyuBookmarks.load().filter { $0.engineMessageId != id }
        bookmarks.insert(AyuBookmark(peerId: id.peerId.toInt64(), namespace: id.namespace, messageId: id.id, chatTitle: chatTitle, text: text, date: date, savedAt: Int32(Date().timeIntervalSince1970)), at: 0)
        AyuBookmarks.save(bookmarks)
    }

    public static func remove(id: EngineMessage.Id) {
        AyuBookmarks.save(AyuBookmarks.load().filter { $0.engineMessageId != id })
    }

    public static func replaceAll(_ bookmarks: [AyuBookmark]) {
        AyuBookmarks.save(bookmarks)
    }
}
