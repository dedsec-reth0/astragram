import Foundation
import UIKit
import TelegramPresentationData
import DeviceAccess
import AyuGramUI

enum ApplicationShortcutItemType: String {
    case search
    case compose
    case camera
    case savedMessages
    case account
    case appIcon
    case ayuGhostMode
    case ayuDedsecSilence
}

struct ApplicationShortcutItem: Equatable {
    let type: ApplicationShortcutItemType
    let title: String
    let subtitle: String?
}

@available(iOS 9.1, *)
extension ApplicationShortcutItem {
    func shortcutItem() -> UIApplicationShortcutItem {
        let icon: UIApplicationShortcutIcon
        switch self.type {
            case .search:
                icon = UIApplicationShortcutIcon(type: .search)
            case .compose:
                icon = UIApplicationShortcutIcon(type: .compose)
            case .camera:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Camera")
            case .savedMessages:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/SavedMessages")
            case .account:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/Account")
            case .appIcon:
                icon = UIApplicationShortcutIcon(templateImageName: "Shortcuts/AppIcon")
            case .ayuGhostMode:
                icon = UIApplicationShortcutIcon(systemImageName: "eye.slash")
            case .ayuDedsecSilence:
                icon = UIApplicationShortcutIcon(systemImageName: "bell.slash")
        }
        return UIApplicationShortcutItem(type: self.type.rawValue, localizedTitle: self.title, localizedSubtitle: self.subtitle, icon: icon, userInfo: nil)
    }
}

/// AyuGram: the home screen menu (iOS shows four items): ghost mode and DEDSEC silence switches first.
func applicationShortcutItems(strings: PresentationStrings, otherAccountName: String?, ghostModeEnabled: Bool, dedsecSilence: Bool) -> [ApplicationShortcutItem] {
    let ayuStrings = AyuStrings(strings)
    var items: [ApplicationShortcutItem] = [
        ApplicationShortcutItem(type: .ayuGhostMode, title: ghostModeEnabled ? ayuStrings.shortcutGhostOff : ayuStrings.shortcutGhostOn, subtitle: ghostModeEnabled ? "👻 " + ayuStrings.shortcutStateOn : ayuStrings.shortcutStateOff),
        ApplicationShortcutItem(type: .ayuDedsecSilence, title: dedsecSilence ? ayuStrings.shortcutDedsecOff : ayuStrings.shortcutDedsecOn, subtitle: dedsecSilence ? ayuStrings.shortcutDedsecSubtitleOn : ayuStrings.shortcutDedsecSubtitleOff),
        ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil)
    ]
    if let otherAccountName = otherAccountName {
        items.append(ApplicationShortcutItem(type: .account, title: strings.Shortcut_SwitchAccount, subtitle: otherAccountName))
    } else {
        items.append(ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil))
    }
    return items
}

func applicationShortcutItems(strings: PresentationStrings, otherAccountName: String?) -> [ApplicationShortcutItem] {
    if let otherAccountName = otherAccountName {
        return [
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil),
            ApplicationShortcutItem(type: .account, title: strings.Shortcut_SwitchAccount, subtitle: otherAccountName)
        ]
    } else {
        return [
            ApplicationShortcutItem(type: .search, title: strings.Common_Search, subtitle: nil),
            ApplicationShortcutItem(type: .compose, title: strings.Compose_NewMessage, subtitle: nil),
            ApplicationShortcutItem(type: .savedMessages, title: strings.Conversation_SavedMessages, subtitle: nil),
            ApplicationShortcutItem(type: .appIcon, title: strings.Shortcut_AppIcon, subtitle: nil)
        ]
    }
}
