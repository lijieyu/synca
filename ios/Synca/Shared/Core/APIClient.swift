import Foundation

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

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
        token = newToken
        KeychainHelper.save(key: "authToken", value: newToken)
        if let userId {
            setCurrentUserId(userId)
        }
    }

    func clearToken() {
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

    // MARK: - Auth

    func loginWithApple(idToken: String, deviceId: String? = nil) async throws -> AuthResponse {
        var body: [String: Any] = ["idToken": idToken]
        if let deviceId { body["deviceId"] = deviceId }
        return try await post("/auth/apple", body: body, authenticated: false)
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

    // MARK: - Messages

    func listMessages(since: String? = nil, limit: Int? = nil) async throws -> [SyncaMessage] {
        var params: [String: String] = [:]
        if let since { params["since"] = since }
        if let limit { params["limit"] = String(limit) }
        let response: MessagesResponse = try await get("/messages", params: params)
        return response.messages
    }

    func sendTextMessage(text: String, sourceDevice: String? = nil) async throws -> SyncaMessage {
        var body: [String: Any] = ["textContent": text]
        if let sourceDevice { body["sourceDevice"] = sourceDevice }
        return try await post("/messages", body: body)
    }

    func sendImageMessage(imageData: Data, sourceDevice: String? = nil) async throws -> SyncaMessage {
        let url = URL(string: "\(baseURL)/messages/image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var data = Data()
        // Image part
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        data.append(imageData)
        data.append("\r\n".data(using: .utf8)!)

        // Source device part
        if let sourceDevice {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"sourceDevice\"\r\n\r\n".data(using: .utf8)!)
            data.append(sourceDevice.data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)
        }

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
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

    func clearMessage(id: String) async throws {
        let _: OkResponse = try await patch("/messages/\(id)/clear")
    }

    func deleteMessage(id: String) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/messages/\(id)")!)
        request.httpMethod = "DELETE"
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let _: OkResponse = try await execute(request)
    }

    func clearAllMessages() async throws -> Int {
        let response: OkResponse = try await post("/messages/clear-all", body: [:])
        return response.clearedCount ?? 0
    }

    func deleteCompletedMessages() async throws -> Int {
        let response: OkResponse = try await post("/messages/delete-completed", body: [:])
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

    func submitFeedback(content: String, email: String, imageDatas: [Data]) async throws {
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

        for (index, imageData) in imageDatas.enumerated() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"images\"; filename=\"feedback-\(index).jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
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
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            print("[APIClient] Body: \(bodyString)")
        }
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[APIClient] ❌ Invalid response type")
            throw APIError.invalidResponse
        }
        
        #if DEBUG
        print("[APIClient] <<< Status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("[APIClient] Response: \(responseString)")
        }
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

        if statusCode == 400,
           let serverError = try? decoder.decode(ServerErrorResponse.self, from: data) {
            switch serverError.error {
            case "message_too_long":
                return .messageTooLong(2000)
            case "feedback_too_long":
                return .feedbackTooLong(2000)
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

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case dailyLimitReached(AccessStatus?)
    case messageTooLong(Int)
    case feedbackTooLong(Int)
    case offerUnavailable
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "api.invalid_response", bundle: .main)
        case .unauthorized: return String(localized: "api.unauthorized", bundle: .main)
        case .dailyLimitReached: return String(localized: "access.limit_reached_title", bundle: .main)
        case .messageTooLong(let limit):
            return String(format: String(localized: "message_list.error_too_long", bundle: .main), limit)
        case .feedbackTooLong(let limit):
            return String(format: String(localized: "feedback.error_content_too_long", bundle: .main), limit)
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
