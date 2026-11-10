import XCTest

final class ScrollTests: XCTestCase {
    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(zh-Hans)"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func checkCollapse(arguments: [String], screenshot: String) {
        let app = launch(arguments)
        let expand = app.buttons["展开"].firstMatch
        // Let the initial lazy-list/image layout settle before asking XCTest for
        // offscreen activation points (which can be invalid during layout).
        app.swipeUp()
        app.swipeUp()
        for _ in 0..<12 {
            if expand.exists && expand.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            XCTAssertTrue(expand.isHittable)
            expand.tap()
            let collapse = app.buttons["收起"].firstMatch
            for _ in 0..<35 {
                if collapse.exists && collapse.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(collapse.isHittable)
            collapse.tap()
            let visible = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "isHittable == true"), object: expand
            )
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
        }
        attach(app, name: screenshot)
    }

    func testSwitchingKeepsImagesReady() {
        let app = launch(["--qa-images"])
        let mounts = app.staticTexts["qa-list-mounts"]
        XCTAssertTrue(mounts.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "生活")).firstMatch.tap()
            XCTAssertTrue(app.staticTexts["周末去看新展览，记得提前预约。"].waitForExistence(timeout: 3))
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "默认")).firstMatch.tap()
        }
        XCTAssertEqual(app.staticTexts["qa-image-resets"].value as? String, "0")
        attach(app, name: "category-switch-images-ready")
    }

    func testMarkdownCollapseRemainsVisible() {
        let app = launch(["--qa-markdown"])
        let expand = app.buttons["展开"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        let collapse = app.buttons["收起"].firstMatch
        for _ in 0..<5 {
            if collapse.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(collapse.isHittable)
        attach(app, name: "markdown-expanded")
        collapse.tap()
        XCTAssertTrue(expand.isHittable)
        attach(app, name: "markdown-collapsed")
    }

    func testLastTextCollapseRemainsVisible() {
        checkCollapse(arguments: [], screenshot: "collapsed-last-text")
    }

    func testPenultimateTextCollapseRemainsVisible() {
        checkCollapse(arguments: ["--qa-penultimate"], screenshot: "collapsed-penultimate-text")
    }

    func testImagesStayAtBottomAfterRepeatedScroll() {
        let app = launch(["--qa-images"])
        let last = app.otherElements["record-qa-image-2"].firstMatch
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(last.exists)
        let originalY = last.frame.minY
        for _ in 0..<3 {
            app.swipeDown()
            app.swipeDown()
            app.swipeUp()
            app.swipeUp()
            app.swipeUp()
        }
        XCTAssertEqual(last.frame.minY, originalY, accuracy: 3)
        // Fixture-only instrumentation: successful images must not revert to a
        // placeholder as lazy rows leave and re-enter the visible viewport.
        XCTAssertEqual(app.staticTexts["qa-image-resets"].value as? String, "0")
        XCTAssertFalse(app.staticTexts["iPhone"].exists)
        XCTAssertFalse(app.staticTexts["MacBook Pro"].exists)
        attach(app, name: "images-bottom")
    }

    func testNewCategoryPaletteUsesAvailableWidth() {
        let app = launch(["--qa-new-category"])
        let first = app.buttons["palette-sky"]
        let last = app.buttons["palette-coral"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(last.exists)
        XCTAssertGreaterThan(last.frame.midX - first.frame.midX, app.frame.width * 0.5)
        attach(app, name: "new-category-palette")
    }
}
