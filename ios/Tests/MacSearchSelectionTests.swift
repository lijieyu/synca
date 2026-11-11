import AppKit
import SwiftUI

@main
struct MacSearchSelectionTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        for marked in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 100),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            let field = SearchQueryField.Field(frame: NSRect(x: 10, y: 20, width: 300, height: 30))
            let coordinator = SearchQueryField.Coordinator(SearchQueryField(text: .constant(""), placeholder: "Search"))
            field.delegate = coordinator
            window.contentView!.addSubview(field)
            window.makeKeyAndOrderFront(nil)
            // A key event can establish the editor before deferred autofocus runs.
            window.makeFirstResponder(field)
            let editor = field.currentEditor() as! NSTextView
            if marked {
                editor.setMarkedText("m", selectedRange: NSRange(location: 1, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
            } else {
                editor.insertText("m", replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            let originalSelection = editor.selectedRange()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            precondition(editor.selectedRange() == originalSelection, "Deferred focus must not select the first character")
            precondition(editor.string == "m", "Input must remain intact")
            if marked { precondition(editor.hasMarkedText(), "Autofocus must not commit IME composition") }
            window.orderOut(nil)
        }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = SearchQueryField.Field(frame: NSRect(x: 10, y: 20, width: 300, height: 30))
        field.stringValue = "previous query"
        window.contentView!.addSubview(field)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 14),
                     "Untouched retained query should remain selected for replacement")
        window.orderOut(nil)
        print("PASS: first committed character, IME composition, retained-query selection")
    }
}
