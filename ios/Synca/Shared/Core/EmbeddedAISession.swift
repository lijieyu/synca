import Foundation

/// The native session is available only to Synca's own top-level AI page.
/// Nothing is placed in URLs, cookies shared with Safari, or persistent WebKit storage.
enum EmbeddedAISession {
    static func isTrusted(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "synca.haerth.cn"
            && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
    }

    private static func literal(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    private static let trustedDocumentGuard = """
      if (window.top !== window || location.origin !== 'https://synca.haerth.cn' ||
          !(location.pathname === '/ai' || location.pathname === '/ai/')) return;
    """

    private static func preferenceAssignments(appearance: String, language: String) -> String {
        let appearance = ["light", "dark"].contains(appearance) ? appearance : "light"
        let language = ["zh-Hans", "zh-Hant", "en"].contains(language) ? language : "en"
        return """
          const preferences = { appearance: \(literal(appearance)), language: \(literal(language)) };
          window.__syncaNativePreferences = preferences;
          localStorage.setItem('synca.appearance', preferences.appearance);
          localStorage.setItem('synca.language', preferences.language);
        """
    }

    static func bootstrap(token: String, email: String?, appearance: String, language: String) -> String {
        """
        (() => {
          \(trustedDocumentGuard)
          window.__syncaEmbeddedAI = true;
          localStorage.setItem('authToken', \(literal(token)));
          localStorage.removeItem('isAdmin');
          localStorage.removeItem('userPlan');
          \(email.map { "localStorage.setItem('userEmail', \(literal($0)));" } ?? "localStorage.removeItem('userEmail');")
          \(preferenceAssignments(appearance: appearance, language: language))
        })();
        """
    }

    /// Updates presentation only, without reloading the page or touching auth state.
    static func preferences(appearance: String, language: String) -> String {
        """
        (() => {
          \(trustedDocumentGuard)
          \(preferenceAssignments(appearance: appearance, language: language))
          if (document.documentElement) {
            document.documentElement.dataset.appearance = preferences.appearance;
            document.documentElement.lang = preferences.language;
          }
          window.dispatchEvent(new CustomEvent('synca-native-preferences', { detail: preferences }));
        })();
        """
    }
}
