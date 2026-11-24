import XCTest
final class EmailUITests: XCTestCase {
    func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func launch(_ dark: Bool = false, signedIn: Bool = false) -> XCUIApplication {
        let reset = expectation(description: "reset isolated auth")
        var request = URLRequest(url: URL(string: "http://127.0.0.1:54671/__qa/reset")!); request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { _, _, _ in reset.fulfill() }.resume()
        wait(for: [reset], timeout: 5)
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-appLanguage", "zh-Hans", "-appAppearance", dark ? "dark" : "light"] + (signedIn ? [] : ["-qa-signed-out"])
        app.launch(); return app
    }
    func testEmailLoginScreensAndWrongCodeThenSuccess() {
        let app = launch()
        XCTAssertTrue(app.buttons["email-login"].waitForExistence(timeout: 10)); shot(app, "email-login-light")
        app.buttons["email-login"].tap()
        let email = app.textFields["email-address"]
        XCTAssertTrue(email.waitForExistence(timeout: 5)); shot(app, "email-form-light")
        email.tap(); email.typeText("test@example.com")
        app.buttons["email-submit"].tap()
        let code = app.textFields["email-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap(); code.typeText("000000"); app.buttons["email-submit"].tap()
        XCTAssertTrue(app.staticTexts["email-error"].waitForExistence(timeout: 5)); shot(app, "email-code-error")
        code.tap()
        // Replace six digits without depending on the localized selection menu.
        code.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "123456")
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 10))
        app.terminate()
        let dark = launch(true)
        XCTAssertTrue(dark.buttons["email-login"].waitForExistence(timeout: 10)); shot(dark, "email-login-dark")
        dark.buttons["email-login"].tap(); XCTAssertTrue(dark.textFields["email-address"].waitForExistence(timeout: 5)); shot(dark, "email-form-dark")
    }
    func testEmailAccountShowsAppleBindingAndHelpDoesNotMoveForm() {
        let app = launch(true)
        XCTAssertTrue(app.buttons["email-login"].waitForExistence(timeout: 10)); app.buttons["email-login"].tap()
        let email = app.textFields["email-address"]; XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap(); email.typeText("email-only@example.com"); app.buttons["email-submit"].tap()
        let code = app.textFields["email-code"]; XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap(); code.typeText("123456")
        // Dismiss keyboard through submit only after checking the compact help presentation.
        app.swipeUp()
        let before = code.frame
        app.buttons["没有收到邮件？"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons.firstMatch.tap()
        XCTAssertEqual(code.frame, before)
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 10)); app.buttons["phone-categories"].tap()
        app.buttons["drawer-settings"].tap(); app.buttons["settings-account"].tap(); app.buttons["account-login-methods"].tap()
        XCTAssertTrue(app.buttons["bind-apple"].waitForExistence(timeout: 5)); shot(app, "email-only-methods-dark")
    }

    func testBindingAndBack() {
        let app = launch(true, signedIn: true)
        XCTAssertTrue(app.buttons["phone-categories"].waitForExistence(timeout: 10)); app.buttons["phone-categories"].tap()
        app.buttons["drawer-settings"].tap(); app.buttons["settings-account"].tap()
        XCTAssertTrue(app.buttons["account-login-methods"].waitForExistence(timeout: 5)); shot(app, "email-account-dark")
        app.buttons["account-login-methods"].tap()
        XCTAssertTrue(app.buttons["bind-email"].waitForExistence(timeout: 5)); shot(app, "email-methods-dark")
        app.buttons["bind-email"].tap()
        let email = app.textFields["email-address"]; XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap(); email.typeText("bound@example.com"); app.buttons["email-submit"].tap()
        let code = app.textFields["email-code"]; XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap(); code.typeText("123456"); app.buttons["email-submit"].tap()
        XCTAssertTrue(app.staticTexts["bound@example.com"].waitForExistence(timeout: 5)); shot(app, "email-bound-dark")
    }
}
