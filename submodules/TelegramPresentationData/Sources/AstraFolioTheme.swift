import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences

// AstraGram 2027 «Folio»: ink on paper with one electric accent, Klein Volt. The theme starts from Telegram's Day or
// Night theme customized with the volt accent, and then every slot the design names is set to its token
// (docs/astragram-redesign-2027.md, sections 2.1 and 2.2). Slots the design does not name keep what the customized
// theme gives them, so nothing new can break where the design is silent.

private let astraFolioThemes = Atomic<[Int: PresentationTheme]>(value: [:])

/// The identities of the `chart` objects of the Folio themes. Every theme derived inside this module
/// (`withUpdated(chat:)`, `withModalBlocksBackground()`, `withUpdated(preview:)`…) passes the same chart object on, so
/// a derived theme is still recognised as Folio, while a theme rebuilt from scratch is not. The cached themes keep
/// their charts alive for the life of the process, so an identity in this set is never reused by another object.
private let astraFolioMarkers = Atomic<Set<ObjectIdentifier>>(value: Set())

public extension PresentationTheme {
    /// Whether this theme is (or derives from) the Folio theme. Resources ask this instead of comparing theme names.
    var isAstraFolio: Bool {
        let identifier = ObjectIdentifier(self.chart)
        return astraFolioMarkers.with { $0.contains(identifier) }
    }
}

/// The Folio colour ramp for one appearance (section 2.1).
private struct AstraFolioPalette {
    let dark: Bool

    let page: UIColor
    let card: UIColor
    let elevated: UIColor
    let pinned: UIColor
    let highlight: UIColor
    let ink: UIColor
    let ink2: UIColor
    let ink3: UIColor
    let hairline: UIColor
    let volt: UIColor
    let voltPressed: UIColor
    let voltWash: UIColor
    let onVolt: UIColor
    let destructive: UIColor
    let online: UIColor

    let voltRGB: UInt32
    let wallpaperRGB: UInt32

    init(dark: Bool) {
        self.dark = dark
        if dark {
            self.page = UIColor(rgb: 0x0B0B0C)
            self.card = UIColor(rgb: 0x161618)
            self.elevated = UIColor(rgb: 0x1E1E21)
            self.pinned = UIColor(rgb: 0x121214)
            self.highlight = UIColor(rgb: 0x222226)
            self.ink = UIColor(rgb: 0xF4F3EE)
            self.ink2 = UIColor(rgb: 0x9C9B96)
            self.ink3 = UIColor(rgb: 0x6E6D69)
            self.hairline = UIColor(rgb: 0x26262A)
            self.volt = UIColor(rgb: 0x8B7DFF)
            self.voltPressed = UIColor(rgb: 0x7565FF)
            self.voltWash = UIColor(rgb: 0x221E45)
            self.onVolt = UIColor(rgb: 0x0B0B0C)
            self.destructive = UIColor(rgb: 0xFF4D5E)
            self.online = UIColor(rgb: 0x2EE59D)
            self.voltRGB = 0x8B7DFF
            self.wallpaperRGB = 0x0B0B0C
        } else {
            self.page = UIColor(rgb: 0xF7F6F2)
            self.card = UIColor(rgb: 0xFFFFFF)
            self.elevated = UIColor(rgb: 0xFFFFFF)
            self.pinned = UIColor(rgb: 0xEFEEE9)
            self.highlight = UIColor(rgb: 0xE7E6E0)
            self.ink = UIColor(rgb: 0x0B0B0C)
            self.ink2 = UIColor(rgb: 0x5C5B57)
            self.ink3 = UIColor(rgb: 0x8A8984)
            self.hairline = UIColor(rgb: 0xE3E2DD)
            self.volt = UIColor(rgb: 0x3D2BFF)
            self.voltPressed = UIColor(rgb: 0x2C1FD6)
            self.voltWash = UIColor(rgb: 0xECEAFF)
            self.onVolt = UIColor(rgb: 0xFFFFFF)
            self.destructive = UIColor(rgb: 0xE5162D)
            self.online = UIColor(rgb: 0x00A86B)
            self.voltRGB = 0x3D2BFF
            self.wallpaperRGB = 0xEFEEE9
        }
    }
}

