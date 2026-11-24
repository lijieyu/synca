import Foundation
import Combine

struct EmailChallenge: Decodable {
    let challengeId: String
    let expiresAt: Date
    let resendAt: Date
}

struct LoginMethods: Decodable {
    let apple: Bool
    let email: String?
}

struct AppleBindingChallenge: Decodable {
    let challengeId: String
    let nonce: String
    let expiresAt: Date
}

enum EmailAuthResult {
    case signedIn(AuthResponse)
    case bound(LoginMethods)
}

struct EmailAuthFailure: LocalizedError {
    let code: String
    var retryAfter: Int? = nil
    var errorDescription: String? {
        let known = ["invalid_email", "invalid_code", "code_expired", "code_attempts_exceeded", "rate_limited",
                     "email_unavailable", "email_send_failed", "email_in_use", "apple_in_use", "email_already_bound",
                     "apple_already_bound", "apple_auth_failed"]
        return AppLocalization.string("email_auth.errors.\(known.contains(code) ? code : "generic")")
    }
}

/// Owns only the two-step form. Session changes happen in the caller after a current response.
@MainActor final class EmailAuthModel: ObservableObject {
    @Published var email = ""
    @Published var code = ""
    @Published private(set) var sentEmail = ""
    @Published private(set) var challenge: EmailChallenge?
    @Published private(set) var isBusy = false
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var retryAt = Date.distantPast
    private var generation = UUID()
    private var codeBlocked = false
    private var verifyRetryAt = Date.distantPast
    private let send: (String) async throws -> EmailChallenge
    private let verify: (String, String) async throws -> EmailAuthResult

    init(send: @escaping (String) async throws -> EmailChallenge,
         verify: @escaping (String, String) async throws -> EmailAuthResult) {
        self.send = send; self.verify = verify
    }
    var hasChallenge: Bool { challenge != nil }
    var resendSeconds: Int { max(0, Int(ceil(retryAt.timeIntervalSinceNow))) }
    var canVerify: Bool { !isBusy && verifyRetryAt <= Date() && !codeBlocked && code.count == 6 && code.utf8.allSatisfy { (48...57).contains($0) } }

    func sendCode() async {
        guard !isBusy, resendSeconds == 0 else { return }
        let address = (hasChallenge ? sentEmail : email).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.count <= 254, address.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            errorMessage = EmailAuthFailure(code: "invalid_email").localizedDescription; return
        }
        let operation = generation
        isBusy = true; isSending = true; errorMessage = nil
        defer { if generation == operation { isBusy = false; isSending = false } }
        do {
            let result = try await send(address)
            guard generation == operation, !Task.isCancelled else { return }
            sentEmail = address; challenge = result; retryAt = result.resendAt; code = ""; codeBlocked = false
        } catch {
            guard generation == operation, !Task.isCancelled else { return }
            handle(error)
        }
    }

    func verifyCode(completion: (EmailAuthResult) -> Void) async {
        guard canVerify, let challenge else { return }
        guard challenge.expiresAt > Date() else {
            handle(EmailAuthFailure(code: "code_expired")); return
        }
        let operation = generation
        isBusy = true; errorMessage = nil
        defer { if generation == operation { isBusy = false; isSending = false } }
        do {
            let result = try await verify(challenge.challengeId, code)
            guard generation == operation, !Task.isCancelled else { return }
            completion(result)
        } catch {
            guard generation == operation, !Task.isCancelled else { return }
            handle(error, verifying: true)
        }
    }

    func changeEmail() {
        cancel(); challenge = nil; sentEmail = ""; code = ""; codeBlocked = false; errorMessage = nil
        // Retain server cooldown when going back to prevent repeat sends.
    }
    func cancel() { generation = UUID(); isBusy = false; isSending = false }
    private func handle(_ error: Error, verifying: Bool = false) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if let failure = error as? EmailAuthFailure {
            if let retry = failure.retryAfter {
                let next = Date().addingTimeInterval(TimeInterval(max(1, retry)))
                if verifying { verifyRetryAt = next } else { retryAt = next }
            }
            if ["code_expired", "code_attempts_exceeded", "email_in_use", "email_already_bound"].contains(failure.code) { codeBlocked = true }
            errorMessage = failure.localizedDescription
        } else if case APIError.unauthorized = error {
            errorMessage = error.localizedDescription
        } else { errorMessage = EmailAuthFailure(code: "generic").localizedDescription }
    }
}
