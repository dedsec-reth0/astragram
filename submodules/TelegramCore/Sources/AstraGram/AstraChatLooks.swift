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

/// AstraGram: the inline calculator. For text whose last line is an arithmetic expression followed by "=" ("2+2*3=",
/// "(10-4)/3 =", "15%*200="), returns the result to put after it; nil for anything else. Numbers may use "." or ","; the
/// result uses the separator the expression used. No `NSExpression`: it raises an Objective-C exception on bad input.
public func astraCalculatorResult(_ text: String) -> String? {
    let line = text.components(separatedBy: "\n").last ?? text
    guard line.hasSuffix("=") else {
        return nil
    }
    let expression = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
    guard expression.count <= 120, !expression.isEmpty else {
        return nil
    }
    let allowed = Set("0123456789.,+-*/×÷:()%^ ")
    guard expression.allSatisfy({ allowed.contains($0) }) else {
        return nil
    }
    // A bare number ("5=", "-5=") is not a calculation: at least one operator after the first character is needed.
    guard expression.contains(where: { "+*×÷^%".contains($0) }) || expression.dropFirst().contains(where: { "-/:".contains($0) }) else {
        return nil
    }
    let usesComma = expression.contains(",") && !expression.contains(".")
    var parser = AstraCalculatorParser(Array(expression.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")))
    guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else {
        return nil
    }
    var string: String
    if abs(value) < 1e15, value == value.rounded() {
        string = String(Int64(value))
    } else {
        string = String(format: "%.6f", value)
        while string.contains(".") && (string.hasSuffix("0") || string.hasSuffix(".")) {
            string.removeLast()
        }
    }
    if usesComma {
        string = string.replacingOccurrences(of: ".", with: ",")
    }
    return line.hasSuffix(" =") ? " " + string : string
}

private struct AstraCalculatorParser {
    private let chars: [Character]
    private var index = 0
    private var depth = 0

    init(_ chars: [Character]) {
        self.chars = chars
    }

    var isAtEnd: Bool {
        return self.index == self.chars.count
    }

    private var current: Character? {
        return self.index < self.chars.count ? self.chars[self.index] : nil
    }

    // expression := term (("+" | "-") term)*
    mutating func parseExpression() -> Double? {
        guard var value = self.parseTerm() else {
            return nil
        }
        while let c = self.current, c == "+" || c == "-" {
            self.index += 1
            guard let rhs = self.parseTerm() else {
                return nil
            }
            value = c == "+" ? value + rhs : value - rhs
        }
        return value
    }

    // term := power (("*" | "/" | "×" | "÷" | ":") power)*
    private mutating func parseTerm() -> Double? {
        guard var value = self.parsePower() else {
            return nil
        }
        while let c = self.current, "*/×÷:".contains(c) {
            self.index += 1
            guard let rhs = self.parsePower() else {
                return nil
            }
            if c == "*" || c == "×" {
                value *= rhs
            } else {
                guard rhs != 0 else {
                    return nil
                }
                value /= rhs
            }
        }
        return value
    }

    // power := unary ("^" power)?
    private mutating func parsePower() -> Double? {
        guard let base = self.parseUnary() else {
            return nil
        }
        if self.current == "^" {
            self.index += 1
            guard let exponent = self.parsePower(), abs(exponent) <= 64 else {
                return nil
            }
            return pow(base, exponent)
        }
        return base
    }

    // unary := "-" unary | primary "%"?
    private mutating func parseUnary() -> Double? {
        if self.current == "-" {
            self.index += 1
            return self.parseUnary().map { -$0 }
        }
        guard var value = self.parsePrimary() else {
            return nil
        }
        if self.current == "%" {
            self.index += 1
            value /= 100.0
        }
        return value
    }

    // primary := number | "(" expression ")"
    private mutating func parsePrimary() -> Double? {
        if self.current == "(" {
            self.depth += 1
            guard self.depth <= 32 else {
                return nil
            }
            self.index += 1
            let value = self.parseExpression()
            guard self.current == ")" else {
                return nil
            }
            self.index += 1
            self.depth -= 1
            return value
        }
        let start = self.index
        while let c = self.current, c.isNumber || c == "." {
            self.index += 1
        }
        guard self.index > start else {
            return nil
        }
        return Double(String(self.chars[start ..< self.index]))
    }
}
