import Foundation
import UIKit
import TelegramPresentationData
import DeviceAccess
import AstraGramUI

enum ApplicationShortcutItemType: String {
    case search
    case compose
    case camera
    case savedMessages
    case account
    case appIcon
    case astraGhostMode
    case astraDedsecSilence
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
            case .astraGhostMode:
                icon = UIApplicationShortcutIcon(systemImageName: "eye.slash")
            case .astraDedsecSilence:
                icon = UIApplicationShortcutIcon(systemImageName: "bell.slash")
        }
        return UIApplicationShortcutItem(type: self.type.rawValue, localizedTitle: self.title, localizedSubtitle: self.subtitle, icon: icon, userInfo: nil)
    }
}

/// AstraGram: the home screen menu (iOS shows four items): ghost mode and DEDSEC silence switches first.
func applicationShortcutItems(strings: PresentationStrings, otherAccountName: String?, ghostModeEnabled: Bool, dedsecSilence: Bool) -> [ApplicationShortcutItem] {
    let astraStrings = AstraStrings(strings)
    var items: [ApplicationShortcutItem] = [
        ApplicationShortcutItem(type: .astraGhostMode, title: ghostModeEnabled ? astraStrings.shortcutGhostOff : astraStrings.shortcutGhostOn, subtitle: ghostModeEnabled ? "👻 " + astraStrings.shortcutStateOn : astraStrings.shortcutStateOff),
        ApplicationShortcutItem(type: .astraDedsecSilence, title: dedsecSilence ? astraStrings.shortcutDedsecOff : astraStrings.shortcutDedsecOn, subtitle: dedsecSilence ? astraStrings.shortcutDedsecSubtitleOn : astraStrings.shortcutDedsecSubtitleOff),
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
