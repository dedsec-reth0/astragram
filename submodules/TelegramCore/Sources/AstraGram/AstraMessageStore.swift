import Foundation
import Postbox
import SwiftSignalKit
internal import sqlcipher

/// What kind of content a saved message had, for list rows.
public enum AstraSavedMediaKind: Int32 {
    case none = 0
    case photo = 1
    case video = 2
    case voice = 3
    case roundVideo = 4
    case sticker = 5
    case gif = 6
    case music = 7
    case file = 8
    case poll = 9
    case contact = 10
    case location = 11
    case webpage = 12
    case service = 13
    case other = 14
}

/// A message the server deleted, as AstraGram saved it.
public struct AstraDeletedMessageRecord: Equatable {
    public let rowId: Int64
    public let peerId: PeerId
    public let messageId: MessageId
    public let threadId: Int64?
    public let authorId: PeerId?
    public let authorName: String
    public let chatTitle: String
    public let timestamp: Int32
    public let deletedAt: Int32
    public let isOutgoing: Bool
    public let text: String
    public let entities: [MessageTextEntity]
    public let mediaKind: AstraSavedMediaKind
    public let fileName: String?
    public let media: [Media]

    public static func ==(lhs: AstraDeletedMessageRecord, rhs: AstraDeletedMessageRecord) -> Bool {
        return lhs.rowId == rhs.rowId && lhs.deletedAt == rhs.deletedAt
    }
}

/// One earlier version of an edited message.
public struct AstraEditedMessageVersion: Equatable {
    public let rowId: Int64
    public let messageId: MessageId
    /// When this version was current: the message date for the original, the previous edit date otherwise.
    public let versionDate: Int32
    /// When AstraGram saw the edit that replaced this version.
    public let replacedAt: Int32
    public let text: String
    public let entities: [MessageTextEntity]
    public let mediaKind: AstraSavedMediaKind
    public let media: [Media]

    public static func ==(lhs: AstraEditedMessageVersion, rhs: AstraEditedMessageVersion) -> Bool {
        return lhs.rowId == rhs.rowId
    }
}

public struct AstraMessageStoreStatistics: Equatable {
    public let deletedCount: Int
    public let editedVersionCount: Int
    public let fileSize: Int64
}

private let SQLITE_TRANSIENT_VALUE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The plain-data copy of a message taken inside a Postbox transaction and written to SQLite off the transaction.
struct AstraMessageSnapshot {
    let peerId: PeerId
    let messageId: MessageId
    let threadId: Int64?
    let authorId: PeerId?
    let authorName: String
    let chatTitle: String
    let timestamp: Int32
    let isOutgoing: Bool
    let text: String
    let entitiesData: Data?
    let mediaKind: AstraSavedMediaKind
    let fileName: String?
    let mediaData: Data?
    let editDate: Int32?

    init(message: Message) {
        self.peerId = message.id.peerId
        self.messageId = message.id
        self.threadId = message.threadId
        self.authorId = message.author?.id
        self.authorName = message.author?.debugDisplayTitle ?? ""
        self.chatTitle = message.peers[message.id.peerId]?.debugDisplayTitle ?? ""
        self.timestamp = message.timestamp
        self.isOutgoing = !message.flags.contains(.Incoming)
        self.text = message.text

        var entitiesData: Data?
        var editDate: Int32?
        for attribute in message.attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                let encoder = PostboxEncoder()
                encoder.encodeRootObject(attribute)
                entitiesData = encoder.makeData()
            } else if let attribute = attribute as? EditedMessageAttribute {
                editDate = attribute.date
            }
        }
        self.entitiesData = entitiesData
        self.editDate = editDate

        let (kind, fileName) = astraMediaKind(message.media)
        self.mediaKind = kind
        self.fileName = fileName
        if message.media.isEmpty {
            self.mediaData = nil
        } else {
            let encoder = PostboxEncoder()
            encoder.encodeGenericObjectArray(message.media.map { $0 as PostboxCoding }, forKey: "m")
            self.mediaData = encoder.makeData()
        }
    }
}

