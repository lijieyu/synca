import Foundation
import UniformTypeIdentifiers

struct PendingFileUpload: Equatable {
    static let maxImageSize = 50 * 1024 * 1024
    static let maxFileSize = 200 * 1024 * 1024
    static let supportedImageExtensions = Set(["jpg", "jpeg", "png", "webp", "heic", "heif", "gif"])

    let uploadID = UUID().uuidString
    let fileURL: URL
    let fileSize: Int
    private let access: ScopedUploadAccess

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.fileURL == rhs.fileURL }
    let fileName: String
    let mimeType: String?

    static func isSupportedFileURL(_ url: URL) -> Bool {
        // Known image formats keep their image-specific size limit and upload path.
        url.isFileURL && !isSupportedImageURL(url)
    }

    static func isSupportedImageURL(_ url: URL) -> Bool {
        supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    static func imageData(from url: URL) -> Data? {
        guard isSupportedImageURL(url) else { return nil }

        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           values.isRegularFile == false {
            return nil
        }

        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxImageSize,
              let data = try? Data(contentsOf: url), data.count <= maxImageSize else {
            return nil
        }

        return data
    }

    static func read(from url: URL) -> PendingFileUpload? {
        guard isSupportedFileURL(url) else { return nil }
        let access = ScopedUploadAccess(url)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maxFileSize else { return nil }
        return PendingFileUpload(fileURL: url, fileSize: size, access: access,
            fileName: url.lastPathComponent, mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType)
    }

}

private final class ScopedUploadAccess {
    let url: URL
    let started: Bool
    init(_ url: URL) { self.url = url; started = url.startAccessingSecurityScopedResource() }
    deinit { if started { url.stopAccessingSecurityScopedResource() } }
}

struct SyncaMessage: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    let type: MessageType
    var textContent: String?
    var imagePath: String?
    var imageUrl: String?
    var filePath: String?
    var fileUrl: String?
    var fileName: String?
    var fileSize: Int?
    var fileMimeType: String?
    var attachmentExpiresAt: String?
    var attachmentExpired: Bool?

    var attachmentExpiryDate: Date? {
        guard let value = attachmentExpiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    var isAttachmentExpired: Bool {
        if attachmentExpired == true { return true }
        return attachmentExpiryDate.map { $0 <= Date() } ?? false
    }
    var categoryId: String?
    var categoryName: String?
    var categoryColor: MessageCategoryColor?
    var categoryColorHex: String?
    var categoryIsDefault: Bool?
    var isCleared: Bool
    var isDeleted: Bool
    var sourceDevice: String?
    let createdAt: String
    var updatedAt: String

    enum MessageType: String, Codable, Sendable {
        case text
        case image
        case file
    }

    var canEditText: Bool {
        type == .text && !isDeleted && imagePath == nil && imageUrl == nil && filePath == nil && fileUrl == nil
    }

    var displayDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: createdAt) else { return createdAt }
            return Self.formatRelativeDate(date)
        }
        return Self.formatRelativeDate(date)
    }

    static func formatRelativeDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                                   locale: Locale = AppLocalization.locale) -> String {
        
        // Time format
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let timeString = timeFormatter.string(from: date)

        if calendar.isDate(date, inSameDayAs: now) {
            return timeString
        } else if calendar.date(byAdding: .day, value: -1, to: now).map({ calendar.isDate(date, inSameDayAs: $0) }) == true {
            return String(format: String(syncaLocalized: "message.date.yesterday", bundle: .main), timeString)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate("Md")
            return "\(f.string(from: date)) \(timeString)"
        } else {
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate("yMd")
            return "\(f.string(from: date)) \(timeString)"
        }
    }
}

enum MessageCategoryColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case sky
    case mint
    case amber
    case coral
    case violet
    case slate
    case rose
    case ocean

    var id: String { rawValue }
}

struct SyncaMessageCategory: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let userId: String
    var name: String
    var color: MessageCategoryColor
    var colorHex: String?
    var isDefault: Bool
    var sortOrder: Int
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case name
        case color
        case colorHex
        case isDefault
        case sortOrder
        case createdAt
        case updatedAt
    }

    init(
        id: String,
        userId: String,
        name: String,
        color: MessageCategoryColor,
        colorHex: String? = nil,
        isDefault: Bool,
        sortOrder: Int = 0,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.color = color
        self.colorHex = colorHex
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(MessageCategoryColor.self, forKey: .color)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
    }
}

struct SyncaUser: Codable {
    let id: String
    let appleUserId: String
    var email: String?
    var nickname: String
    let createdAt: String
    let updatedAt: String
}

