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

    static func bootstrap(token: String, email: String?) -> String {
        func literal(_ value: String) -> String {
            // JSON serialization escapes quotes, control characters and backslashes.
            let data = try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            return String(decoding: data, as: UTF8.self)
        }
        return """
        (() => {
          if (window.top !== window || location.origin !== 'https://synca.haerth.cn' ||
              !(location.pathname === '/ai' || location.pathname === '/ai/')) return;
          window.__syncaEmbeddedAI = true;
          localStorage.setItem('authToken', \(literal(token)));
          localStorage.removeItem('isAdmin');
          localStorage.removeItem('userPlan');
          \(email.map { "localStorage.setItem('userEmail', \(literal($0)));" } ?? "localStorage.removeItem('userEmail');")
        })();
        """
    }
}
