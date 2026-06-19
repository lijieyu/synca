import Foundation
import CryptoKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import ImageIO
#endif

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

    static func loadData(for url: URL, authorizationToken: String?) async throws -> Data {
        if let cachedData = getCachedData(for: url) {
            return cachedData
        }

        var request = URLRequest(url: url)
        if let authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        saveCachedData(data, for: url)
        return data
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

enum ImageClipboard {
    @MainActor
    static func write(_ data: Data) -> Bool {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return false }
        UIPasteboard.general.image = image
        return true
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return false }

        let item = NSPasteboardItem()
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let typeIdentifier = CGImageSourceGetType(source) {
            item.setData(data, forType: NSPasteboard.PasteboardType(typeIdentifier as String))
        } else if let tiffData = image.tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        } else {
            return false
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
        #endif
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
