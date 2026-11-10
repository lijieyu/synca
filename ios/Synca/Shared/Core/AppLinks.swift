import Foundation

enum AppLinks {
    static let developerProfileURL = URL(string: "https://www.xiaohongshu.com/user/profile/612f8178000000000201da34")!
    private static let baseURL = URL(string: "https://synca.haerth.cn")!
    private static let standardTermsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    static var aiConnectionURL: URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("ai", isDirectory: true), resolvingAgainstBaseURL: false)!
        let language = AppLocalization.identifier
        components.queryItems = [URLQueryItem(name: "lng", value: language)]
        return components.url!
    }

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
        let languageCode = AppLocalization.identifier.lowercased()
        let path = languageCode.hasPrefix("zh") ? pathZH : pathEN
        return baseURL.appendingPathComponent(String(path.dropFirst()))
    }
}
