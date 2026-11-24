import XCTest
final class PolishTests: XCTestCase {
 func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
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
  for (entry,name) in [("settings-account","account"),("settings-categories","categories"),("settings-about","about"),("settings-ai","ai")] {
   let button=app.buttons[entry]; if !button.isHittable { app.swipeUp() }; button.tap()
   XCTAssertTrue(app.navigationBars.buttons.element(boundBy:0).waitForExistence(timeout:3)); shot(app,"after-"+name)
   if name == "account" { app.buttons["account-plan"].tap(); shot(app,"after-plan"); back(app) }
   back(app)
   XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 4))
  }
  app.buttons["settings-feedback"].tap(); XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3)); shot(app,"after-feedback")
  app.buttons["取消"].tap(); app.buttons["settings-close"].tap()
  XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 4)); XCTAssertEqual(app.textViews.firstMatch.value as? String, "Keep my draft 123"); app.buttons["search-open"].tap(); shot(app,"after-search")
 }
 func testIPadLandscape() {
  guard UIDevice.current.userInterfaceIdiom == .pad else { return }
  XCUIDevice.shared.orientation = .landscapeLeft
  let app = launch(); shot(app,"ipad-main-landscape"); settings(app); shot(app,"ipad-settings-landscape")
  app.buttons["settings-categories"].tap(); shot(app,"ipad-categories-landscape")
  app.buttons["修改"].firstMatch.tap()
  XCTAssertTrue(app.navigationBars["编辑分类"].waitForExistence(timeout: 4))
  XCTAssertEqual(app.textFields.count, 0)
  shot(app,"ipad-default-category-edit")
  app.buttons["取消"].tap()
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
