# AstraGram 2027 — «Folio» redesign specification

Status: final spec, the single source of truth for the implementation team. Phase 1 was read-only; nothing here has been built yet.
Paths are relative to `submodules/` unless they start with `docs/` or `TelegramUI/Sources`. Line numbers come from the hook map. They are anchors: search the quoted code before editing, because lines drift.

---

## 1. Name, concept, principles

**Name:** AstraGram Folio. Settings label: «Дизайн 2027 «Folio»» / "Design 2027 “Folio”". Flag: `design2027`.

**Concept.** AstraGram is set like a good magazine page, not a glass toy. Ink on paper, with one electric colour, **Klein Volt** (`#3D2BFF` light / `#8B7DFF` dark). Glass stays, because iOS 26 is built on it, but it is frosted down to matte coated stock with a hairline rim. The look is a counter-trend to 2025–26 "liquid" maximalism: calm, high-contrast, typographic. That is the 2027 move.

**Principles (every surface, no exceptions):**

1. **One accent, three meanings.** Volt marks only (a) what is yours (outgoing bubbles, your selection), (b) what needs you (unread counts, unread date, the send button, the selected tab) and (c) what you can tap (links, switches, primary actions). Everything else is ink, paper and hairlines. No second accent and no gradients in the UI chrome.
2. **Type does the work.** Bold, slightly tight titles. Small metadata with **tabular digits wherever a number can change** (dates, times, badges, counters, durations). Chips use uppercase with tracking. Weights are limited to Regular, Medium, Semibold and Bold. No Light, no Heavy.
3. **Two shapes: slab and pill.** *Slabs* are containers: continuous corners of 8–22pt, never full capsules (bubbles, cards, menus, sheets, the input field, toasts, chips). *Pills* are controls: full capsules or circles (buttons, badges, switches, send/attach/mic, tabs, avatars, the title capsule).
4. **Three depth planes (from Aurora).** Z0 is the page: paper or ink, flat. Z1 is the slabs: cards, rows and bubbles, with **no shadows**, only a tone step and hairlines. Z2 is floating controls: tab bar, input, nav capsules, menus, sheets, toasts. They get frosted glass with a **rim**, and the non-native ones get a soft Z2 shadow placed on a sibling layer. Depth is shown by the rim and the tone step, never by glow.
5. **Contrast is checked.** All body and meta text meets WCAG AA (4.5:1) on its own background. Only placeholders and disabled text drop to 3:1.
6. **Behind one flag, reversible.** With `design2027 == false`, every code path is byte-for-byte stock AstraGram. Every geometry change is `AstraLook.design2027 ? folio : stock`, with the stock value kept literally in the else branch.

**Signature moves (why it is unmistakably not Telegram):** no Telegram blue; tailless bubbles with 16/4 "typeset column" corners; inverse-ink date and service chips in tracked uppercase; flat print-set avatar placeholders; flat monochrome settings tiles; the 1pt ink rule under the profile title (used in only two places in the app); volt as the only colour.

