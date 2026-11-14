import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext

/// Downloads `resource` of `media` in `message` (it may already be cached) and returns the path of its data.
public func ayuDownloadResource(context: AccountContext, message: Message, media: Media, resource: TelegramMediaResource) -> Signal<String?, NoError> {
    let mediaBox = context.account.postbox.mediaBox
    let reference = AnyMediaReference.message(message: MessageReference(message), media: media).resourceReference(resource)
    let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(message.id.peerId), userContentType: .other, reference: reference)
    let completed = mediaBox.resourceData(resource)
    |> filter { $0.complete }
    |> take(1)
    |> map { data -> String? in
        return data.path
    }
    |> timeout(5.0 * 60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    return Signal { subscriber in
        let fetchDisposable = fetch.start()
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

private func ayuAuthorName(_ message: Message, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder) -> String {
    if !message.flags.contains(.Incoming) {
        return AyuStrings(strings).you
    }
    if let author = message.author {
        return EnginePeer(author).displayTitle(strings: strings, displayOrder: nameDisplayOrder)
    }
    if let peer = message.peers[message.id.peerId] {
        return EnginePeer(peer).displayTitle(strings: strings, displayOrder: nameDisplayOrder)
    }
    return "?"
}

private func ayuMediaLabel(_ message: Message) -> String? {
    for media in message.media {
        if media is TelegramMediaImage {
            return "[photo]"
        } else if let file = media as? TelegramMediaFile {
            if file.isVoice {
                return "[voice]"
            } else if file.isInstantVideo {
                return "[video message]"
            } else if file.isSticker {
                return "[sticker]"
            } else if file.isVideo {
                return "[video]"
            } else {
                return "[file]"
            }
        } else if media is TelegramMediaPoll {
            return "[poll]"
        } else if media is TelegramMediaMap {
            return "[location]"
        }
    }
    return nil
}

/// A chat as plain text, "[date] Name: text" per line (chat export and AI summaries).
public func ayuChatTranscript(messages: [Message], strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    var lines: [String] = []
    for message in messages {
        var text = message.text
        if let label = ayuMediaLabel(message) {
            text = text.isEmpty ? label : label + " " + text
        }
        if text.isEmpty {
            continue
        }
        let date = formatter.string(from: Date(timeIntervalSince1970: Double(message.timestamp)))
        lines.append("[\(date)] \(ayuAuthorName(message, strings: strings, nameDisplayOrder: nameDisplayOrder)): \(text)")
    }
    return lines.joined(separator: "\n")
}

/// Chat statistics over `messages`: totals, per author, media and active hours.
public func ayuChatStatistics(messages: [Message], strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder) -> String {
    let isRussian = AyuStrings(strings).isRussian
    var perAuthor: [String: Int] = [:]
    var perHour = [Int](repeating: 0, count: 24)
    var mediaCount = 0
    var characters = 0
    let calendar = Calendar.current
    for message in messages {
        perAuthor[ayuAuthorName(message, strings: strings, nameDisplayOrder: nameDisplayOrder), default: 0] += 1
        if ayuMediaLabel(message) != nil {
            mediaCount += 1
        }
        characters += message.text.count
        let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: Double(message.timestamp)))
        perHour[hour] += 1
    }
    var lines: [String] = []
    lines.append((isRussian ? "Сообщений: " : "Messages: ") + "\(messages.count)")
    if let first = messages.first, let last = messages.last {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        lines.append((isRussian ? "Период: " : "Period: ") + formatter.string(from: Date(timeIntervalSince1970: Double(first.timestamp))) + " — " + formatter.string(from: Date(timeIntervalSince1970: Double(last.timestamp))))
    }
    lines.append((isRussian ? "Медиа: " : "Media: ") + "\(mediaCount)")
    lines.append((isRussian ? "Символов: " : "Characters: ") + "\(characters)")
    lines.append("")
    lines.append(isRussian ? "По участникам:" : "By author:")
    for (name, count) in perAuthor.sorted(by: { $0.value > $1.value }) {
        let percent = messages.isEmpty ? 0 : count * 100 / messages.count
        lines.append("• \(name): \(count) (\(percent)%)")
    }
    if let busiest = perHour.enumerated().max(by: { $0.element < $1.element }), busiest.element > 0 {
        lines.append("")
        lines.append((isRussian ? "Самый активный час: " : "Busiest hour: ") + String(format: "%02d:00", busiest.offset))
    }
    return lines.joined(separator: "\n")
}

/// The AI actions of the message menu.
public enum AyuAIAction {
    case translate
    case summarize
    case explain
    case reply
    case improve
    case formal
    case friendly
    case chatSummary
    case actionPoints

    public func prompt(languageName: String) -> String {
        let answerLanguage = "Answer in \(languageName)."
        switch self {
        case .translate:
            return "Translate the user's message into \(languageName). Reply with the translation only."
        case .summarize:
            return "Summarize the user's message in 1-3 short sentences. \(answerLanguage)"
        case .explain:
            return "Explain the user's message simply: meaning, context, slang or terms. \(answerLanguage)"
        case .reply:
            return "Suggest three short, natural replies to this chat message, each on its own line, numbered. Use the message's language."
        case .improve:
            return "Fix grammar, spelling and punctuation and make the text read naturally, keeping its meaning and language. Reply with the improved text only."
        case .formal:
            return "Rewrite the text in a polite, formal tone, keeping its meaning and language. Reply with the rewritten text only."
        case .friendly:
            return "Rewrite the text in a warm, friendly, casual tone, keeping its meaning and language. Reply with the rewritten text only."
        case .chatSummary:
            return "The user gives a chat transcript. Summarize what was discussed: main topics, decisions and open questions, as a short list. \(answerLanguage)"
        case .actionPoints:
            return "The user gives a chat transcript. List the key points, the tasks and promises (who, what, when) and the questions still waiting for an answer. \(answerLanguage)"
        }
    }
}

/// The name of the interface language, for AI prompts.
public func ayuLanguageName(_ strings: PresentationStrings) -> String {
    let code = strings.baseLanguageCode.lowercased()
    if code.hasPrefix("ru") {
        return "Russian"
    }
    if let name = Locale(identifier: "en").localizedString(forLanguageCode: code) {
        return name
    }
    return "English"
}