/// The default chat background of Folio: solid paper (or ink), or the four-stop «Живой фон» gradient, which Telegram
/// rotates natively on send.
private func astraFolioWallpaper(dark: Bool, livingWallpaper: Bool, palette: AstraFolioPalette) -> TelegramWallpaper {
    if livingWallpaper {
        let colors: [UInt32] = dark ? [0x0B0B0C, 0x15122E, 0x0E0E10, 0x1B1745] : [0xEFEEE9, 0xE8E6F6, 0xF3F1EA, 0xE4E2F8]
        return .gradient(TelegramWallpaper.Gradient(id: nil, colors: colors, settings: WallpaperSettings()))
    }
    return .color(palette.wallpaperRGB)
}

/// The inverse-ink date and service chips. Bubble-free mode overwrites the service message colours, so this is applied
/// once more after it.
private func astraFolioServiceMessage(_ serviceMessage: PresentationThemeServiceMessage, palette: AstraFolioPalette) -> PresentationThemeServiceMessage {
    let fill = palette.dark ? UIColor(rgb: 0xF4F3EE, alpha: 0.92) : UIColor(rgb: 0x2A2A2A)
    let floatingFill = fill.withAlphaComponent(fill.alpha * 0.9)
    let primaryText = palette.dark ? UIColor(rgb: 0x0B0B0C) : UIColor(rgb: 0xF7F6F2)
    let linkHighlight = palette.volt.withAlphaComponent(0.3)
    let components = serviceMessage.components
    return serviceMessage.withUpdated(
        components: components.withUpdated(
            withDefaultWallpaper: components.withDefaultWallpaper.withUpdated(fill: fill, primaryText: primaryText, linkHighlight: linkHighlight, dateFillStatic: fill, dateFillFloating: floatingFill),
            withCustomWallpaper: components.withCustomWallpaper.withUpdated(fill: fill, primaryText: primaryText, linkHighlight: linkHighlight, dateFillStatic: fill, dateFillFloating: floatingFill)
        ),
        dateTextColor: PresentationThemeVariableColor(color: primaryText)
    )
}

