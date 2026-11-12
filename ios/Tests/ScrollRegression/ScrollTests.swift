import XCTest

final class ScrollTests: XCTestCase {
    func testTailPositionAndFreshSearch() {
        for mode in ["--qa-four", "--qa-forty", "--qa-search"] {
            let app = XCUIApplication(); app.launchArguments = [mode, "-AppleLanguages", "(zh-Hans)"]; app.launch()
            let open = app.buttons["search-open"]; XCTAssertTrue(open.waitForExistence(timeout: 8))
            open.tap()
            let field = app.textFields["search-query"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.typeText(mode == "--qa-search" ? "提纲" : "尾条定位验收")
            let targetID = mode == "--qa-search" ? "search-long" : "tail-39"
            let result = app.buttons["search-result-" + targetID]; XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
            let row = app.otherElements["record-" + targetID].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let initial = row.frame
            Thread.sleep(forTimeInterval: 0.35)
            let early = row.frame
            Thread.sleep(forTimeInterval: 1.2)
            let settled = row.frame
            let positionTrace = app.scrollViews["record-feed"].value as? String ?? ""
            let positions = positionTrace.split(separator: ",").compactMap { Int($0) }
            XCTAssertFalse(positions.isEmpty)
            if mode == "--qa-search" {
                // Preferences include intermediate layout passes that never
                // reach the display. Assert the settled deep position here;
                // verify the visible transition with the recorded frames.
                XCTAssertLessThan(positions.last ?? 0, 0, "The long tail's deep match was not reached")
            } else {
                XCTAssertLessThanOrEqual(Set(positions).count, 1)
            }
            print("TAIL-ALL-POSITIONS \(mode): \(positionTrace)")
            print("TAIL-GEOMETRY \(mode): initial \(initial), early \(early), settled \(settled)")
            XCTAssertEqual(early.minY, settled.minY, accuracy: 2)
            if mode != "--qa-search" {
                XCTAssertGreaterThan(settled.minY, 150)
                XCTAssertLessThan(settled.maxY, app.frame.height - 60)
            }
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name=mode; shot.lifetime = .keepAlways; add(shot)
            open.tap(); XCTAssertTrue(field.waitForExistence(timeout: 5))
            XCTAssertEqual(field.value as? String, field.placeholderValue)
            let fresh = XCTAttachment(screenshot: app.screenshot()); fresh.name="fresh-"+mode; fresh.lifetime = .keepAlways; add(fresh)
            app.terminate()
        }
    }
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

    func testSearchLocatesCompletedLongAndImageRows() {
        let app = launch(["--qa-search"])
        let search = app.buttons["search-open"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        for (query, id) in [("ms", "search-completed"), ("长文", "search-long"), ("照片", "search-image")] {
            search.tap()
            let field = app.textFields["search-query"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            if app.buttons["清除搜索"].exists { app.buttons["清除搜索"].tap() }
            field.typeText(query)
            let result = app.buttons["search-result-" + id]
            XCTAssertTrue(result.waitForExistence(timeout: 10))
            result.tap()
            let target = app.otherElements["record-" + id].firstMatch
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: target)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
            XCTAssertLessThan(target.frame.minY, app.frame.height - 140)
            XCTAssertGreaterThanOrEqual(target.frame.minY, 0)
            attach(app, name: "search-located-" + id)
            // A stable delayed observation catches image-load/initial-bottom callbacks.
            let stable = expectation(description: "No late jump")
            let y = target.frame.minY
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { stable.fulfill() }
            wait(for: [stable], timeout: 12)
            XCTAssertTrue(target.isHittable)
            XCTAssertEqual(target.frame.minY, y, accuracy: 6)
        }
    }

    func testLocatedCardIsFullyInsideFeed() {
        for (query, id, name) in [("playing", "search-completed", "first"),
                                  ("中间定位验收", "life-follow-5", "middle")] {
            let app = launch(["--qa-search"])
            app.buttons["search-open"].tap()
            let field = app.textFields["search-query"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText(query)
            let result = app.buttons["search-result-" + id]
            XCTAssertTrue(result.waitForExistence(timeout: 8))
            result.tap()
            let row = app.otherElements["record-" + id].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let feed = app.scrollViews["record-feed"].firstMatch
            let settled = expectation(description: "Positioning settles")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
            attach(app, name: "located-complete-card-" + name)
            XCTAssertGreaterThanOrEqual(row.frame.minY, feed.frame.minY + 6)
            XCTAssertLessThanOrEqual(row.frame.maxY, feed.frame.maxY - 6)
            app.terminate()
        }
    }

    func testSearchRetainsQuerySelectsAllAndResetsOnRelaunch() {
        let app = launch(["--qa-search"])
        let search = app.buttons["search-open"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(search.frame.midX, app.frame.width * 0.4)
        attach(app, name: "search-toolbar-trailing")
        search.tap()
        let field = app.textFields["search-query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertLessThan(field.frame.height, 50)
        attach(app, name: "search-empty-polished")
        field.typeText("ms")
        XCTAssertTrue(app.buttons["search-result-search-completed"].waitForExistence(timeout: 8))
        attach(app, name: "search-phonetic-highlights")
        app.buttons["取消"].tap()
        search.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "ms")
        // Do not tap again: focus on reopen must already select the previous query.
        field.typeText("照片")
        XCTAssertEqual(field.value as? String, "照片")
        XCTAssertTrue(app.buttons["search-result-search-image"].waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertNotEqual(field.value as? String, "照片")
    }

    func testSearchWalkthroughStates() {
        let app = launch(["--qa-search"])
        let search = app.buttons["search-open"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        let field = app.textFields["search-query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["输入关键词，查找你的记录"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.progressIndicators.firstMatch.exists)
        attach(app, name: "walkthrough-empty")
        field.typeText("zzzznotfound")
        XCTAssertTrue(app.staticTexts["没有找到相关记录"].waitForExistence(timeout: 8))
        attach(app, name: "walkthrough-no-results")
        app.buttons["清除搜索"].tap()
        field.typeText("ms")
        XCTAssertTrue(app.buttons["search-result-search-completed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "找到 3 条记录")).firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "walkthrough-results")
    }

    func testSearchRefinementTypingAndGlyphs() {
        let app = launch(["--qa-search"])
        XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 8))
        attach(app, name: "round2-toolbar")
        app.buttons["search-open"].tap()
        let field = app.textFields["search-query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("ms")
        XCTAssertTrue(app.buttons["search-result-search-completed"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.progressIndicators.firstMatch.exists)
        attach(app, name: "round2-results")
        app.buttons["清除搜索"].tap()
        field.typeText("playing")
        XCTAssertTrue(app.buttons["search-result-search-completed"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.progressIndicators.firstMatch.exists)
        attach(app, name: "round2-latin-marker")
    }

    func testSearchWalkthroughDarkResults() {
        let app = launch(["--qa-search", "-appAppearance", "dark"])
        XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 8))
        app.buttons["search-open"].tap()
        let field = app.textFields["search-query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("ms")
        XCTAssertTrue(app.buttons["search-result-search-completed"].waitForExistence(timeout: 8))
        attach(app, name: "walkthrough-dark-results")
    }

    func testSearchRevealsFoldedTail() {
        let app = launch(["--qa-search"])
        XCTAssertTrue(app.buttons["search-open"].waitForExistence(timeout: 8))
        app.buttons["search-open"].tap()
        let field = app.textFields["search-query"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("尾部定位验收")
        let result = app.buttons["search-result-search-long"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        attach(app, name: "walkthrough-tail-excerpt")
        result.tap()
        let collapse = app.buttons["收起"].firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: collapse)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
        attach(app, name: "walkthrough-tail-located")
        let y = collapse.frame.minY
        let settled = expectation(description: "Tail anchor stays stable")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { settled.fulfill() }
        wait(for: [settled], timeout: 4)
        XCTAssertEqual(collapse.frame.minY, y, accuracy: 6)
    }

    func testCancelSearchPreservesVisibleRecord() {
        let app = launch(["--qa-search"])
        let row = app.otherElements["record-search-completed"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        let y = row.frame.minY
        app.buttons["search-open"].tap()
        XCTAssertTrue(app.textFields["search-query"].waitForExistence(timeout: 5))
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.frame.minY, y, accuracy: 6)
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