**Grafts taken from the runners-up:** the Z0/Z1/Z2 depth rule, the top-lit rim overlay and Z2 shadows on a sibling container (Aurora); a pinned-row plate in `contextContainer` and a press plate that reuses the springPresses branch at the same radius (Aurora/Jelly); the badge-appear pop, the Reduce Motion fallback and light haptics (Jelly); the `astraNoOutgoingTail` field on the bubble-corners struct, a computed `isEnabled` so the toggle is live, an optional sub-option for the costly or "living" part, and the legacy glass path skipping the rim (Stellar); greying out the glass-material row while Folio is on (Aurora); keeping ResizableSheet 40 and AttachmentContainer 38 so sheets stay concentric with the device corner (judges' caveat on Folio).

---

## 2. Tokens

### 2.1 Colour — core ramp

| Token | Light «Paper» | Dark «Ink» | Notes / contrast |
|---|---|---|---|
| `page` (Z0) | `#F7F6F2` | `#0B0B0C` | app, list blocks and chat list background |
| `card` (Z1) | `#FFFFFF` | `#161618` | list cards, plain list background |
| `elevated` (Z2 solid) | `#FFFFFF` | `#1E1E21` | sheets, action sheet, alerts and legacy menus |
| `wallpaper` | `#EFEEE9` | `#0B0B0C` | default chat wallpaper, solid |
| `pinned` | `#EFEEE9` | `#121214` | pinned chat row plate |
| `highlight` | `#E7E6E0` | `#222226` | pressed rows and items |
| `ink` (text primary) | `#0B0B0C` | `#F4F3EE` | 18.6:1 / 17.9:1 |
| `ink2` (text secondary) | `#5C5B57` | `#9C9B96` | 6.3:1 on page (L); 6.5:1 on card (D) |
| `ink3` (placeholder/disabled) | `#8A8984` | `#6E6D69` | 3:1+, **never body text** (dark value lightened from `#64635F` so it clears 3:1 on card) |
| `inverse` | `#F7F6F2` | `#0B0B0C` | text on ink and paper chips |
| `hairline` | `#E3E2DD` | `#26262A` | every separator |
| `rule` (1pt editorial rule) | `#0B0B0C` | `#F4F3EE` | used in exactly 2 places |
| `volt` (accent) | `#3D2BFF` | `#8B7DFF` | 6.5:1 on paper; 6.1:1 on ink |
| `voltPressed` | `#2C1FD6` | `#7565FF` | |
| `voltWash` | `#ECEAFF` | `#221E45` | selected rows, lens, active reaction on incoming |
| `onVolt` (text on volt) | `#FFFFFF` (7.0:1) | `#0B0B0C` (6.1:1) | |
| `destructive` | `#E5162D` | `#FF4D5E` | 4.7:1 / 6.0:1 |
| `online` / `success` | `#00A86B` | `#2EE59D` | |
| `warning` | `#B25E00` | `#FFB347` | |

### 2.2 Colour — PresentationTheme slot mapping

Field names are from `TelegramPresentationData/Sources/PresentationTheme.swift`. For `PresentationThemeList`, verify the exact field names at :555 (`withUpdated`). Any slot not listed **keeps the value produced by `customizePresentationTheme`** with accent = volt.

**rootController**
- `tabBar`: backgroundColor = page @ 0.0 (glass draws it); separatorColor `#00000000`; iconColor = ink; selectedIconColor = volt; textColor = ink2; selectedTextColor = volt; badgeBackgroundColor = volt; badgeStrokeColor = page; badgeTextColor = onVolt.
- `navigationBar`: buttonColor = volt; disabledButtonColor = ink3; primaryTextColor = ink; secondaryTextColor = ink2; controlColor = ink2; accentTextColor = volt; blurredBackgroundColor = page @ 0.92; opaqueBackgroundColor = page; separatorColor = hairline; badgeBackground/Stroke/Text = volt/page/onVolt; segmentedBackgroundColor = hairline; segmentedForegroundColor = card; segmentedTextColor = ink; segmentedDividerColor = hairline; clearButtonBackgroundColor = ink3 @ 0.3; clearButtonForegroundColor = ink.
- `navigationSearchBar`: backgroundColor = page; inputFillColor = card (light) or `#1E1E21` (dark); inputTextColor = ink; inputPlaceholderTextColor = ink3; inputIconColor = ink2; accentColor = volt.

**list**
- blocksBackgroundColor = page; plainBackgroundColor = card; itemBlocksBackgroundColor = card; itemModalBlocksBackgroundColor = card (L) / elevated (D); itemHighlightedBackgroundColor = highlight.
- itemPrimaryTextColor = ink; itemSecondaryTextColor = ink2; itemDisabledTextColor = ink3; itemPlaceholderTextColor = ink3; itemAccentColor = volt; itemHighlightedColor = volt; itemDestructiveColor = destructive.
- itemBlocksSeparatorColor = hairline; itemPlainSeparatorColor = hairline; disclosureArrowColor = ink3; sectionHeaderTextColor = ink2; freeTextColor = ink2; freeTextErrorColor = destructive; freeTextSuccessColor = online.
- itemSwitchColors: frameColor = hairline (L) / `#2A2A2E` (D); handleColor `#FFFFFF`; contentColor = volt; positiveColor = online; negativeColor = destructive.
- itemCheckColors: fill = volt, foreground = onVolt, stroke = ink3.

**chatList**
- backgroundColor = page; itemBackgroundColor = page; itemSeparatorColor = hairline; pinnedItemBackgroundColor = pinned; itemHighlightedBackgroundColor = highlight; pinnedItemHighlightedBackgroundColor = highlight; itemSelectedBackgroundColor = voltWash.
- titleColor = ink; secretTitleColor = online; dateTextColor = ink2; authorNameColor = ink; messageTextColor = ink2; messageHighlightedTextColor = ink; messageDraftTextColor = destructive; checkmarkColor = volt; pendingIndicatorColor = ink3; failedFillColor = destructive; failedForegroundColor `#FFFFFF`; muteIconColor = ink3.
- unreadBadgeActiveBackgroundColor = volt; unreadBadgeActiveTextColor = onVolt; unreadBadgeInactiveBackgroundColor = hairline (L) / `#2A2A2E` (D); unreadBadgeInactiveTextColor = ink; reactionBadgeActiveBackgroundColor = volt; pinnedBadgeColor = ink3.
- pinnedSearchBarColor = card; regularSearchBarColor = card; sectionHeaderFillColor = page; sectionHeaderTextColor = ink2.
- verifiedIconFillColor = volt; verifiedIconForegroundColor = onVolt; secretIconColor = online; pinnedArchiveAvatarColor = volt / `#3D2BFF`; unpinnedArchiveAvatarColor = ink3.
- onlineDotColor = online.
- storyUnseenColors = [volt, volt] (flat, no gradient); storyUnseenPrivateColors = [online, online]; storySeenColors = [`#C9C8C2`, `#C9C8C2`] (L) / [`#3A3A3F`, `#3A3A3F`] (D).

**chat.message.incoming** (`PresentationThemePartedColors`)
- bubble.withWallpaper and bubble.withoutWallpaper: fill [`#FFFFFF`] (L) / [`#1C1C1F`] (D); highlightedFill = highlight; stroke `#00000000` (the hairline is drawn by the rim, §2.6); shadow nil.
- primaryTextColor = ink; secondaryTextColor `#6B6A65` (5.3:1) (L) / `#9C9B96` (D); linkTextColor = volt; linkHighlightColor = volt @ 0.2; accentTextColor = volt; accentControlColor = volt; mediaActiveControlColor = volt; fileTitleColor = ink; fileDescriptionColor = ink2; fileDurationColor = ink2; textSelectionColor = volt @ 0.2; textSelectionKnobColor = volt.
- reactionInactiveBackground `#EFEEE9` (L) / `#26262A` (D); reactionInactiveForeground = ink; reactionActiveBackground = volt; reactionActiveForeground = onVolt.

**chat.message.outgoing**
- bubble fill: **a single stop** [volt] (this keeps the knockout gradient path off); highlightedFill = voltPressed; stroke clear; shadow nil.
- primaryTextColor = onVolt; secondaryTextColor `#D9D5FF` (L, 5.0:1) / `#1F1A4D` (D, 4.9:1); linkTextColor = onVolt (underlined, see §4 WP2); accentTextColor = onVolt; accentControlColor = onVolt; mediaActiveControlColor = onVolt; fileTitleColor = onVolt; fileDescriptionColor = secondary; checks: `chat.message.outgoingCheckColor` = secondary.
- Reply/quote bar: onVolt @ 0.60 (L) / ink @ 0.55 (D).
- reactionInactiveBackground `#2C1FD6` (L) / `#7565FF` (D); reactionInactiveForeground = onVolt; reactionActiveBackground `#FFFFFF` (L) / `#0B0B0C` (D); reactionActiveForeground = volt.

**chat.serviceMessage** (inverse chips; use the `bubblelessPresentationTheme` pattern, `BubblelessPresentationTheme.swift:52`)
- components.withDefaultWallpaper / withCustomWallpaper: fill `#2A2A2A` (L: ink @ 0.86 over the wallpaper) / `#F4F3EE` @ 0.92 (D); primaryText `#F7F6F2` (L, 12.9:1) / `#0B0B0C` (D, ~16:1); linkHighlight = volt @ 0.3; dateFillStatic = the same as fill; dateFillFloating = fill @ 0.9.
- dateTextColor: the same as primaryText.

**chat.inputPanel**
- panelBackgroundColor and panelBackgroundColorNoWallpaper = clear (the glass draws it); panelSeparatorColor clear; panelControlAccentColor = volt; panelControlColor = ink; panelControlDisabledColor = ink3; panelControlDestructiveColor = destructive.
- inputBackgroundColor = card @ 0.0 (glass); inputStrokeColor = hairline; inputPlaceholderColor = ink3; inputTextColor = ink; inputControlColor = ink2.
- actionControlFillColor = volt; actionControlForegroundColor = onVolt; mediaRecordingDotColor = destructive; mediaRecordingControl: activeFill = volt.

**chat.historyNavigation**: fillColor = page @ 0.9; strokeColor = hairline; foregroundColor = ink; badgeBackgroundColor = volt; badgeTextColor = onVolt.

**actionSheet**: dimColor `#0B0B0C` @ 0.40 (L) / `#000000` @ 0.55 (D); backgroundType .light / .dark; opaqueItemBackgroundColor = elevated; itemBackgroundColor = elevated @ 0.96; opaqueItemHighlightedBackgroundColor = highlight; itemHighlightedBackgroundColor = highlight; opaqueItemSeparatorColor = hairline; standardActionTextColor = volt; destructiveActionTextColor = destructive; disabledActionTextColor = ink3; primaryTextColor = ink; secondaryTextColor = ink2; controlAccentColor = volt; inputBackgroundColor = page; inputPlaceholderColor = ink3; inputTextColor = ink; checkContentColor = onVolt.

**contextMenu**: dimColor = the same as actionSheet; backgroundColor = elevated @ 0.88 (used under glass); itemSeparatorColor = hairline; sectionSeparatorColor = page; itemBackgroundColor clear; itemHighlightedBackgroundColor = highlight; primaryColor = ink; secondaryColor = ink2; destructiveColor = destructive; badgeFillColor = volt; badgeForegroundColor = onVolt; badgeInactiveFillColor = hairline; badgeInactiveForegroundColor = ink; extractedContentTintColor = ink.

**inAppNotification**: fillColor = elevated; primaryTextColor = ink; expandedNotification backgroundType per mode.

**Avatar placeholder print set** (replaces Telegram's two-stop gradients; see WP5): light `#3D2BFF, #E5162D, #00A86B, #B25E00, #0B0B0C, #7A3CFF, #0E7C86`; dark `#8B7DFF, #FF4D5E, #2EE59D, #FFB347, #F4F3EE, #B08CFF, #3FC7D1`. Initials `#FFFFFF` on light fills and `#0B0B0C` on dark fills. **User-chosen peer name colours (`PeerNameColors` for names and reply bars) stay stock**, because they carry meaning; only the placeholder fill is flattened.

**Optional «Живой фон» wallpaper** (sub-option, default off): Telegram 4-stop `.gradient`, no pattern, with native rotation on send. Light `#EFEEE9, #E8E6F6, #F3F1EA, #E4E2F8`; dark `#0B0B0C, #15122E, #0E0E10, #1B1745`. Bubbles stay single-stop volt.

### 2.3 Glass tint (`GlassBackgroundView.astraMaterialTint`, Folio branch)

| Kind | Light | Dark |
|---|---|---|
| `.panel` → `.custom(style: .default, color:)` | `#F7F6F2` @ 0.72 | `#0B0B0C` @ 0.70 |
| `.clear` → custom | `#F7F6F2` @ 0.55 | `#0B0B0C` @ 0.55 |
| `.untinted` (tab bar, lens bars) → custom | `#F7F6F2` @ 0.45 | `#0B0B0C` @ 0.40 |
| `.custom` / accent tints | unchanged | unchanged |
| Rim stroke (top → bottom) | ink @ 0.10 → ink @ 0.10 (uniform hairline) plus an inner top highlight white @ 0.70 → 0 at 40% height | white @ 0.16 → white @ 0.06 |
| LiquidLens fill | volt @ 0.12 | volt @ 0.18 |

Blur stays native. Never use `nativeBlurRadius` (private API).

### 2.4 Typography

SF Pro (**not Rounded**). There is no global font reroute and no restart for fonts. Use `Font.with(size:design:.regular, weight:, traits: .monospacedNumbers)` for tabular digits. Sizes are bases at the 17pt list size and scale with the existing `baseDisplaySize / 17` ratios. Tracking is `NSAttributedString.Key.kern` in pt.

| Role | Spec | Stock |
|---|---|---|
| Profile name (display) | 30 Bold, kern −0.4 | Medium 28 |
| Nav title / chat-list header word | 17 Bold | Semibold 17 |
| Chat title capsule | 17 Bold, monospaced digits | Semibold 17 |
| Chat title subtitle | 13 Medium, ink2 ("online" in volt) | Regular 13 |
| Chat list title | 17 Bold (`floor(base*17/17)`) | Semibold 16 |
| Chat list preview | 15 Regular, ink2; author name inline 15 Semibold ink | |
| Chat list date | 13 Medium tabular, ink2; **unread → 13 Semibold volt** | Regular 14 |
| Chat list badge | 13 Bold tabular | |
| Folder tab | 15 Semibold (selected) / 15 Medium | Medium 15 |
| Folder counter | 12 Bold tabular | Medium 12 |
| Message body | 17 Regular (user scale) | same |
| Group sender name | 14 Bold | |
| Message time | 11 Medium tabular | |
| Date chip | 11 Semibold, UPPERCASE, kern +0.8 ("23 НОЯБРЯ") | Medium 13 |
| Service message | 13 Medium, emphasis 13 Bold | Regular / Semibold 13 |
| List section header | 12 Semibold, UPPERCASE, kern +0.9, ink2, inset 20 | inset 15 |
| List row title / value | 17 Regular / 17 Regular ink2 | |
| List footer | 13 Regular ink2, inset 20, line height ×1.25 | inset 15 |
| Action sheet button | 19 Medium; destructive and cancel 19 Semibold | 20 Regular |
| Context menu item / secondary | 17 Regular / 14 Regular | |
| Alert title / body / buttons | 18 Bold / 15 Regular / primary 17 Semibold, others 17 Regular | |
| Toast | 15 Medium | |
| Profile header button label | 12 Medium | |

### 2.5 Radii (all `cornerCurve = .continuous`), centralised in `AstraLook`

| Constant | Value | Stock | Where |
|---|---|---|---|
| `bubbleMain` / `bubbleAux` | 16 / 4 | user's / 8-ish | PresentationChatBubbleCorners |
| `bubbleMedia` / `bubbleMediaMerged` | 15 / 4 | 15 / 7 | ChatMessageItemCommon |
| `chipRadius` | 8 | h/2 | date chip (both paths) |
| `serviceRadius` | 8 | 11 | service chip inner and outer |
| `inputRadius` | 16 | minH*0.5 | input slab |
| `cardRadius` | 20 | 26 | cornersImage; PeerInfo container 20, clip 19.25 |
| `rowPlateRadius` | 16 | 24 (springPresses) | chat-list press and pinned plates |
| `menuRadius` | 22 | min(30, h/2) | ContextControllerActionsStackNode |
| `menuHighlightRadius` | 12 | min(20, h/2) | menu item highlight |
| `legacyMenuRadius` | 16 | 10 | Display ContextMenuContainerNode |
| `sheetGroupRadius` | 22 | 16 | ActionSheetItemGroupNode clip **and** dim cutout |
| `alertRadius` | 28 | 35 | AlertComponent |
| `legacyAlertRadius` | 20 | 14 | AlertControllerNode |
| `modalRadius` | 16 | 10 | NavigationModalContainer |
| `toastRadius` | 16 | 25 | UndoOverlay; ToastContent `min(16, h/2)` |
| `profileButtonRadius` | 16 | min(16, h/2) | PeerInfoHeaderButtonNode (already the default; verify) |
| `settingsIconRadius` | 9 | 8 | 30×30 tiles |
| **Unchanged** | ResizableSheet 40, AttachmentContainer 38, NavigationModalFrame 38, AttachmentPanel lens 28, tab bar and folder capsules, avatars round | | concentric with the device corner |

Hard caps: the bubble radius must stay ≤ 16.5 (33pt image); cornersImage ≤ 28 (56px image).

### 2.6 Spacing, strokes, shadows, dims

- **Grid:** 4pt. Allowed: 4, 8, 12, 16, 20, 28, 32. Side margins stay **16** (iPhone Duo safe; `listSideMargins` and `peerInfoSideInsets` untouched).
- **Bubbles:** defaultSpacing 4 (stock 2+px); mergedSpacing 1 (0); text insets 8 vertical / 12 horizontal (6/11); edgeInset 3 (stock).
- **List rhythm** (`itemListNeighborsGroupedInsets`): first top 20, between sections 28, reduced 12, last bottom 32. Settings root `sectionSpacing` 20.
- **Chat list row:** height +4 (2 top, 2 bottom); avatar 60, left edge 16, text inset 24 + d (all stock); hairline separators 1px from the text inset to 16 before the right edge.
- **Incoming bubble rim:** 0.75pt, ink @ 0.08 (L) / white @ 0.08 (D), via `astraOutlineColor`. Outgoing: none. The anti-delete red outline (1.5pt) always wins.
- **Z2 shadows** (only context menu, action sheet, toast and legacy alert; never on native glass, never on clipped layers; placed on a sibling or container layer): `#000000`, opacity 0.10 (L) / 0.40 (D), radius 24, y 8.
- **No** glows, coloured shadows, bubble shadows or card shadows.
- **Dims:** `#0B0B0C` @ 0.40 (L) / `#000000` @ 0.55 (D) for SheetComponent (0.4), ResizableSheet (0.4) and AttachmentController (0.25 → 0.40).
- **Nav edge fade:** edgeEffectColor = page, tint alpha 0.92 (stock 0.85), edge length 54 unchanged.
- **Editorial rule:** a 1pt (one point, not one pixel) `rule` line. It appears only (1) under the profile title block, inset 16, and (2) between the settings-root header and its first card.

### 2.7 Motion

Still and precise. Durations are in seconds.

| Event | Spec |
|---|---|
| Press down (`AstraLook.press`, HighlightableButton) | scale 0.97, 0.10 ease-out. Forced on under Folio regardless of `springPresses`. |
| Release | spring response 0.34, damping 0.80 (no overshoot) |
| Row press plate | fade in 0.12, fade out 0.22 ease-out |
| Badge appear (0 → n) | scale 0.6 → 1.08 → 1.0, keyframes 0 / 0.6 / 1, 0.30 easeOut |
| Badge count change | stock crossfade 0.18 with scale 0.9 → 1.0 |
| Toast in / out | 0.25 ease-out, rising 12pt |
| Theme toggle | stock PresentationData crossfade (~0.3) |
| Lens, context-menu morph, sheet present, nav push | stock; only radii and colours change |
| «Живой фон» (opt-in) | Telegram's native 4-stop rotation on send, at no extra cost |
| Haptics | `UIImpactFeedbackGenerator(style: .light)` on the Folio toggle and on send (only if stock does not already fire one at send) |
| Reduce Motion | every Folio spring becomes 0.2 easeInOut; no badge pop; no toast rise (fade only) |

---

## 3. Architecture

### 3a. Settings — `TelegramCore/Sources/AstraGram/AstraGramSettings.swift`

Add two fields in the **five places** next to `monochrome` (property ~92, default ~201, init param ~275, assignment ~347, decode ~424):

```swift
public var design2027: Bool                 // default false
public var design2027LivingWallpaper: Bool  // default false
...
self.design2027 = try container.decodeIfPresent(Bool.self, forKey: .design2027) ?? d.design2027
self.design2027LivingWallpaper = try container.decodeIfPresent(Bool.self, forKey: .design2027LivingWallpaper) ?? d.design2027LivingWallpaper
```

CodingKeys and encode are synthesized, so old saves decode to off.

### 3b. Settings UI — `AstraGramUI/Sources/AstraGramSettingsController.swift` (look section, :734+)

**Free ids are 125–129 and 142+; 123 and 124 are taken** (astraBadgeClear, streaks).

```swift
entries.append(.header(id: 110, ...))
entries.append(.flag(id: 125, section: .look, title: strings.design2027, value: settings.design2027, enabled: true, keyPath: \.design2027))
if settings.design2027 {
    entries.append(.flag(id: 126, section: .look, title: strings.design2027LivingWallpaper, value: settings.design2027LivingWallpaper, enabled: true, keyPath: \.design2027LivingWallpaper))
    if settings.design2027 != AstraLook.design2027AtLaunch {
        entries.append(.button(id: 127, section: .look, title: strings.restartApp, label: "", kind: .restartApp))
    }
}
entries.append(.flag(id: 111, ... \.monochrome))   // existing
```

- **Mutual exclusion:** in the flag-toggle handler (where keyPath flags are written, near the glassMaterial handlers at :517/:853), turning `design2027` on sets `monochrome = false`, and turning `monochrome` on sets `design2027 = false`. Do it in the same `AstraGramSettings.update` transaction.
- **Glass material row (id 119):** while `design2027` is on, show the label `strings.glassMaterialFolio` («Folio») and make the `.glassMaterial` handler return early, so the row is greyed in effect. If `.button` supports `enabled`, pass false.
- Show the restart row also when the value was turned **off** and differs from launch (settings icons are a launch constant).
- **Strings** (`AstraStrings.swift` near :264):
  - `design2027 = t("Дизайн 2027 «Folio»", "Design 2027 “Folio”")`
  - `design2027LivingWallpaper = t("Живой фон чата", "Living chat background")`
  - `design2027Footer = t("Чернила, бумага и один электрический акцент. Новые формы сообщений, меню и карточек. Иконки настроек обновятся после перезапуска.", "Ink, paper and one electric accent. New message, menu and card shapes. Settings icons update after restart.")`. Append it to the `lookFooter` text when the flag is on, or add a footer entry.
  - `glassMaterialFolio = t("Folio", "Folio")`

### 3c. Display flag — `Display/Source/AstraLook.swift` and `TelegramUI/Sources/AppDelegate.swift`

`AstraLook` additions (one place for every constant):

```swift
public static var design2027: Bool = false            // live
public static var design2027AtLaunch: Bool = false    // set once; restart-only resources
public static var livingWallpaper: Bool = false
public enum Folio {
    public static let bubbleMain: CGFloat = 16, bubbleAux: CGFloat = 4
    public static let bubbleMedia: CGFloat = 15, bubbleMediaMerged: CGFloat = 4
    public static let chipRadius: CGFloat = 8, serviceRadius: CGFloat = 8, inputRadius: CGFloat = 16
    public static let cardRadius: CGFloat = 20, cardClipRadius: CGFloat = 19.25, rowPlateRadius: CGFloat = 16
    public static let menuRadius: CGFloat = 22, menuHighlightRadius: CGFloat = 12, legacyMenuRadius: CGFloat = 16
    public static let sheetGroupRadius: CGFloat = 22, alertRadius: CGFloat = 28, legacyAlertRadius: CGFloat = 20
    public static let modalRadius: CGFloat = 16, toastRadius: CGFloat = 16, settingsIconRadius: CGFloat = 9
    public static let dimLight = UIColor(rgb: 0x0B0B0C).withAlphaComponent(0.40)
    public static let dimDark = UIColor(white: 0.0, alpha: 0.55)
    public static func z2Shadow(_ layer: CALayer, dark: Bool) { /* #000, 0.10/0.40, r24, y8 */ }
}
```

- `press(_:down:)`: change the guard to `guard AstraLook.springPresses || AstraLook.design2027, ...`. When `design2027` is on, use scale 0.97 (instead of `pressedScale`) with release spring response 0.34 / damping 0.80. When `UIAccessibility.isReduceMotionEnabled`, use a 0.2 easeInOut basic animation.
- **AppDelegate** (:511–525): at launch set `AstraLook.design2027 = current.design2027`, `AstraLook.design2027AtLaunch = current.design2027` and `AstraLook.livingWallpaper = current.design2027LivingWallpaper`. Extend the live tuple `(Int, Bool, Bool)` → `(Int, Bool, Bool, Bool, Bool)` with `design2027` and `design2027LivingWallpaper`, and assign them in the sink (not `AtLaunch`).
- The ordering is already safe: this runs before `currentPresentationDataAndSettings` (AppDelegate:1217).
- **Live correctness:** Display statics are read only on the next `update()` (Glass `Params` equality at :818). The PresentationData swap (§3d) forces every screen to relayout, so the toggle is live everywhere except the settings icons.
- For ChatListUI and other TelegramCore-aware modules, read `AstraLook.design2027` (computed at the read site, never a `static let`) so it follows live.

### 3d. Theme — new file `TelegramPresentationData/Sources/AstraFolioTheme.swift`

```swift
private let astraFolioThemes = Atomic<[Int: PresentationTheme]>(value: [:])
public func makeAstraFolioPresentationTheme(dark: Bool, bubbleMode: Bool, livingWallpaper: Bool) -> PresentationTheme
```

- Cache key: `(dark ? 1 : 0) | (bubbleMode ? 2 : 0) | (livingWallpaper ? 4 : 0)`. Never mutate a cached theme. A fresh instance makes per-theme resources (cornersImage, badges, bubble images) regenerate.
- Pipeline:
  1. `makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)`.
  2. `customizePresentationTheme(_, editing: true, accentColor: volt, outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [voltRGB], animateBubbleColors: nil, wallpaper: folioWallpaper)`.
  3. Restyle with the `withUpdated` helpers: RootTabBar (:88), RootNavigationBar (:157), NavigationSearchBar (:197), RootController (:217), ActionSheet (:272), ContextMenu (:310), Switch (:330), List (:555), ChatList (:698), BubbleColorComponents (:841), BubbleColor (:884), PartedColors (:1012), ChatMessage (:1056), ServiceMessage* (:1079/1110/1130), ChatInputPanel (:1206), HistoryNavigation (:1381), Chat (:1407), InAppNotification (:1461). All values come from §2.2.
  4. Rebuild with a full `PresentationTheme(name: .builtin(...) or custom "AstraFolio", index:, referenceTheme:, overallDarkAppearance: dark, intro:, passcode:, rootController:, list:, chatList:, chat:, actionSheet:, contextMenu:, inAppNotification:, chart:, preview:)`, as at PresentationTheme.swift:1650.
  5. If `!bubbleMode`, run `bubblelessPresentationTheme(theme)`, then re-apply the serviceMessage restyle (bubbleless overwrites it).
- Add a public marker so resources can ask without string-matching names: `public extension PresentationTheme { var isAstraFolio: Bool }`, backed by a module-private `NSHashTable`/`ObjectIdentifier` set filled on creation. Do not compare theme names.
- `folioWallpaper`: `.color(0xEFEEE9 / 0x0B0B0C)`, or `.gradient` with the §2.2 «Живой фон» stops when `livingWallpaper` is on.

### 3e. PresentationData — `TelegramPresentationData/Sources/PresentationData.swift`

1. **PresentationChatBubbleCorners (:67):** add `public var astraNoOutgoingTail: Bool = false` with a default in init, so all existing call sites compile unchanged. It must participate in `==`.
2. **Initial load (:411):** add a block **before** the monochrome block:
   ```swift
   if AstraGramSettings.current.design2027 {   // Folio wins over Monochrome
       let autoNight = automaticThemeShouldSwitchNow(...)
       let presentationData = astraFolioPresentationData(mediaBox:, themeSettings:, autoNightModeTriggered: autoNight, localizationSettings:, nameDisplayOrder:)
       return InitialPresentationDataAndSettings(...)
   }
   ```
3. **Live signal (:764):** the mask becomes `($0.monochrome ? 1 : 0) | ($0.monochromePlainBackground ? 2 : 0) | ($0.design2027 ? 4 : 0) | ($0.design2027LivingWallpaper ? 8 : 0)`. Before `if astraMonochrome` (:778), add `if (astraMonochromeState & 4) != 0 { ... }`, copying the monochrome block (applicationInForeground → automaticThemeShouldSwitch → map) and calling `astraFolioPresentationData`.
4. **Builder** `private func astraFolioPresentationData(...)`, copied from `astraMonochromePresentationData` (:942):
   - `dark = astraMonochromeIsDark(themeSettings:autoNightModeTriggered:)` (reuse it; it is public).
   - `bubbleMode = themeSettings.chatBubbleSettings.bubbleMode`.
   - `theme = makeAstraFolioPresentationTheme(dark:, bubbleMode:, livingWallpaper: AstraGramSettings.current.design2027LivingWallpaper)`.
   - `chatBubbleCorners = PresentationChatBubbleCorners(mainRadius: 16, auxiliaryRadius: 4, mergeBubbleCorners: true, hasTails: false, bubbleMode: bubbleMode, serifMessageText: <user's>, astraNoOutgoingTail: true)`.
   - Wallpaper: `astraChosenChatWallpaper(...)` (:974) if the user chose one, else `theme.chat.defaultWallpaper`.
   - Fonts, strings and formats exactly as in monochrome.
5. Precedence: Folio > Monochrome > bubbleless > stock. The UI also keeps the two exclusive.

---

## 4. Work packages (disjoint file ownership)

Each file belongs to exactly one package. If you need a change in a file you do not own, ask its owner. Every edit is `if AstraLook.design2027 { folio } else { stock }`, or a ternary with the stock literal. **WP0 lands first** (constants and flags), and everyone else codes against `AstraLook.design2027` and `AstraLook.Folio.*`.

### WP0 — Theme, settings and flag plumbing
**Owns:** `TelegramCore/Sources/AstraGram/AstraGramSettings.swift`, `AstraGramUI/Sources/AstraGramSettingsController.swift`, `AstraGramUI/Sources/AstraStrings.swift`, `Display/Source/AstraLook.swift`, `TelegramUI/Sources/AppDelegate.swift`, `TelegramPresentationData/Sources/PresentationData.swift`, **new** `TelegramPresentationData/Sources/AstraFolioTheme.swift` (and its BUILD entry if sources are not globbed), `Display/Source/HighlightableButton.swift` (only if `press` needs a call-site change).
**Changes:** everything in §3a–§3e and the press constants in §2.7.
**Acceptance:**
- The toggle appears in Оформление above Monochrome. Turning it on switches Monochrome off and the reverse.
- After toggling, an already-open chat list and an open chat recolour within ~0.3s without a restart.
- The «Живой фон» row appears only when Folio is on. The restart row appears when the value differs from launch.
- Killing and relaunching keeps the state. Turning it off restores stock colours exactly (screenshot diff vs. a pre-change build).
- An old settings blob without the keys loads as off.

### WP1 — Chat list, folder tabs, header, tab bar
**Owns:** `ChatListUI/Sources/Node/ChatListItem.swift`, `ChatListUI/Sources/Node/ChatListBadgeNode.swift` (if separate), `TelegramUI/Components/HorizontalTabsComponent/Sources/HorizontalTabsComponent.swift`, `TelegramUI/Components/ChatListHeaderComponent/Sources/ChatListNavigationBar.swift`, `TelegramUI/Components/TabBarComponent/Sources/TabBarComponent.swift`, `TabBarUI/Sources/TabBarContollerNode.swift`, `TelegramPresentationData/Sources/Resources/PresentationResourcesChatList.swift`.
**Changes:**
- ChatListItem :2458–2461: title `Font.bold(floor(base*17/17))`; text regular 15; date `Font.with(size: floor(base*13/17), weight: .medium, traits: .monospacedNumbers)`. **Unread** (any unread count > 0 and not muted-only): the date in `Font.with(... weight: .semibold, traits: .monospacedNumbers)` with colour `theme.list.itemAccentColor`. The preview author name is Semibold.
- Row height :4296: `+ (AstraLook.design2027 ? 4 : 0)`, split 2/2 (shift the content rect at :4314 by 2). Avatar diameter and edge are **unchanged** at both :2160 and :2728.
- Separators :5639–5662: hairline 1px, left = text inset, right inset 16. Keep them visible (Folio uses hairlines, not floating plates).
- Press plate :5731–5735: the branch fires on `AstraLook.springPresses || AstraLook.design2027`. Under Folio: inset 8 horizontally / 2 vertically, radius `Folio.rowPlateRadius` (16), continuous, colour `itemHighlightedBackgroundColor`, fade in 0.12 / out 0.22.
- Pinned rows: under Folio, clear `backgroundNode` (as AstraLiquidGlass does at :5706) and draw a new `astraPinnedPlateNode` as the **bottom subnode of `contextContainer`**. Frame = bounds inset by dx 8 / dy 2, radius 16, colour `pinnedItemBackgroundColor`. It slides with swipe and is hidden when Folio is off.
- Badge: text 13 Bold tabular. Add an appear pop (0.6 → 1.08 → 1.0 / 0.30, skipped under Reduce Motion) when the count goes from 0 to >0. No glow.
- Online dot: colour from the theme. The 2pt cutout uses the page colour (already theme-driven; verify).
- HorizontalTabsComponent :1326: `Font.semibold(15)` when selected, `Font.medium(15)` otherwise; counter :1401 `Font.with(size: 12, weight: .bold, traits: .monospacedNumbers)`. Height stays 46.
- ChatListNavigationBar :291: edge tint alpha `design2027 ? 0.92 : 0.85`; edge length 54 unchanged. The header title word in Bold (where the large/compact title font is set).
- TabBarComponent: **geometry unchanged** (56 + 2×4, side inset 21). The selected icon and label take volt from the theme. The lens fill comes from WP6. Verify that the `.untinted` frost keeps the lens visible.
- PresentationResourcesChatList :23: no change needed (flat badges come from theme colours). Badge text weight is handled in ChatListBadgeNode.
**Acceptance (screenshot, light and dark):**
- Paper `#F7F6F2` / ink `#0B0B0C` background with no backdrop view.
- Bold 17 titles; 13pt tabular dates, volt and semibold on unread rows.
- Volt pill badges with white (L) / ink (D) digits; grey pills for muted.
- Hairline separators starting at the text column.
- Pinned rows as an inset 16pt `#EFEEE9` slab that moves with a swipe.
- The press shows the same-shaped plate.
- The tab bar is a paper-frosted capsule with a volt selected icon.
- The story ring is a flat volt circle.
- Off: stock pixel-identical.

### WP2 — Chat bubbles and service messages
**Owns:** `TelegramPresentationData/Sources/PresentationThemeEssentialGraphics.swift`, `TelegramPresentationData/Sources/ChatMessageBubbleImages.swift` (verify only, no edits expected), `TelegramUI/Components/Chat/ChatMessageItemCommon/Sources/ChatMessageItemCommon.swift`, `TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift`, `ChatMessageBackground/Sources/ChatMessageBackground.swift`, `TelegramUI/Components/Chat/ChatMessageItemImpl/Sources/ChatMessageDateHeader.swift`, `TelegramUI/Components/Chat/ChatMessageActionBubbleContentNode/Sources/ChatMessageActionBubbleContentNode.swift`, `Components/ReactionButtonListComponent/Sources/ReactionButtonListComponent.swift`, the text bubble content node (for link underline on outgoing).
**Changes:**
- EssentialGraphics :273: `let outgoingTail = bubbleCorners.bubbleMode && !bubbleCorners.astraNoOutgoingTail`. Incoming is already tailless via `hasTails: false` (→ `.Extracted`). With `mergeBubbleCorners` and main ≥ 10, merged sides use aux 4, which gives the 16/4 typeset column. **Do not** touch `messageBubbleArguments` or `messageBubbleImage` merge rules.
- ChatMessageItemCommon :146 (compact) and :158 (regular), under the flag: defaultSpacing 4, mergedSpacing 1, text insets top/bottom 8 and left/right 12, image defaultCornerRadius 15, merged 4. edgeInset and avatarInset stay stock.
- ChatMessageBackground :101–153: make the ring `lineWidth` a stored parameter (default 1.5 = anti-delete), and include lineWidth in the ring cache key.
- ChatMessageBubbleItemNode :4504: if the anti-delete outline is active, keep existing behaviour (1.5pt red). **Else if** `AstraLook.design2027 && incoming && bubbleMode`, set `astraOutlineColor` = ink @ 0.08 (L) / white @ 0.08 (D) with lineWidth 0.75 and `astraFillAlpha` 1. **Else** set it to nil.
- Outgoing links: underline them (`.underlineStyle: .single`) when outgoing && Folio. The colour comes from the theme.
- ChatMessageDateHeader :329/:352/:372: `Font.semibold(floor(base*11/17))`, text uppercased with the current locale, kern 0.8. Geometry :458–476: **both** paths, backgroundNode (:464) and the glass island (:475), use corner radius `Folio.chipRadius` (8) and horizontal padding 10. Height stays `chatDateSize`.
- ChatMessageActionBubbleContentNode :488: `innerRadius: 8, outerRadius: 8`. Fonts :354–356: Medium 13 / Bold 13.
- ReactionButtonList: colours only via theme. No forced glass under Folio (flat pills); if stock glass is forced by the AstraGram glass setting, leave that logic alone.
**Acceptance:**
- In bubble mode: no tails on either side. A single bubble has 16pt corners. In a run of 3 outgoing messages, the right-side inner corners are 4pt.
- Outgoing is solid volt with white (L) / ink (D) text and underlined links. Incoming is white / `#1C1C1F` with a barely visible hairline.
- The date chip is an ink slab (L) / paper slab (D) with "23 НОЯБРЯ" uppercase tracked, radius 8. Service messages use the same inverse chip.
- Anti-delete messages still show the red outline.
- Bubbleless mode: still renders, service chips inverse, no crash.
- Media in bubbles clips to 15 / 4.

### WP3 — Chat input panel and chat header
**Owns:** `TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift`, `TelegramUI/Components/Chat/ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift`, `TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift`, `TelegramUI/Components/Chat/ChatAvatarNavigationNode/Sources/ChatAvatarNavigationNode.swift` (verify only), the history-navigation button node (scroll-to-bottom/mentions, colours only).
**Changes:**
- ChatTextInputPanelNode :3349: `cornerRadius: isAgentLayout ? 20 : (AstraLook.design2027 ? min(Folio.inputRadius, floor(minimalInputHeight*0.5)) : floor(minimalInputHeight*0.5))`. Attach (:3808), menu (:2805) and mic stay circles. The tint comes from the global hook (WP6).
- Send button (ChatTextInputActionButtonsNode :482–500 / glass variant :353): it stays a circle and the fill comes from `actionControlFillColor` (volt). Add a light haptic on the send tap under Folio, only if stock does not already fire one. **No gradient layer, no glow.**
- ChatTitleView :26–27: make `titleFont` and `subtitleFont` computed: `design2027 ? Font.with(size: 17, weight: .bold, traits: .monospacedNumbers) : <stock>`; subtitle `Font.medium(13)`. The "online" state colour is volt (from the theme accent; verify where the subtitle colour is chosen).
**Acceptance:**
- The input is a frosted paper slab with 16pt corners (not a capsule) when it is one line high, and stays 16pt when it grows.
- The attach and mic buttons are frosted circles. Send is a solid volt circle with a white (L) / ink (D) glyph.
- The title capsule is a frosted paper pill with a Bold 17 name and a Medium 13 subtitle; "online" is in volt.
- Scroll-to-bottom is a frosted circle with an ink glyph and a volt badge.

### WP4 — Item lists, settings, action sheets, context menus, alerts
**Owns:** `TelegramPresentationData/Sources/Resources/PresentationResourcesItemList.swift`, `TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift`, `ItemListUI/Sources/ItemListItem.swift`, `ItemListUI/Sources/Items/ItemListSectionHeaderItem.swift`, `ItemListUI/Sources/Items/ItemListTextItem.swift`, `Display/Source/ContextMenuContainerNode.swift`, `TelegramUI/Components/ContextControllerImpl/Sources/ContextControllerActionsStackNode.swift`, `Display/Source/ActionSheetItemGroupNode.swift`, `Display/Source/ActionSheetControllerNode.swift`, `Display/Source/ActionSheetButtonItem.swift`, `Display/Source/AlertControllerNode.swift`, `Display/Source/TextAlertController.swift` (fonts/button height), `TelegramUI/Components/AlertComponent/Sources/AlertComponent.swift`.
**Changes:**
- cornersImage :391: `let cornerRadius: CGFloat = glass ? (AstraLook.design2027 ? Folio.cardRadius : 26.0) : 11.0`. The cap of 28 is unchanged. The cache is per theme; the Folio theme is a new instance, so it redraws.
- itemListNeighborsGroupedInsets :97–128: 20 / 28 / 12 / 32 under the flag.
- Section header :180–183/:228/:252: inset 20, `Font.semibold(floor(base*12/17))`, `text.uppercased()`, kern 0.9, colour sectionHeaderTextColor. Keep the height formula.
- Footer (ItemListTextItem :162–172): inset 20, regular 13, paragraph lineHeightMultiple 1.25.
- Settings icons (PresentationResourcesSettings :7–35, :73, :122): add `private let astraFolioIcons = AstraGramSettings.current.design2027` (launch constant, like Monochrome :8). Under it, every `renderSettingsIcon` tile is a flat `#0B0B0C` fill, radius 9, white glyph, and a 0.5pt inner stroke of white @ 0.14 (so it reads on dark cards). **The AstraGram row tile is flat volt `#3D2BFF`.** If both Monochrome and Folio are somehow set, Folio wins. Restart is required (WP0 shows the row).
- Display ContextMenuContainerNode :68: `design2027 ? Folio.legacyMenuRadius : 10`.
- ContextControllerActionsStackNode :1580: container radius `design2027 ? min(Folio.menuRadius, h/2) : min(30, h/2)`; item highlight :1131 `min(12, h/2)` with a 6pt horizontal inset; sideInset 18 unchanged; fonts :231–239: 17 Regular / secondary 14 Regular. The Z2 shadow is applied to the stack's container (a sibling of the glass view), never to the glass.
- ActionSheetItemGroupNode :26 **and** :44: both `Folio.sheetGroupRadius` (22). ActionSheetControllerNode :5: containerInsets left/right 10, bottom 12. ActionSheetButtonItem :172: height 56; font :65–66/:153–155 `Font.medium(19)` (scaled); destructive and cancel `Font.semibold(19)`. The Z2 shadow goes on the group container.
- AlertControllerNode :51: 20. TextAlertController: button height 48 (:494); title Bold 18, body 15 Regular, primary action Semibold 17, others Regular 17 (:600–611).
- AlertComponent :602: radius `design2027 ? 28 : 35`; title, body and action fonts as above. The tint comes from the global hook.
**Acceptance:**
- Any settings screen: paper background, white / `#161618` cards with 20pt corners, no dark slivers at the corners, hairline separators.
- Headers "УВЕДОМЛЕНИЯ"-style uppercase tracked 12 Semibold at inset 20; footers at inset 20.
- 20/28 rhythm. Switches are volt when on, with a white thumb.
- After a restart, the settings root icons are ink tiles with white glyphs and the AstraGram tile is volt.
- Long-press on a message: a 22pt frosted slab menu with 12pt highlight plates and a soft shadow.
- An action sheet: 22pt groups, 56pt rows, Medium 19 volt text, red destructive, Semibold cancel.
- An alert: a 28pt glass slab with a Bold 18 title and Semibold volt primary.

### WP5 — Profile (PeerInfo) and avatars
**Owns:** `TelegramUI/Components/PeerInfo/PeerInfoScreen/Sources/PeerInfoScreen.swift`, `.../PeerInfoHeaderNode.swift`, `.../PeerInfoHeaderButtonNode.swift`, `.../PeerInfoScreenItemSectionContainerNode.swift`, `.../PeerInfoPaneContainerNode.swift`, `.../PeerInfoAvatarTransformContainerNode.swift` (verify only), `AvatarNode/Sources/AvatarNode.swift`, `AvatarNode/Sources/PeerAvatar.swift` (verify only), `AccountContext/Sources/PeerNameColors.swift` (verify only, see below).
**Changes:**
- PeerInfoScreenItemSectionContainerNode :69 / :174: under Folio, **always** take the rounded path (as if `astraTint != nil && hasCorners`), with radius 20, clip 19.25, continuous. Stock keeps 26 / 25.25 only with astraTint.
- PeerInfoScreen :5720: `sectionSpacing = design2027 ? 20 : 24`. Side insets are unchanged.
- PeerInfoHeaderNode :1415–1416: title `Font.bold(30)` plus kern −0.4 in the MultiScaleText attributes. Subtitles stay 16 Regular; online status in volt.
- PeerInfoHeaderNode, **the editorial rule:** add `astraFolioRuleLayer` (a CALayer, 1pt high, colour `rule`, inset 16 on both sides). Place it 12pt below the bottom of the title and subtitle block in the expanded/regular state. Fade it out with the same alpha as the subtitle during collapse, and hide it when the avatar is expanded or Folio is off.
- Buttons row :2343: `buttonSpacing = design2027 ? 6 : 8`. Height 58 is unchanged. PeerInfoHeaderButtonNode :331: the default branch is already `min(16, h/2)`, so verify it equals 16. `roundProfileButtons` keeps precedence if the user enabled it. Labels are 12 Medium. contextMenuSourcePath follows the shape.
- PeerInfoPaneContainerNode :1461: the tabs capsule is unchanged; the frost comes from the global tint.
- AvatarNode :85 (the placeholder colours, Monochrome precedent): when `AstraGramSettings.current.design2027`, replace the two-stop placeholder gradient with the flat print-set colour chosen by the same index Telegram uses (peer id mod 7), with initials in `#FFFFFF` (light) / `#0B0B0C` (dark). Dark is read from the theme's `overallDarkAppearance` if available at that call site; otherwise use the light set. **Avatar shape stays round everywhere.**
- PeerNameColors :117/:130: **no change** (name colours are user-meaningful). Only check that the Monochrome branch does not run when Folio is on (exclusive anyway).
- AstraGram extras (astraBubbleTint, astraSurface, astraAvatarRing, groove, flow overlay, music pill and vignette, astraSectionPresentationData / `astraSurfaceTheme` :7864) must keep working. Verify that `astraSurfaceTheme` derives from the presentation theme passed in (the Folio theme), not from a freshly built stock theme.
**Acceptance:**
- A profile: round 100pt avatar with a flat volt story ring when there are unseen stories; name in Bold 30 tight; a crisp 1pt ink line under the title block.
- 58pt slab buttons with 16pt corners and 6pt gaps. 20pt cards with 20pt gaps. A frosted tabs capsule.
- Chat-list placeholder avatars are flat print colours, not gradients.
- Music pill and flow tint still animate on a profile that has them.
- Off: stock.

### WP6 — Glass, nav bars, sheets, toasts, lens
**Owns:** `TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift`, `TelegramUI/Components/LiquidLens/Sources/LiquidLensView.swift`, `TelegramUI/Components/NavigationBarNode/Sources/NavigationBarNode.swift`, `Display/Source/Navigation/NavigationModalContainer.swift`, `Display/Source/Navigation/NavigationModalFrame.swift` (verify only, stays 38), `Components/SheetComponent/Sources/SheetComponent.swift`, `Components/ResizableSheetComponent/Sources/ResizableSheetComponent.swift`, `AttachmentUI/Sources/AttachmentController.swift`, `UndoUI/Sources/UndoOverlayControllerNode.swift`, `TelegramUI/Components/ToastComponent/Sources/ToastContentComponent.swift`.
**Changes:**
- `astraMaterialTint` (:2134): the first statement is `if AstraLook.design2027 { return folioTint(tintColor, isDark) }`, mapping per §2.3. `.custom` passes through. This precedes `glassMaterial` and the Monochrome special cases.
- **Rim overlay:** a new `private var astraRimView: UIView?` (non-interactive), added **above `nativeParamsView`** on the native iOS 26 path only. The legacy path draws its own rim, so skip it there. Content: a `CAShapeLayer` stroking `outlinePath` (:541) at 0.5pt (light) / 0.67pt (dark), its colour supplied through a `CAGradientLayer` mask per §2.3. Size and path are updated in the frame block (:915–926) **inside the same transition** as the clipping shape, so it follows morphs (context menu, nav capsules). Remove it when the flag is off. **Never touch `nativeView.layer`**; `renewNativeView` (:568) must re-add the rim above the new view.
- LiquidLensView :43/:48: `astraHasOwnFill` includes `AstraLook.design2027`; fill = volt @ 0.12 (L) / 0.18 (D). Read dark from the existing isDark parameter.
- NavigationBarNode :421–430: under Folio, edgeEffectColor = the theme page colour (already theme-driven) and alpha 0.92.
- NavigationModalContainer :413: `design2027 ? Folio.modalRadius : 10`.
- Dims: SheetComponent :204 and ResizableSheet :992: under Folio use `Folio.dimLight / dimDark` (instead of black @ 0.4). AttachmentController :633: 0.25 → 0.40 (L) with ink, 0.55 (D). **Radii are unchanged:** ResizableSheet stays 40 at all six sites, AttachmentContainer stays 38.
- UndoOverlayControllerNode :1572/:1577/:1581/:1701/:1704: under Folio, radius 16 continuous. The fill is solid (blur effect hidden): light mode `#0B0B0C` @ 0.92 with `#F7F6F2` text; dark mode `#F4F3EE` @ 0.94 with `#0B0B0C` text. **The action-button colour flips by surface:** `#8B7DFF` on the ink toast (light mode), `#3D2BFF` on the paper toast (dark mode). Add the Z2 shadow on the panel's container, and the entrance animation from §2.7 (0.25 ease-out, rise 12, fade only under Reduce Motion). Text is 15 Medium.
- ToastContentComponent :118: radius `design2027 ? min(16, h/2) : min(25, h/2)`. It stays an always-dark glass (it is shared with media UI).
**Acceptance:**
- On iOS 26: nav capsules, the tab bar, the input field and menus read as matte paper frost (light) / ink frost (dark), with a fine rim visible on the top edge.
- The tab-bar lens is still visible as a soft volt wash.
- Long-press menu morph: the rim stays glued to the shape through the animation, with no lag frame.
- Undo toast after deleting a chat: an ink slab, 16pt corners, a volt "Отменить".
- Sheets: 40pt corners as stock, with an ink dim.
- On the legacy (pre-26 / custom glass) path: tints apply, there is no doubled rim, and nothing crashes.

---

## 5. Do not touch / hard rules

- **Everything behind the flag.** With `design2027 == false`, no colour, radius, font, inset, view or animation changes. New views (the rim, pinned plate and rule) are not created, or are removed and hidden, when the flag is off. Verify with a screenshot diff of the chat list, a chat, settings, a profile, a context menu and an action sheet against the stock build.
- **Do not touch:**
  - Avatar shapes, the story-ring masks, the story bar geometry (52pt ellipses), and the PeerInfo avatar transform.
  - Header heights 46 and 44 and the search animation math.
  - Tab bar geometry, folder strip geometry, and chat-list avatar diameter and item insets (no real gaps between rows).
  - `ItemListSystemStyle` (no global legacy→glass flip), SwitchNode internals (recolour only), and the action-sheet layout logic.
  - The 33pt bubble image box, stretch points and the duplicated merge rules (`messageBubbleArguments` / `messageBubbleImage`). Keep radius ≤ 16.5. `bubbleMode` semantics (never reuse it to remove tails).
  - cornersImage above 28. `listSideMargins` / `peerInfoSideInsets` bases (iPhone Duo strip logic).
  - `nativeView.layer`, `nativeBlurRadius` / EffectSettingsContainerView (private API), the GlassBackgroundView shape transform (no global capsule→slab rewrite), NavigationBarComponent glass animations, and `UIGlassContainerEffect` spacing.
  - ResizableSheet 40, AttachmentContainer 38, NavigationModalFrame 38, AttachmentPanel lens 28.
  - A global Font reroute or a rounded font. Raw `UIFont.systemFont` sites. ChatMessageTextFonts.
  - PeerNameColors (user name colours), anti-delete outline semantics (it always wins), and the AstraGram profile flow, music and ring features (verify only).
  - Share and Notification Content extensions stay stock in v1 (known limitation; they build presentation data separately).
- **Caching:** never mutate a cached PresentationTheme. Ring and outline caches must include lineWidth.
- **Threading:** `AstraGramSettings.current` reads on draw threads are fine (the Monochrome precedent). `AstraLook` statics are written only on the main queue.
- **No new continuous animations** (no backdrop, no CADisplayLink) and no shadows on rasterized layers.

## 6. Test matrix

Light and dark (including auto night) × bubble mode and bubbleless × default solid wallpaper, «Живой фон», a user-chosen wallpaper (pattern and solid) × iOS 26 native glass and the legacy glass path × Reduce Motion on/off × font size small, default and largest.

Also check:
- Live toggle from inside an open chat and from settings, then a restart (icons).
- Monochrome ↔ Folio exclusivity, and both stored true (Folio wins).
- An anti-delete message in Folio.
- iPhone Duo side strips.
- Glass material row disabled while Folio is on.
- Dark outgoing (ink text on `#8B7DFF`) checked by eye by the user for preference.
- Snapshot and app unit tests (docs/app-unit-tests.md) updated only where layout constants legitimately change under the flag.

---

## 7. Polish round (after the first build, design-lead review)

The first build reads as "Telegram recoloured, plus card rows". Three critiques (surfaces, coverage, contrast/accessibility) were merged into one polish round. All of it stays behind `design2027`, keeps the stock value in the else branch, adds no per-frame work, and respects §5.

**Accepted (by theme):**

1. **Contrast is a feature.** Light `online` 0x007F55 and `destructive` 0xD0102A. `ink3` raised to text strength (light 0x76756F, dark 0x807F7A); the old values become `ink4`, used only for decorative glyphs (pinned glyph, disclosure arrow). `incomingSecondary` collapses to `ink2` (three greys, not four). New `pressed` token (light 0xE2E1DA, dark 0x2A2A2F); pinned highlight is one step past the pinned plate. Off switch track light 0xB5B4AE / dark 0x48484E. Selected rows 0xDCD8FF / 0x2E2860. Dark `voltPressed` brightens (0x9D91FF). Outgoing selection, knobs and link highlight use `onVolt`; inactive outgoing reactions are `onVolt` @0.18.
2. **One ground.** `list.plainBackgroundColor = page`, so Chats, Contacts, Calls and search share Z0.
3. **No Telegram blue anywhere.** Emoji/sticker/GIF panel, bot keyboard, keyboard appearance, passcode, intro and charts are mapped to ink, paper, hairline and volt. The call-screen gradient becomes ink with one volt stop; errors stay red.
4. **Volt discipline.** Profile/settings icon actions are ink text with a volt glyph. Volt text is kept for links, switches, badges, unread and one primary action per screen.
5. **Tiles that read in the dark.** Dark settings tiles are elevated (0x2A2A2E) with an ink glyph; the AstraGram tile is dark volt 0x8B7DFF. Tiles are cached per appearance, and the launch-time freeze is removed.
6. **Chat list as a folio insert.** Pinned rows form one grouped stack (outer corners 20, inner 6, 6pt gaps, no separators inside). The pin glyph disappears under Folio because the plate already says "pinned". Light pinned plate 0xEAE9E3. Row extra height scales with text size.
7. **The profile mark.** The full-width white rule becomes a 28×2 volt mark (white @0.6 on covers), kept when the music capsule is shown. The missing-name bug is investigated first.
8. **One typographic system for labels.** ItemList and plain-list (ListSectionHeaderNode) headers, profile field labels, profile pane tabs, story chips, EntityKeyboard group titles, tooltips, the attachment counter and call durations share the running head: Semibold 12 uppercase, kern = 0.06·size, tabular digits for numbers. All-caps and tracking turn off at AX sizes (base > 23).
9. **Notes in the margin.** Tooltips match the undo toast: an inverse ink slab, radius 16, volt action.
10. **Quieter chips.** Light date/service chips use `ink` @0.86; dark chips are opaque over custom wallpapers; the chip link highlight is the chip text colour @0.25.
11. **Increase Contrast.** `AstraFolioPalette(highContrast:)` (cache bit 8) strengthens hairlines, ink2, card rims and the incoming-bubble rim.

12. **Settings rhythm.** Section headers get 28pt above and 10pt below; footers are 13pt ink2. The «Оформление» section splits into «Дизайн» and «Профиль и вкладки». «Перезапустить AstraGram» gets its own one-row card, shown only while a restart is pending.

**Rejected or deferred (and why):**
- *SF Rounded/Expanded display face, global type tokens*: §5 forbids a rounded font or a global font reroute. The identity comes from weight, tracking and tabular digits instead.
- *Large left-aligned masthead and underline folder tabs*: §5 fixes header heights 46/44, the search animation math and the folder strip geometry.
- *Volt-dot tab indicator without the pill*: §5 fixes tab-bar geometry. Done instead: ink2 unselected icons (a luminance jump) and a semibold selected title.
- *New bubble corner scheme and an incoming hairline rim drawn in the image*: §5 keeps the 33pt bubble box and the merge rules. Only the rim alpha is raised (0.12 light / 0.10 dark).
- *Static date header as hairline divider*: the static/floating fill is shared through `selectDateFillStaticColor`, so there is no clean static-only state to hook into. Deferred to v2; this round softens the chip instead.
- *Folio preview swatches in settings, media-viewer chrome*: they need new item types or deeper GalleryUI changes. Deferred.
- A light-mode screenshot pass (chat list, chat, settings, profile, alert, action sheet, toast) is required before release.