/// The Folio theme for an appearance and a bubble mode. Themes are cached and never mutated: a toggle produces a
/// different instance, so per-theme resources (corner images, badges, bubble images) are generated anew.
public func makeAstraFolioPresentationTheme(dark: Bool, bubbleMode: Bool, livingWallpaper: Bool) -> PresentationTheme {
    let key = (dark ? 1 : 0) | (bubbleMode ? 2 : 0) | (livingWallpaper ? 4 : 0)
    if let cached = astraFolioThemes.with({ $0[key] }) {
        return cached
    }
    let p = AstraFolioPalette(dark: dark)
    let wallpaper = astraFolioWallpaper(dark: dark, livingWallpaper: livingWallpaper, palette: p)

    // 1–2. Telegram's own theme with the volt accent and a single-stop volt bubble (one stop keeps the knockout
    // gradient path off).
    let defaultTheme = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    let base = customizePresentationTheme(defaultTheme, editing: true, accentColor: p.volt, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [p.voltRGB], animateBubbleColors: nil, wallpaper: wallpaper)

    // 3. Every slot the design names.
    let rootController = base.rootController.withUpdated(
        tabBar: base.rootController.tabBar.withUpdated(
            backgroundColor: p.page.withAlphaComponent(0.0),
            separatorColor: UIColor(rgb: 0x000000, alpha: 0.0),
            iconColor: p.ink,
            selectedIconColor: p.volt,
            textColor: p.ink2,
            selectedTextColor: p.volt,
            badgeBackgroundColor: p.volt,
            badgeStrokeColor: p.page,
            badgeTextColor: p.onVolt
        ),
        navigationBar: base.rootController.navigationBar.withUpdated(
            buttonColor: p.volt,
            disabledButtonColor: p.ink3,
            primaryTextColor: p.ink,
            secondaryTextColor: p.ink2,
            controlColor: p.ink2,
            accentTextColor: p.volt,
            blurredBackgroundColor: p.page.withAlphaComponent(0.92),
            opaqueBackgroundColor: p.page,
            separatorColor: p.hairline,
            badgeBackgroundColor: p.volt,
            badgeStrokeColor: p.page,
            badgeTextColor: p.onVolt,
            segmentedBackgroundColor: p.hairline,
            segmentedForegroundColor: p.card,
            segmentedTextColor: p.ink,
            segmentedDividerColor: p.hairline,
            clearButtonBackgroundColor: p.ink3.withAlphaComponent(0.3),
            clearButtonForegroundColor: p.ink
        ),
        navigationSearchBar: base.rootController.navigationSearchBar.withUpdated(
            backgroundColor: p.page,
            accentColor: p.volt,
            inputFillColor: dark ? UIColor(rgb: 0x1E1E21) : p.card,
            inputTextColor: p.ink,
            inputPlaceholderTextColor: p.ink3,
            inputIconColor: p.ink2
        )
    )

    let list = base.list.withUpdated(
        blocksBackgroundColor: p.page,
        plainBackgroundColor: p.card,
        itemPrimaryTextColor: p.ink,
        itemSecondaryTextColor: p.ink2,
        itemDisabledTextColor: p.ink3,
        itemAccentColor: p.volt,
        itemHighlightedColor: p.volt,
        itemDestructiveColor: p.destructive,
        itemPlaceholderTextColor: p.ink3,
        itemBlocksBackgroundColor: p.card,
        itemModalBlocksBackgroundColor: dark ? p.elevated : p.card,
        itemHighlightedBackgroundColor: p.highlight,
        itemBlocksSeparatorColor: p.hairline,
        itemPlainSeparatorColor: p.hairline,
        disclosureArrowColor: p.ink3,
        sectionHeaderTextColor: p.ink2,
        freeTextColor: p.ink2,
        freeTextErrorColor: p.destructive,
        freeTextSuccessColor: p.online,
        itemSwitchColors: base.list.itemSwitchColors.withUpdated(
            frameColor: dark ? UIColor(rgb: 0x2A2A2E) : p.hairline,
            handleColor: UIColor(rgb: 0xFFFFFF),
            contentColor: p.volt,
            positiveColor: p.online,
            negativeColor: p.destructive
        ),
        itemCheckColors: base.list.itemCheckColors.withUpdated(fillColor: p.volt, strokeColor: p.ink3, foregroundColor: p.onVolt)
    )

    let chatList = base.chatList.withUpdated(
        backgroundColor: p.page,
        itemSeparatorColor: p.hairline,
        itemBackgroundColor: p.page,
        pinnedItemBackgroundColor: p.pinned,
        itemHighlightedBackgroundColor: p.highlight,
        pinnedItemHighlightedBackgroundColor: p.highlight,
        itemSelectedBackgroundColor: p.voltWash,
        titleColor: p.ink,
        secretTitleColor: p.online,
        dateTextColor: p.ink2,
        authorNameColor: p.ink,
        messageTextColor: p.ink2,
        messageHighlightedTextColor: p.ink,
        messageDraftTextColor: p.destructive,
        checkmarkColor: p.volt,
        pendingIndicatorColor: p.ink3,
        failedFillColor: p.destructive,
        failedForegroundColor: UIColor(rgb: 0xFFFFFF),
        muteIconColor: p.ink3,
        unreadBadgeActiveBackgroundColor: p.volt,
        unreadBadgeActiveTextColor: p.onVolt,
        unreadBadgeInactiveBackgroundColor: dark ? UIColor(rgb: 0x2A2A2E) : p.hairline,
        unreadBadgeInactiveTextColor: p.ink,
        reactionBadgeActiveBackgroundColor: p.volt,
        pinnedBadgeColor: p.ink3,
        pinnedSearchBarColor: p.card,
        regularSearchBarColor: p.card,
        sectionHeaderFillColor: p.page,
        sectionHeaderTextColor: p.ink2,
        verifiedIconFillColor: p.volt,
        verifiedIconForegroundColor: p.onVolt,
        secretIconColor: p.online,
        pinnedArchiveAvatarColor: base.chatList.pinnedArchiveAvatarColor.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: p.volt, bottomColor: p.volt)),
        unpinnedArchiveAvatarColor: base.chatList.unpinnedArchiveAvatarColor.withUpdated(backgroundColors: PresentationThemeGradientColors(topColor: p.ink3, bottomColor: p.ink3)),
        onlineDotColor: p.online,
        // Story rings are flat: one colour at both ends of the gradient.
        storyUnseenColors: PresentationThemeGradientColors(topColor: p.volt, bottomColor: p.volt),
        storyUnseenPrivateColors: PresentationThemeGradientColors(topColor: p.online, bottomColor: p.online),
        storySeenColors: dark ? PresentationThemeGradientColors(topColor: UIColor(rgb: 0x3A3A3F), bottomColor: UIColor(rgb: 0x3A3A3F)) : PresentationThemeGradientColors(topColor: UIColor(rgb: 0xC9C8C2), bottomColor: UIColor(rgb: 0xC9C8C2))
    )

    // Incoming messages: white (or near-black) slabs without a stroke; the hairline rim is drawn by the bubble node.
    let incomingBase = base.chat.message.incoming
    let incomingComponents = incomingBase.bubble.withoutWallpaper.withUpdated(
        fill: [dark ? UIColor(rgb: 0x1C1C1F) : UIColor(rgb: 0xFFFFFF)],
        highlightedFill: p.highlight,
        stroke: UIColor(rgb: 0x000000, alpha: 0.0),
        reactionInactiveBackground: dark ? UIColor(rgb: 0x26262A) : UIColor(rgb: 0xEFEEE9),
        reactionInactiveForeground: p.ink,
        reactionActiveBackground: p.volt,
        reactionActiveForeground: p.onVolt
    )
    let incomingSecondary = dark ? UIColor(rgb: 0x9C9B96) : UIColor(rgb: 0x6B6A65)
    let incoming = incomingBase.withUpdated(
        bubble: incomingBase.bubble.withUpdated(withWallpaper: incomingComponents, withoutWallpaper: incomingComponents),
        primaryTextColor: p.ink,
        secondaryTextColor: incomingSecondary,
        linkTextColor: p.volt,
        linkHighlightColor: p.volt.withAlphaComponent(0.2),
        accentTextColor: p.volt,
        accentControlColor: p.volt,
        mediaActiveControlColor: p.volt,
        fileTitleColor: p.ink,
        fileDescriptionColor: p.ink2,
        fileDurationColor: p.ink2,
        textSelectionColor: p.volt.withAlphaComponent(0.2),
        textSelectionKnobColor: p.volt
    )

    // Outgoing messages: one solid volt stop, text and controls in the colour that sits on volt.
    let outgoingBase = base.chat.message.outgoing
    let outgoingComponents = outgoingBase.bubble.withoutWallpaper.withUpdated(
        fill: [p.volt],
        highlightedFill: p.voltPressed,
        stroke: UIColor(rgb: 0x000000, alpha: 0.0),
        reactionInactiveBackground: dark ? UIColor(rgb: 0x7565FF) : UIColor(rgb: 0x2C1FD6),
        reactionInactiveForeground: p.onVolt,
        reactionActiveBackground: dark ? UIColor(rgb: 0x0B0B0C) : UIColor(rgb: 0xFFFFFF),
        reactionActiveForeground: p.volt
    )
    let outgoingSecondary = dark ? UIColor(rgb: 0x1F1A4D) : UIColor(rgb: 0xD9D5FF)
    let outgoing = outgoingBase.withUpdated(
        bubble: outgoingBase.bubble.withUpdated(withWallpaper: outgoingComponents, withoutWallpaper: outgoingComponents),
        primaryTextColor: p.onVolt,
        secondaryTextColor: outgoingSecondary,
        linkTextColor: p.onVolt,
        accentTextColor: p.onVolt,
        accentControlColor: p.onVolt,
        mediaActiveControlColor: p.onVolt,
        fileTitleColor: p.onVolt,
        fileDescriptionColor: outgoingSecondary
    )

    let message = base.chat.message.withUpdated(incoming: incoming, outgoing: outgoing, outgoingCheckColor: outgoingSecondary)

    let inputPanel = base.chat.inputPanel.withUpdated(
        panelBackgroundColor: UIColor(rgb: 0x000000, alpha: 0.0),
        panelBackgroundColorNoWallpaper: UIColor(rgb: 0x000000, alpha: 0.0),
        panelSeparatorColor: UIColor(rgb: 0x000000, alpha: 0.0),
        panelControlAccentColor: p.volt,
        panelControlColor: p.ink,
        panelControlDisabledColor: p.ink3,
        panelControlDestructiveColor: p.destructive,
        inputBackgroundColor: p.card.withAlphaComponent(0.0),
        inputStrokeColor: p.hairline,
        inputPlaceholderColor: p.ink3,
        inputTextColor: p.ink,
        inputControlColor: p.ink2,
        actionControlFillColor: p.volt,
        actionControlForegroundColor: p.onVolt,
        mediaRecordingDotColor: p.destructive,
        mediaRecordingControl: base.chat.inputPanel.mediaRecordingControl.withUpdated(buttonColor: p.volt)
    )

    let historyNavigation = base.chat.historyNavigation.withUpdated(
        fillColor: p.page.withAlphaComponent(0.9),
        strokeColor: p.hairline,
        foregroundColor: p.ink,
        badgeBackgroundColor: p.volt,
        badgeTextColor: p.onVolt
    )

    let chat = base.chat.withUpdated(
        defaultWallpaper: wallpaper,
        message: message,
        serviceMessage: astraFolioServiceMessage(base.chat.serviceMessage, palette: p),
        inputPanel: inputPanel,
        historyNavigation: historyNavigation
    )

    let dimColor = dark ? UIColor(rgb: 0x000000, alpha: 0.55) : UIColor(rgb: 0x0B0B0C, alpha: 0.40)
    let actionSheet = base.actionSheet.withUpdated(
        dimColor: dimColor,
        backgroundType: dark ? .dark : .light,
        opaqueItemBackgroundColor: p.elevated,
        itemBackgroundColor: p.elevated.withAlphaComponent(0.96),
        opaqueItemHighlightedBackgroundColor: p.highlight,
        itemHighlightedBackgroundColor: p.highlight,
        opaqueItemSeparatorColor: p.hairline,
        standardActionTextColor: p.volt,
        destructiveActionTextColor: p.destructive,
        disabledActionTextColor: p.ink3,
        primaryTextColor: p.ink,
        secondaryTextColor: p.ink2,
        controlAccentColor: p.volt,
        inputBackgroundColor: p.page,
        inputPlaceholderColor: p.ink3,
        inputTextColor: p.ink,
        checkContentColor: p.onVolt
    )

    // The context menu's `withUpdated` does not reach the badge and extracted-content colours, so the menu is built
    // with its (module-internal) initializer.
    let contextMenu = PresentationThemeContextMenu(
        dimColor: dimColor,
        backgroundColor: p.elevated.withAlphaComponent(0.88),
        itemSeparatorColor: p.hairline,
        sectionSeparatorColor: p.page,
        itemBackgroundColor: UIColor(rgb: 0x000000, alpha: 0.0),
        itemHighlightedBackgroundColor: p.highlight,
        primaryColor: p.ink,
        secondaryColor: p.ink2,
        destructiveColor: p.destructive,
        badgeFillColor: p.volt,
        badgeForegroundColor: p.onVolt,
        badgeInactiveFillColor: p.hairline,
        badgeInactiveForegroundColor: p.ink,
        extractedContentTintColor: p.ink
    )

    let inAppNotification = base.inAppNotification.withUpdated(
        fillColor: p.elevated,
        primaryTextColor: p.ink,
        expandedNotification: base.inAppNotification.expandedNotification.withUpdated(backgroundType: dark ? .dark : .light)
    )

    // 4. The whole theme, rebuilt.
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

    // 5. Bubble-free mode, then the inverse chips once more (bubble-free mode overwrites them with gray pills).
    if !bubbleMode {
        theme = bubblelessPresentationTheme(theme)
        theme = theme.withUpdated(chat: theme.chat.withUpdated(serviceMessage: astraFolioServiceMessage(theme.chat.serviceMessage, palette: p)))
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
    let _ = astraFolioMarkers.modify { markers in
        var markers = markers
        markers.insert(chartIdentifier)
        return markers
    }

    let result = theme
    let _ = astraFolioThemes.modify { themes in
        var themes = themes
        themes[key] = result
        return themes
    }
    return result
}
