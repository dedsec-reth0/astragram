import Foundation
import UIKit
import UserNotifications

/// AyuGram: "Restart AyuGram". iOS has no way for an app to relaunch itself, so the app leaves a local notification
/// that opens it again when tapped, goes to the Home Screen and exits.
public enum AyuAppRestart {
    public static func perform(title: String, text: String) {
        UserDefaults.standard.synchronize()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        let request = UNNotificationRequest(identifier: "ayugram.restart", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false))
        UNUserNotificationCenter.current().add(request, withCompletionHandler: { _ in
            DispatchQueue.main.async {
                // Leaves to the Home Screen with the usual animation instead of vanishing like a crash.
                let suspend = NSSelectorFromString("suspend")
                if UIApplication.shared.responds(to: suspend) {
                    let _ = UIApplication.shared.perform(suspend)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: {
                    exit(0)
                })
            }
        })
    }
}
