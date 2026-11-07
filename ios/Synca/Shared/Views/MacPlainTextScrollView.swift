#if os(macOS)
import AppKit

/// The text view owns its tracked container width; the scroll view owns document height.
@MainActor
final class MacPlainTextScrollView: NSScrollView {
    private var isUpdatingTextLayout = false

    override func layout() {
        super.layout()
        updateTextLayout()
    }

    func updateTextLayout() {
        guard !isUpdatingTextLayout, contentSize.width > 0,
              let textView = documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        isUpdatingTextLayout = true
        defer { isUpdatingTextLayout = false }

        // widthTracksTextView subtracts both textContainerInset margins automatically.
        // Setting containerSize directly would override that when typing at an unchanged width.
        textView.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, textView.frame.height)))
        layoutManager.ensureLayout(for: textContainer)
        var textBottom = layoutManager.usedRect(for: textContainer).maxY
        if layoutManager.extraLineFragmentTextContainer === textContainer {
            textBottom = max(textBottom, layoutManager.extraLineFragmentRect.maxY)
        }
        let documentHeight = max(contentSize.height, ceil(textBottom + textView.textContainerInset.height * 2))
        textView.setFrameSize(NSSize(width: contentSize.width, height: documentHeight))
    }
}
#endif
