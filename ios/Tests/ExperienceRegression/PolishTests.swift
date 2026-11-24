import XCTest
import StoreKitTest
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
  link.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.2)
  let copyPredicate = NSPredicate(format: "label == '拷贝链接' OR label == 'Copy Link'")
  let copy = app.descendants(matching: .any).matching(copyPredicate).firstMatch
  // A record-level Copy action is not evidence that the URL menu works.
  guard copy.waitForExistence(timeout: 5) else {
   shot(app,"link-menu-not-found")
   XCTFail("The URL-specific Copy Link action was not found")
   return
  }
  XCTAssertEqual(app.state, .runningForeground)
  let openLink = app.descendants(matching: .any).matching(NSPredicate(format: "label == '打开链接' OR label == 'Open Link' OR label == '打开' OR label == 'Open'")).firstMatch
  XCTAssertTrue(openLink.exists, "This must be the link menu, not the record menu")
  XCTAssertEqual(app.webViews.count, 0, "Long press must not load a remote webpage preview")
  XCTAssertFalse(app.buttons["隐藏预览"].exists)
  shot(app,"link-long-press")
  copy.tap(); XCTAssertEqual(app.state, .runningForeground)
 }
 func testLinkTap() {
  let app = launch()
  XCTAssertTrue(app.links.firstMatch.waitForExistence(timeout: 5))
  app.links.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
 func testSettingsRefinement() {
  for style in ["light", "dark"] {
   let app = launch(["-appAppearance",style])
   app.buttons["phone-categories"].tap()
   XCTAssertTrue(app.buttons["drawer-settings"].waitForExistence(timeout: 4))
   XCTAssertTrue(app.buttons["drawer-settings"].label.contains("设置"))
   shot(app,"refined-drawer-"+style)
   app.buttons["drawer-settings"].tap()
   app.buttons["settings-account"].tap()
   XCTAssertTrue(app.buttons["account-plan"].waitForExistence(timeout: 4))
   XCTAssertTrue(app.buttons["account-delete"].isHittable)
   shot(app,"refined-account-"+style)
   app.buttons["account-plan"].tap(); back(app)
   XCTAssertTrue(app.buttons["account-signout"].waitForExistence(timeout: 4))
   back(app)
   app.buttons["settings-feedback"].tap()
   let editor = app.textViews["feedback-content"]
   XCTAssertTrue(editor.waitForExistence(timeout: 4))
   shot(app,"refined-feedback-"+style)
   editor.tap(); editor.typeText("Feedback draft")
   app.buttons.matching(identifier:"取消").allElementsBoundByIndex.first(where: { $0.isHittable })!.tap()
   XCTAssertTrue(app.buttons["放弃修改"].waitForExistence(timeout: 3))
   if app.buttons["继续编辑"].exists { app.buttons["继续编辑"].tap() }
   else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap() }
   XCTAssertFalse(app.buttons["放弃修改"].exists)
   XCTAssertEqual(editor.value as? String,"Feedback draft")
   app.terminate()
  }
 }
 @MainActor func testAIPlans() async throws {
  for plan in ["free", "free-dark", "pro", "pro-dark", "connected", "connected-dark", "pro-large"] {
   _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54671/__qa/plan/" + plan)!)
   var extra = ["-appAppearance", plan.hasSuffix("dark") ? "dark" : "light"]
   if plan.hasSuffix("large") { extra += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
   let app=launch(extra); settings(app)
   for _ in 0..<8 { if app.buttons["settings-ai"].isHittable { break }; app.swipeUp() }
   app.buttons["settings-ai"].tap()
   XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))
   let label = plan.hasPrefix("free") ? "升级 Synca Pro" : plan.hasPrefix("connected") ? "撤销连接" : "复制连接指令"
   let action = app.webViews.buttons[label].firstMatch
   XCTAssertTrue(action.waitForExistence(timeout: 10))
   shot(app,"refined-ai-"+plan)
   if !plan.hasPrefix("free") && !plan.hasPrefix("connected") {
    for _ in 0..<8 { if action.isHittable { break }; app.webViews.firstMatch.swipeUp() }
    XCTAssertTrue(action.isHittable)
    shot(app,"refined-ai-actions-"+plan)
    if !plan.hasSuffix("large") {
     let preview = app.webViews.buttons["查看指令"]
     for _ in 0..<4 { if preview.isHittable { break }; app.webViews.firstMatch.swipeUp() }
     preview.tap()
     XCTAssertTrue(app.webViews.buttons["收起指令"].waitForExistence(timeout: 3))
    }
   }
   back(app); app.terminate()
  }
 }
 @MainActor func testAIUpgradeAndDrawerPlacement() async throws {
  for style in ["light", "dark"] {
   _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:54671/__qa/plan/free")!)
   let app = launch(["-appAppearance",style])
   app.buttons["phone-categories"].tap()
   let account = app.buttons["drawer-settings"]
   let quota = app.staticTexts.matching(NSPredicate(format:"label CONTAINS '今日记录'")).firstMatch
   XCTAssertTrue(quota.waitForExistence(timeout: 3))
   XCTAssertGreaterThan(quota.frame.minY, account.frame.maxY)
   shot(app,"round4-drawer-"+style)
   account.tap(); app.buttons["settings-ai"].tap()
   let upgrade=app.webViews.buttons["升级 Synca Pro"]
   XCTAssertTrue(upgrade.waitForExistence(timeout: 8))
   if !upgrade.isHittable { app.webViews.firstMatch.swipeUp() }
   shot(app,"round4-ai-free-"+style)
   upgrade.tap()
   XCTAssertTrue(app.buttons["upgrade-primary"].waitForExistence(timeout: 5))
   XCTAssertTrue(app.buttons["恢复购买"].exists)
   shot(app,"round4-native-upgrade-"+style)
   app.buttons["关闭"].tap()
   XCTAssertTrue(app.webViews.buttons["升级 Synca Pro"].waitForExistence(timeout:5))
   app.terminate()
   _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:54671/__qa/plan/connected")!)
   let connected=launch(["-appAppearance",style]); settings(connected); connected.buttons["settings-ai"].tap()
   XCTAssertTrue(connected.webViews.buttons["撤销连接"].firstMatch.waitForExistence(timeout:8))
   shot(connected,"round4-ai-connected-"+style); connected.terminate()
  }
 }
 @MainActor func testUpgradePresentation() async throws {
  let session = try SKTestSession(configurationFileNamed: "UpgradePreview")
  session.disableDialogs = true
  session.storefront = "CHN"
  defer { session.resetToDefaultState() }
  _ = try await URLSession.shared.data(from: URL(string:"http://127.0.0.1:54671/__qa/plan/free")!)
  for mode in ["light", "dark", "failure-light", "failure-dark", "large", "english"] {
   var extra = ["-appAppearance", mode.hasSuffix("dark") ? "dark" : "light"]
   if mode.hasPrefix("failure") { extra += ["-qa-products-unavailable"] }
   if mode == "large" { extra += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
   if mode == "english" { extra += ["-AppleLanguages", "(en)", "-appLanguage", "en"] }
   let app=launch(extra); settings(app)
   for _ in 0..<8 { if app.buttons["settings-ai"].isHittable { break }; app.swipeUp() }
   app.buttons["settings-ai"].tap()
   let entry=app.webViews.buttons[mode == "english" ? "Upgrade to Synca Pro" : "升级 Synca Pro"]
   XCTAssertTrue(entry.waitForExistence(timeout:8))
   for _ in 0..<8 { if entry.isHittable { break }; app.webViews.firstMatch.swipeUp() }
   entry.tap()
   let primary=app.buttons["upgrade-primary"]
   XCTAssertTrue(primary.waitForExistence(timeout:8))
   if mode.hasPrefix("failure") {
    XCTAssertEqual(primary.label,"重试")
    XCTAssertFalse(app.staticTexts["upgrade-price"].exists)
   } else { XCTAssertTrue(app.staticTexts["upgrade-price"].waitForExistence(timeout:8)) }
   XCTAssertFalse(app.staticTexts["附件空间"].exists)
   shot(app,"upgrade-"+mode)
   for _ in 0..<8 { if primary.isHittable { break }; app.swipeUp() }
   XCTAssertTrue(primary.isHittable)
   if mode == "large" { shot(app,"upgrade-large-actions") }
   let restore = app.buttons[mode == "english" ? "Restore Purchases" : "恢复购买"]
   for _ in 0..<6 { if restore.isHittable { break }; app.swipeUp() }
   XCTAssertTrue(restore.isHittable)
   app.buttons["upgrade-close"].tap(); XCTAssertTrue(entry.waitForExistence(timeout:5)); app.terminate()
  }
 }
 func testDarkAndLargeType() {
  var app=launch(["-appAppearance","dark"]); settings(app); shot(app,"after-settings-dark"); app.terminate()
  app=launch(["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]); settings(app); shot(app,"after-settings-large-text")
  app.swipeUp(); XCTAssertTrue(app.buttons["settings-about"].isHittable); shot(app,"after-settings-large-text-bottom")
 }
}
