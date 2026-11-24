import XCTest
final class PolishTests: XCTestCase {
 func shot(_ app: XCUIApplication, _ name: String) { Thread.sleep(forTimeInterval: 0.4); let a = XCTAttachment(screenshot: UIDevice.current.userInterfaceIdiom == .pad ? app.screenshot() : XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
 func launch(_ extra: [String] = []) -> XCUIApplication {
  let app = XCUIApplication(); app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-appLanguage", "zh-Hans", "-appAppearance", "light"] + extra; app.launch()
  XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 15)); return app
 }
 func settings(_ app: XCUIApplication) {
  if app.buttons["phone-categories"].exists {
   app.buttons["phone-categories"].tap(); XCTAssertTrue(app.buttons["drawer-settings"].waitForExistence(timeout: 5)); app.buttons["drawer-settings"].tap()
  } else { app.buttons["设置"].tap() }
  XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 5))
 }
 func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap() }
 func testWalkthrough() {
  let app=launch(); shot(app,"after-main")
  XCTAssertTrue(app.buttons["phone-sync"].exists); XCTAssertTrue(app.buttons["phone-clear"].exists)
  app.textViews.firstMatch.tap(); app.textViews.firstMatch.typeText("Keep my draft 123")
  app.buttons["phone-categories"].tap(); shot(app,"after-drawer")
  app.buttons["drawer-category-2"].tap(); XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 3))
  settings(app); shot(app,"after-settings")
  for (entry,name) in [("settings-account","account"),("settings-categories","categories"),("settings-about","about")] {
   let button=app.buttons[entry]; if !button.isHittable { app.swipeUp() }; button.tap()
   XCTAssertTrue(app.navigationBars.buttons.element(boundBy:0).waitForExistence(timeout:3)); shot(app,"after-"+name)
   if name == "account" { app.buttons["account-plan"].tap(); shot(app,"after-plan"); back(app) }
   back(app)
   XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 4))
  }
  app.buttons["settings-feedback"].tap(); XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3)); shot(app,"after-feedback")
  app.buttons.matching(identifier: "取消").allElementsBoundByIndex.first(where: { $0.isHittable })!.tap(); app.buttons["settings-close"].tap()
  XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 4)); XCTAssertEqual(app.textViews.firstMatch.value as? String, "Keep my draft 123"); app.buttons["search-open"].tap(); shot(app,"after-search")
 }
 func testDrawerAndCategoryEditing() {
  let app = launch()
  let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.48))
  start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.48)), withVelocity: .slow, thenHoldForDuration: 0.1)
  XCTAssertTrue(app.buttons["drawer-settings"].waitForExistence(timeout: 4))
  shot(app,"detail-drawer")
  app.buttons["drawer-category-3"].tap()
  shot(app,"detail-category-header")
  settings(app); app.buttons["settings-categories"].tap()
  XCTAssertTrue(app.buttons["category-edit-1"].waitForExistence(timeout: 4))
  let handle = app.images["category-reorder-1"]
  let trash = app.buttons["category-delete-1"]
  XCTAssertLessThan(handle.frame.midX, trash.frame.midX)
  shot(app,"detail-categories")
  app.buttons["category-edit-1"].tap()
  XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 4))
  app.buttons.matching(identifier: "取消").allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
  app.buttons["category-edit-0"].tap()
  XCTAssertTrue(app.navigationBars["编辑分类"].waitForExistence(timeout: 4)); XCTAssertEqual(app.textFields.count, 0)
  app.buttons.matching(identifier: "取消").allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
  handle.press(forDuration: 0.1, thenDragTo: app.images["category-reorder-3"], withVelocity: .slow, thenHoldForDuration: 0.1)
  XCTAssertTrue(app.buttons["category-edit-1"].waitForExistence(timeout: 4))
  XCTAssertGreaterThan(app.buttons["category-edit-1"].frame.midY, app.buttons["category-edit-3"].frame.midY)
  shot(app,"detail-categories-reordered")
 }
 func testImageCompletion() {
  let app = launch()
  let buttons = app.buttons.matching(identifier: "标记完成")
  XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 8))
  app.swipeUp()
  let visible = buttons.allElementsBoundByIndex.filter { $0.isHittable }
  XCTAssertGreaterThanOrEqual(visible.count, 2)
  guard visible.count >= 2 else { return }
  let neighbor = visible[visible.count - 2]
  let neighborID = neighbor.identifier
  let originalY = neighbor.frame.midY
  shot(app,"images-before-complete")
  visible.last!.tap()
  let countUpdated = NSPredicate(format: "label CONTAINS '5'")
  let countExpectation = XCTNSPredicateExpectation(predicate: countUpdated, object: app.buttons["phone-categories"])
  XCTAssertEqual(XCTWaiter.wait(for: [countExpectation], timeout: 8), .completed)
  let remaining = buttons.allElementsBoundByIndex.filter { $0.isHittable }
  XCTAssertFalse(remaining.isEmpty)
  XCTAssertEqual(app.buttons[neighborID].frame.midY, originalY, accuracy: 12)
  shot(app,"images-after-complete")
 }
 @MainActor func testImageCompletionFailureAndNavigation() async throws {
  _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54671/__qa/mode/failure")!)
  var app = launch(); app.swipeUp()
  let target = app.buttons["record-completion-5"]
  XCTAssertTrue(target.waitForExistence(timeout: 5))
  let oldY = target.frame.midY; target.tap()
  // The explicit error must preserve completion state and the viewport.
  let error = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '失败'")).firstMatch
  _ = error.waitForExistence(timeout: 4)
  XCTAssertEqual(target.label, "标记完成")
  XCTAssertEqual(target.frame.midY, oldY, accuracy: 12)
  shot(app,"images-failed-completion")
  app.terminate()
  _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54671/__qa/mode/delay")!)
  app = launch(); app.swipeUp(); app.buttons["record-completion-5"].tap()
  // Navigating during the pending write must never cancel the user's completion.
  app.buttons["phone-categories"].tap(); app.buttons["drawer-category-1"].tap()
  let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '5'"), object: app.buttons["phone-categories"])
  let result = await XCTWaiter.fulfillment(of: [updated], timeout: 8)
  XCTAssertEqual(result, .completed)
  shot(app,"images-completed-after-navigation")
  _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54671/__qa/mode/normal")!)
 }
 func testLinkLongPress() {
  let app = launch()
  let link = app.links.firstMatch
  XCTAssertTrue(link.waitForExistence(timeout: 5))
  link.press(forDuration: 1.2)
  XCTAssertTrue(app.menuItems["拷贝链接"].waitForExistence(timeout: 3) || app.buttons["拷贝链接"].exists || app.buttons["拷贝"].exists || app.menuItems["拷贝"].exists)
  XCTAssertEqual(app.state, .runningForeground)
  shot(app,"link-long-press")
  let copy = app.buttons.matching(NSPredicate(format: "label == '拷贝' OR label == '拷贝链接' OR label == 'Copy' OR label == 'Copy Link'")).firstMatch
  XCTAssertTrue(copy.exists); copy.tap(); XCTAssertEqual(app.state, .runningForeground)
 }
 func testLinkTap() {
  let app = launch()
  XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 5))
  app.links.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)).tap()
  let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
  XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 8))
  app.activate()
 }
 func testDetailDarkAndLargeType() {
  for extra in [["-appAppearance","dark"], ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]] {
   let app = launch(extra)
   let style = extra[0] == "-appAppearance" ? "dark" : "large"
   shot(app,"detail-main-" + style)
   app.buttons["phone-categories"].tap(); shot(app,"detail-drawer-" + style)
   app.buttons["drawer-settings"].tap(); shot(app,"detail-settings-" + style)
   for _ in 0..<8 { if app.buttons["settings-categories"].isHittable { break }; app.swipeUp() }
   app.buttons["settings-categories"].tap()
   XCTAssertTrue(app.buttons["category-edit-1"].waitForExistence(timeout: 4))
   XCTAssertTrue(app.buttons["category-delete-1"].isHittable)
   shot(app,"detail-categories-" + style)
   app.terminate()
  }
 }
 func testIPadLandscape() {
  guard UIDevice.current.userInterfaceIdiom == .pad else { return }
  let app = launch()
  XCUIDevice.shared.orientation = .landscapeLeft
  let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
  XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 8), .completed)
  shot(app,"ipad-main-landscape"); settings(app); shot(app,"ipad-settings-landscape")
  app.buttons["settings-categories"].tap(); shot(app,"ipad-categories-landscape")
  app.buttons["category-edit-0"].tap()
  XCTAssertTrue(app.navigationBars["编辑分类"].waitForExistence(timeout: 4))
  XCTAssertEqual(app.textFields.count, 0)
  shot(app,"ipad-default-category-edit")
  app.buttons.matching(identifier: "取消").allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
  XCTAssertTrue(app.navigationBars["分类管理"].waitForExistence(timeout: 4))
  app.navigationBars["分类管理"].buttons.firstMatch.tap()
  XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 4))
  app.buttons["settings-close"].tap(); XCUIDevice.shared.orientation = .portrait
 }
 @MainActor func testAIPlans() async throws {
  for plan in ["free", "pro", "pro-dark"] {
   _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54671/__qa/plan/" + plan)!)
   let app=launch(plan == "pro-dark" ? ["-appAppearance", "dark"] : []); settings(app); app.buttons["settings-ai"].tap()
   XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))
   let label = plan == "free" ? "查看升级权益" : "复制连接指令"
   XCTAssertTrue(app.webViews.buttons[label].waitForExistence(timeout: 10))
   shot(app,"ai-"+plan); back(app); app.terminate()
  }
 }
 func testDarkAndLargeType() {
  var app=launch(["-appAppearance","dark"]); settings(app); shot(app,"after-settings-dark"); app.terminate()
  app=launch(["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]); settings(app); shot(app,"after-settings-large-text")
  app.swipeUp(); XCTAssertTrue(app.buttons["settings-about"].isHittable); shot(app,"after-settings-large-text-bottom")
 }
}
