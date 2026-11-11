import XCTest
import SwiftUI
import UIKit
@testable import Synca

final class SearchInputTests: XCTestCase {
    @MainActor private final class Model: ObservableObject {
        @Published var text = "面试"
        @Published var clearRevision = 0
        @Published var hasDraft = false
    }
    private struct Host: View {
        @ObservedObject var model: Model
        var body: some View { SearchQueryField(text: $model.text, placeholder: "搜索", clearRevision: model.clearRevision, onDraftChange: { model.hasDraft = $0 }) }
    }
    @MainActor private func settle() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    @MainActor private func findField(_ view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        return view.subviews.lazy.compactMap { self.findField($0) }.first
    }
    @MainActor func testMarkedTextRetainsCommittedQueryAndExternalClearWins() async throws {
        let model = Model()
        let host = UIHostingController(rootView: Host(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        await settle()
        let field = try XCTUnwrap(findField(host.view))
        field.becomeFirstResponder()
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.setMarkedText("gou", selectedRange: NSRange(location: 3, length: 0))
        XCTAssertNotNil(field.markedTextRange)
        field.sendActions(for: .editingChanged)
        await settle()
        XCTAssertEqual(model.text, "面试", "Candidate text must not replace committed query")
        XCTAssertNotNil(field.markedTextRange, "A SwiftUI update must not end composition")
        field.setMarkedText("沟通", selectedRange: NSRange(location: 2, length: 0))
        field.unmarkText()
        await settle()
        XCTAssertEqual(model.text, "面试沟通", "Commit must publish even without editingChanged")
        field.setMarkedText("new", selectedRange: NSRange(location: 3, length: 0))
        field.sendActions(for: .editingChanged)
        model.text = ""
        await settle()
        XCTAssertNil(field.markedTextRange)
        XCTAssertEqual(field.text, "")
        XCTAssertEqual(model.text, "", "Deferred composition callback must not restore cleared text")
    }
    @MainActor func testFreshMarkedDraftCanBeClearedWithoutPublishingCandidate() async throws {
        let model = Model()
        model.text = ""
        let host = UIHostingController(rootView: Host(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        await settle()
        let field = try XCTUnwrap(findField(host.view))
        field.becomeFirstResponder()
        field.setMarkedText("mian", selectedRange: NSRange(location: 4, length: 0))
        field.sendActions(for: .editingChanged)
        await settle()
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.hasDraft, "Clear affordance must be available for an uncommitted draft")
        XCTAssertNotNil(field.markedTextRange)
        model.hasDraft = false
        model.clearRevision += 1
        await settle()
        XCTAssertEqual(field.text, "")
        XCTAssertNil(field.markedTextRange)
        XCTAssertEqual(model.text, "")
        XCTAssertFalse(model.hasDraft)
    }
    @MainActor func testCancelledCompositionPreservesExistingQuery() async throws {
        let model = Model()
        let host = UIHostingController(rootView: Host(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        await settle()
        let field = try XCTUnwrap(findField(host.view))
        field.becomeFirstResponder()
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.setMarkedText("abc", selectedRange: NSRange(location: 3, length: 0))
        field.sendActions(for: .editingChanged)
        XCTAssertEqual(model.text, "面试")
        field.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
        field.unmarkText()
        await settle()
        XCTAssertEqual(model.text, "面试")
    }
}
