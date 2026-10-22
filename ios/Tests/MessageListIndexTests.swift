import Foundation

@main
struct MessageListIndexTests {
    static func message(_ id: String, category: String?, cleared: Bool = false, date: String = "2026-10-22T00:00:00Z") -> SyncaMessage {
        SyncaMessage(id: id, userId: "test", type: .text, categoryId: category,
                     isCleared: cleared, isDeleted: false, createdAt: date, updatedAt: date)
    }

    static func main() async throws {
        let empty = MessageListIndex(messages: [])
        precondition(empty.ordered.isEmpty && empty.byCategory.isEmpty && empty.todoCount == 0)

        let sample = [message("b", category: "one"), message("a", category: "two"),
                      message("c", category: "one", cleared: true), message("d", category: nil)]
        let index = MessageListIndex(messages: sample)
        precondition(index.ordered.map(\.id) == ["c", "a", "b", "d"])
        precondition(index.byCategory["one"]?.map(\.id) == ["c", "b"])
        precondition(index.byCategory["missing"] == nil)
        precondition(index.todoCount == 3 && index.todoCountsByCategory["one"] == 1)
        precondition(MessageListIndex(messages: sample.reversed()).ordered == index.ordered)

        var edited = sample
        edited[0].categoryId = "two"
        edited[0].isCleared = true
        edited.removeLast()
        let changed = MessageListIndex(messages: edited)
        precondition(changed.todoCount == 1)
        precondition(changed.byCategory["one"]?.map(\.id) == ["c"])
        precondition(changed.byCategory["two"]?.map(\.id) == ["b", "a"])

        precondition(PendingFileUpload.maxFileSize == 200 * 1024 * 1024)
        precondition(PendingFileUpload.maxImageSize == 50 * 1024 * 1024)
        var expired = message("expiry", category: nil)
        expired.attachmentExpiresAt = "2000-01-01T00:00:00.000Z"
        precondition(expired.isAttachmentExpired)
        expired.attachmentExpiresAt = "2999-01-01T00:00:00.000Z"
        precondition(!expired.isAttachmentExpired)
        expired.attachmentExpired = true
        precondition(expired.isAttachmentExpired)
        let decoded = try JSONDecoder().decode(SyncaMessage.self, from: JSONEncoder().encode(expired))
        precondition(decoded == expired)

        expired.attachmentExpired = false
        expired.attachmentExpiresAt = "2000-01-01T00:00:00Z"
        precondition(expired.isAttachmentExpired)
        let origin = URL(string: "https://synca.example/api")!
        precondition(AttachmentOrigin.matches(URL(string: "https://synca.example:443/api/media/a")!, baseURL: origin))
        for invalid in ["https://evil.example/a", "http://synca.example/a", "https://synca.example:8443/a", "https://user@synca.example/a", "file:///tmp/a"] {
            precondition(!AttachmentOrigin.matches(URL(string: invalid)!, baseURL: origin))
        }
        let saveDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: saveDirectory) }
        let existing = saveDirectory.appendingPathComponent("report.pdf")
        try Data("original".utf8).write(to: existing)
        let target = AttachmentFileName.availableURL(in: saveDirectory, suggestedName: "report.pdf")
        precondition(target.lastPathComponent == "report (2).pdf")
        let existingContents = try String(contentsOf: existing, encoding: .utf8)
        precondition(existingContents == "original")
        let localizedName = AttachmentFileName.sanitized(String(repeating: "中文📁", count: 100) + ".pdf")
        precondition(localizedName.utf8.count <= 160 && localizedName.hasSuffix(".pdf"))
        let hostile = AttachmentFileName.availableURL(in: saveDirectory, suggestedName: "../../file.pdf")
        precondition(hostile.deletingLastPathComponent().path == saveDirectory.path)
        print("PASS: timestamp variants, authenticated media origin restrictions, safe filenames, duplicate save preservation")

        var state = MessageSyncState()
        let initial = state.ticket
        precondition(state.accepts(initial))
        state.changed()
        precondition(!state.accepts(initial))
        let beforeLogout = state.ticket
        state.reset()
        precondition(!state.accepts(beforeLogout))
        precondition(MessageSyncState.overlappingCursor("2026-10-22T00:00:01.000Z") == "2026-10-22T00:00:00.000Z")
        precondition(MessageSyncState.overlappingCursor("2026-10-22T00:00:01Z") == "2026-10-22T00:00:00.000Z")
        var tombstone = sample[0]
        tombstone.isDeleted = true
        let delta = [tombstone, message("new", category: "two")]
        let merged = MessageSyncState.merging(delta, into: sample)
        precondition(!merged.contains { $0.id == tombstone.id })
        precondition(merged.count == sample.count)
        precondition(MessageSyncState.merging(delta, into: merged) == merged)
        let cache = MessageSnapshotStore()
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        try await cache.write(merged, to: cacheURL, revision: 2)
        try await cache.write(sample, to: cacheURL, revision: 1)
        let snapshot = await cache.read([SyncaMessage].self, from: cacheURL)
        precondition(snapshot == merged)
        try await cache.remove(cacheURL, revision: 4)
        try await cache.write(sample, to: cacheURL, revision: 3)
        precondition(!FileManager.default.fileExists(atPath: cacheURL.path))
        print("PASS: mutation/session fences, overlapping cursor, tombstones, idempotent merge, ordered cache writes and logout removal")

        let large = (0..<10_000).map {
            message(String(format: "%05d", $0), category: "category-\($0 % 20)", cleared: $0 % 3 == 0,
                    date: String(format: "%08d", $0))
        }
        let start = Date()
        let largeIndex = MessageListIndex(messages: large.reversed())
        for category in 0..<20 {
            let id = "category-\(category)"
            let expected = large.filter { $0.categoryId == id }.sorted {
                if $0.isCleared != $1.isCleared { return $0.isCleared }
                return $0.createdAt < $1.createdAt
            }
            precondition(largeIndex.byCategory[id] == expected)
            precondition(largeIndex.todoCountsByCategory[id] == expected.filter { !$0.isCleared }.count)
        }
        precondition(largeIndex.ordered.count == 10_000)
        print("PASS: empty, stable ordering, categories, edits, deletion, counts, and 10,000-message dataset (\(Date().timeIntervalSince(start))s)")
    }
}
