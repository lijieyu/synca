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

enum AttachmentCache {
    private static let cacheDirectory: URL = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let cacheBase = urls[0].appendingPathComponent("SyncaAttachmentCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        return cacheBase
    }()

    static func cachedFileURL(for url: URL, suggestedFileName: String) -> URL? {
        let fileURL = cachePath(for: url, suggestedFileName: suggestedFileName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    static func isCached(_ url: URL, suggestedFileName: String) -> Bool {
        cachedFileURL(for: url, suggestedFileName: suggestedFileName) != nil
    }

    static func save(_ data: Data, for url: URL, suggestedFileName: String) throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let fileURL = cachePath(for: url, suggestedFileName: suggestedFileName)
        let tempURL = cacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        try data.write(to: tempURL, options: .atomic)
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }

    static func cachePath(for url: URL, suggestedFileName: String) -> URL {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        let prefix = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(prefix)-\(safeFileName(suggestedFileName, fallback: url.lastPathComponent))")
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private static func safeFileName(_ name: String, fallback: String) -> String {
        let source = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : name
        let sanitized = source
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sanitized.isEmpty else { return "Attachment" }
        guard sanitized.count > 140 else { return sanitized }

        let ext = (sanitized as NSString).pathExtension
        let base = (sanitized as NSString).deletingPathExtension
        let maxBaseLength = ext.isEmpty ? 140 : max(1, 139 - ext.count)
        let truncatedBase = String(base.prefix(maxBaseLength))
        return ext.isEmpty ? truncatedBase : "\(truncatedBase).\(ext)"
    }
}
