import XCTest

final class DrawerGestureTests: XCTestCase {
    func drag(_ app: XCUIApplication, from: CGVector, to: CGVector, hold: TimeInterval = 0.4) {
        app.coordinate(withNormalizedOffset: from).press(forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: to), withVelocity: .slow, thenHoldForDuration: hold)
    }
    func marker(_ app: XCUIApplication) throws -> XCUIElement {
        let feed = app.scrollViews["record-feed"].frame
        let candidates = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'qa-record-'")).allElementsBoundByIndex
            .filter { $0.frame.midY > feed.minY + 50 && $0.frame.midY < feed.maxY - 50 }
        return try XCTUnwrap(candidates.first, "Need a visible stable record anchor")
    }
    func testDrawerDragDoesNotScrollFeed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-appLanguage", "zh-Hans", "-appAppearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 12))
        // Start away from either scroll boundary; otherwise clamping could hide this bug.
        drag(app, from: CGVector(dx: 0.5, dy: 0.4), to: CGVector(dx: 0.5, dy: 0.67))
        let anchor = try marker(app); let y = anchor.frame.midY
        drag(app, from: CGVector(dx: 0.015, dy: 0.55), to: CGVector(dx: 0.78, dy: 0.35))
        XCTAssertTrue(app.buttons["drawer-settings"].waitForExistence(timeout: 4))
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); opened.name = "drawer-diagonal-open"; opened.lifetime = .keepAlways; add(opened)
        app.buttons["取消"].tap()
        XCTAssertTrue(anchor.waitForExistence(timeout: 4))
        XCTAssertEqual(anchor.frame.midY, y, accuracy: 2, "Horizontal opening must not change the underlying feed offset")
        let cancelledY = anchor.frame.midY
        drag(app, from: CGVector(dx: 0.015, dy: 0.55), to: CGVector(dx: 0.09, dy: 0.54), hold: 1)
        XCTAssertFalse(app.buttons["drawer-settings"].isHittable)
        XCTAssertEqual(anchor.frame.midY, cancelledY, accuracy: 2, "Cancelling a partial opening must preserve the feed offset")
        drag(app, from: CGVector(dx: 0.015, dy: 0.4), to: CGVector(dx: 0.05, dy: 0.61))
        XCTAssertFalse(app.buttons["drawer-settings"].isHittable, "A mostly vertical edge drag must remain a scroll")
        XCTAssertGreaterThan(abs(anchor.frame.midY - cancelledY), 20, "Ordinary vertical scrolling must remain responsive")
    }
}
