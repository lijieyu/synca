import AppKit
import SwiftUI

@main
struct MacInputCompositionTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        var submits = 0
        var text = ""
        var height: CGFloat = 34
        func root() -> MacInputTextView {
            MacInputTextView(text: Binding(get: { text }, set: { text = $0 }),
                             height: Binding(get: { height }, set: { height = $0 }),
                             isSending: false, onPasteImage: { _ in }, onPasteFile: { _ in }, onSubmit: { submits += 1 })
        }
        let host = NSHostingView(rootView: root())
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 34)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> PasteAwareMacTextView? {
            if let textView = view as? PasteAwareMacTextView { return textView }
            return view.subviews.compactMap(find).first
        }
        let input = find(host)!
        func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        func refresh() { host.rootView = root(); host.layoutSubtreeIfNeeded(); settle() }
        settle()
        precondition(input.shouldDrawPlaceholder, "Empty composer shows placeholder")
        // Regression from real Sogou Wubi traces: committed CJK has shorter
        // fallback-font metrics than the next Latin marked run. Preserve both
        // the existing glyph baseline and host height across that transition.
        let emptyHeight = height
        input.insertText("是", replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh()
        func firstBaseline() -> CGFloat {
            let manager = input.layoutManager!
            manager.ensureLayout(for: input.textContainer!)
            return input.textContainerOrigin.y
                + manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
                + manager.location(forGlyphAt: 0).y
        }
        let committedBaseline = firstBaseline()
        let committedHeight = height
        input.setMarkedText(NSAttributedString(string: "j", attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]), selectedRange: NSRange(location: 1, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh()
        print("CJK/marked baseline:", committedBaseline, firstBaseline(), "height:", emptyHeight, committedHeight, height)
        precondition(abs(firstBaseline() - committedBaseline) < 0.1,
                     "Latin marked run after committed CJK must not move existing text baseline")
        precondition(abs(height - committedHeight) < 0.1 && abs(height - emptyHeight) < 0.1,
                     "Empty, committed CJK and marked Latin must retain the same field height")
        input.insertText("是", replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh()
        precondition(abs(firstBaseline() - committedBaseline) < 0.1, "Committing candidate must retain baseline")
        text = ""; refresh()
        let marker = NSAttributedString.Key("IMERegressionMarker")
        let composing = NSAttributedString(string: "ni", attributes: [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            marker: "owned-by-input-method"
        ])
        input.setMarkedText(composing, selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(!input.shouldDrawPlaceholder, "Marked text must hide placeholder before a binding refresh")
        // Some input methods annotate the marked run after setMarkedText.
        input.textStorage?.addAttribute(marker, value: "owned-by-input-method", range: input.markedRange())
        let markedRange = input.markedRange()
        let selection = input.selectedRange()
        refresh()
        precondition(input.hasMarkedText() && input.markedRange() == markedRange && input.selectedRange() == selection, "Refresh must preserve marked text and selection")
        precondition(input.textStorage?.attribute(marker, at: 0, effectiveRange: nil) as? String == "owned-by-input-method", "Refresh must not overwrite IME-owned attributes")
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        input.keyDown(with: returnKey)
        precondition(submits == 0, "Return must belong to the IME while composition is active")
        input.insertText("你", replacementRange: NSRange(location: NSNotFound, length: 0))
        refresh()
        let baselinePadding = input.textContainerInset.height
        for prefix in ["", "中文", "a", "中文 a"] {
            input.string = prefix
            input.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
            text = prefix
            refresh()
            for pinyin in ["h", "hao", "hao'hao"] {
                input.setMarkedText(pinyin, selectedRange: NSRange(location: pinyin.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                refresh()
                precondition(abs(input.textContainerInset.height - baselinePadding) < 0.5, "Single-line composition must keep stable padding")
                let used = input.layoutManager!.usedRect(for: input.textContainer!).height
                precondition(abs(input.textContainerOrigin.y - (emptyHeight - used) / 2) < 0.51, "Actual AppKit text origin must be centered, including Chinese system language metrics")
                precondition(abs(input.enclosingScrollView!.contentView.bounds.minY) < 0.01, "Single-line IME must not scroll inside an unchanged composer")
                precondition(abs(height - emptyHeight) < 0.1, "Single-line composition must not resize the field")
            }
            input.insertText("好好", replacementRange: NSRange(location: NSNotFound, length: 0))
            refresh()
            precondition(input.string == prefix + "好好", "Candidate commit must replace marked text only")
        }
        window.contentView = nil
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 34)
        for sample in ["中文\n", String(repeating: "中文 English 👨‍👩‍👧‍👦 ", count: 30)] {
            text = sample; refresh()
            precondition(height > emptyHeight && height <= 104, "Multiline input must grow within the field cap")
            let lm = input.layoutManager!, tc = input.textContainer!
            precondition(input.frame.height >= max(lm.usedRect(for: tc).maxY, lm.extraLineFragmentRect.maxY) + input.textContainerInset.height * 2 - 1, "Trailing newline and overflow must fit the document")
        }
        let scroll = input.enclosingScrollView
        precondition(scroll != nil, "Capped composer must have an actual scroll view")
        precondition(scroll!.hasVerticalScroller && !scroll!.hasHorizontalScroller, "Composer only scrolls vertically")
        input.setSelectedRange(NSRange(location: 0, length: 0))
        input.scrollRangeToVisible(input.selectedRange())
        precondition(scroll!.contentView.bounds.minY < 2, "First line must be reachable")
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        input.scrollRangeToVisible(input.selectedRange())
        precondition(scroll!.contentView.bounds.minY > 0, "Last line must be reachable after overflow")
        text = ""; refresh()
        precondition(abs(height - emptyHeight) < 0.1 && abs(input.textContainerInset.height - baselinePadding) < 0.5, "Clearing must restore the same single-line layout")
        precondition(input.shouldDrawPlaceholder, "Clearing restores placeholder")
        precondition(!input.enclosingScrollView!.hasVerticalScroller, "Clearing overflow must hide the scroller again")
        precondition(input.enclosingScrollView!.contentView.bounds.origin == .zero, "Clearing overflow must restore the viewport origin")
        input.setMarkedText("a", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        precondition(!input.shouldDrawPlaceholder, "First IME keystroke hides placeholder")
        input.insertText("", replacementRange: input.markedRange())
        precondition(input.shouldDrawPlaceholder, "Cancelled composition restores placeholder immediately")
        // Exercise editing through AppKit, using an isolated pasteboard rather
        // than reading or replacing the user's clipboard.
        window.contentView = host
        window.makeFirstResponder(input)
        text = ""; refresh()
        let undo = input.undoManager!
        undo.removeAllActions()
        input.breakUndoCoalescing()
        input.insertText("撤销测试", replacementRange: NSRange(location: NSNotFound, length: 0))
        input.breakUndoCoalescing()
        refresh()
        precondition(undo.canUndo, "Typing remains undoable")
        undo.undo(); refresh()
        precondition(input.string.isEmpty && input.shouldDrawPlaceholder, "Undo restores the empty composer")
        undo.redo(); refresh()
        precondition(input.string == "撤销测试", "Redo restores committed text")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let pastedText = "粘贴 English 👨‍👩‍👧‍👦\n第二行"
        pasteboard.setString(pastedText, forType: .string)
        pasteboard.setString(pastedText, forType: NSPasteboard.PasteboardType("NSStringPboardType"))
        input.setSelectedRange(NSRange(location: 0, length: input.string.utf16.count))
        precondition(input.readSelection(from: pasteboard), "Plain text paste is accepted")
        refresh()
        precondition(input.string == pastedText && height > emptyHeight, "Paste preserves Unicode and line breaks")
        let shiftReturn = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        input.keyDown(with: shiftReturn); refresh()
        precondition(input.string == pastedText + "\n" && submits == 0, "Shift Return adds a line without sending")
        text = ""; refresh()
        precondition(input.shouldDrawPlaceholder && abs(height - emptyHeight) < 0.1, "Editing reset restores placeholder and height")

        // A minimum line box must not turn into a maximum that clips large runs.
        let largeFont = NSFont.systemFont(ofSize: 36)
        input.textStorage?.setAttributedString(NSAttributedString(string: "大 Ag 👨‍👩‍👧‍👦", attributes: [.font: largeFont]))
        input.layoutManager!.ensureLayout(for: input.textContainer!)
        precondition(input.layoutManager!.usedRect(for: input.textContainer!).height >= input.layoutManager!.defaultLineHeight(for: largeFont),
                     "Taller glyphs retain their natural line space")
        print("PASS: undo/redo, isolated Unicode paste, Shift Return, placeholder restore, and large-font line space")
        print("PASS: IME attributes/selection, Latin/CJK composition and commit, stable single-line padding and zero internal scroll, multiline growth, overflow and clear")
    }
}
