import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

// AstraGram «Liquid Glass»: deep-space indigo (or a pale morning sky) under an aurora, with every surface made of glass.
// Cards, rows and bubbles are see-through tints with a bright rim, so the aurora and the chat background glow through
// them. The theme starts from Telegram's Night or Day theme with the prism accent; the slots the design names are set
// to its tokens, the rest keep what the customised theme gives them.

private let astraLiquidGlassThemes = Atomic<[Int: PresentationTheme]>(value: [:])

/// The identities of the `chart` objects of the Liquid Glass themes, so that resources and nodes can tell a glass
/// theme (or one derived from it inside this module) from any other.
private let astraLiquidGlassMarkers = Atomic<Set<ObjectIdentifier>>(value: Set())

public extension PresentationTheme {
    /// Whether this theme is (or derives from) the Liquid Glass theme.
    var isAstraLiquidGlass: Bool {
        let identifier = ObjectIdentifier(self.chart)
        return astraLiquidGlassMarkers.with { $0.contains(identifier) }
    }
}

/// The Liquid Glass colour tokens for one appearance.
public struct AstraLiquidGlassPalette {
    public let dark: Bool
    /// The page under everything (the aurora's base).
    public let page: UIColor
    /// A page for sheets and modal lists, which have no aurora behind them.
    public let modalPage: UIColor
    /// Glass: a card, a row, a bubble of the other side.
    public let glass: UIColor
    public let glassPinned: UIColor
    public let glassPressed: UIColor
    /// Solid glass, for what must not be see-through (modal rows).
    public let glassSolid: UIColor
    /// The bright edge of glass.
    public let rim: UIColor
    public let hairline: UIColor
    public let text: UIColor
    public let text2: UIColor
    public let text3: UIColor
    public let accent: UIColor
    public let accentPressed: UIColor
    public let accentWash: UIColor
    public let onAccent: UIColor
    public let cyan: UIColor
    public let destructive: UIColor
    public let online: UIColor
    public let accentRGB: UInt32

    public init(dark: Bool) {
        self.dark = dark
        if dark {
            self.page = UIColor(rgb: 0x07061A)
            self.modalPage = UIColor(rgb: 0x0D0B24)
            self.glass = UIColor(rgb: 0xFFFFFF, alpha: 0.075)
            self.glassPinned = UIColor(rgb: 0xB9AEFF, alpha: 0.12)
            self.glassPressed = UIColor(rgb: 0xFFFFFF, alpha: 0.16)
            self.glassSolid = UIColor(rgb: 0x17153A)
            self.rim = UIColor(rgb: 0xFFFFFF, alpha: 0.18)
            self.hairline = UIColor(rgb: 0xFFFFFF, alpha: 0.09)
            self.text = UIColor(rgb: 0xF3F1FF)
            self.text2 = UIColor(rgb: 0xA8A4CF)
            self.text3 = UIColor(rgb: 0x6E6A96)
            self.accent = UIColor(rgb: 0x9C88FF)
            self.accentPressed = UIColor(rgb: 0x8470FF)
            self.accentWash = UIColor(rgb: 0x9C88FF, alpha: 0.22)
            self.onAccent = UIColor(rgb: 0xFFFFFF)
            self.cyan = UIColor(rgb: 0x3FD8F5)
            self.destructive = UIColor(rgb: 0xFF5A7A)
            self.online = UIColor(rgb: 0x3FE3C2)
            self.accentRGB = 0x8C76FF
        } else {
            self.page = UIColor(rgb: 0xEEF1FF)
            self.modalPage = UIColor(rgb: 0xF2F2FA)
            self.glass = UIColor(rgb: 0xFFFFFF, alpha: 0.6)
            self.glassPinned = UIColor(rgb: 0xFFFFFF, alpha: 0.78)
            self.glassPressed = UIColor(rgb: 0xFFFFFF, alpha: 0.92)
            self.glassSolid = UIColor(rgb: 0xFFFFFF)
            self.rim = UIColor(rgb: 0xFFFFFF, alpha: 0.85)
            self.hairline = UIColor(rgb: 0x1B1650, alpha: 0.08)
            self.text = UIColor(rgb: 0x141238)
            self.text2 = UIColor(rgb: 0x5D5A80)
            self.text3 = UIColor(rgb: 0x8E8BAD)
            self.accent = UIColor(rgb: 0x5B3DF5)
            self.accentPressed = UIColor(rgb: 0x4A2DDE)
            self.accentWash = UIColor(rgb: 0x5B3DF5, alpha: 0.12)
            self.onAccent = UIColor(rgb: 0xFFFFFF)
            self.cyan = UIColor(rgb: 0x0BA5C9)
            self.destructive = UIColor(rgb: 0xE5264D)
            self.online = UIColor(rgb: 0x00B38A)
            self.accentRGB = 0x5B3DF5
        }
    }
}