func astraMediaKind(_ media: [Media]) -> (AstraSavedMediaKind, String?) {
    for item in media {
        if item is TelegramMediaImage {
            return (.photo, nil)
        } else if let file = item as? TelegramMediaFile {
            if file.isInstantVideo {
                return (.roundVideo, nil)
            } else if file.isVoice {
                return (.voice, nil)
            } else if file.isSticker {
                return (.sticker, nil)
            } else if file.isAnimated {
                return (.gif, nil)
            } else if file.isVideo {
                return (.video, nil)
            } else if file.isMusic {
                return (.music, file.fileName)
            } else {
                return (.file, file.fileName)
            }
        } else if item is TelegramMediaPoll {
            return (.poll, nil)
        } else if item is TelegramMediaContact {
            return (.contact, nil)
        } else if item is TelegramMediaMap {
            return (.location, nil)
        } else if item is TelegramMediaAction {
            return (.service, nil)
        } else if item is TelegramMediaWebpage {
            continue
        } else {
            return (.other, nil)
        }
    }
    if media.contains(where: { $0 is TelegramMediaWebpage }) {
        return (.webpage, nil)
    }
    return (.none, nil)
}

private func decodeEntities(_ data: Data?) -> [MessageTextEntity] {
    guard let data = data, !data.isEmpty else {
        return []
    }
    let decoder = PostboxDecoder(buffer: MemoryBuffer(data: data))
    if let attribute = decoder.decodeRootObject() as? TextEntitiesMessageAttribute {
        return attribute.entities
    }
    return []
}

private func decodeMedia(_ data: Data?) -> [Media] {
    guard let data = data, !data.isEmpty else {
        return []
    }
    let decoder = PostboxDecoder(buffer: MemoryBuffer(data: data))
    return decoder.decodeObjectArrayForKey("m").compactMap { $0 as? Media }
}

/// AstraGram's local database of deleted messages and edit history.
///
/// One SQLite file per account, next to the account's Postbox (inside the app group container, so that the app and
/// the notification service extension write to the same file). Writes are asynchronous on the store's own queue;
/// callers inside a Postbox transaction only take `AstraMessageSnapshot`s.
public final class AstraMessageStore {
    private static let stores = Atomic<[String: AstraMessageStore]>(value: [:])

    static func forMediaBoxBasePath(_ mediaBoxBasePath: String) -> AstraMessageStore {
        let path = URL(fileURLWithPath: mediaBoxBasePath).deletingLastPathComponent().appendingPathComponent("ayugram.sqlite").path
        return AstraMessageStore.stores.modify { stores in
            var stores = stores
            if stores[path] == nil {
                stores[path] = AstraMessageStore(path: path)
            }
            return stores
        }[path]!
    }

    public static func forAccount(_ account: Account) -> AstraMessageStore {
        return AstraMessageStore.forMediaBoxBasePath(account.postbox.mediaBox.basePath)
    }

    private let path: String
    let queue: Queue
    private var database: OpaquePointer?
    let changesPipe = ValuePipe<Void>()

    private init(path: String) {
        self.path = path
        self.queue = Queue(name: "org.astragram.MessageStore")
        self.queue.async {
            self.open()
        }
    }

    // MARK: Encryption

    /// The key of the accounts' Postbox (key + salt, as SQLCipher's raw key). The store is encrypted with the same key
    /// as Telegram's own database, so the app and the notification service extension both can open it.
    private static let encryptionKey = Atomic<Data?>(value: nil)

    /// Called before an account's Postbox opens (the app and the notification service extension).
    public static func setEncryptionParameters(_ parameters: ValueBoxEncryptionParameters) {
        let data = parameters.key.data + parameters.salt.data
        let _ = AstraMessageStore.encryptionKey.swap(data)
    }

    private static func hexString(_ data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }

