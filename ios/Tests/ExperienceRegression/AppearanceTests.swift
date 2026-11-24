import XCTest

final class AppearanceTests: XCTestCase {
    private func expectScheme(_ app: XCUIApplication, _ scheme: String, probe: String = "qa-settings-scheme", file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts[probe]
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", scheme), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed, "Expected \(scheme), actual \(element.label)", file: file, line: line)
    }

    private func select(_ label: String, in app: XCUIApplication) {
        app.buttons["qa-appearance-picker"].tap()
        let choice = app.buttons[label].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
    }

    // Run under both actual system appearances; the root probe captures the OS value.
    func testFollowSystemUpdatesPresentedSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-appLanguage", "zh-Hans", "-appAppearance", "system"]
        app.launch()
        XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["qa-root-scheme"].waitForExistence(timeout: 5))
        let systemScheme = app.staticTexts["qa-root-scheme"].label
        XCTAssertTrue(["light", "dark"].contains(systemScheme))
        let opposite = systemScheme == "dark" ? "light" : "dark"
        app.textViews.firstMatch.tap()
        app.textViews.firstMatch.typeText("Appearance draft survives")
        app.buttons["phone-categories"].tap()
        app.buttons["drawer-settings"].tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 5))
        expectScheme(app, systemScheme)
        select(opposite == "light" ? "浅色" : "深色", in: app)
        expectScheme(app, opposite)
        select("跟随系统", in: app)
        expectScheme(app, systemScheme)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "appearance-system-\(systemScheme)-with-settings-open"
        capture.lifetime = .keepAlways
        add(capture)
        // Explicit overrides remain functional after clearing one.
        select("深色", in: app)
        expectScheme(app, "dark")
        select("浅色", in: app)
        expectScheme(app, "light")
        select("跟随系统", in: app)
        expectScheme(app, systemScheme)
        app.buttons["settings-about"].tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["settings-account"].waitForExistence(timeout: 3))
        app.buttons["settings-close"].tap()
        XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 3))
        expectScheme(app, systemScheme, probe: "qa-root-scheme")
        XCTAssertEqual(app.textViews.firstMatch.value as? String, "Appearance draft survives")
    }
}
