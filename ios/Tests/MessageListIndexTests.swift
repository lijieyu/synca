import Foundation

@main
struct MessageListIndexTests {
    static func message(_ id: String, category: String?, cleared: Bool = false, date: String = "2026-10-22T00:00:00Z") -> SyncaMessage {
        SyncaMessage(id: id, userId: "test", type: .text, categoryId: category,
                     isCleared: cleared, isDeleted: false, createdAt: date, updatedAt: date)
    }

    static func main() async throws {
        let drag = CategoryReorderDrag.payload(for: "work")
        let nextDrag = CategoryReorderDrag.payload(for: "work")
        precondition(drag != nextDrag, "Each new drag must invalidate the prior session payload")
        precondition(CategoryReorderDrag.validatedID(from: Data(drag.utf8), expected: drag) == "work")
        for unrelated in ["work", "unrelated external text", nextDrag, CategoryReorderDrag.payload(for: "life")] {
            precondition(CategoryReorderDrag.validatedID(from: Data(unrelated.utf8), expected: drag) == nil,
                         "Unrelated text and stale or foreign drag sessions must never select a category")
        }
        precondition(CategoryReorderDrag.validatedID(from: nil, expected: drag) == nil)
        precondition(CategoryReorderDrag.validatedID(from: Data("work\ninvalid-nonce".utf8), expected: "work\ninvalid-nonce") == nil)
        let acceptsText = CategoryReorderDrag.load([NSItemProvider(object: "external text" as NSString)], expected: drag) { _ in
            preconditionFailure("Generic text must not reach reorder callback")
        }
        precondition(!acceptsText)
        let acceptedID: String = await withCheckedContinuation { continuation in
            let accepted = CategoryReorderDrag.load([CategoryReorderDrag.provider(drag)], expected: drag) { id in
                continuation.resume(returning: id)
            }
            precondition(accepted, "The app's registered category provider must be accepted")
        }
        precondition(acceptedID == "work", "Verified provider bytes must deliver the dragged category")
        let decoder = JSONDecoder()
        let legacyCategory = Data(#"{"id":"category","userId":"test","name":"Work","color":"sky","isDefault":false,"createdAt":"2026-11-09T00:00:00Z","updatedAt":"2026-11-09T00:00:00Z"}"#.utf8)
        let legacy = try decoder.decode(SyncaMessageCategory.self, from: legacyCategory)
        precondition(legacy.color == .sky && legacy.colorHex == nil && legacy.sortOrder == 0)
        for preset in CategoryColorPreset.all {
            var payload = try JSONSerialization.jsonObject(with: legacyCategory) as! [String: Any]
            payload["color"] = preset.legacy.rawValue
            payload["colorHex"] = preset.hex
            let decoded = try decoder.decode(SyncaMessageCategory.self, from: JSONSerialization.data(withJSONObject: payload))
            precondition(decoded.color == preset.legacy && decoded.colorHex == preset.hex)
            precondition(CategoryColorPreset.matching(preset.hex.uppercased())?.hex == preset.hex)
            let roundtrip = try decoder.decode(SyncaMessageCategory.self, from: JSONEncoder().encode(decoded))
            precondition(roundtrip == decoded)
        }
        precondition(CategoryColorPreset.all.count == 16 && MessageCategoryColor.allCases.count == 8)
        precondition(CategoryColorPreset.matching("#abcdef") == nil)
        var metadata = message("metadata", category: "category")
        metadata.categoryColor = .sky; metadata.categoryColorHex = "#4169a8"
        let decodedMessage = try decoder.decode(SyncaMessage.self, from: JSONEncoder().encode(metadata))
        precondition(decodedMessage.categoryColor == .sky && decodedMessage.categoryColorHex == "#4169a8")
        print("PASS: category drag validates actual payload and nonce, rejects stale/foreign/generic text and malformed data")
        print("PASS: legacy category decode, all 16 compatible presets, cache roundtrip, invalid hex fallback and record color metadata")
        for character in ["a", "中", "👩🏽‍💻", "e\u{301}"] {
            let boundary = String(repeating: character, count: 10000)
            precondition(MessageTextPolicy.accepts(boundary))
            precondition(!MessageTextPolicy.accepts(boundary + character))
        }
        print("PASS: message limit accepts 10000 graphemes and rejects 10001 for ASCII, CJK and composed emoji")
        var editable = message("edit", category: "one", cleared: true)
        precondition(editable.canEditText)
        editable.imagePath = "legacy.png"
        precondition(!editable.canEditText)
        editable.imagePath = nil
        editable.fileUrl = "https://synca.example/api/media/file"
        precondition(!editable.canEditText)
        editable.fileUrl = nil
        editable.isDeleted = true
        precondition(!editable.canEditText)
        let image = SyncaMessage(id: "image", userId: "test", type: .image, isCleared: false, isDeleted: false,
                                 createdAt: "2026-11-06T00:00:00Z", updatedAt: "2026-11-06T00:00:00Z")
        precondition(!image.canEditText)
        print("PASS: pure text editing allows completed text but rejects attachments and deleted records")
        let order = ["all", "one", "two"]
        precondition(CategorySwipeNavigation.target(order: order, selected: "one", horizontal: -80, vertical: 10) == "two")
        precondition(CategorySwipeNavigation.target(order: order, selected: "one", horizontal: 80, vertical: 10) == "all")
        precondition(CategorySwipeNavigation.target(order: order, selected: "one", horizontal: 80, vertical: 100) == nil)
        precondition(CategorySwipeNavigation.target(order: order, selected: "one", horizontal: 20, vertical: 0) == nil)
        precondition(CategorySwipeNavigation.target(order: order, selected: "all", horizontal: 80, vertical: 0) == nil)
        precondition(CategorySwipeNavigation.target(order: order, selected: "two", horizontal: -80, vertical: 0) == nil)
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

        let newer = message("mutation", category: "two", date: "2026-11-02T00:00:02.000Z")
        let delayed = message("mutation", category: "one", cleared: true, date: "2026-11-02T00:00:01Z")
        precondition(!MessageSyncState.acceptingMutation(delayed, over: newer))
        precondition(MessageSyncState.acceptingMutation(newer, over: delayed))
        var originalText = delayed
        originalText.isCleared = false
        originalText.textContent = "original draft source"
        var categoryUpdated = originalText
        categoryUpdated.categoryName = "Renamed"
        categoryUpdated.updatedAt = newer.updatedAt
        precondition(MessageSyncState.textEditRevision(original: originalText, current: categoryUpdated) == newer.updatedAt)
        var concurrentText = categoryUpdated
        concurrentText.textContent = "another device"
        precondition(MessageSyncState.textEditRevision(original: originalText, current: concurrentText) == nil)
        precondition(MessageSyncState.textEditRevision(original: categoryUpdated, current: originalText) == nil)
        var deletedText = categoryUpdated
        deletedText.isDeleted = true
        precondition(MessageSyncState.textEditRevision(original: originalText, current: deletedText) == nil)
        print("PASS: category metadata rebase uses authoritative revision; concurrent text, stale response and deletion remain protected")
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
