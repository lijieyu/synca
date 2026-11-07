import AppKit

@main
struct MacPlainTextLayoutTests {
    @MainActor static func main() {
        let scrollView = MacPlainTextScrollView(frame: NSRect(x: 0, y: 0, width: 430, height: 160))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        scrollView.documentView = textView
        let original = String(repeating: "最后一个汉字不能被裁切，英文 English 和数字 123 也需要正确换行。", count: 12) + "\n"
        for inset: CGFloat in [12, 0] {
            textView.textContainerInset = NSSize(width: inset, height: 16)
            textView.string = original
            textView.setSelectedRange(NSRange(location: original.utf16.count, length: 0))

            for width: CGFloat in [430, 310, 520, 365, 430] {
                scrollView.setFrameSize(NSSize(width: width, height: 160))
                scrollView.updateTextLayout()
                scrollView.updateTextLayout() // Typing updates layout again without changing the frame.
                let expectedWidth = scrollView.contentSize.width - 2 * textView.textContainerInset.width
                precondition(abs(textContainer.containerSize.width - expectedWidth) < 1, "Text container must subtract both horizontal insets")
                layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)) { rect, used, _, _, _ in
                    precondition(used.maxX <= expectedWidth + 1, "CJK line must fit within the visible trailing inset")
                    precondition(rect.width <= expectedWidth + 1)
                }
                let textBottom = max(layoutManager.usedRect(for: textContainer).maxY, layoutManager.extraLineFragmentRect.maxY)
                precondition(textView.frame.height >= textBottom + 2 * textView.textContainerInset.height - 1, "Trailing newline caret must stay in scrollable document")
                precondition(textView.frame.height > scrollView.contentSize.height, "Long content must remain vertically scrollable")
                precondition(textView.string == original && textView.selectedRange().location == original.utf16.count, "Layout must preserve text and selection")
            }
        }
        textView.string = "短文本"
        scrollView.updateTextLayout()
        precondition(abs(textView.frame.height - scrollView.contentSize.height) < 1, "Short content must shrink back to viewport height")
        textView.setMarkedText("组合输入", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let markedRange = textView.markedRange()
        let composingText = textView.string
        let selection = textView.selectedRange()
        scrollView.setFrameSize(NSSize(width: 310, height: 160))
        scrollView.updateTextLayout()
        precondition(textView.hasMarkedText() && textView.markedRange() == markedRange && textView.string == composingText && textView.selectedRange() == selection,
                     "Resizing must preserve active IME composition")
        textView.unmarkText()
        print("PASS: symmetric editor insets (0 and 12pt), CJK wrapping at five widths, trailing caret, vertical overflow, selection/IME preservation and shrinking")
    }
}
