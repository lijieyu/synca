import Foundation
import Combine

// Test process only: never read or write the user's real keychain.
enum KeychainHelper {
    static func load(key: String) -> String? { nil }
    static func save(key: String, value: String) {}
    static func delete(key: String) {}
}

@main
struct NativeTransferTests {
    @MainActor
    static func main() async throws {
        let api = APIClient.shared
        api.setToken("native-fixture")
        defer { api.cancelPendingRequests() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func file(_ name: String, size: Int) throws -> PendingFileUpload {
            let url = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: UInt64(size)); try handle.close()
            return PendingFileUpload.read(from: url)!
        }
        let large = try file("large.zip", size: PendingFileUpload.maxFileSize)
        let result = try await api.sendFileMessage(file: large, progress: { _ in })
        precondition(result.id == large.uploadID && result.fileSize == PendingFileUpload.maxFileSize)
        print("PASS: actual 200 MB streamed multipart upload and response decoding")
        let retry = try file("retry.txt", size: 1024)
        do { _ = try await api.sendFileMessage(file: retry, progress: { _ in }); preconditionFailure("expected 503") }
        catch APIError.httpError(let status, _) { precondition(status == 503) }
        let retried = try await api.sendFileMessage(file: retry, progress: { _ in })
        precondition(retried.id == retry.uploadID)
        let slow = try file("slow.txt", size: 1024)
        let upload = Task { try await api.sendFileMessage(file: slow, progress: { _ in }) }
        try await Task.sleep(nanoseconds: 100_000_000)
        api.cancelUploads()
        do { _ = try await upload.value; preconditionFailure("cancelled upload succeeded") }
        catch { precondition(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
        print("PASS: failed upload retry preserves upload ID; active upload cancellation")
        let base = "http://127.0.0.1:3000/api/media/"
        let saved = try await api.downloadAttachment(from: URL(string: base+"file")!)
        let contents = try String(contentsOf: saved, encoding: .utf8)
        precondition(contents == "original fixture attachment")
        try FileManager.default.removeItem(at: saved)
        do { _ = try await api.downloadAttachment(from: URL(string: base+"expired")!); preconditionFailure("expired attachment succeeded") }
        catch APIError.attachmentExpired {}
        do { _ = try await api.downloadAttachment(from: URL(string: base+"redirect")!); preconditionFailure("cross origin redirect succeeded") }
        catch APIError.httpError(let status, _) { precondition(status == 302) }
        do { _ = try await api.downloadAttachment(from: URL(string: "http://127.0.0.1:3001/leak")!); preconditionFailure("cross origin attachment succeeded") }
        catch APIError.invalidResponse {}
        let download = Task { try await api.downloadAttachment(from: URL(string: base+"slow")!) }
        try await Task.sleep(nanoseconds: 100_000_000)
        api.setToken("new-session")
        do { _ = try await download.value; preconditionFailure("old-session download succeeded") }
        catch { precondition(error is CancellationError || (error as NSError).code == NSURLErrorCancelled) }
        api.setToken("native-fixture")
        let imageFile = try await api.downloadAttachment(from: URL(string: base+"image")!)
        defer { try? FileManager.default.removeItem(at: imageFile) }
        let cacheDirectory = directory.appendingPathComponent("bounded-cache")
        let cache = BoundedFileCache(directory: cacheDirectory, maximumBytes: 10, maximumAge: 60)
        let generation = cache.generation
        try cache.write(Data(repeating: 1, count: 4), named: "one", generation: generation)
        try cache.write(Data(repeating: 2, count: 4), named: "two", generation: generation)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -30)], ofItemAtPath: cacheDirectory.appendingPathComponent("one").path)
        try cache.write(Data(repeating: 3, count: 4), named: "three", generation: generation)
        precondition(cache.data(named: "one") == nil && cache.data(named: "two")?.count == 4)
        let expiredURL = cacheDirectory.appendingPathComponent("two")
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSinceNow: -120), .modificationDate: Date(timeIntervalSinceNow: -120)], ofItemAtPath: expiredURL.path)
        precondition(cache.data(named: "two") == nil)
        try cache.write(Data(repeating: 0, count: 11), named: "oversize", generation: generation)
        precondition(cache.data(named: "oversize") == nil)
        cache.clear()
        try cache.write(Data(repeating: 0, count: 4), named: "stale", generation: generation)
        precondition(cache.data(named: "stale") == nil)
        let downloaded = directory.appendingPathComponent("downloaded")
        try Data(repeating: 0, count: 8).write(to: downloaded)
        let cached = try cache.moveDownloadedFile(downloaded, named: "download")
        precondition(FileManager.default.fileExists(atPath: cached.path) && !FileManager.default.fileExists(atPath: downloaded.path))
        print("PASS: cache byte budget, least-recently-used eviction, fixed TTL, oversize rejection, stale post-logout writes, disk-backed cache move")
        let image = try ImageCache.thumbnail(from: Data(contentsOf: imageFile), maximumPixelSize: 1024)
        precondition(image.width == 1024 && image.height == 512)
        print("PASS: HTTP 410, origin/redirect validation, session-change cancellation, 4096px image downsampled to 1024px")
    }
}
