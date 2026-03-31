import Foundation

@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    private let baseURL: String
    @Published var token: String?

    private init() {
        self.baseURL = (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://127.0.0.1:3000"
        self.token = KeychainHelper.load(key: "authToken")
    }

    var isAuthenticated: Bool { token != nil }

    func setToken(_ newToken: String) {
        token = newToken
        KeychainHelper.save(key: "authToken", value: newToken)
    }

    func clearToken() {
        token = nil
        KeychainHelper.delete(key: "authToken")
    }

    // MARK: - Auth

    func loginWithApple(idToken: String, deviceId: String? = nil) async throws -> AuthResponse {
        var body: [String: Any] = ["idToken": idToken]
        if let deviceId { body["deviceId"] = deviceId }
        return try await post("/auth/apple", body: body, authenticated: false)
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
            throw APIError.httpError(httpResponse.statusCode, String(data: responseData, encoding: .utf8))
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

    // MARK: - Generic HTTP Methods

    private func get<T: Decodable>(_ path: String, params: [String: String] = [:],
                                    authenticated: Bool = true) async throws -> T {
        var components = URLComponents(string: "\(baseURL)\(path)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
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
            throw APIError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器响应异常"
        case .unauthorized: return "登录已过期，请重新登录"
        case .httpError(let code, let message): return "请求失败 (\(code)): \(message ?? "")"
        }
    }
}
