import Foundation

enum AppLinks {
    private static let baseURL = URL(string: "https://synca.haerth.cn")!
    private static let standardTermsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var privacyPolicyURL: URL {
        localizedURL(pathEN: "/en/privacy-policy", pathZH: "/zh-hans/privacy-policy")
    }

    static var termsOfUseURL: URL {
        standardTermsOfUseURL
    }

    static var supportURL: URL {
        localizedURL(pathEN: "/en/support", pathZH: "/zh-hans/support")
    }

    private static func localizedURL(pathEN: String, pathZH: String) -> URL {
        let languageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        let path = languageCode.hasPrefix("zh") ? pathZH : pathEN
        return baseURL.appendingPathComponent(String(path.dropFirst()))
    }
}
