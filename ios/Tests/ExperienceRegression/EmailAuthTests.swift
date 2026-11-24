import XCTest
import UIKit
import AuthenticationServices
@testable import Synca

@MainActor final class EmailAuthTests: XCTestCase {
    func challenge(_ delay: TimeInterval = 60) -> EmailChallenge {
        EmailChallenge(challengeId: "proof", expiresAt: Date().addingTimeInterval(600), resendAt: Date().addingTimeInterval(delay))
    }
    func testSendNormalizesEmailAndPreventsImmediateResend() async {
        var sends = 0
        let model = EmailAuthModel(send: { email in
            XCTAssertEqual(email, "test@example.com"); sends += 1; return self.challenge()
        }, verify: { _, _ in .bound(LoginMethods(apple: true, email: "test@example.com")) })
        model.email = " Test@Example.com  "
        await model.sendCode()
        XCTAssertEqual(model.sentEmail, "test@example.com")
        XCTAssertTrue(model.hasChallenge)
        await model.sendCode()
        XCTAssertEqual(sends, 1)
    }
    func testWrongCodeDoesNotCompleteAndCanRetry() async {
        var completed = false
        var attempts = 0
        let model = EmailAuthModel(send: { _ in self.challenge() }, verify: { _, code in
            attempts += 1
            if code != "123456" { throw EmailAuthFailure(code: "invalid_code") }
            return .bound(LoginMethods(apple: true, email: "test@example.com"))
        })
        model.email = "test@example.com"; await model.sendCode()
        model.code = "000000"; await model.verifyCode { _ in completed = true }
        XCTAssertFalse(completed); XCTAssertNotNil(model.errorMessage)
        model.code = "123456"; await model.verifyCode { _ in completed = true }
        XCTAssertTrue(completed); XCTAssertEqual(attempts, 2)
    }
    func testBackDiscardsLateChallenge() async {
        var pending: CheckedContinuation<EmailChallenge, Error>?
        let model = EmailAuthModel(send: { _ in try await withCheckedThrowingContinuation { pending = $0 } }, verify: { _, _ in fatalError() })
        model.email = "test@example.com"
        let request = Task { await model.sendCode() }
        while pending == nil { await Task.yield() }
        model.cancel()
        pending?.resume(returning: challenge())
        await request.value
        XCTAssertFalse(model.hasChallenge); XCTAssertFalse(model.isBusy)
    }
    func testBackDiscardsLateVerification() async {
        var pending: CheckedContinuation<EmailAuthResult, Error>?
        var completed = false
        let model = EmailAuthModel(send: { _ in self.challenge() }, verify: { _, _ in try await withCheckedThrowingContinuation { pending = $0 } })
        model.email = "test@example.com"; await model.sendCode(); model.code = "123456"
        let request = Task { await model.verifyCode { _ in completed = true } }
        while pending == nil { await Task.yield() }
        model.cancel(); pending?.resume(returning: .bound(LoginMethods(apple: true, email: "test@example.com")))
        await request.value
        XCTAssertFalse(completed)
    }
    func testAttemptLimitRequiresFreshCodeAndBlocksDuplicateVerify() async {
        var calls = 0
        let model = EmailAuthModel(send: { _ in self.challenge(-1) }, verify: { _, _ in
            calls += 1; throw EmailAuthFailure(code: "code_attempts_exceeded")
        })
        model.email = "test@example.com"; await model.sendCode(); model.code = "123456"
        await model.verifyCode { _ in XCTFail() }
        await model.verifyCode { _ in XCTFail() }
        XCTAssertEqual(calls, 1); XCTAssertFalse(model.canVerify)
        await model.sendCode(); model.code = "123456"; XCTAssertTrue(model.canVerify)
    }

    func testRateLimitAndExpiry() async {
        let model = EmailAuthModel(send: { _ in throw EmailAuthFailure(code: "rate_limited", retryAfter: 90) }, verify: { _, _ in fatalError() })
        model.email = "test@example.com"; await model.sendCode()
        XCTAssertGreaterThan(model.resendSeconds, 85)
        XCTAssertFalse(model.isBusy)
        let expired = EmailAuthModel(send: { _ in EmailChallenge(challengeId: "old", expiresAt: Date().addingTimeInterval(-1), resendAt: Date()) }, verify: { _, _ in XCTFail("Expired proof must not be submitted"); return .bound(LoginMethods(apple: false, email: nil)) })
        expired.email = "test@example.com"; await expired.sendCode(); expired.code = "123456"
        await expired.verifyCode { _ in XCTFail() }
        XCTAssertNotNil(expired.errorMessage)
    }
}

