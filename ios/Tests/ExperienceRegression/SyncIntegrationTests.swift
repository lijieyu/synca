import XCTest
import UIKit
@testable import Synca

final class SyncFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var phase = 0
    static var paths: [String] = []
    static func setPhase(_ value: Int) { lock.lock(); phase = value; paths = []; lock.unlock() }
    static func capturedPaths() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let phase = Self.phase; Self.paths.append(request.url!.absoluteString); Self.lock.unlock()
        let path = request.url!.path
        var status = 200
        let body: [String: Any]
        func message(_ id: String, _ text: String, cleared: Bool = false, deleted: Bool = false) -> [String: Any] {
            ["id": id, "userId": "visual-fixture", "type": "text", "textContent": text,
             "isCleared": cleared, "isDeleted": deleted, "categoryId": "0", "sourceDevice": "iPhone",
             "createdAt": "2026-11-24T05:30:00.000Z", "updatedAt": phase == 0 ? "2026-11-24T05:30:00.000Z" : "2026-11-24T05:31:00.000Z"]
        }
        if path == "/messages" {
            if phase == 2 { status = 503; body = ["error":"unavailable"] }
            else if phase == 0 { body = ["messages": [message("one", "Original"), message("two", "Remove me")]] }
            else { body = ["messages": [message("one", "Edited", cleared: true), message("two", "Remove me", deleted: true), message("three", "New record")]] }
        } else if path == "/message-categories" {
            body = ["categories": [["id":"0","userId":"visual-fixture","name":phase == 0 ? "Default" : "Renamed","color":"slate","isDefault":true,"sortOrder":0,"createdAt":"2026-11-24T05:30:00.000Z","updatedAt":"2026-11-24T05:31:00.000Z"]]]
        } else if path == "/me/push-token" {
            body = ["ok":true]
        } else if path == "/me/access-status" {
            body = ["accessStatus": ["plan":"free","isUnlimited":false,"isTrial":false,"todayUsed":7,"todayLimit":20,"dailyResetAt":"2026-11-25T00:00:00Z"]]
        } else { status = 404; body = ["error":"unexpected test path"] }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SyncIntegrationTests: XCTestCase {
    @MainActor func testPushSyncMergesAndFailurePreservesState() async throws {
        URLProtocol.registerClass(SyncFixtureProtocol.self)
        defer { URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        SyncFixtureProtocol.setPhase(0)
        let push = PushTokenManager.shared
        push.cacheDeviceToken(Data([1,2,3,4]))
        UserDefaults.standard.set(APIClient.shared.token, forKey: "uploadedPushAuthToken")
        UserDefaults.standard.removeObject(forKey: "uploadedPushContext")
        await push.uploadCachedTokenIfPossible()
        await push.uploadCachedTokenIfPossible()
        XCTAssertEqual(SyncFixtureProtocol.capturedPaths().filter { $0.contains("/me/push-token") }.count, 1)
        push.clearUploadedSessionMarker()
        let sync = SyncManager.shared
        sync.reset()
        SyncFixtureProtocol.setPhase(0)
        let loaded = await sync.fullSync()
        XCTAssertTrue(loaded); XCTAssertEqual(sync.unclearedCount,2)
        XCTAssertEqual(sync.messages.count,2)
        SyncFixtureProtocol.setPhase(1)
        let delegate = AppDelegate()
        let result = await withCheckedContinuation { continuation in
            delegate.application(UIApplication.shared,didReceiveRemoteNotification:["aps":["content-available":1]],fetchCompletionHandler:{ continuation.resume(returning:$0) })
        }
        XCTAssertEqual(result,.newData)
        XCTAssertEqual(sync.messages.count,2)
        XCTAssertEqual(sync.messages.first(where:{$0.id == "one"})?.textContent,"Edited")
        XCTAssertNil(sync.messages.first(where:{$0.id == "two"}))
        XCTAssertEqual(sync.unclearedCount,1)
        XCTAssertEqual(sync.categories.first?.name,"Renamed")
        XCTAssertTrue(SyncFixtureProtocol.capturedPaths().contains(where:{$0.contains("/messages?since=")}))
        let snapshot = sync.messages
        SyncFixtureProtocol.setPhase(2)
        let failure = await withCheckedContinuation { continuation in
            delegate.application(UIApplication.shared,didReceiveRemoteNotification:["aps":["content-available":1]],fetchCompletionHandler:{ continuation.resume(returning:$0) })
        }
        XCTAssertEqual(failure,.failed)
        XCTAssertEqual(sync.messages,snapshot)
        XCTAssertEqual(sync.unclearedCount,1)
        sync.reset()
    }
}