struct AuthResponse: Codable {
    let token: String
    let user: SyncaUser
    let accessStatus: AccessStatus
}

struct MessagesResponse: Codable {
    let messages: [SyncaMessage]
}

struct MessageCategoriesResponse: Codable {
    let categories: [SyncaMessageCategory]
}

struct UnclearedCountResponse: Codable {
    let count: Int
}

struct OkResponse: Codable {
    let ok: Bool
    var clearedCount: Int?
    var deletedCount: Int?
}

struct ErrorResponse: Codable {
    let error: String
}

/// Built once per message mutation; category switches reuse the ordered buckets.
struct MessageListIndex {
    let ordered: [SyncaMessage]
    let byCategory: [String: [SyncaMessage]]
    let todoCount: Int
    let todoCountsByCategory: [String: Int]

    init(messages: [SyncaMessage]) {
        ordered = messages.sorted {
            if $0.isCleared != $1.isCleared { return $0.isCleared }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
        var buckets: [String: [SyncaMessage]] = [:]
        var counts: [String: Int] = [:]
        var total = 0
        for message in ordered {
            if let categoryId = message.categoryId {
                buckets[categoryId, default: []].append(message)
                if !message.isCleared { counts[categoryId, default: 0] += 1 }
            }
            if !message.isCleared { total += 1 }
        }
        byCategory = buckets
        todoCountsByCategory = counts
        todoCount = total
    }
}

/// A pull owns its cursor. Local mutations invalidate earlier snapshots instead of advancing it.
struct MessageSyncState {
    private(set) var generation = UUID()
    private(set) var revision: UInt64 = 0

    struct Ticket {
        let generation: UUID
        let revision: UInt64
    }

    var ticket: Ticket { Ticket(generation: generation, revision: revision) }
    mutating func changed() { revision &+= 1 }
    mutating func reset() { generation = UUID(); changed() }
    func accepts(_ ticket: Ticket) -> Bool {
        ticket.generation == generation && ticket.revision == revision
    }

    static func overlappingCursor(_ cursor: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: cursor)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: cursor)
        }
        guard let date else { return cursor }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date.addingTimeInterval(-1))
    }

    static func textEditRevision(original: SyncaMessage, current: SyncaMessage) -> String? {
        guard original.id == current.id, original.canEditText, current.canEditText,
              original.textContent == current.textContent,
              acceptingMutation(current, over: original) else { return nil }
        return current.updatedAt
    }

    static func acceptingMutation(_ response: SyncaMessage, over current: SyncaMessage) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ value: String) -> Date? {
            if let date = formatter.date(from: value) { return date }
            let fallback = ISO8601DateFormatter()
            return fallback.date(from: value)
        }
        guard response.id == current.id, !current.isDeleted,
              let incomingDate = date(response.updatedAt), let currentDate = date(current.updatedAt) else { return false }
        return incomingDate >= currentDate
    }

    static func merging(_ incoming: [SyncaMessage], into current: [SyncaMessage]) -> [SyncaMessage] {
        var byID: [String: SyncaMessage] = [:]
        for message in current { byID[message.id] = message }
        for message in incoming {
            if message.isDeleted { byID.removeValue(forKey: message.id) }
            else { byID[message.id] = message }
        }
        return byID.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }
}

