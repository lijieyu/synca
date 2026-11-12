import AppKit
import SwiftUI

@MainActor
private final class SearchModel: ObservableObject {
    @Published var text = ""
    @Published var draft = false
    @Published var revision = 0
    @Published var echo = ""
    var delayedEcho = false
    var binding: Binding<String> {
        Binding(get: { self.delayedEcho ? self.echo : self.text }, set: { value in
            self.text = value
            if self.delayedEcho {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { self.echo = value }
            }
        })
    }
}
private struct SearchHost: View {
    @ObservedObject var model: SearchModel
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                SearchQueryField(text: model.binding, placeholder: "Search", clearRevision: model.revision,
                                 onDraftChange: { model.draft = $0 })
                if model.draft { Button("Clear") { model.text = ""; model.revision += 1 } }
            }
            Text(model.text)
        }.frame(width: 500, height: 120)
    }
}

@main
struct MacSearchSelectionTests {
    @MainActor static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12)) }
    @MainActor static func findField(_ view: NSView) -> SearchQueryField.Field? {
        if let field = view as? SearchQueryField.Field { return field }
        return view.subviews.lazy.compactMap { findField($0) }.first
    }
    @MainActor static func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 120),
                 styleMask: [.titled], backing: .buffered, defer: false)
    }
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // Exercise the actual NSViewRepresentable, delegate, binding and updateNSView.
        // A delayed echo models a pending older render after a native edit.
        for delayed in [false, true] {
            let model = SearchModel(); model.delayedEcho = delayed
            let window = window()
            window.contentView = NSHostingView(rootView: SearchHost(model: model))
            window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true); settle()
            let field = findField(window.contentView!)!
            let editor = field.currentEditor() as! NSTextView
            for (letter, expected) in [("m", "m"), ("a", "ma"), ("c", "mac")] {
                editor.insertText(letter, replacementRange: NSRange(location: NSNotFound, length: 0))
                settle()
                print("typing delayedEcho=\(delayed) query=\(editor.string) selection=\(NSStringFromRange(editor.selectedRange()))")
                fflush(stdout)
                precondition(editor.string == expected && model.text == expected, "Binding echo must not replace live input")
                precondition(editor.selectedRange() == NSRange(location: expected.utf16.count, length: 0), "Typing must leave the caret at the end")
                precondition(findField(window.contentView!) === field, "Clear-button appearance must not recreate the field")
            }
            editor.setMarkedText("gou", selectedRange: NSRange(location: 3, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            model.draft = true; settle()
            precondition(editor.hasMarkedText() && model.text == "mac", "Candidate text must not replace the committed query")
            precondition(editor.selectedRange().length == 0, "Candidate selection must not become select-all")
            editor.insertText("沟", replacementRange: NSRange(location: NSNotFound, length: 0)); settle()
            precondition(model.text == "mac沟" && editor.selectedRange() == NSRange(location: 4, length: 0), "IME commit must preserve trailing caret")
            editor.setMarkedText("new", selectedRange: NSRange(location: 3, length: 0),
                                 replacementRange: NSRange(location: NSNotFound, length: 0))
            model.text = ""; model.echo = ""; model.revision += 1; settle()
            precondition(editor.string.isEmpty && !editor.hasMarkedText() && editor.selectedRange() == NSRange(location: 0, length: 0), "Explicit clear must cancel composition")
            window.orderOut(nil)
        }
        for marked in [false, true] {
            let window = window()
            let field = SearchQueryField.Field()
            field.frame = NSRect(x: 10, y: 20, width: 300, height: 30)
            let coordinator = SearchQueryField.Coordinator(SearchQueryField(text: .constant(""), placeholder: "Search"))
            field.delegate = coordinator
            window.contentView!.addSubview(field); window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(field)
            let editor = field.currentEditor() as! NSTextView
            if marked { editor.setMarkedText("m", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
            else { editor.insertText("m", replacementRange: NSRange(location: NSNotFound, length: 0)) }
            let selection = editor.selectedRange(); settle()
            precondition(editor.selectedRange() == selection && editor.string == "m", "Deferred focus must not select new input")
            if marked { precondition(editor.hasMarkedText(), "Autofocus must not commit IME composition") }
            window.orderOut(nil)
        }
        let model = SearchModel(); model.text = "previous query"
        for _ in 0..<2 {
            let window = window(); window.contentView = NSHostingView(rootView: SearchHost(model: model))
            window.makeKeyAndOrderFront(nil); settle()
            let field = findField(window.contentView!)!
            precondition(field.currentEditor()?.selectedRange == NSRange(location: 0, length: 14), "Reopened untouched query remains selected for replacement")
            window.orderOut(nil)
        }
        print("PASS: hosted binding updates, delayed stale echo, continuous typing, IME draft/commit/clear, stable field identity, initial focus race, reopened history")
    }
}
