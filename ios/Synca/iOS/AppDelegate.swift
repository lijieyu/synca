import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let notifDelegate = NotificationDelegate.shared
        UNUserNotificationCenter.current().delegate = notifDelegate

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[apns] device token: \(token.prefix(12))...")

        Task { @MainActor in
            guard APIClient.shared.isAuthenticated else { return }
            let topic = Bundle.main.bundleIdentifier
            let env = Self.currentAPNsEnvironment()
            do {
                try await APIClient.shared.registerPushToken(
                    token: token,
                    platform: "ios",
                    apnsEnvironment: env,
                    topic: topic
                )
                print("[apns] token uploaded (\(env))")
            } catch {
                print("[apns] token upload failed: \(error.localizedDescription)")
            }
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[apns] registration failed: \(error.localizedDescription)")
    }

    // Handle silent push (content-available) - trigger sync
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("[apns] received remote notification")
        Task { @MainActor in
            await SyncManager.shared.incrementalSync(manual: false)

            // Update badge
            let count = SyncManager.shared.unclearedCount
            UNUserNotificationCenter.current().setBadgeCount(count) { _ in }

            completionHandler(.newData)
        }
    }

    static func currentAPNsEnvironment() -> String {
        if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let profile = String(data: data, encoding: .ascii) {
            if profile.contains("<key>aps-environment</key><string>production</string>") {
                return "production"
            }
            return "sandbox"
        }

        if let configured = Bundle.main.object(forInfoDictionaryKey: "APNSUploadEnvironment") as? String {
            let normalized = configured.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "production" { return "production" }
            if normalized == "sandbox" || normalized == "development" { return "sandbox" }
        }

        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

// Separate class for UNUserNotificationCenterDelegate to avoid concurrency issues
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    // Show notifications while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Trigger sync on foreground notification
        Task { @MainActor in
            await SyncManager.shared.incrementalSync()
        }
        completionHandler([])  // Don't show banner since app is in foreground
    }
}
