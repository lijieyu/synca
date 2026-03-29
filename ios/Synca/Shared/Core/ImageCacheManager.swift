import Foundation
import CryptoKit

enum ImageCache {
    private static let cacheDirectory: URL = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheBase = urls[0].appendingPathComponent("SyncaImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        return cacheBase
    }()

    static func getCachedData(for url: URL) -> Data? {
        let fileURL = cachePath(for: url)
        return try? Data(contentsOf: fileURL)
    }

    static func saveCachedData(_ data: Data, for url: URL) {
        let fileURL = cachePath(for: url)
        try? data.write(to: fileURL)
    }

    static func cachePath(for url: URL) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let filename = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(filename)
    }
    
    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
