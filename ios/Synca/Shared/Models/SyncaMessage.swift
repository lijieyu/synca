import Foundation

struct SyncaMessage: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let type: MessageType
    var textContent: String?
    var imagePath: String?
    var imageUrl: String?
    var isCleared: Bool
    var isDeleted: Bool
    var sourceDevice: String?
    let createdAt: String
    var updatedAt: String

    enum MessageType: String, Codable {
        case text
        case image
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
}

struct MessagesResponse: Codable {
    let messages: [SyncaMessage]
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
