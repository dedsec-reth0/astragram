import Foundation
import Postbox
import SwiftSignalKit
internal import sqlcipher

/// AstraGram "Streak" (огонёк) with one person in a private chat.
///
/// The rules:
/// - A day counts when each of the two sent at least `messagesPerDay` messages that day (service messages do not count).
/// - The streak is the number of counted days in a row, up to today (or up to yesterday while today is not done yet).
/// - A missed day can be restored during the day after it, at most `restoresPerWeek` times in a calendar week
///   (Monday to Sunday). A day that is neither done nor restored by then ends the streak, and it starts over.
/// - A streak starts on the day it is turned on; earlier messages do not count.
///
/// Everything is counted on this device from the messages of the chat, so it works with someone who does not use
/// AstraGram. A restore is also sent to the chat as a message with an invisible mark, so that another AstraGram on the
/// other side counts the same restore.
public struct AstraStreakState: Equatable {
    public var count: Int
    public var todayMine: Int
    public var todayTheirs: Int
    public var todayDone: Bool
    public var restoresLeft: Int
    /// Yesterday, when it was missed and can still be restored.
    public var restorableDay: Int32?
    /// The streak a restore would save (shown while `restorableDay` is set).
    public var lostCount: Int
    public var today: Int32
    public var startDay: Int32

    public init(count: Int, todayMine: Int, todayTheirs: Int, todayDone: Bool, restoresLeft: Int, restorableDay: Int32?, lostCount: Int, today: Int32, startDay: Int32) {
        self.count = count
        self.todayMine = todayMine
        self.todayTheirs = todayTheirs
        self.todayDone = todayDone
        self.restoresLeft = restoresLeft
        self.restorableDay = restorableDay
        self.lostCount = lostCount
        self.today = today
        self.startDay = startDay
    }

    /// The number shown beside the name: the saved streak while it can be restored.
    public var displayCount: Int {
        if self.restorableDay != nil {
            return max(self.count, self.lostCount)
        }
        return self.count
    }
}

public enum AstraStreak {
    public static let messagesPerDay = 3
    public static let restoresPerWeek = 5

    /// The mark of a restore message: these invisible characters on both sides of the restored day's number, written in
    /// base 4 with four other invisible characters (none of them joins with its neighbours).
    private static let restoreMark: [Unicode.Scalar] = ["\u{2062}", "\u{2063}", "\u{2064}"]
    private static let invisibleDigits: [Unicode.Scalar] = ["\u{200B}", "\u{200C}", "\u{2060}", "\u{2061}"]

    /// The invisible characters of restore messages (to show such a text without them).
    public static let invisibleCharacters = CharacterSet(charactersIn: "\u{2062}\u{2063}\u{2064}\u{200B}\u{200C}\u{2060}\u{2061}")

    /// The number of the local calendar day of a moment.
    public static func dayNumber(_ timestamp: Int32) -> Int32 {
        let date = Date(timeIntervalSince1970: Double(timestamp))
        let offset = TimeZone.current.secondsFromGMT(for: date)
        let local = Int64(timestamp) + Int64(offset)
        return Int32(local >= 0 ? local / 86400 : (local - 86399) / 86400)
    }

    public static func today() -> Int32 {
        return AstraStreak.dayNumber(Int32(Date().timeIntervalSince1970))
    }

    /// The calendar week (Monday to Sunday) of a day; day 0 (1 January 1970) is a Thursday.
    public static func week(_ day: Int32) -> Int32 {
        let shifted = day + 3
        return shifted >= 0 ? shifted / 7 : (shifted - 6) / 7
    }