/// Serial disk access. Revision fences prevent late tasks from resurrecting a cleared cache.
actor MessageSnapshotStore {
    private var revisions: [URL: UInt64] = [:]

    func write<Value: Encodable & Sendable>(_ value: Value, to url: URL, revision: UInt64) throws {
        guard revision > revisions[url, default: 0] else { return }
        revisions[url] = revision
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func read<Value: Decodable & Sendable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func remove(_ url: URL, revision: UInt64) throws {
        guard revision > revisions[url, default: 0] else { return }
        revisions[url] = revision
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Server-provided names never choose directories or replace a user's existing saved file.
enum AttachmentFileName {
    static func sanitized(_ value: String) -> String {
        let name = value.replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { return "Attachment" }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        func prefix(_ text: String, maximumBytes: Int) -> String {
            var result = ""
            var bytes = 0
            for character in text {
                let count = String(character).utf8.count
                guard bytes + count <= maximumBytes else { break }
                result.append(character)
                bytes += count
            }
            return result
        }
        // The cache adds a 65-byte hash prefix; UTF-8 names must still fit a filesystem component.
        let safeExt = prefix(ext, maximumBytes: 24)
        return safeExt.isEmpty ? prefix(name, maximumBytes: 160)
            : "\(prefix(stem, maximumBytes: 159 - safeExt.utf8.count)).\(safeExt)"
    }

    static func availableURL(in directory: URL, suggestedName: String) -> URL {
        let name = sanitized(suggestedName)
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = "\(stem) (\(suffix))"
            candidate = directory.appendingPathComponent(ext.isEmpty ? numbered : "\(numbered).\(ext)")
            suffix += 1
        }
        return candidate
    }
}

struct AttachmentOrigin {
    static func matches(_ url: URL, baseURL: URL) -> Bool {
        func port(_ value: URL) -> Int? { value.port ?? (value.scheme?.lowercased() == "https" ? 443 : 80) }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            && url.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && url.host?.lowercased() == baseURL.host?.lowercased()
            && port(url) == port(baseURL) && url.user == nil && url.password == nil
    }
}

// Shared, deterministic navigation policy: no wraparound and vertical scrolling wins.
enum CategorySwipeNavigation {
    static let minimumDistance: Double = 56
    static let horizontalDominance: Double = 1.5
    static func target(order: [String], selected: String, horizontal: Double, vertical: Double) -> String? {
        guard abs(horizontal) >= minimumDistance,
              abs(horizontal) > abs(vertical) * horizontalDominance,
              let index = order.firstIndex(of: selected) else { return nil }
        let next = index + (horizontal < 0 ? 1 : -1)
        return order.indices.contains(next) ? order[next] : nil
    }
}

/// User-visible character limits count extended grapheme clusters, matching Swift text editing.
enum MessageTextPolicy {
    static let maximumCharacters = 10000
    static func accepts(_ text: String) -> Bool { text.count <= maximumCharacters }
}

/// Additive presets retain the legacy wire token for old servers and clients.
struct CategoryColorPreset: Identifiable, Sendable {
    let name: String
    let hex: String
    let legacy: MessageCategoryColor
    var id: String { hex }
    static let all: [CategoryColorPreset] = [
        .init(name: "sky", hex: "#3b82f6", legacy: .sky),
        .init(name: "mint", hex: "#22c55e", legacy: .mint),
        .init(name: "amber", hex: "#f59e0b", legacy: .amber),
        .init(name: "coral", hex: "#ef4444", legacy: .coral),
        .init(name: "violet", hex: "#a855f7", legacy: .violet),
        .init(name: "slate", hex: "#64748b", legacy: .slate),
        .init(name: "rose", hex: "#ec4899", legacy: .rose),
        .init(name: "ocean", hex: "#06b6d4", legacy: .ocean),
        .init(name: "graphite", hex: "#676d78", legacy: .slate),
        .init(name: "denim", hex: "#4169a8", legacy: .sky),
        .init(name: "teal", hex: "#4a9a9d", legacy: .ocean),
        .init(name: "olive", hex: "#8da35e", legacy: .mint),
        .init(name: "honey", hex: "#d9b24b", legacy: .amber),
        .init(name: "peach", hex: "#df8e73", legacy: .coral),
        .init(name: "berry", hex: "#af597b", legacy: .rose),
        .init(name: "lavender", hex: "#8276c2", legacy: .violet)
    ]
    /// A missing legacy shade resolves exactly like selecting that color today.
    static func resolved(legacy: MessageCategoryColor, hex: String?) -> CategoryColorPreset {
        matching(hex) ?? all.first { $0.legacy == legacy } ?? all[5]
    }
    static func matching(_ hex: String?) -> CategoryColorPreset? {
        guard let hex else { return nil }
        return all.first { $0.hex == hex.lowercased() }
    }
}

/// Reordering accepts only this process's current drag payload, never generic text drops.
enum CategoryReorderDrag {
    static let type = UTType(exportedAs: "org.haerth.synca.category-reorder")
    static func payload(for id: String) -> String { id + "\n" + UUID().uuidString }
    static func provider(_ payload: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(Data(payload.utf8), nil)
            return nil
        }
        return provider
    }
    static func validatedID(from data: Data?, expected: String) -> String? {
        guard let data, String(data: data, encoding: .utf8) == expected else { return nil }
        let parts = expected.split(separator: "\n", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, UUID(uuidString: String(parts[1])) != nil else { return nil }
        return String(parts[0])
    }
    static func load(_ providers: [NSItemProvider], expected: String, onDrop: @escaping @MainActor @Sendable (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
            guard error == nil, let id = validatedID(from: data, expected: expected) else { return }
            Task { @MainActor in onDrop(id) }
        }
        return true
    }
}
