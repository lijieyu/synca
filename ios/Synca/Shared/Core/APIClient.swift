import Foundation
import UniformTypeIdentifiers

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    private var sessionGeneration = UUID()
    private var downloads: [UUID: Task<(URL, URLResponse), Error>] = [:]
    private var requests: [UUID: Task<(Data, URLResponse), Error>] = [:]

    func cancelPendingRequests() {
        sessionGeneration = UUID()
        requests.values.forEach { $0.cancel() }
        requests.removeAll()
        downloads.values.forEach { $0.cancel() }
        downloads.removeAll()
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let generation = sessionGeneration
        let id = UUID()
        let task = Task { try await URLSession.shared.data(for: request) }
        requests[id] = task
        defer { requests.removeValue(forKey: id) }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard generation == sessionGeneration else { throw CancellationError() }
            try Task.checkCancellation()
            return result
        } catch {
            guard generation == sessionGeneration else { throw CancellationError() }
            throw error
        }
    }

    private let baseURL: String
    private let currentUserIdKey = "currentUserId"
    private let currentUserEmailKey = "currentUserEmail"
    @Published var token: String?
    @Published private(set) var currentUserId: String?
    @Published private(set) var currentUserEmail: String?

    private init() {
        self.baseURL = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://127.0.0.1:3000"
        self.token = KeychainHelper.load(key: "authToken")
        self.currentUserId = UserDefaults.standard.string(forKey: currentUserIdKey)
        self.currentUserEmail = UserDefaults.standard.string(forKey: currentUserEmailKey)
    }

    var isAuthenticated: Bool { token != nil }

    func setToken(_ newToken: String, userId: String? = nil) {
        cancelPendingRequests()
        token = newToken
        KeychainHelper.save(key: "authToken", value: newToken)
        if let userId {
            setCurrentUserId(userId)
        }
    }

    func clearToken() {
        cancelPendingRequests()
        ImageCache.clearCache()
        AttachmentCache.clearCache()
        token = nil
        KeychainHelper.delete(key: "authToken")
        setCurrentUserId(nil)
        setCurrentUserEmail(nil)
    }

    func setCurrentUserId(_ newUserId: String?) {
        currentUserId = newUserId
        if let newUserId {
            UserDefaults.standard.set(newUserId, forKey: currentUserIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentUserIdKey)
        }
    }

    func setCurrentUserEmail(_ newEmail: String?) {
        currentUserEmail = newEmail
        if let newEmail {
            UserDefaults.standard.set(newEmail, forKey: currentUserEmailKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentUserEmailKey)
        }
    }

    func attachmentSession(for url: URL) throws -> UUID {
        _ = try attachmentRequest(for: url)
        return sessionGeneration
    }

    func isCurrentSession(_ identifier: UUID) -> Bool { identifier == sessionGeneration }

    private func attachmentRequest(for url: URL) throws -> URLRequest {
        guard let base = URL(string: baseURL), AttachmentOrigin.matches(url, baseURL: base) else {
            throw APIError.invalidResponse
        }
        guard let token else { throw APIError.unauthorized }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15 * 60
        return request
    }

    /// Disk-backed downloads are session-fenced, including images saved from a row action.
    func downloadAttachment(from url: URL) async throws -> URL {
        let generation = sessionGeneration
        let request = try attachmentRequest(for: url)
        let id = UUID()
        let delegate = AttachmentRedirectDelegate(origin: url)
        let task = Task { try await URLSession.shared.download(for: request, delegate: delegate) }
        downloads[id] = task
        defer { downloads.removeValue(forKey: id) }
        let (temporaryURL, response) = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        do {
            guard generation == sessionGeneration else { throw CancellationError() }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200...299).contains(response.statusCode) else {
                let handle = try FileHandle(forReadingFrom: temporaryURL)
                defer { try? handle.close() }
                throw decodeAPIError(statusCode: response.statusCode, data: try handle.read(upToCount: 64 * 1024) ?? Data())
            }
            return temporaryURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    // MARK: - Auth

    func loginWithApple(idToken: String, deviceId: String?, name: String? = nil) async throws -> AuthResponse {
        var body: [String: Any] = ["idToken": idToken]
        if let deviceId { body["deviceId"] = deviceId }
        if let name { body["name"] = name }

        return try await post("/auth/apple", body: body, authenticated: false)
    }

    func updateTimezone(offsetSeconds: Int) async throws {
        let _: OkResponse = try await post("/me/timezone", body: [
            "offsetSeconds": offsetSeconds,
        ])
    }

    func getAccessStatus() async throws -> AccessStatus {
        let response: AccessStatusResponse = try await get("/me/access-status")
        if let userId = response.userId {
            setCurrentUserId(userId)
        }
        if let email = response.email, !email.isEmpty {
            setCurrentUserEmail(email)
        }
        return response.accessStatus
    }

    func syncPurchases(signedTransactions: [String]) async throws -> AccessStatus {
        let response: AccessStatusResponse = try await post("/me/purchases/sync", body: [
            "signedTransactions": signedTransactions,
        ])
        if let userId = response.userId {
            setCurrentUserId(userId)
        }
        if let email = response.email, !email.isEmpty {
            setCurrentUserEmail(email)
        }
        return response.accessStatus
    }

    func requestLifetimeUpgradeOfferCode(kind: LifetimeUpgradeOfferKind) async throws -> LifetimeUpgradeOfferCodeResponse {
        try await post("/me/lifetime-upgrade-offer-code", body: [
            "kind": kind.rawValue,
        ])
    }

    func deleteAccount() async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/me/account")!)
        request.httpMethod = "DELETE"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let _: OkResponse = try await execute(request)
    }

    // MARK: - Messages

    func listMessages(since: String? = nil, limit: Int? = nil) async throws -> [SyncaMessage] {
        var params: [String: String] = [:]
        if let since { params["since"] = MessageSyncState.overlappingCursor(since) }
        if let limit { params["limit"] = String(limit) }
        let response: MessagesResponse = try await get("/messages", params: params)
        return response.messages
    }

    func listMessageCategories() async throws -> [SyncaMessageCategory] {
        let response: MessageCategoriesResponse = try await get("/message-categories")
        return response.categories
    }

    func createMessageCategory(name: String, color: MessageCategoryColor) async throws -> SyncaMessageCategory {
        try await post("/message-categories", body: [
            "name": name,
            "color": color.rawValue,
        ])
    }

    func updateMessageCategory(id: String, name: String? = nil, color: MessageCategoryColor? = nil) async throws -> SyncaMessageCategory {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let color { body["color"] = color.rawValue }
        return try await patch("/message-categories/\(id)", body: body)
    }

    func deleteMessageCategory(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/message-categories/\(id)")!)
        request.httpMethod = "DELETE"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let _: OkResponse = try await execute(request)
    }

    func reorderMessageCategories(categoryIds: [String]) async throws {
        let _: OkResponse = try await put("/message-categories/order", body: [
            "categoryIds": categoryIds,
        ])
    }

    func sendTextMessage(text: String, sourceDevice: String? = nil, categoryId: String? = nil) async throws -> SyncaMessage {
        var body: [String: Any] = ["textContent": text]
        if let sourceDevice { body["sourceDevice"] = sourceDevice }
        if let categoryId { body["categoryId"] = categoryId }
        return try await post("/messages", body: body)
    }

    private func detectMimeType(for data: Data) -> (mime: String, ext: String) {
        if data.count >= 8 {
            let header = data.prefix(8)
            // PNG: 89 50 4E 47 0D 0A 1A 0A
            if header.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) {
                return ("image/png", ".png")
            }
            // JPEG: FF D8 FF
            if header.prefix(3) == Data([0xFF, 0xD8, 0xFF]) {
                return ("image/jpeg", ".jpg")
            }
            // GIF: 47 49 46 38
            if header.prefix(4) == Data([0x47, 0x49, 0x46, 0x38]) {
                return ("image/gif", ".gif")
            }
        }
        if data.count >= 12 {
            // HEIC/HEIF: Look for "ftypheic", "ftypheif", "ftypmif1", etc at offset 4
            let sub = data[4..<12]
            if let brand = String(data: sub, encoding: .ascii) {
                if brand.hasPrefix("ftyp") && (brand.contains("heic") || brand.contains("heif") || brand.contains("mif1") || brand.contains("heix") || brand.contains("hevc")) {
                    return ("image/heic", ".heic")
                }
            }
        }
        return ("image/jpeg", ".jpg") // Default to JPEG
    }

    func sendImageMessage(imageData: Data, sourceDevice: String? = nil, categoryId: String? = nil) async throws -> SyncaMessage {
        guard imageData.count <= PendingFileUpload.maxImageSize else { throw APIError.imageTooLarge }
        let url = URL(string: "\(baseURL)/messages/image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        request.setValue(String(imageData.count), forHTTPHeaderField: "X-Upload-Size")
        let format = detectMimeType(for: imageData)

        var data = Data()
        // Image part
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo\(format.ext)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(format.mime)\r\n\r\n".data(using: .utf8)!)
        data.append(imageData)
        data.append("\r\n".data(using: .utf8)!)

        // Source device part
        if let sourceDevice {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"sourceDevice\"\r\n\r\n".data(using: .utf8)!)
            data.append(sourceDevice.data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)
        }

        if let categoryId {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"categoryId\"\r\n\r\n".data(using: .utf8)!)
            data.append(categoryId.data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)
        }

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = data

        let (responseData, response) = try await performRequest(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard httpResponse.statusCode == 201 else {
            throw decodeAPIError(statusCode: httpResponse.statusCode, data: responseData)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SyncaMessage.self, from: responseData)
    }

    func sendFileMessage(file: PendingFileUpload, sourceDevice: String? = nil, categoryId: String? = nil,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> SyncaMessage {
        let generation = sessionGeneration
        let fileURL = file.fileURL
        let size = file.fileSize
        let boundary = UUID().uuidString
        let name = multipartUploadFileName(for: file.fileName)
        let mime = file.mimeType ?? "application/octet-stream"
        var fields = ["fileName": multipartFieldValue(file.fileName)]
        if let sourceDevice { fields["sourceDevice"] = multipartFieldValue(sourceDevice) }
        if let categoryId { fields["categoryId"] = multipartFieldValue(categoryId) }
        let uploadFields = fields
        let preparation = Task.detached(priority: .userInitiated) {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: destination.path, contents: nil)
            do {
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                func write(_ value: String) throws { try output.write(contentsOf: Data(value.utf8)) }
                try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: \(mime)\r\n\r\n")
                let input = try FileHandle(forReadingFrom: fileURL)
                defer { try? input.close() }
                var copied = 0
                while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    copied += chunk.count
                    guard copied <= size else { throw APIError.fileTooLarge }
                    try output.write(contentsOf: chunk)
                }
                guard copied == size else { throw APIError.invalidResponse }
                try write("\r\n")
                for (key, value) in uploadFields {
                    try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n")
                }
                try write("--\(boundary)--\r\n")
                return destination
            } catch { try? FileManager.default.removeItem(at: destination); throw error }
        }
        let bodyURL = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        guard generation == sessionGeneration else { throw CancellationError() }
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "\(baseURL)/messages/file")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15 * 60
        request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "X-Upload-Size")
        request.setValue(file.uploadID, forHTTPHeaderField: "X-Upload-ID")
        let delegate = UploadProgressDelegate(progress)
        let task = Task { try await URLSession.shared.upload(for: request, fromFile: bodyURL, delegate: delegate) }
        let id = UUID()
        requests[id] = task
        uploadRequests[id] = task
        defer { requests.removeValue(forKey: id); uploadRequests.removeValue(forKey: id) }
        let (data, response) = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard generation == sessionGeneration else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard response.statusCode == 201 else { throw decodeAPIError(statusCode: response.statusCode, data: data) }
        return try JSONDecoder().decode(SyncaMessage.self, from: data)
    }

    private var uploadRequests: [UUID: Task<(Data, URLResponse), Error>] = [:]
    func cancelUploads() { uploadRequests.values.forEach { $0.cancel() } }

    func clearMessage(id: String) async throws {
        let _: OkResponse = try await patch("/messages/\(id)/clear")
    }

    func updateMessageCategoryAssignment(messageId: String, categoryId: String?) async throws -> SyncaMessage {
        var body: [String: Any] = [:]
        body["categoryId"] = categoryId ?? NSNull()
        return try await patch("/messages/\(messageId)/category", body: body)
    }

    func deleteMessage(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages/\(id)")!)
        request.httpMethod = "DELETE"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let _: OkResponse = try await execute(request)
    }

    func clearAllMessages(categoryId: String? = nil) async throws -> Int {
        var body: [String: Any] = [:]
        body["categoryId"] = categoryId ?? NSNull()
        let response: OkResponse = try await post("/messages/clear-all", body: body)
        return response.clearedCount ?? 0
    }

    func deleteCompletedMessages(categoryId: String? = nil) async throws -> Int {
        var body: [String: Any] = [:]
        body["categoryId"] = categoryId ?? NSNull()
        let response: OkResponse = try await post("/messages/delete-completed", body: body)
        return response.deletedCount ?? 0
    }

    func getUnclearedCount() async throws -> Int {
        let response: UnclearedCountResponse = try await get("/messages/uncleared-count")
        return response.count
    }

    // MARK: - Push Token

    func registerPushToken(token: String, platform: String = "ios", apnsEnvironment: String, topic: String? = nil) async throws {
        var body: [String: Any] = [
            "token": token,
            "platform": platform,
            "apnsEnvironment": apnsEnvironment,
        ]
        if let topic { body["topic"] = topic }
        let _: OkResponse = try await post("/me/push-token", body: body)
    }

    func submitFeedback(content: String, email: String, imageDatas: [Data],
                         deviceModel: String, osVersion: String, appVersion: String) async throws {
        let url = URL(string: "\(baseURL)/feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "content", value: content)
        appendField(name: "email", value: email)
        appendField(name: "deviceModel", value: deviceModel)
        appendField(name: "osVersion", value: osVersion)
        appendField(name: "appVersion", value: appVersion)

        for (index, imageData) in imageDatas.enumerated() {
            let format = detectMimeType(for: imageData)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"images\"; filename=\"feedback-\(index)\(format.ext)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(format.mime)\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let _: OkResponse = try await execute(request)
    }

    // MARK: - Generic HTTP Methods

    private func get<T: Decodable>(_ path: String, params: [String: String] = [:],
                                    authenticated: Bool = true) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(path)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await execute(request)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any],
                                     authenticated: Bool = true) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func put<T: Decodable>(_ path: String, body: [String: Any],
                                    authenticated: Bool = true) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func patch<T: Decodable>(_ path: String, body: [String: Any] = [:],
                                      authenticated: Bool = true) async throws -> T {
        var request = URLRequest(url: URL(string: "\(baseURL)\(path)")!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        #if DEBUG
        print("[APIClient] >>> \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
        #endif

        let (data, response) = try await performRequest(request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIClient] ❌ Invalid response type")
            throw APIError.invalidResponse
        }
        
        #if DEBUG
        print("[APIClient] <<< Status: \(httpResponse.statusCode)")
        #endif

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw decodeAPIError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func decodeAPIError(statusCode: Int, data: Data) -> APIError {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if statusCode == 401 {
            return .unauthorized
        }

        if let error = try? decoder.decode(ServerErrorResponse.self, from: data) {
            if error.error == "storage_limit_reached" { return .storageFull }
            if error.error == "file_upload_requires_paid" { return .fileRequiresPaid }
            if error.error == "attachment_expired" { return .attachmentExpired }
        }

        if statusCode == 413 {
            return .fileTooLarge
        }

        if statusCode == 400,
           let serverError = try? decoder.decode(ServerErrorResponse.self, from: data) {
            switch serverError.error {
            case "message_too_long":
                return .messageTooLong(2000)
            case "feedback_too_long":
                return .feedbackTooLong(2000)
            case "file_too_large":
                return .fileTooLarge
            case "unsupported_file_type", "invalid_upload", "no_file_provided":
                return .unsupportedFileType
            default:
                break
            }
        }

        if (statusCode == 403 || statusCode == 409),
           let serverError = try? decoder.decode(ServerErrorResponse.self, from: data) {
            switch serverError.error {
            case "offer_not_eligible", "offer_code_unavailable":
                return .offerUnavailable
            default:
                break
            }
        }

        if statusCode == 403,
           let serverError = try? decoder.decode(ServerErrorResponse.self, from: data),
           serverError.error == "daily_limit_reached" {
            return .dailyLimitReached(serverError.accessStatus)
        }

        return .httpError(statusCode, String(data: data, encoding: .utf8))
    }
}

private extension APIClient {
    func multipartFieldValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    func multipartUploadFileName(for fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let safeExt = PendingFileUpload.supportedExtensions.contains(ext) ? ext : "bin"
        return "attachment.\(safeExt)"
    }

    func mimeTypeForFileName(_ fileName: String) -> String? {
        let ext = URL(fileURLWithPath: fileName).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else {
            return nil
        }
        return type.preferredMIMEType
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case dailyLimitReached(AccessStatus?)
    case messageTooLong(Int)
    case feedbackTooLong(Int)
    case storageFull, fileRequiresPaid, attachmentExpired, imageTooLarge
    case fileTooLarge
    case unsupportedFileType
    case offerUnavailable
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .storageFull: return String(localized: "storage.full", bundle: .main)
        case .fileRequiresPaid: return String(localized: "storage.paid_required", bundle: .main)
        case .attachmentExpired: return String(localized: "storage.expired", bundle: .main)
        case .imageTooLarge: return String(localized: "storage.image_too_large", bundle: .main)
        case .invalidResponse: return String(localized: "api.invalid_response", bundle: .main)
        case .unauthorized: return String(localized: "api.unauthorized", bundle: .main)
        case .dailyLimitReached: return String(localized: "access.limit_reached_title", bundle: .main)
        case .messageTooLong(let limit):
            return String(format: String(localized: "message_list.error_too_long", bundle: .main), limit)
        case .feedbackTooLong(let limit):
            return String(format: String(localized: "feedback.error_content_too_long", bundle: .main), limit)
        case .fileTooLarge:
            return String(localized: "message_file.error_too_large", bundle: .main)
        case .unsupportedFileType:
            return String(localized: "message_file.error_unsupported", bundle: .main)
        case .offerUnavailable:
            return String(localized: "access.offer_unavailable", bundle: .main)
        case .httpError(let code, let message): return String(format: String(localized: "api.http_error", bundle: .main), code, message ?? "")
        }
    }
}

private struct ServerErrorResponse: Decodable {
    let error: String
    let accessStatus: AccessStatus?
}

struct LifetimeUpgradeOfferCodeResponse: Codable {
    let ok: Bool
    let kind: LifetimeUpgradeOfferKind
    let code: String
    let discountedPriceLabel: String
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
    }
}

private final class AttachmentRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { AttachmentOrigin.matches($0, baseURL: origin) } == true ? request : nil)
    }
}
