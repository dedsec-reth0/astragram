import Foundation
import Postbox
import SwiftSignalKit

/// DEDSEC silence: one switch that turns off notifications and sounds of every group and channel.
///
/// It uses Telegram's own notification categories (Settings → Notifications → Groups / Channels), synchronized with the
/// server, so new groups and channels are silent too, and a chat with its own exception (notifications turned on in its
/// profile) keeps notifying.
public enum AstraDedsecSilence {
    public static func apply(account: Account, silent: Bool) -> Signal<Void, NoError> {
        return updateGlobalNotificationSettingsInteractively(postbox: account.postbox, { settings in
            var settings = settings
            settings.groupChats.enabled = !silent
            settings.channels.enabled = !silent
            return settings
        })
    }
}
