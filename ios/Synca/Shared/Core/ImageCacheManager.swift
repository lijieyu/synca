import Foundation
import CryptoKit
import ImageIO
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ImageCache {
    private static let cache = BoundedFileCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncaImageCache", isDirectory: true),
        maximumBytes: 128 * 1024 * 1024, maximumAge: 7 * 24 * 60 * 60)

    static func getCachedData(for url: URL, authorizationToken: String?) -> Data? {
        cache.data(named: cacheKey(for: url, authorizationToken: authorizationToken))
    }

    static func loadData(for url: URL, authorizationToken: String?) async throws -> Data {
        let cacheGeneration = cache.generation
        let session = try await APIClient.shared.attachmentSession(for: url)
        // The captured token keeps a request from adopting a newly signed-in account.
        guard authorizationToken == (await APIClient.shared.token) else { throw CancellationError() }
        if let cachedData = getCachedData(for: url, authorizationToken: authorizationToken) {
            guard await APIClient.shared.isCurrentSession(session) else { throw CancellationError() }
            return cachedData
        }
        let temporaryURL = try await APIClient.shared.downloadAttachment(from: url)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        try Task.checkCancellation()
        guard await APIClient.shared.isCurrentSession(session) else { throw CancellationError() }
        try? cache.write(data, named: cacheKey(for: url, authorizationToken: authorizationToken), generation: cacheGeneration)
        return data
    }

    static func thumbnail(for url: URL, authorizationToken: String?, maximumPixelSize: Int) async throws -> CGImage {
        let data = try await loadData(for: url, authorizationToken: authorizationToken)
        try Task.checkCancellation()
        return try thumbnail(from: data, maximumPixelSize: maximumPixelSize)
    }

    static func thumbnail(from data: Data, maximumPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        return image
    }

    private static func cacheKey(for url: URL, authorizationToken: String?) -> String {
        let hash = SHA256.hash(data: Data("\(authorizationToken ?? "")|\(url.absoluteString)".utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func clearCache() { cache.clear() }

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

@MainActor
enum AttachmentCache {
    private static let cache = BoundedFileCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncaAttachmentCache", isDirectory: true),
        maximumBytes: 256 * 1024 * 1024, maximumAge: 7 * 24 * 60 * 60)

    static func cachedFileURL(for url: URL, suggestedFileName: String) -> URL? {
        cache.cachedURL(named: cacheKey(for: url, suggestedFileName: suggestedFileName))
    }

    static func isCached(_ url: URL, suggestedFileName: String) -> Bool {
        cachedFileURL(for: url, suggestedFileName: suggestedFileName) != nil
    }

    static func saveDownloadedFile(_ source: URL, for url: URL, suggestedFileName: String) throws -> URL {
        try cache.moveDownloadedFile(source, named: cacheKey(for: url, suggestedFileName: suggestedFileName))
    }

    private static func cacheKey(for url: URL, suggestedFileName: String) -> String {
        let hash = SHA256.hash(data: Data("\(APIClient.shared.token ?? "")|\(url.absoluteString)".utf8))
        let prefix = hash.compactMap { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(AttachmentFileName.sanitized(suggestedFileName))"
    }

    static func clearCache() { cache.clear() }
}

/// File-backed cache: fixed lifetime, bounded bytes, recent-use eviction. The lock serializes
/// background image requests with logout, preventing a finished old request recreating its cache.
final class BoundedFileCache: @unchecked Sendable {
    let directory: URL
    let maximumBytes: Int
    let maximumAge: TimeInterval
    private let lock = NSLock()
    private var currentGeneration: UInt64 = 0
    var generation: UInt64 { lock.withLock { currentGeneration } }

    init(directory: URL, maximumBytes: Int, maximumAge: TimeInterval) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.maximumAge = maximumAge
        _ = lock.withLock { prune(reserving: 0) }
    }

    func cachedURL(named name: String) -> URL? {
        lock.withLock { validURL(named: name) }
    }

    func data(named name: String) -> Data? {
        lock.withLock {
            guard let url = validURL(named: name) else { return nil }
            return try? Data(contentsOf: url, options: .mappedIfSafe)
        }
    }

    func write(_ data: Data, named name: String, generation: UInt64) throws {
        try lock.withLock {
            guard generation == currentGeneration, data.count <= maximumBytes else { return }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            guard prune(reserving: data.count) else { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: destination, options: .atomic)
        }
    }

    func moveDownloadedFile(_ source: URL, named name: String) throws -> URL {
        try lock.withLock {
            if let existing = validURL(named: name) { return existing }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard prune(reserving: size) else { throw CocoaError(.fileWriteOutOfSpace) }
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.moveItem(at: source, to: destination)
            try? FileManager.default.setAttributes([.creationDate: Date(), .modificationDate: Date()], ofItemAtPath: destination.path)
            return destination
        }
    }

    func clear() {
        lock.withLock {
            currentGeneration &+= 1
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func validURL(named name: String) -> URL? {
        let url = directory.appendingPathComponent(name)
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        let created = values.creationDate ?? values.contentModificationDate ?? .distantPast
        guard Date().timeIntervalSince(created) < maximumAge else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    private func prune(reserving bytes: Int) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        var entries: [(url: URL, size: Int, touched: Date)] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let created = values.creationDate ?? values.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(created) >= maximumAge {
                do { try FileManager.default.removeItem(at: url) }
                catch {
                    // A failed removal still occupies disk space and must count against the budget.
                    entries.append((url, values.fileSize ?? 0, values.contentModificationDate ?? created))
                }
            } else { entries.append((url, values.fileSize ?? 0, values.contentModificationDate ?? created)) }
        }
        var total = entries.reduce(0) { $0 + $1.size } + bytes
        var count = entries.count + (bytes > 0 ? 1 : 0)
        for entry in entries.sorted(by: { $0.touched < $1.touched }) where total > maximumBytes || count > 512 {
            do { try FileManager.default.removeItem(at: entry.url); total -= entry.size; count -= 1 } catch { }
        }
        return total <= maximumBytes && count <= 512
    }
}
