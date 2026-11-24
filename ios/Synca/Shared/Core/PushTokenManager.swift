import Foundation

@MainActor
final class PushTokenManager {
    static let shared = PushTokenManager()

    private let cachedTokenKey = "cachedPushDeviceToken"
    private let uploadedAuthTokenKey = "uploadedPushAuthToken"
    private let uploadedContextKey = "uploadedPushContext"

    private init() {}

    func cacheDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        if UserDefaults.standard.string(forKey: cachedTokenKey) != token {
            clearUploadedSessionMarker()
        }
        UserDefaults.standard.set(token, forKey: cachedTokenKey)
    }

    func uploadCachedTokenIfPossible() async {
        guard APIClient.shared.isAuthenticated,
              let pushToken = UserDefaults.standard.string(forKey: cachedTokenKey),
              let authToken = APIClient.shared.token else {
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
        let context = "\(topic ?? "")|\(env)"
        // Re-register after an environment correction, including existing installations.
        if UserDefaults.standard.string(forKey: uploadedAuthTokenKey) == authToken,
           UserDefaults.standard.string(forKey: uploadedContextKey) == context { return }


        do {
            try await APIClient.shared.registerPushToken(
                token: pushToken,
                platform: platform,
                apnsEnvironment: env,
                topic: topic
            )
            guard APIClient.shared.token == authToken,
                  UserDefaults.standard.string(forKey: cachedTokenKey) == pushToken else { return }
            UserDefaults.standard.set(authToken, forKey: uploadedAuthTokenKey)
            UserDefaults.standard.set(context, forKey: uploadedContextKey)
            print("[apns] token uploaded (\(platform), \(env))")
        } catch {
            print("[apns] token upload failed: \(error.localizedDescription)")
        }
    }

    func clearUploadedSessionMarker() {
        UserDefaults.standard.removeObject(forKey: uploadedAuthTokenKey)
        UserDefaults.standard.removeObject(forKey: uploadedContextKey)
    }

    /// Profiles are CMS containers; read the embedded plist rather than matching XML whitespace.
    nonisolated static func environment(in profile: Data) -> String? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound], options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let entitlements = dictionary["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String else { return nil }
        switch environment {
        case "production": return "production"
        case "development": return "sandbox"
        default: return nil
        }
    }

    private func currentAPNsEnvironment() -> String {
        #if os(iOS)
        if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let environment = Self.environment(in: data) {
            return environment
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
