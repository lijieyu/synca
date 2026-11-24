import XCTest
@MainActor final class FeedLayoutTests: XCTestCase {
 func testShortFeedStartsBelowToolbar() {
  let app = XCUIApplication()
  app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-appLanguage", "zh-Hans", "-appAppearance", "dark"]
  app.launch()
  XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 10))
  Thread.sleep(forTimeInterval: 2)
  XCTAssertTrue(app.textViews.firstMatch.isHittable, "Composer remains visible")
  let header = app.staticTexts["待整理"]
  XCTAssertTrue(header.exists)
  let gap = header.frame.minY - app.buttons["phone-categories"].frame.maxY
  print("SHORT_FEED_TOP_GAP=\(gap)")
  let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name="short-feed-initial";attachment.lifetime = .keepAlways;add(attachment)
  XCTAssertLessThan(gap, 60, "Short feed must start below toolbar, not be bottom-aligned")
  app.buttons["phone-categories"].tap()
  let drawer = XCTAttachment(screenshot: XCUIScreen.main.screenshot());drawer.name="single-category-icon";drawer.lifetime = .keepAlways;add(drawer)
  app.buttons["drawer-category-2"].tap()
  Thread.sleep(forTimeInterval: 1)
  XCTAssertLessThan(header.frame.minY - app.buttons["phone-categories"].frame.maxY, 60)
 }
 func testLongFeedStillRevealsLatestRecord() {
  let app = XCUIApplication()
  app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-appLanguage", "zh-Hans", "-appAppearance", "light", "-qa-long-feed"]
  app.launch()
  XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 10))
  let latest = app.buttons["record-completion-49"]
  let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in latest.exists && latest.isHittable }, object: nil)
  XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
  XCTAssertTrue(app.textViews.firstMatch.isHittable)
  let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot());capture.name="long-feed-latest";capture.lifetime = .keepAlways;add(capture)
 }
}
