import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

// AyuGram "Monochrome": the whole interface in black, white and grays. The dark variant is Night with Telegram's own
// white accent (gray bubbles), the light one is Day with a black accent (black bubbles with white text); every color
// left after that (switches, badges, online marks, destructive actions) is turned into the gray of its brightness.

private let ayuMonochromeThemes = Atomic<[Int: PresentationTheme]>(value: [:])

/// Whether Monochrome takes its dark variant: night mode is on, or the chosen theme is a dark one.
public func ayuMonochromeIsDark(themeSettings: PresentationThemeSettings, autoNightModeTriggered: Bool) -> Bool {
    if autoNightModeTriggered {
        return true
    }
    for reference in [themeSettings.currentModeTheme, themeSettings.theme] {
        switch reference {
        case let .builtin(builtin):
            if builtin == .night || builtin == .nightAccent || builtin == .neutralNight {
                return true
            }
        case let .cloud(info):
            if let baseTheme = info.theme.settings?.first?.baseTheme, baseTheme == .night || baseTheme == .tinted {
                return true
            }
        case .local:
            break
        }
    }
    return false
}

public func makeAyuMonochromePresentationTheme(dark: Bool, bubbleMode: Bool) -> PresentationTheme {
    let key = (dark ? 1 : 0) | (bubbleMode ? 2 : 0)
    if let cached = ayuMonochromeThemes.with({ $0[key] }) {
        return cached
    }
    let accentColor = dark ? UIColor(rgb: 0xffffff) : UIColor(rgb: 0x000000)
    // Without bubbles your own messages take the text colors of the other side's, which need a pale bubble in the
    // light variant.
    let bubbleColors: [UInt32] = (!bubbleMode && !dark) ? [neutralOutgoingBubbleColor(dark: false)] : []
    let defaultTheme = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    var theme = customizePresentationTheme(defaultTheme, editing: true, accentColor: accentColor, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: bubbleColors, animateBubbleColors: nil, wallpaper: .color(dark ? 0x000000 : 0xffffff))
    if !bubbleMode {
        theme = bubblelessPresentationTheme(theme)
    }
    theme = ayuGrayscalePresentationTheme(theme)
    let _ = ayuMonochromeThemes.modify { themes in
        var themes = themes
        themes[key] = theme
        return themes
    }
    return theme
}

/// The theme with every color replaced by the gray of its brightness: it is written out as a theme file and read back
/// with the colors converted on the way. A theme that does not survive that is returned as it is.
private func ayuGrayscalePresentationTheme(_ theme: PresentationTheme) -> PresentationTheme {
    guard let string = encodePresentationTheme(theme), let data = string.data(using: .utf8) else {
        return theme
    }
    let threadDictionary = Thread.current.threadDictionary
    threadDictionary.setObject(true as NSNumber, forKey: ayuThemeGrayscaleDecodingKey)
    defer {
        threadDictionary.removeObject(forKey: ayuThemeGrayscaleDecodingKey)
    }
    return makePresentationTheme(data: data) ?? theme
}