    private static func openConnection(_ path: String) -> OpaquePointer? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &database, flags, nil) != SQLITE_OK {
            if let database = database {
                sqlite3_close(database)
            }
            return nil
        }
        sqlite3_busy_timeout(database, 5000)
        return database
    }

    private static func exec(_ database: OpaquePointer, _ sql: String) -> Bool {
        return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private static func removeFiles(_ path: String) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    /// Whether the file is an old store without encryption (its schema reads without a key).
    private static func isPlaintext(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path), let database = AstraMessageStore.openConnection(path) else {
            return false
        }
        defer {
            sqlite3_close(database)
        }
        return AstraMessageStore.exec(database, "SELECT count(*) FROM sqlite_master")
    }

    /// Copies an old store into an encrypted file and puts it in its place. The caller holds the store's file lock,
    /// because the app and the notification service extension may start at the same time.
    private static func encryptPlaintextStore(_ path: String, hexKey: String) {
        guard AstraMessageStore.isPlaintext(path), let database = AstraMessageStore.openConnection(path) else {
            return
        }
        let exportPath = path + ".encrypted"
        AstraMessageStore.removeFiles(exportPath)
        let _ = AstraMessageStore.exec(database, "PRAGMA cipher_default_plaintext_header_size=32")
        var exported = AstraMessageStore.exec(database, "ATTACH DATABASE '\(exportPath)' AS encrypted KEY \"x'\(hexKey)'\"")
        if exported {
            exported = AstraMessageStore.exec(database, "SELECT sqlcipher_export('encrypted')")
            let _ = AstraMessageStore.exec(database, "DETACH DATABASE encrypted")
        }
        sqlite3_close(database)
        if exported {
            // The encrypted copy replaces the old file in one rename: deleting first left a moment without a file, in
            // which another opener created an empty store, the move then failed and every saved message was lost.
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
            if Darwin.rename(exportPath, path) == 0 {
                Logger.shared.log("AstraGram", "encrypted the message store")
            } else {
                // The plaintext store stays in place and the export is kept; the next launch tries again.
                Logger.shared.log("AstraGram", "could not replace the message store: errno \(errno)")
            }
        } else {
            AstraMessageStore.removeFiles(exportPath)
            Logger.shared.log("AstraGram", "could not encrypt the message store")
        }
    }

    private func open(attempt: Int = 0) {
        guard let key = AstraMessageStore.encryptionKey.with({ $0 }) else {
            // The key comes with the account's Postbox; the store is not opened without it.
            if attempt < 60 {
                self.queue.after(1.0, {
                    self.open(attempt: attempt + 1)
                })
            } else {
                Logger.shared.log("AstraGram", "no key for the message store")
            }
            return
        }
        let hexKey = AstraMessageStore.hexString(key)
        // One lock over the whole check, migration and open: the app and the notification service extension both open
        // the store, and an opener running during another's migration would otherwise create an empty file in its place.
        // It is taken here only, since a second flock on another descriptor in the same process would wait for itself.
        let lockFd = Darwin.open(self.path + ".lock", O_CREAT | O_RDWR, 0o600)
        if lockFd >= 0 {
            flock(lockFd, LOCK_EX)
        }
        defer {
            if lockFd >= 0 {
                flock(lockFd, LOCK_UN)
                Darwin.close(lockFd)
            }
        }
        if AstraMessageStore.isPlaintext(self.path) {
            AstraMessageStore.encryptPlaintextStore(self.path, hexKey: hexKey)
        }
        var opened: OpaquePointer?
        for _ in 0 ..< 2 {
            guard let database = AstraMessageStore.openConnection(self.path) else {
                break
            }
            let _ = AstraMessageStore.exec(database, "PRAGMA cipher_plaintext_header_size=32")
            let _ = AstraMessageStore.exec(database, "PRAGMA cipher_default_plaintext_header_size=32")
            let _ = AstraMessageStore.exec(database, "PRAGMA key=\"x'\(hexKey)'\"")
            if AstraMessageStore.exec(database, "SELECT count(*) FROM sqlite_master") {
                opened = database
                break
            }
            let code = sqlite3_extended_errcode(database) & 0xff
            sqlite3_close(database)
            guard code == SQLITE_NOTADB || code == SQLITE_CORRUPT else {
                // Busy (the extension has it open) or not readable yet: the saved messages are kept and it is tried again.
                Logger.shared.log("AstraGram", "the message store did not open (\(code)), trying again")
                if attempt < 60 {
                    self.queue.after(5.0, {
                        self.open(attempt: attempt + 1)
                    })
                }
                return
            }
            // Unreadable with the key (damaged): it is started anew rather than left broken.
            Logger.shared.log("AstraGram", "the message store is unreadable, starting anew")
            AstraMessageStore.removeFiles(self.path)
        }
        guard let database = opened else {
            Logger.shared.log("AstraGram", "could not open \(self.path)")
            return
        }
        self.database = database
        self.execute("PRAGMA journal_mode=WAL")
        self.execute("PRAGMA synchronous=NORMAL")
        self.execute("""
            CREATE TABLE IF NOT EXISTS deleted_messages (
                row_id INTEGER PRIMARY KEY AUTOINCREMENT,
                peer_id INTEGER NOT NULL,
                namespace INTEGER NOT NULL,
                message_id INTEGER NOT NULL,
                thread_id INTEGER,
                author_id INTEGER,
                author_name TEXT NOT NULL,
                chat_title TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                deleted_at INTEGER NOT NULL,
                is_outgoing INTEGER NOT NULL,
                text TEXT NOT NULL,
                entities BLOB,
                media_kind INTEGER NOT NULL,
                file_name TEXT,
                media BLOB,
                UNIQUE(peer_id, namespace, message_id)
            )
            """)
        self.execute("CREATE INDEX IF NOT EXISTS deleted_messages_peer ON deleted_messages(peer_id, deleted_at)")
        self.execute("""
            CREATE TABLE IF NOT EXISTS edit_history (
                row_id INTEGER PRIMARY KEY AUTOINCREMENT,
                peer_id INTEGER NOT NULL,
                namespace INTEGER NOT NULL,
                message_id INTEGER NOT NULL,
                version_date INTEGER NOT NULL,
                replaced_at INTEGER NOT NULL,
                text TEXT NOT NULL,
                entities BLOB,
                media_kind INTEGER NOT NULL,
                media BLOB
            )
            """)
        self.execute("CREATE INDEX IF NOT EXISTS edit_history_message ON edit_history(peer_id, namespace, message_id)")
        self.createStreakTables()
    }

    func execute(_ sql: String) {
        guard let database = self.database else {
            return
        }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &error) != SQLITE_OK {
            if let error = error {
                Logger.shared.log("AstraGram", "sqlite error: \(String(cString: error))")
                sqlite3_free(error)
            }
        }
    }

    func prepare(_ sql: String) -> OpaquePointer? {
        guard let database = self.database else {
            return nil
        }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK {
            Logger.shared.log("AstraGram", "sqlite prepare error: \(String(cString: sqlite3_errmsg(database)))")
            return nil
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT_VALUE)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Data?) {
        if let value = value, !value.isEmpty {
            value.withUnsafeBytes { bytes in
                _ = sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT_VALUE)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int64?) {
        if let value = value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func columnData(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        let count = sqlite3_column_bytes(statement, index)
        guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        return Data(bytes: bytes, count: Int(count))
    }

    private func columnOptionalInt64(_ statement: OpaquePointer, _ index: Int32) -> Int64? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL {
            return nil
        }
        return sqlite3_column_int64(statement, index)
    }

    // MARK: Writing

    func saveDeleted(_ snapshots: [AstraMessageSnapshot], deletedAt: Int32) {
        if snapshots.isEmpty {
            return
        }
        self.queue.async {
            guard let statement = self.prepare("""
                INSERT OR REPLACE INTO deleted_messages
                (peer_id, namespace, message_id, thread_id, author_id, author_name, chat_title, timestamp, deleted_at, is_outgoing, text, entities, media_kind, file_name, media)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """) else {
                return
            }
            defer {
                sqlite3_finalize(statement)
            }
            self.execute("BEGIN")
            for snapshot in snapshots {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, snapshot.peerId.toInt64())
                sqlite3_bind_int(statement, 2, snapshot.messageId.namespace)
                sqlite3_bind_int(statement, 3, snapshot.messageId.id)
                self.bind(statement, 4, snapshot.threadId)
                self.bind(statement, 5, snapshot.authorId?.toInt64())
                self.bind(statement, 6, snapshot.authorName)
                self.bind(statement, 7, snapshot.chatTitle)
                sqlite3_bind_int(statement, 8, snapshot.timestamp)
                sqlite3_bind_int(statement, 9, deletedAt)
                sqlite3_bind_int(statement, 10, snapshot.isOutgoing ? 1 : 0)
                self.bind(statement, 11, snapshot.text)
                self.bind(statement, 12, snapshot.entitiesData)
                sqlite3_bind_int(statement, 13, snapshot.mediaKind.rawValue)
                self.bind(statement, 14, snapshot.fileName)
                self.bind(statement, 15, snapshot.mediaData)
                if sqlite3_step(statement) != SQLITE_DONE, let database = self.database {
                    Logger.shared.log("AstraGram", "sqlite insert error: \(String(cString: sqlite3_errmsg(database)))")
                }
            }
            self.execute("COMMIT")
            self.changesPipe.putNext(Void())
        }
    }

    func saveEdit(previous: AstraMessageSnapshot, replacedAt: Int32) {
        self.queue.async {
            guard let statement = self.prepare("""
                INSERT INTO edit_history (peer_id, namespace, message_id, version_date, replaced_at, text, entities, media_kind, media)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """) else {
                return
            }
            defer {
                sqlite3_finalize(statement)
            }
            sqlite3_bind_int64(statement, 1, previous.peerId.toInt64())
            sqlite3_bind_int(statement, 2, previous.messageId.namespace)
            sqlite3_bind_int(statement, 3, previous.messageId.id)
            sqlite3_bind_int(statement, 4, previous.editDate ?? previous.timestamp)
            sqlite3_bind_int(statement, 5, replacedAt)
            self.bind(statement, 6, previous.text)
            self.bind(statement, 7, previous.entitiesData)
            sqlite3_bind_int(statement, 8, previous.mediaKind.rawValue)
            self.bind(statement, 9, previous.mediaData)
            if sqlite3_step(statement) != SQLITE_DONE, let database = self.database {
                Logger.shared.log("AstraGram", "sqlite insert error: \(String(cString: sqlite3_errmsg(database)))")
            }
            // At most `maxEditVersions` versions a message: someone who keeps editing one message must not grow this
            // store without end. The oldest go (the first version, as sent, is kept).
            if let trim = self.prepare("""
                DELETE FROM edit_history WHERE peer_id = ?1 AND namespace = ?2 AND message_id = ?3
                  AND row_id != (SELECT MIN(row_id) FROM edit_history WHERE peer_id = ?1 AND namespace = ?2 AND message_id = ?3)
                  AND row_id NOT IN (SELECT row_id FROM edit_history WHERE peer_id = ?1 AND namespace = ?2 AND message_id = ?3 ORDER BY row_id DESC LIMIT ?4)
                """) {
                sqlite3_bind_int64(trim, 1, previous.peerId.toInt64())
                sqlite3_bind_int(trim, 2, previous.messageId.namespace)
                sqlite3_bind_int(trim, 3, previous.messageId.id)
                sqlite3_bind_int(trim, 4, AstraMessageStore.maxEditVersions - 1)
                let _ = sqlite3_step(trim)
                sqlite3_finalize(trim)
            }
            self.changesPipe.putNext(Void())
        }
    }

    static let maxEditVersions: Int32 = 50

    // MARK: Reading

    private func readDeleted(where condition: String, bindings: (OpaquePointer) -> Void, limit: Int) -> [AstraDeletedMessageRecord] {
        guard let statement = self.prepare("""
            SELECT row_id, peer_id, namespace, message_id, thread_id, author_id, author_name, chat_title, timestamp, deleted_at, is_outgoing, text, entities, media_kind, file_name, media
            FROM deleted_messages \(condition) ORDER BY deleted_at DESC, row_id DESC LIMIT \(limit)
            """) else {
            return []
        }
        defer {
            sqlite3_finalize(statement)
        }
        bindings(statement)
        var result: [AstraDeletedMessageRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let peerId = PeerId(sqlite3_column_int64(statement, 1))
            let messageId = MessageId(peerId: peerId, namespace: sqlite3_column_int(statement, 2), id: sqlite3_column_int(statement, 3))
            result.append(AstraDeletedMessageRecord(
                rowId: sqlite3_column_int64(statement, 0),
                peerId: peerId,
                messageId: messageId,
                threadId: self.columnOptionalInt64(statement, 4),
                authorId: self.columnOptionalInt64(statement, 5).flatMap { PeerId($0) },
                authorName: self.columnString(statement, 6) ?? "",
                chatTitle: self.columnString(statement, 7) ?? "",
                timestamp: sqlite3_column_int(statement, 8),
                deletedAt: sqlite3_column_int(statement, 9),
                isOutgoing: sqlite3_column_int(statement, 10) != 0,
                text: self.columnString(statement, 11) ?? "",
                entities: decodeEntities(self.columnData(statement, 12)),
                mediaKind: AstraSavedMediaKind(rawValue: sqlite3_column_int(statement, 13)) ?? .other,
                fileName: self.columnString(statement, 14),
                media: decodeMedia(self.columnData(statement, 15))
            ))
        }
        return result
    }

    /// Deleted messages, newest deletion first, optionally of one chat; updates whenever the store changes.
    public func deletedMessages(peerId: PeerId? = nil, limit: Int = 500) -> Signal<[AstraDeletedMessageRecord], NoError> {
        let read: () -> Signal<[AstraDeletedMessageRecord], NoError> = {
            return Signal { subscriber in
                self.queue.async {
                    let result: [AstraDeletedMessageRecord]
                    if let peerId = peerId {
                        result = self.readDeleted(where: "WHERE peer_id = ?", bindings: { statement in
                            sqlite3_bind_int64(statement, 1, peerId.toInt64())
                        }, limit: limit)
                    } else {
                        result = self.readDeleted(where: "", bindings: { _ in }, limit: limit)
                    }
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        return (read() |> then(self.changesPipe.signal() |> mapToSignal { _ in read() }))
    }

    /// The chats that have deleted messages saved, with their count and the time of the last deletion.
    public func chatsWithDeletedMessages() -> Signal<[(peerId: PeerId, title: String, count: Int, lastDeletedAt: Int32)], NoError> {
        let read: () -> Signal<[(peerId: PeerId, title: String, count: Int, lastDeletedAt: Int32)], NoError> = {
            return Signal { subscriber in
                self.queue.async {
                    var result: [(peerId: PeerId, title: String, count: Int, lastDeletedAt: Int32)] = []
                    if let statement = self.prepare("SELECT d.peer_id, (SELECT chat_title FROM deleted_messages d2 WHERE d2.peer_id = d.peer_id ORDER BY d2.deleted_at DESC, d2.row_id DESC LIMIT 1), COUNT(*), MAX(d.deleted_at) FROM deleted_messages d GROUP BY d.peer_id ORDER BY MAX(d.deleted_at) DESC") {
                        while sqlite3_step(statement) == SQLITE_ROW {
                            result.append((
                                peerId: PeerId(sqlite3_column_int64(statement, 0)),
                                title: self.columnString(statement, 1) ?? "",
                                count: Int(sqlite3_column_int64(statement, 2)),
                                lastDeletedAt: sqlite3_column_int(statement, 3)
                            ))
                        }
                        sqlite3_finalize(statement)
                    }
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        return (read() |> then(self.changesPipe.signal() |> mapToSignal { _ in read() }))
    }

    /// Earlier versions of a message, oldest first; updates whenever the store changes.
    public func editHistory(messageId: MessageId) -> Signal<[AstraEditedMessageVersion], NoError> {
        let read: () -> Signal<[AstraEditedMessageVersion], NoError> = {
            return Signal { subscriber in
                self.queue.async {
                    var result: [AstraEditedMessageVersion] = []
                    if let statement = self.prepare("SELECT row_id, version_date, replaced_at, text, entities, media_kind, media FROM edit_history WHERE peer_id = ? AND namespace = ? AND message_id = ? ORDER BY row_id ASC") {
                        sqlite3_bind_int64(statement, 1, messageId.peerId.toInt64())
                        sqlite3_bind_int(statement, 2, messageId.namespace)
                        sqlite3_bind_int(statement, 3, messageId.id)
                        while sqlite3_step(statement) == SQLITE_ROW {
                            result.append(AstraEditedMessageVersion(
                                rowId: sqlite3_column_int64(statement, 0),
                                messageId: messageId,
                                versionDate: sqlite3_column_int(statement, 1),
                                replacedAt: sqlite3_column_int(statement, 2),
                                text: self.columnString(statement, 3) ?? "",
                                entities: decodeEntities(self.columnData(statement, 4)),
                                mediaKind: AstraSavedMediaKind(rawValue: sqlite3_column_int(statement, 5)) ?? .other,
                                media: decodeMedia(self.columnData(statement, 6))
                            ))
                        }
                        sqlite3_finalize(statement)
                    }
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        return (read() |> then(self.changesPipe.signal() |> mapToSignal { _ in read() }))
    }

    public func statistics() -> Signal<AstraMessageStoreStatistics, NoError> {
        let read: () -> Signal<AstraMessageStoreStatistics, NoError> = {
            return Signal { subscriber in
                self.queue.async {
                    var deletedCount = 0
                    var editedCount = 0
                    if let statement = self.prepare("SELECT (SELECT COUNT(*) FROM deleted_messages), (SELECT COUNT(*) FROM edit_history)") {
                        if sqlite3_step(statement) == SQLITE_ROW {
                            deletedCount = Int(sqlite3_column_int64(statement, 0))
                            editedCount = Int(sqlite3_column_int64(statement, 1))
                        }
                        sqlite3_finalize(statement)
                    }
                    var fileSize: Int64 = 0
                    for suffix in ["", "-wal", "-shm"] {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: self.path + suffix), let size = attributes[.size] as? NSNumber {
                            fileSize += size.int64Value
                        }
                    }
                    subscriber.putNext(AstraMessageStoreStatistics(deletedCount: deletedCount, editedVersionCount: editedCount, fileSize: fileSize))
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        return (read() |> then(self.changesPipe.signal() |> mapToSignal { _ in read() }))
    }

    // MARK: Clearing

    public func removeDeletedMessage(rowId: Int64) {
        self.queue.async {
            if let statement = self.prepare("DELETE FROM deleted_messages WHERE row_id = ?") {
                sqlite3_bind_int64(statement, 1, rowId)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            self.changesPipe.putNext(Void())
        }
    }

    public func clearDeletedMessages(peerId: PeerId? = nil) {
        self.queue.async {
            if let peerId = peerId {
                if let statement = self.prepare("DELETE FROM deleted_messages WHERE peer_id = ?") {
                    sqlite3_bind_int64(statement, 1, peerId.toInt64())
                    sqlite3_step(statement)
                    sqlite3_finalize(statement)
                }
            } else {
                self.execute("DELETE FROM deleted_messages")
            }
            self.changesPipe.putNext(Void())
        }
    }

    public func clearAll() {
        self.queue.async {
            self.execute("DELETE FROM deleted_messages")
            self.execute("DELETE FROM edit_history")
            self.execute("VACUUM")
            self.changesPipe.putNext(Void())
        }
    }
}
