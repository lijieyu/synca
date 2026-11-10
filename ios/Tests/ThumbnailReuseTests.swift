import Foundation
import Combine

enum KeychainHelper {
    static func load(key: String) -> String? { nil }
    static func save(key: String, value: String) {}
    static func delete(key: String) {}
}

@main
struct ThumbnailReuseTests {
    @MainActor static func main() async throws {
        let api = APIClient.shared
        api.setToken("native-fixture")
        ImageCache.clearCache()
        let url = URL(string: "http://127.0.0.1:3000/api/media/image")!
        let start = Date()
        let first = try await ImageCache.thumbnail(for: url, authorizationToken: api.token, maximumPixelSize: 1024)
        let cold = Date().timeIntervalSince(start)
        let warmStart = Date()
        for _ in 0..<30 {
            let next = try await ImageCache.thumbnail(for: url, authorizationToken: api.token, maximumPixelSize: 1024)
            precondition(first === next, "Warm switching must reuse decoded pixels, not decode again")
        }
        let warm = Date().timeIntervalSince(warmStart) / 30
        ImageCache.clearCache()
        let cleared = try await ImageCache.thumbnail(for: url, authorizationToken: api.token, maximumPixelSize: 1024)
        precondition(first !== cleared, "Cache clearing must discard decoded pixels")
        api.setToken("different-account")
        do { _ = try await ImageCache.thumbnail(for: url, authorizationToken: "native-fixture", maximumPixelSize: 1024); preconditionFailure("Old session reused thumbnail") }
        catch {}
        print("PASS thumbnail reuse and session isolation. Cold ms: \(cold*1000), warm ms: \(warm*1000)")
    }
}
