import Foundation

@MainActor
final class PushTokenManager {
    static let shared = PushTokenManager()

    private let cachedTokenKey = "cachedPushDeviceToken"
    private let uploadedAuthTokenKey = "uploadedPushAuthToken"

    private init() {}

    func cacheDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: cachedTokenKey)
    }

    func uploadCachedTokenIfPossible() async {
        guard APIClient.shared.isAuthenticated,
              let pushToken = UserDefaults.standard.string(forKey: cachedTokenKey),
              let authToken = APIClient.shared.token else {
            return
        }

        // Skip duplicate uploads for the same authenticated session.
        if UserDefaults.standard.string(forKey: uploadedAuthTokenKey) == authToken {
            return
        }

        let platform: String
        #if os(iOS)
        platform = "ios"
        #else
        platform = "macos"
        #endif

        let topic = Bundle.main.bundleIdentifier
        let env = currentAPNsEnvironment()

        do {
            try await APIClient.shared.registerPushToken(
                token: pushToken,
                platform: platform,
                apnsEnvironment: env,
                topic: topic
            )
            UserDefaults.standard.set(authToken, forKey: uploadedAuthTokenKey)
            print("[apns] token uploaded (\(platform), \(env))")
        } catch {
            print("[apns] token upload failed: \(error.localizedDescription)")
        }
    }

    func clearUploadedSessionMarker() {
        UserDefaults.standard.removeObject(forKey: uploadedAuthTokenKey)
    }

    private func currentAPNsEnvironment() -> String {
        #if os(iOS)
        if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let profile = String(data: data, encoding: .ascii) {
            if profile.contains("<key>aps-environment</key><string>production</string>") {
                return "production"
            }
            return "sandbox"
        }
        #endif

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
