import XCTest
@MainActor
final class MarkdownParityTests: XCTestCase {
    func testRecordAndScratch() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Scratchpad"].waitForExistence(timeout: 10))
        capture("record-light-top")
        app.swipeUp(); capture("record-light-code-table"); app.swipeDown()
        let recordTasks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markdown-task-"))
        XCTAssertGreaterThan(recordTasks.count, 0)
        var task = recordTasks.allElementsBoundByIndex.first(where: { $0.isHittable })
        for _ in 0..<4 where task == nil { app.swipeUp(); task = recordTasks.allElementsBoundByIndex.first(where: { $0.isHittable }) }
        XCTAssertNotNil(task, "A task must be visible and interactive")
        guard let task else { return }
        let before = task.value as? String
        task.tap()
        let saved = NSPredicate { _, _ in task.isEnabled && task.value as? String != before }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: task)], timeout: 5), .completed)
        app.buttons["Scratchpad"].tap()
        capture("scratch-light-top")
        app.swipeUp(); capture("scratch-light-code-table"); app.swipeDown()
        let scratchTasks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markdown-task-"))
        XCTAssertGreaterThan(scratchTasks.count, 0)
        // The shared showcase starts this task unchecked in the independent scratch draft.
        let scratchTask = scratchTasks.matching(NSPredicate(format: "label == %@", "核对记录和草稿本")).firstMatch
        XCTAssertTrue(scratchTask.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if scratchTask.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(scratchTask.isHittable, "The scratch task must actually be reachable")
        let scratchBefore = scratchTask.value as? String
        scratchTask.tap()
        let scratchSaved = NSPredicate { _, _ in scratchTask.isEnabled && scratchTask.value as? String != scratchBefore }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: scratchSaved, object: scratchTask)], timeout: 5), .completed)
        let editMode = app.segmentedControls.buttons.matching(NSPredicate(format: "label IN %@", ["Edit", "编辑", "編輯"])).firstMatch
        XCTAssertTrue(editMode.isHittable); editMode.tap()
        let scratchEditor = app.textViews["scratch-editor"]
        XCTAssertTrue(scratchEditor.waitForExistence(timeout: 5))
        XCTAssertTrue(scratchEditor.isHittable)
        let scratchSource = scratchEditor.value as? String ?? ""
        XCTAssertTrue(scratchSource.contains("- [x] 核对记录和草稿本"), "Preview task changes must persist into the actual scratch source")
        XCTAssertTrue(scratchSource.contains("```swift"), "Task editing must retain unrelated Markdown source")
        capture("scratch-editor-task-source")
        let previewMode = app.segmentedControls.buttons.matching(NSPredicate(format: "label IN %@", ["Preview", "预览", "預覽"])).firstMatch
        XCTAssertTrue(previewMode.isHittable); previewMode.tap()
        XCTAssertTrue(scratchTask.waitForExistence(timeout: 5))
        XCTAssertNotEqual(scratchTask.value as? String, scratchBefore)
        capture("scratch-light-after-task")
        app.buttons["Record"].tap()
        capture("record-light-after-task")
    }
    func testDarkAppearance() {
        let app = XCUIApplication(); app.launchArguments = ["-qa-dark"]; app.launch()
        XCTAssertTrue(app.buttons["Scratchpad"].waitForExistence(timeout: 10))
        guard assertDarkAppearance(app) else { return }
        capture("record-dark-top")
        app.swipeUp()
        guard assertDarkAppearance(app) else { return }
        capture("record-dark-code-table")
        app.buttons["Scratchpad"].tap()
        guard assertDarkAppearance(app) else { return }
        capture("scratch-dark-top")
        app.swipeUp()
        guard assertDarkAppearance(app) else { return }
        capture("scratch-dark-code-table")
    }
    private func assertDarkAppearance(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let labelledSwitch = app.switches["Dark"]
        let innerSwitch = labelledSwitch.switches.firstMatch
        let control = innerSwitch.exists ? innerSwitch : labelledSwitch
        let probe = app.staticTexts["qa-rendered-scheme"]
        let renderedDark = NSPredicate { _, _ in probe.exists && probe.label == "dark" && control.value as? String == "1" }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: renderedDark, object: probe)], timeout: 5)
        guard result == .completed else {
            XCTFail("Dark captures require the actual switch value 1 and rendered color scheme dark", file: file, line: line)
            return false
        }
        return true
    }
    func testLargeTaskListUsesBoundedPages() {
        let app = XCUIApplication(); app.launchArguments = ["-qa-fixture", "large-tasks"]; app.launch()
        let tasks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markdown-task-"))
        XCTAssertTrue(tasks.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(tasks.count, 128, "250k input must not instantiate 31250 task controls")
        let firstID = tasks.firstMatch.identifier
        let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markdown-next-items-")).firstMatch
        XCTAssertTrue(next.isHittable); next.tap()
        XCTAssertEqual(tasks.count, 128)
        XCTAssertNotEqual(tasks.firstMatch.identifier, firstID)
        capture("record-large-task-page-two")
    }
    func testFencedImagesStayLiteral() {
        let app = XCUIApplication(); app.launchArguments = ["-qa-fixture", "fences"]; app.launch()
        XCTAssertTrue(app.buttons["Scratchpad"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["代码内图片"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markdown-task-")).count, 0)
        capture("record-fenced-literal")
        app.buttons["Scratchpad"].tap()
        XCTAssertFalse(app.images["代码内图片"].exists)
        capture("scratch-fenced-literal")
    }
    func testNestedAndTableOwnedImages() {
        let app = XCUIApplication(); app.launchArguments = ["-qa-fixture", "image-nesting-table"]; app.launch()
        assertVisibleImage("嵌套图片", in: app)
        assertVisibleImage("表格图片", in: app)
        XCTAssertFalse(app.images["代码图片"].exists)
        capture("record-nested-table-images")
        app.buttons["Scratchpad"].tap()
        assertVisibleImage("嵌套图片", in: app)
        assertVisibleImage("表格图片", in: app)
        XCTAssertFalse(app.images["代码图片"].exists)
        capture("scratch-nested-table-images")
    }
    func testOwnedImagesAndLiteralCode() { assertImages(uppercase: false) }
    func testUppercaseOwnedImageScheme() { assertImages(uppercase: true) }
    func testEncodedOwnedImageDestination() { assertImages(uppercase: false, encoded: true) }
    private func assertImages(uppercase: Bool, encoded: Bool = false) {
        let app = XCUIApplication()
        app.launchArguments = ["-qa-fixture", "images"] + (uppercase ? ["-qa-uppercase-images"] : []) + (encoded ? ["-qa-encoded-images"] : [])
        app.launch()
        assertVisibleImage("本机上传", in: app)
        XCTAssertEqual(app.images.matching(identifier: "本机上传").count, 1)
        XCTAssertFalse(app.images["代码图片"].exists)
        XCTAssertFalse(app.images["引用图片"].exists, "Unowned UUID remains a source fallback")
        capture(encoded ? "record-owned-encoded" : uppercase ? "record-owned-uppercase" : "record-owned-images")
        app.buttons["Scratchpad"].tap()
        assertVisibleImage("本机上传", in: app)
        XCTAssertFalse(app.images["代码图片"].exists)
        XCTAssertFalse(app.images["引用图片"].exists)
        capture(encoded ? "scratch-owned-encoded" : uppercase ? "scratch-owned-uppercase" : "scratch-owned-images")
    }
    func testEditorRetainsSource() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Source"].waitForExistence(timeout: 10))
        app.buttons["Source"].tap()
        let editor = app.textViews["message-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(editor.isHittable, "Read the visible editor, not the selectable preview behind its sheet")
        let value = editor.value as? String ?? ""
        XCTAssertTrue(value.contains("#### 项目记录"))
        XCTAssertTrue(value.contains("~~旧计划~~"))
        XCTAssertTrue(value.contains("```swift"))
        XCTAssertTrue(value.contains("| :--- | :---: |"))
        capture("editor-raw-source")
    }
    func testFailedTaskRollsBack() { assertRollback(argument: "-qa-task-failure") }
    func testConflictTaskRollsBack() { assertRollback(argument: "-qa-task-conflict") }
    private func assertRollback(argument: String) {
        let app = XCUIApplication(); app.launchArguments = [argument]; app.launch()
        let tasks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markdown-task-"))
        XCTAssertTrue(tasks.firstMatch.waitForExistence(timeout: 10))
        if !tasks.firstMatch.isHittable { app.swipeUp() }
        let task = tasks.firstMatch
        let before = task.value as? String
        task.tap()
        let rolledBack = NSPredicate { _, _ in task.isEnabled && task.value as? String == before }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rolledBack, object: task)], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts["qa-source-state"].label, "source-original")
        capture(argument)
    }
    func testLargestText() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); capture("record-largest-top")
        app.swipeUp(); capture("record-largest-middle")
        app.buttons["Scratchpad"].tap(); capture("scratch-largest-top")
        app.swipeUp(); capture("scratch-largest-middle")
    }
    private func assertVisibleImage(_ label: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let image = app.images[label]
        _ = image.waitForExistence(timeout: 5)
        for _ in 0..<4 {
            if image.exists && image.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(image.exists, "Owned image must expose an image accessibility element: \(label)", file: file, line: line)
        XCTAssertTrue(image.isHittable, "Owned image must be reachable after scrolling: \(label)", file: file, line: line)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
