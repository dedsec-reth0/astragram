import Foundation
import Postbox
import SwiftSignalKit

/// Compiled message filters: plain entries match case-insensitively as substrings, `/pattern/` entries as regular
/// expressions.
public final class AstraMessageFilterMatcher {
    private let words: [String]
    private let expressions: [NSRegularExpression]

    public var isEmpty: Bool {
        return self.words.isEmpty && self.expressions.isEmpty
    }

    public init(filters: [String]) {
        var words: [String] = []
        var expressions: [NSRegularExpression] = []
        for filter in filters {
            let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.count >= 2 && trimmed.hasPrefix("/") && trimmed.hasSuffix("/") {
                if let expression = try? NSRegularExpression(pattern: String(trimmed.dropFirst().dropLast()), options: [.caseInsensitive]) {
                    expressions.append(expression)
                }
            } else {
                words.append(trimmed.lowercased())
            }
        }
        self.words = words
        self.expressions = expressions
    }

    public func matches(_ text: String) -> Bool {
        if text.isEmpty {
            return false
        }
        let lowercased = text.lowercased()
        for word in self.words {
            if lowercased.contains(word) {
                return true
            }
        }
        let range = NSRange(text.startIndex..., in: text)
        for expression in self.expressions {
            if expression.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// Whether a filter entry is valid (a `/pattern/` entry must be a valid regular expression).
    public static func isValid(_ filter: String) -> Bool {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return false
        }
        if trimmed.count >= 2 && trimmed.hasPrefix("/") && trimmed.hasSuffix("/") {
            return (try? NSRegularExpression(pattern: String(trimmed.dropFirst().dropLast()), options: [.caseInsensitive])) != nil
        }
        return true
    }
}

public extension AstraGramSettings {
    private static let matcherCache = Atomic<(filters: [String], matcher: AstraMessageFilterMatcher)?>(value: nil)

    /// The matcher for the current filters, or nil when filtering is off. Safe to call from any queue.
    static func currentMessageFilterMatcher() -> AstraMessageFilterMatcher? {
        let settings = AstraGramSettings.current
        guard settings.messageFiltersEnabled, !settings.messageFilters.isEmpty else {
            return nil
        }
        if let cached = AstraGramSettings.matcherCache.with({ $0 }), cached.filters == settings.messageFilters {
            return cached.matcher.isEmpty ? nil : cached.matcher
        }
        let matcher = AstraMessageFilterMatcher(filters: settings.messageFilters)
        let _ = AstraGramSettings.matcherCache.swap((filters: settings.messageFilters, matcher: matcher))
        return matcher.isEmpty ? nil : matcher
    }

    /// Whether AstraGram's message filters hide `message` from chat histories. Your own messages are never hidden.
    static func shouldHideMessage(_ message: Message) -> Bool {
        if AstraHiddenMessages.contains(message.id) {
            return true
        }
        if !message.flags.contains(.Incoming) {
            return false
        }
        // Messages of blocked users, except in the private chat with them.
        if AstraGramSettings.current.hideBlockedUsersMessages, let authorId = message.author?.id, authorId != message.id.peerId, AstraBlockedPeers.isBlocked(authorId) {
            return true
        }
        // Stickers and GIFs of other people ("Hide stickers" / "Hide GIFs").
        let settings = AstraGramSettings.current
        if settings.hideStickersFromOthers || settings.hideGifsFromOthers {
            for media in message.media {
                if let file = media as? TelegramMediaFile {
                    if settings.hideStickersFromOthers && file.isSticker {
                        return true
                    }
                    if settings.hideGifsFromOthers && file.isAnimated && !file.isSticker {
                        return true
                    }
                }
            }
        }
        if AstraPluginHooks.shouldHide(message) {
            return true
        }
        if let matcher = AstraGramSettings.currentMessageFilterMatcher() {
            return matcher.matches(message.text)
        }
        return false
    }
}