/// The chat background: a four-stop aurora gradient, which Telegram swirls natively when a message is sent.
private func astraLiquidGlassWallpaper(dark: Bool) -> TelegramWallpaper {
    let colors: [UInt32] = dark ? [0x2A1670, 0x07061A, 0x0C3D66, 0x4A1468] : [0xD6CCFF, 0xF4F0FF, 0xC4EDFF, 0xFFD3F3]
    return .gradient(TelegramWallpaper.Gradient(id: nil, colors: colors, settings: WallpaperSettings()))
}

/// Date and service chips of frosted glass.
private func astraLiquidGlassServiceMessage(_ serviceMessage: PresentationThemeServiceMessage, palette p: AstraLiquidGlassPalette) -> PresentationThemeServiceMessage {
    let fill = p.dark ? UIColor(rgb: 0xFFFFFF, alpha: 0.13) : UIColor(rgb: 0x2A2070, alpha: 0.26)
    let primaryText = UIColor(rgb: 0xFFFFFF)
    let linkHighlight = UIColor(rgb: 0xFFFFFF, alpha: 0.25)
    let components = serviceMessage.components
    return serviceMessage.withUpdated(
        components: components.withUpdated(
            withDefaultWallpaper: components.withDefaultWallpaper.withUpdated(fill: fill, primaryText: primaryText, linkHighlight: linkHighlight, dateFillStatic: fill, dateFillFloating: fill),
            withCustomWallpaper: components.withCustomWallpaper.withUpdated(fill: fill, primaryText: primaryText, linkHighlight: linkHighlight, dateFillStatic: fill, dateFillFloating: fill)
        ),
        dateTextColor: PresentationThemeVariableColor(color: primaryText)
    )
}

