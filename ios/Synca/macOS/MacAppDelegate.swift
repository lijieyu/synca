import Cocoa
import UserNotifications

class MacAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notifDelegate = MacNotificationDelegate.shared
        UNUserNotificationCenter.current().delegate = notifDelegate

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MacWindowBehaviorController.shared.restoreMainWindow()
        }
        return true
    }

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[apns:mac] device token: \(token.prefix(12))...")

        Task { @MainActor in
            PushTokenManager.shared.cacheDeviceToken(deviceToken)
            await PushTokenManager.shared.uploadCachedTokenIfPossible()
        }
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[apns:mac] registration failed: \(error.localizedDescription)")
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        print("[apns:mac] received remote notification")
        Task { @MainActor in
            await SyncManager.shared.fullSync(manual: false, showSuccessStatus: false)

            // Update Dock badge
            let count = SyncManager.shared.unclearedCount
            if count > 0 {
                NSApp.dockTile.badgeLabel = "\(count)"
            } else {
                NSApp.dockTile.badgeLabel = nil
            }
        }
    }
}

// Separate class to avoid Swift 6 concurrency issues
final class MacNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = MacNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            await SyncManager.shared.fullSync(manual: false, showSuccessStatus: false)
        }
        completionHandler([])
    }
}