    /// The date of a day, for showing it.
    public static func date(ofDay day: Int32) -> Date {
        let utcMidday = Double(day) * 86400.0 + 43200.0
        let offset = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: utcMidday))
        return Date(timeIntervalSince1970: utcMidday - Double(offset))
    }

    // MARK: Restore messages

    public static func restoreMessageText(day: Int32, isRussian: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: isRussian ? "ru_RU" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        let dateText = formatter.string(from: AstraStreak.date(ofDay: day))
        var digits: [Unicode.Scalar] = []
        var value = max(0, Int(day))
        repeat {
            digits.insert(AstraStreak.invisibleDigits[value % 4], at: 0)
            value /= 4
        } while value > 0
        var mark = String.UnicodeScalarView()
        mark.append(contentsOf: AstraStreak.restoreMark)
        mark.append(contentsOf: digits)
        mark.append(contentsOf: AstraStreak.restoreMark)
        let markText = String(mark)
        if isRussian {
            return "🔥 Восстанавливаю наш огонёк за \(dateText)\(markText)"
        } else {
            return "🔥 Restoring our streak for \(dateText)\(markText)"
        }
    }

    /// The day a restore message restores, if the text is one.
    public static func restoredDay(in text: String) -> Int32? {
        let scalars = Array(text.unicodeScalars)
        let mark = AstraStreak.restoreMark
        guard scalars.count >= mark.count * 2 + 1 else {
            return nil
        }
        var index = 0
        while index + mark.count <= scalars.count {
            if Array(scalars[index ..< index + mark.count]) == mark {
                var position = index + mark.count
                var value: Int64 = 0
                var count = 0
                while position < scalars.count, let digit = AstraStreak.invisibleDigits.firstIndex(of: scalars[position]) {
                    value = value * 4 + Int64(digit)
                    count += 1
                    position += 1
                    if count > 16 {
                        return nil
                    }
                }
                if count > 0 && position + mark.count <= scalars.count && Array(scalars[position ..< position + mark.count]) == mark {
                    return Int32(clamping: value)
                }
            }
            index += 1
        }
        return nil
    }

    // MARK: Counting

    /// Counts the streak from the messages of the chat.
    public static func compute(postbox: Postbox, peerId: PeerId, startDay: Int32, localRestores: Set<Int32>) -> Signal<AstraStreakState, NoError> {
        return postbox.transaction { transaction -> AstraStreakState in
            let today = AstraStreak.today()
            // At most a year back: older days are not read.
            let firstDay = max(startDay, today - 370)
            let fromTimestamp = Int32(clamping: Int64(firstDay) * 86400 - 2 * 86400)
            var mine: [Int32: Int] = [:]
            var theirs: [Int32: Int] = [:]
            var restored = localRestores
            var chatRestores = Set<Int32>()
            let messages = transaction.getMessages(
                peerId: peerId,
                namespace: Namespaces.Message.Cloud,
                from: MessageIndex.upperBound(peerId: peerId, namespace: Namespaces.Message.Cloud),
                includeFrom: false,
                to: MessageIndex(id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 0), timestamp: fromTimestamp),
                limit: 30000
            )
            for message in messages {
                if message.media.contains(where: { $0 is TelegramMediaAction }) {
                    continue
                }
                if message.flags.contains(.Failed) || message.flags.contains(.Unsent) {
                    continue
                }
                // A message kept in the chat after deletion is gone for everyone else, so it must not count, or this
                // device's streak diverges from the other side's and from the bot.
                if message.astraDeletedAt != nil {
                    continue
                }
                if let day = AstraStreak.restoredDay(in: message.text) {
                    // A restore is sent the day after the missed day. A mark for any other day (an old message, a
                    // forged one, a different time zone by more than a day) does not count.
                    let sentDay = AstraStreak.dayNumber(message.timestamp)
                    if day >= sentDay - 2 && day <= sentDay - 1 {
                        chatRestores.insert(day)
                    }
                    continue
                }
                let day = AstraStreak.dayNumber(message.timestamp)
                if day < firstDay {
                    continue
                }
                if message.flags.contains(.Incoming) {
                    theirs[day, default: 0] += 1
                } else {
                    mine[day, default: 0] += 1
                }
            }
            // At most restoresPerWeek restores count in a week, whoever sent them.
            var perWeek: [Int32: Int] = [:]
            for day in restored {
                perWeek[AstraStreak.week(day), default: 0] += 1
            }
            for day in chatRestores.sorted() where !restored.contains(day) {
                let week = AstraStreak.week(day)
                if perWeek[week, default: 0] < AstraStreak.restoresPerWeek {
                    perWeek[week, default: 0] += 1
                    restored.insert(day)
                }
            }
            return AstraStreak.state(today: today, startDay: firstDay, mine: mine, theirs: theirs, restored: restored)
        }
    }

    /// The rules, on per-day counts.
    public static func state(today: Int32, startDay: Int32, mine: [Int32: Int], theirs: [Int32: Int], restored: Set<Int32>) -> AstraStreakState {
        func messagesDone(_ day: Int32) -> Bool {
            return (mine[day] ?? 0) >= AstraStreak.messagesPerDay && (theirs[day] ?? 0) >= AstraStreak.messagesPerDay
        }
        func done(_ day: Int32) -> Bool {
            return day >= startDay && (messagesDone(day) || restored.contains(day))
        }
        func chain(endingAt day: Int32) -> Int {
            var count = 0
            var current = day
            while done(current) {
                count += 1
                current -= 1
            }
            return count
        }
        let todayDone = done(today)
        let count = chain(endingAt: todayDone ? today : today - 1)
        let restoresUsed = restored.filter { AstraStreak.week($0) == AstraStreak.week(today - 1) && !messagesDone($0) }.count
        let restoresLeft = max(0, AstraStreak.restoresPerWeek - restoresUsed)
        var restorableDay: Int32?
        var lostCount = 0
        let yesterday = today - 1
        if !done(yesterday) && yesterday > startDay {
            let before = chain(endingAt: yesterday - 1)
            if before > 0 && restoresLeft > 0 {
                restorableDay = yesterday
                lostCount = before + (todayDone ? 1 : 0)
            }
        }
        return AstraStreakState(
            count: count,
            todayMine: mine[today] ?? 0,
            todayTheirs: theirs[today] ?? 0,
            todayDone: todayDone,
            restoresLeft: restoresLeft,
            restorableDay: restorableDay,
            lostCount: lostCount,
            today: today,
            startDay: startDay
        )
    }

    /// Counts the streak of an account's chat (for the app's modules, which do not use Postbox).
    public static func compute(account: Account, peerId: EnginePeer.Id, startDay: Int32, localRestores: Set<Int32>) -> Signal<AstraStreakState, NoError> {
        return AstraStreak.compute(postbox: account.postbox, peerId: peerId, startDay: startDay, localRestores: localRestores)
    }

    /// The id of the newest message of each chat; changes when a chat gets a message.
    public static func topMessageIds(account: Account, peerIds: [EnginePeer.Id]) -> Signal<[EnginePeer.Id: Int32], NoError> {
        if peerIds.isEmpty {
            return .single([:])
        }
        let key: PostboxViewKey = .topChatMessage(peerIds: peerIds)
        return account.postbox.combinedView(keys: [key])
        |> map { views -> [EnginePeer.Id: Int32] in
            var result: [EnginePeer.Id: Int32] = [:]
            if let view = views.views[key] as? TopChatMessageView {
                for (peerId, message) in view.messages {
                    result[peerId] = message.id.id
                }
            }
            return result
        }
        |> distinctUntilChanged
    }

    // MARK: The values shown in the chat list

    private static let cache = Atomic<[String: AstraStreakState]>(value: [:])
    private static let updatesPipe = ValuePipe<Void>()

    private static func cacheKey(accountPeerId: PeerId, peerId: PeerId) -> String {
        return "\(accountPeerId.toInt64()):\(peerId.toInt64())"
    }

    public static func cached(accountPeerId: PeerId, peerId: PeerId) -> AstraStreakState? {
        return AstraStreak.cache.with { $0[AstraStreak.cacheKey(accountPeerId: accountPeerId, peerId: peerId)] }
    }

    public static func setCached(accountPeerId: PeerId, peerId: PeerId, state: AstraStreakState?) {
        let key = AstraStreak.cacheKey(accountPeerId: accountPeerId, peerId: peerId)
        var changed = false
        let _ = AstraStreak.cache.modify { cache in
            var cache = cache
            if cache[key] != state {
                changed = true
                cache[key] = state
            }
            return cache
        }
        if changed {
            AstraStreak.updatesPipe.putNext(Void())
            AstraMarks.changed()
        }
    }

    /// Fires when a shown value changes.
    public static var updates: Signal<Void, NoError> {
        return AstraStreak.updatesPipe.signal()
    }
}

