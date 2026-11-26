import Foundation
import Postbox

/// AstraGram: reactions under messages are not drawn in the kinds of chats Settings → AstraGram → Chats chose. Tags in
/// Saved Messages always show (they are the user's own labels, not reactions).
public func astraHidesReactions(message: Message, accountPeerId: PeerId) -> Bool {
    let settings = AstraGramSettings.current
    guard settings.hideReactionsPrivate || settings.hideReactionsGroups || settings.hideReactionsChannels else {
        return false
    }
    if message.id.peerId == accountPeerId {
        return false
    }
    guard let peer = message.peers[message.id.peerId] else {
        return false
    }
    if let channel = peer as? TelegramChannel {
        if case .broadcast = channel.info {
            return settings.hideReactionsChannels
        }
        return settings.hideReactionsGroups
    }
    if peer is TelegramGroup {
        return settings.hideReactionsGroups
    }
    return settings.hideReactionsPrivate
}

/// AstraGram: "zalgo" text, letters buried under stacks of combining marks, is drawn with at most two marks per letter.
/// Each extra mark becomes a zero-width space, so the text keeps its length and every entity keeps its range.
public func astraFilterZalgo(_ text: String) -> String {
    let units = Array(text.utf16)
    var result = units
    var run = 0
    var changed = false
    for (index, unit) in units.enumerated() {
        let isCombining = (0x0300 ... 0x036F).contains(unit) || (0x1AB0 ... 0x1AFF).contains(unit) || (0x1DC0 ... 0x1DFF).contains(unit) || (0x20D0 ... 0x20FF).contains(unit) || (0xFE20 ... 0xFE2F).contains(unit)
        if isCombining {
            run += 1
            if run > 2 {
                result[index] = 0x200B
                changed = true
            }
        } else {
            run = 0
        }
    }
    return changed ? String(decoding: result, as: UTF16.self) : text
}