final class EmailFixtureProtocol: URLProtocol {
    static var captured: [URLRequest] = []
    static var failure = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured.append(request)
        let body: String
        if Self.failure { body = #"{"error":"rate_limited","retryAfter":120}"# }
        else if request.url!.path.hasSuffix("/code") { body = #"{"challengeId":"proof","expiresAt":"2099-12-31T23:59:00.000Z","resendAt":"2099-12-31T23:50:00Z"}"# }
        else if request.url!.path.hasSuffix("/challenge") { body = #"{"challengeId":"proof","nonce":"server-nonce","expiresAt":"2099-12-31T23:59:00Z"}"# }
        else { body = #"{"apple":true,"email":"test@example.com"}"# }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.failure ? 429 : 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension EmailAuthTests {
    func testAPIKeepsLoginAndBindingSeparateAndDecodesRetryDelay() async throws {
        URLProtocol.registerClass(EmailFixtureProtocol.self)
        defer { URLProtocol.unregisterClass(EmailFixtureProtocol.self); EmailFixtureProtocol.failure = false }
        EmailFixtureProtocol.captured = []; EmailFixtureProtocol.failure = false
        APIClient.shared.setToken("isolated-session", userId: "user")
        let challenge = try await APIClient.shared.sendEmailCode(email: "test@example.com", binding: false)
        XCTAssertEqual(challenge.challengeId, "proof")
        XCTAssertNil(EmailFixtureProtocol.captured.last?.value(forHTTPHeaderField: "Authorization"))
        _ = try await APIClient.shared.sendEmailCode(email: "test@example.com", binding: true)
        XCTAssertEqual(EmailFixtureProtocol.captured.last?.url?.path, "/me/login-methods/email/code")
        XCTAssertEqual(EmailFixtureProtocol.captured.last?.value(forHTTPHeaderField: "Authorization"), "Bearer isolated-session")
        let bound = try await APIClient.shared.bindEmail(challengeId: "proof", code: "123456")
        XCTAssertTrue(bound.apple)
        let apple = try await APIClient.shared.appleBindingChallenge()
        XCTAssertEqual(apple.nonce, "server-nonce")
        _ = try await APIClient.shared.bindApple(challengeId: apple.challengeId, idToken: "identity-proof")
        XCTAssertEqual(EmailFixtureProtocol.captured.last?.url?.path, "/me/login-methods/apple")
        EmailFixtureProtocol.failure = true
        do { _ = try await APIClient.shared.sendEmailCode(email: "test@example.com", binding: false); XCTFail() }
        catch let error as EmailAuthFailure { XCTAssertEqual(error.retryAfter, 120); XCTAssertEqual(error.code, "rate_limited") }
    }
}

extension EmailAuthTests {
    func testEmailOnlyAccountDecodesWithoutAppleIdentity() throws {
        let payload = #"{"token":"email-session","user":{"id":"email-user","appleUserId":null,"email":"test@example.com","nickname":"Synca 用户","createdAt":"2026-11-24T00:00:00Z","updatedAt":"2026-11-24T00:00:00Z"},"accessStatus":{"plan":"free","isUnlimited":false,"isTrial":false,"todayUsed":0,"todayLimit":20,"dailyResetAt":"2026-11-25T00:00:00Z"}}"#
        let response = try JSONDecoder().decode(AuthResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.user.email, "test@example.com")
        XCTAssertNil(response.user.appleUserId)
    }
}

extension EmailAuthTests {
    func testVerifyRateLimitBlocksVerifyButNotResend() async {
        let model = EmailAuthModel(send: { _ in self.challenge(-1) }, verify: { _, _ in throw EmailAuthFailure(code: "rate_limited", retryAfter: 120) })
        model.email = "test@example.com"; await model.sendCode(); model.code = "123456"
        await model.verifyCode { _ in XCTFail() }
        XCTAssertFalse(model.canVerify)
        XCTAssertEqual(model.resendSeconds, 0)
    }
}

extension EmailAuthTests {
    func testPurchaseLookupCannotCrossIntoAnotherSession() async {
        URLProtocol.registerClass(EmailFixtureProtocol.self)
        defer { URLProtocol.unregisterClass(EmailFixtureProtocol.self) }
        EmailFixtureProtocol.captured = []; EmailFixtureProtocol.failure = false
        APIClient.shared.setToken("first-session", userId: "first-user")
        PurchaseSessionFixture.switchSession = true
        do { _ = try await PurchaseManager.shared.syncLatestTransactions(); XCTFail("Must cancel a stale account lookup") }
        catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
        XCTAssertTrue(EmailFixtureProtocol.captured.isEmpty, "No stale purchase call may use the next account")
    }
}


extension EmailAuthTests {
    func testCancelledAppleControllerCannotCompleteTheNextRequest() async {
        var controllers: [ASAuthorizationController] = []
        let authorizer = AppleBindingAuthorization { controllers.append($0) }
        let window = UIWindow()
        let first = Task { try await authorizer.authorize(nonce: "first", window: window) }
        while controllers.count < 1 { await Task.yield() }
        authorizer.cancel()
        do { _ = try await first.value; XCTFail() } catch is CancellationError {} catch { XCTFail() }
        let second = Task { try await authorizer.authorize(nonce: "second", window: window) }
        while controllers.count < 2 { await Task.yield() }
        authorizer.authorizationController(controller: controllers[0], didCompleteWithError: NSError(domain: ASAuthorizationErrorDomain, code: 1001))
        authorizer.authorizationController(controller: controllers[1], didCompleteWithError: NSError(domain: "current-request", code: 42))
        do { _ = try await second.value; XCTFail() } catch { XCTAssertEqual((error as NSError).domain, "current-request") }
    }
}