/// The Liquid Glass theme for an appearance and a bubble mode. Themes are cached and never mutated.
public func makeAstraLiquidGlassPresentationTheme(dark: Bool, bubbleMode: Bool) -> PresentationTheme {
    let key = (dark ? 1 : 0) | (bubbleMode ? 2 : 0)
    if let cached = astraLiquidGlassThemes.with({ $0[key] }) {
        return cached
    }
    let p = AstraLiquidGlassPalette(dark: dark)
    let wallpaper = astraLiquidGlassWallpaper(dark: dark)

    let defaultTheme = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    let base = customizePresentationTheme(defaultTheme, editing: true, accentColor: p.accent, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [p.accentRGB], animateBubbleColors: nil, wallpaper: wallpaper)

    let rootController = base.rootController.withUpdated(
        tabBar: base.rootController.tabBar.withUpdated(
            backgroundColor: p.page.withAlphaComponent(0.0),
            separatorColor: UIColor(rgb: 0x000000, alpha: 0.0),
            iconColor: p.text2,
            selectedIconColor: p.accent,
            textColor: p.text2,
            selectedTextColor: p.accent,
            badgeBackgroundColor: p.destructive,
            badgeStrokeColor: UIColor(rgb: 0x000000, alpha: 0.0),
            badgeTextColor: UIColor(rgb: 0xFFFFFF)
        ),
        navigationBar: base.rootController.navigationBar.withUpdated(
            buttonColor: p.accent,
            disabledButtonColor: p.text3,
            primaryTextColor: p.text,
            secondaryTextColor: p.text2,
            controlColor: p.text2,
            accentTextColor: p.accent,
            blurredBackgroundColor: p.page.withAlphaComponent(0.55),
            opaqueBackgroundColor: p.page,
            separatorColor: UIColor(rgb: 0x000000, alpha: 0.0),
            badgeBackgroundColor: p.destructive,
            badgeStrokeColor: UIColor(rgb: 0x000000, alpha: 0.0),
            badgeTextColor: UIColor(rgb: 0xFFFFFF),
            segmentedBackgroundColor: p.glass,
            segmentedForegroundColor: p.glassPressed,
            segmentedTextColor: p.text,
            segmentedDividerColor: p.hairline,
            clearButtonBackgroundColor: p.text3.withAlphaComponent(0.35),
            clearButtonForegroundColor: p.text
        ),
        navigationSearchBar: base.rootController.navigationSearchBar.withUpdated(
            backgroundColor: p.page.withAlphaComponent(0.0),
            accentColor: p.accent,
            inputFillColor: p.glass,
            inputTextColor: p.text,
            inputPlaceholderTextColor: p.text3,
            inputIconColor: p.text2
        )
    )

    let list = base.list.withUpdated(
        blocksBackgroundColor: p.page,
        modalBlocksBackgroundColor: p.modalPage,
        plainBackgroundColor: p.page,
        modalPlainBackgroundColor: p.modalPage,
        itemPrimaryTextColor: p.text,
        itemSecondaryTextColor: p.text2,
        itemDisabledTextColor: p.text3,
        itemAccentColor: p.accent,
        itemHighlightedColor: p.accent,
        itemDestructiveColor: p.destructive,
        itemPlaceholderTextColor: p.text3,
        itemBlocksBackgroundColor: p.glass,
        itemModalBlocksBackgroundColor: p.glassSolid,
        itemHighlightedBackgroundColor: p.glassPressed,
        itemBlocksSeparatorColor: p.hairline,
        itemPlainSeparatorColor: p.hairline,
        disclosureArrowColor: p.text3,
        sectionHeaderTextColor: p.text2,
        freeTextColor: p.text2,
        freeTextErrorColor: p.destructive,
        freeTextSuccessColor: p.online,
        itemSwitchColors: base.list.itemSwitchColors.withUpdated(
            frameColor: p.dark ? UIColor(rgb: 0x2A2752) : UIColor(rgb: 0xDAD8EE),
            handleColor: UIColor(rgb: 0xFFFFFF),
            contentColor: p.accent,
            positiveColor: p.online,
            negativeColor: p.destructive
        ),
        itemCheckColors: base.list.itemCheckColors.withUpdated(fillColor: p.accent, strokeColor: p.text3, foregroundColor: p.onAccent)
    )

    let chatList = base.chatList.withUpdated(
        backgroundColor: p.page,
        itemSeparatorColor: UIColor(rgb: 0x000000, alpha: 0.0),
        itemBackgroundColor: p.page.withAlphaComponent(0.0),
        pinnedItemBackgroundColor: p.page.withAlphaComponent(0.0),
        itemHighlightedBackgroundColor: p.glassPressed,
        pinnedItemHighlightedBackgroundColor: p.glassPressed,
        itemSelectedBackgroundColor: p.accentWash,
        titleColor: p.text,
        secretTitleColor: p.online,
        dateTextColor: p.text2,
        authorNameColor: p.text,
        messageTextColor: p.text2,
        messageHighlightedTextColor: p.text,
        messageDraftTextColor: p.destructive,
        checkmarkColor: p.cyan,
        pendingIndicatorColor: p.text3,
        failedFillColor: p.destructive,
        failedForegroundColor: UIColor(rgb: 0xFFFFFF),
        muteIconColor: p.text3,
        unreadBadgeActiveBackgroundColor: p.accent,
        unreadBadgeActiveTextColor: p.onAccent,
        unreadBadgeInactiveBackgroundColor: p.dark ? UIColor(rgb: 0x34315C) : UIColor(rgb: 0xC9C6E2),
        unreadBadgeInactiveTextColor: p.dark ? p.text : UIColor(rgb: 0xFFFFFF),
        reactionBadgeActiveBackgroundColor: p.destructive,
        pinnedBadgeColor: p.text3,
        pinnedSearchBarColor: p.glass,
        regularSearchBarColor: p.glass,
        sectionHeaderFillColor: p.page.withAlphaComponent(0.92),
        sectionHeaderTextColor: p.text2,
        verifiedIconFillColor: p.cyan,
        verifiedIconForegroundColor: UIColor(rgb: 0xFFFFFF),
        secretIconColor: p.online,
        pinnedArchiveAvatarColor: base.chatList.pinnedArchiveAvatarColor.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: p.accent, bottomColor: p.cyan)),
        unpinnedArchiveAvatarColor: base.chatList.unpinnedArchiveAvatarColor.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: p.text3, bottomColor: p.text3)),
        onlineDotColor: p.online,
        storyUnseenColors: PresentationThemeGradientColors(topColor: p.cyan, bottomColor: p.accent),
        storyUnseenPrivateColors: PresentationThemeGradientColors(topColor: p.online, bottomColor: p.cyan),
        storySeenColors: p.dark ? PresentationThemeGradientColors(topColor: UIColor(rgb: 0x3A3766), bottomColor: UIColor(rgb: 0x3A3766)) : PresentationThemeGradientColors(topColor: UIColor(rgb: 0xC9C6E2), bottomColor: UIColor(rgb: 0xC9C6E2))
    )

    // Bubbles of glass: the other side's are a clear tint with a bright rim, yours a violet glass the background
    // glows through.
    let incomingBase = base.chat.message.incoming
    let incomingComponents = incomingBase.bubble.withoutWallpaper.withUpdated(
        fill: [p.dark ? UIColor(rgb: 0xFFFFFF, alpha: 0.12) : UIColor(rgb: 0xFFFFFF, alpha: 0.62)],
        highlightedFill: p.dark ? UIColor(rgb: 0xFFFFFF, alpha: 0.2) : UIColor(rgb: 0xFFFFFF, alpha: 0.85),
        stroke: p.rim,
        reactionInactiveBackground: p.dark ? UIColor(rgb: 0xFFFFFF, alpha: 0.12) : UIColor(rgb: 0x5B3DF5, alpha: 0.1),
        reactionInactiveForeground: p.text,
        reactionActiveBackground: p.accent,
        reactionActiveForeground: p.onAccent
    )
    let incoming = incomingBase.withUpdated(
        bubble: incomingBase.bubble.withUpdated(withWallpaper: incomingComponents, withoutWallpaper: incomingComponents),
        primaryTextColor: p.text,
        secondaryTextColor: p.text2,
        linkTextColor: p.dark ? p.cyan : p.accent,
        linkHighlightColor: p.accent.withAlphaComponent(0.2),
        accentTextColor: p.dark ? UIColor(rgb: 0xB7A9FF) : p.accent,
        accentControlColor: p.accent,
        mediaActiveControlColor: p.accent,
        fileTitleColor: p.text,
        fileDescriptionColor: p.text2,
        fileDurationColor: p.text2,
        textSelectionColor: p.accent.withAlphaComponent(0.25),
        textSelectionKnobColor: p.accent
    )

    let outgoingBase = base.chat.message.outgoing
    let outgoingFill = p.dark ? UIColor(rgb: 0x7A60FF, alpha: 0.62) : UIColor(rgb: 0x6A4DFF, alpha: 0.82)
    let outgoingComponents = outgoingBase.bubble.withoutWallpaper.withUpdated(
        fill: [outgoingFill],
        highlightedFill: p.dark ? UIColor(rgb: 0x8C76FF, alpha: 0.8) : UIColor(rgb: 0x5B3DF5, alpha: 0.95),
        stroke: UIColor(rgb: 0xFFFFFF, alpha: p.dark ? 0.26 : 0.45),
        reactionInactiveBackground: UIColor(rgb: 0xFFFFFF, alpha: 0.18),
        reactionInactiveForeground: UIColor(rgb: 0xFFFFFF),
        reactionActiveBackground: UIColor(rgb: 0xFFFFFF),
        reactionActiveForeground: p.accent
    )
    let outgoingSecondary = UIColor(rgb: 0xFFFFFF, alpha: 0.7)
    let outgoing = outgoingBase.withUpdated(
        bubble: outgoingBase.bubble.withUpdated(withWallpaper: outgoingComponents, withoutWallpaper: outgoingComponents),
        primaryTextColor: UIColor(rgb: 0xFFFFFF),
        secondaryTextColor: outgoingSecondary,
        linkTextColor: UIColor(rgb: 0xFFFFFF),
        accentTextColor: UIColor(rgb: 0xFFFFFF),
        accentControlColor: UIColor(rgb: 0xFFFFFF),
        mediaActiveControlColor: UIColor(rgb: 0xFFFFFF),
        fileTitleColor: UIColor(rgb: 0xFFFFFF),
        fileDescriptionColor: outgoingSecondary
    )

    let message = base.chat.message.withUpdated(incoming: incoming, outgoing: outgoing, outgoingCheckColor: outgoingSecondary)

    let inputPanel = base.chat.inputPanel.withUpdated(
        panelControlAccentColor: p.accent,
        panelControlColor: p.text2,
        panelControlDisabledColor: p.text3,
        panelControlDestructiveColor: p.destructive,
        inputPlaceholderColor: p.text3,
        inputTextColor: p.text,
        inputControlColor: p.text2,
        actionControlFillColor: p.accent,
        actionControlForegroundColor: p.onAccent,
        mediaRecordingDotColor: p.destructive,
        mediaRecordingControl: base.chat.inputPanel.mediaRecordingControl.withUpdated(buttonColor: p.accent)
    )

    let historyNavigation = base.chat.historyNavigation.withUpdated(
        foregroundColor: p.text,
        badgeBackgroundColor: p.accent,
        badgeTextColor: p.onAccent
    )

    let chat = base.chat.withUpdated(
        defaultWallpaper: wallpaper,
        message: message,
        serviceMessage: astraLiquidGlassServiceMessage(base.chat.serviceMessage, palette: p),
        inputPanel: inputPanel,
        historyNavigation: historyNavigation
    )

    let dimColor = p.dark ? UIColor(rgb: 0x03020C, alpha: 0.55) : UIColor(rgb: 0x1B1650, alpha: 0.28)
    let actionSheet = base.actionSheet.withUpdated(
        dimColor: dimColor,
        backgroundType: p.dark ? .dark : .light,
        opaqueItemBackgroundColor: p.glassSolid,
        itemBackgroundColor: p.dark ? UIColor(rgb: 0x16143A, alpha: 0.72) : UIColor(rgb: 0xFFFFFF, alpha: 0.72),
        opaqueItemHighlightedBackgroundColor: p.dark ? UIColor(rgb: 0x23205A) : UIColor(rgb: 0xE9E6FF),
        itemHighlightedBackgroundColor: p.glassPressed,
        opaqueItemSeparatorColor: p.hairline,
        standardActionTextColor: p.accent,
        destructiveActionTextColor: p.destructive,
        disabledActionTextColor: p.text3,
        primaryTextColor: p.text,
        secondaryTextColor: p.text2,
        controlAccentColor: p.accent,
        inputBackgroundColor: p.glass,
        inputPlaceholderColor: p.text3,
        inputTextColor: p.text,
        checkContentColor: p.onAccent
    )

    let contextMenu = base.contextMenu.withUpdated(
        dimColor: dimColor,
        backgroundColor: p.dark ? UIColor(rgb: 0x16143A, alpha: 0.6) : UIColor(rgb: 0xFFFFFF, alpha: 0.6),
        itemSeparatorColor: p.hairline,
        itemBackgroundColor: UIColor(rgb: 0x000000, alpha: 0.0),
        itemHighlightedBackgroundColor: p.glassPressed,
        primaryColor: p.text,
        secondaryColor: p.text2,
        destructiveColor: p.destructive
    )

    let inAppNotification = base.inAppNotification.withUpdated(
        fillColor: p.glassSolid,
        primaryTextColor: p.text,
        expandedNotification: base.inAppNotification.expandedNotification.withUpdated(backgroundType: p.dark ? .dark : .light)
    )

    var theme = PresentationTheme(
        name: base.name,
        index: base.index,
        referenceTheme: base.referenceTheme,
        overallDarkAppearance: dark,
        intro: base.intro,
        passcode: base.passcode,
        rootController: rootController,
        list: list,
        chatList: chatList,
        chat: chat,
        actionSheet: actionSheet,
        contextMenu: contextMenu,
        inAppNotification: inAppNotification,
        chart: base.chart,
        preview: false
    )

    if !bubbleMode {
        theme = bubblelessPresentationTheme(theme)
        theme = theme.withUpdated(chat: theme.chat.withUpdated(serviceMessage: astraLiquidGlassServiceMessage(theme.chat.serviceMessage, palette: p)))
    }

    // A chart object of its own, so the marker cannot match the stock theme this one was made from.
    let chart = theme.chart.withUpdated()
    theme = PresentationTheme(
        name: theme.name,
        index: theme.index,
        referenceTheme: theme.referenceTheme,
        overallDarkAppearance: theme.overallDarkAppearance,
        intro: theme.intro,
        passcode: theme.passcode,
        rootController: theme.rootController,
        list: theme.list,
        chatList: theme.chatList,
        chat: theme.chat,
        actionSheet: theme.actionSheet,
        contextMenu: theme.contextMenu,
        inAppNotification: theme.inAppNotification,
        chart: chart,
        preview: false
    )
    let chartIdentifier = ObjectIdentifier(chart)
    let _ = astraLiquidGlassMarkers.modify { markers in
        var markers = markers
        markers.insert(chartIdentifier)
        return markers
    }

    let result = theme
    let _ = astraLiquidGlassThemes.modify { themes in
        var themes = themes
        themes[key] = result
        return themes
    }
    return result
}
