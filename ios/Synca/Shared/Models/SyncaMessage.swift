import Foundation

struct PendingFileUpload: Equatable {
    let data: Data
    let fileName: String
    let mimeType: String?
}

struct SyncaMessage: Codable, Identifiable, Equatable {
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
    var categoryId: String?
    var categoryName: String?
    var categoryColor: MessageCategoryColor?
    var categoryIsDefault: Bool?
    var isCleared: Bool
    var isDeleted: Bool
    var sourceDevice: String?
    let createdAt: String
    var updatedAt: String

    enum MessageType: String, Codable {
        case text
        case image
        case file
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

    private static func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        // Time format
        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.setLocalizedDateFormatFromTemplate("Hm")
        let timeString = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return timeString
        } else if calendar.isDateInYesterday(date) {
            return String(format: String(localized: "message.date.yesterday", bundle: .main), timeString)
        } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            // Within a week, show weekday
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("EEEE")
            return "\(f.string(from: date)) \(timeString)"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("Md")
            return "\(f.string(from: date)) \(timeString)"
        } else {
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("yMd")
            return "\(f.string(from: date)) \(timeString)"
        }
    }
}

enum MessageCategoryColor: String, Codable, CaseIterable, Identifiable {
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

struct SyncaMessageCategory: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    var name: String
    var color: MessageCategoryColor
    var isDefault: Bool
    let createdAt: String
    var updatedAt: String
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