// MARK: - Storage

extension AstraMessageStore {
    func createStreakTables() {
        self.execute("CREATE TABLE IF NOT EXISTS streaks (peer_id INTEGER PRIMARY KEY, start_day INTEGER NOT NULL)")
        self.execute("CREATE TABLE IF NOT EXISTS streak_restores (peer_id INTEGER NOT NULL, day INTEGER NOT NULL, PRIMARY KEY(peer_id, day))")
    }

    /// The chats with a streak turned on, with the day each started; updates whenever the store changes.
    public func streaks() -> Signal<[PeerId: Int32], NoError> {
        let read: () -> Signal<[PeerId: Int32], NoError> = {
            return Signal { subscriber in
                self.queue.async {
                    var result: [PeerId: Int32] = [:]
                    if let statement = self.prepare("SELECT peer_id, start_day FROM streaks") {
                        while sqlite3_step(statement) == SQLITE_ROW {
                            result[PeerId(sqlite3_column_int64(statement, 0))] = sqlite3_column_int(statement, 1)
                        }
                        sqlite3_finalize(statement)
                    }
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        // Saving a deleted message or an edit fires changesPipe; the start days rarely change, so only re-emit (and
        // re-run the per-streak compute downstream) when they actually do.
        return (read() |> then(self.changesPipe.signal() |> mapToSignal { _ in read() }))
        |> distinctUntilChanged
    }

    /// Turns a streak on (from `startDay`) or off (nil). Turning it off forgets its restores.
    public func setStreak(peerId: PeerId, startDay: Int32?) {
        self.queue.async {
            if let startDay = startDay {
                if let statement = self.prepare("INSERT OR IGNORE INTO streaks (peer_id, start_day) VALUES (?, ?)") {
                    sqlite3_bind_int64(statement, 1, peerId.toInt64())
                    sqlite3_bind_int(statement, 2, startDay)
                    sqlite3_step(statement)
                    sqlite3_finalize(statement)
                }
            } else {
                for sql in ["DELETE FROM streaks WHERE peer_id = ?", "DELETE FROM streak_restores WHERE peer_id = ?"] {
                    if let statement = self.prepare(sql) {
                        sqlite3_bind_int64(statement, 1, peerId.toInt64())
                        sqlite3_step(statement)
                        sqlite3_finalize(statement)
                    }
                }
            }
            self.changesPipe.putNext(Void())
        }
    }

    /// Turns a streak on with exactly `startDay`, replacing the start day it already has: the account's list from the
    /// streak bot decides it, so every device counts from the same day.
    public func setStreakStartDay(peerId: PeerId, startDay: Int32) {
        self.queue.async {
            if let statement = self.prepare("INSERT INTO streaks (peer_id, start_day) VALUES (?, ?) ON CONFLICT (peer_id) DO UPDATE SET start_day = excluded.start_day") {
                sqlite3_bind_int64(statement, 1, peerId.toInt64())
                sqlite3_bind_int(statement, 2, startDay)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            self.changesPipe.putNext(Void())
        }
    }

    /// The days restored on this device (requests from the bot included).
    public func streakRestores(peerId: PeerId) -> Signal<Set<Int32>, NoError> {
        return Signal { subscriber in
            self.queue.async {
                var result = Set<Int32>()
                if let statement = self.prepare("SELECT day FROM streak_restores WHERE peer_id = ?") {
                    sqlite3_bind_int64(statement, 1, peerId.toInt64())
                    while sqlite3_step(statement) == SQLITE_ROW {
                        result.insert(sqlite3_column_int(statement, 0))
                    }
                    sqlite3_finalize(statement)
                }
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }

    public func addStreakRestore(peerId: PeerId, day: Int32) {
        self.queue.async {
            if let statement = self.prepare("INSERT OR IGNORE INTO streak_restores (peer_id, day) VALUES (?, ?)") {
                sqlite3_bind_int64(statement, 1, peerId.toInt64())
                sqlite3_bind_int(statement, 2, day)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
            self.changesPipe.putNext(Void())
        }
    }
}
