import XCTest
final class Release121Tests: XCTestCase {
 func shot(_ name:String) { let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
 func select(_ app:XCUIApplication,_ id:String,_ label:String) {
  if app.buttons["phone-categories"].exists { app.buttons["phone-categories"].tap();app.buttons["drawer-category-"+id].tap() }
  else { app.buttons.matching(NSPredicate(format:"label == %@",label)).firstMatch.tap() }
 }
 func testCollectionsAndScratchpad() {
  let app=XCUIApplication();app.launchArguments=["-AppleLanguages","(zh-Hans)","-appLanguage","zh-Hans","-appAppearance","light"];app.launch()
  XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout:15))
  select(app,"__collections__","收藏");XCTAssertTrue(app.buttons["collection-category"].waitForExistence(timeout:5));shot("121-collections-light")
  XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS '保存到'")).firstMatch.exists)
  select(app,"__scratchpad__","草稿本");let editor=app.textViews["scratch-editor"];XCTAssertTrue(editor.waitForExistence(timeout:5))
  let loaded=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value CONTAINS '随时接着写'"),object:editor);XCTAssertEqual(XCTWaiter.wait(for:[loaded],timeout:10),.completed);shot("121-scratch-edit")
  app.buttons["预览"].tap();shot("121-scratch-preview")
  app.terminate();app.launchArguments=["-AppleLanguages","(zh-Hans)","-appLanguage","zh-Hans","-appAppearance","dark"];app.launch();XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout:10));select(app,"__collections__","收藏");shot("121-collections-dark")
 }
}
