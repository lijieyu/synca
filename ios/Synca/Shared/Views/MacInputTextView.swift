import SwiftUI

#if os(macOS)
import AppKit

struct MacInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let onPasteImage: (Data) -> Void
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onPasteImage: onPasteImage, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> ClickForwardingScrollView {
        let scrollView = ClickForwardingScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = PasteAwareMacTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor
        ]
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: ClickForwardingScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteAwareMacTextView else { return }
        context.coordinator.onSubmit = onSubmit
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        if textView.string != text {
            // Use replaceCharacters instead of string= to preserve typingAttributes
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            textView.textStorage?.replaceCharacters(in: fullRange, with: text)
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        }
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        let onPasteImage: (Data) -> Void
        var onSubmit: (() -> Void)?

        init(text: Binding<String>, height: Binding<CGFloat>, onPasteImage: @escaping (Data) -> Void, onSubmit: (() -> Void)?) {
            _text = text
            _height = height
            self.onPasteImage = onPasteImage
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            recalculateHeight(for: textView)
        }

        @MainActor
        func recalculateHeight(for textView: NSTextView) {
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
            let contentHeight = max(40, min(150, ceil(usedHeight + textView.textContainerInset.height * 2)))
            if abs(height - contentHeight) > 0.5 {
                height = contentHeight
            }
        }
    }
}

/// Forwards mouse clicks to the inner NSTextView so SwiftUI doesn't swallow them.
final class ClickForwardingScrollView: NSScrollView {
    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }
}

final class PasteAwareMacTextView: NSTextView {
    var onPasteImage: ((Data) -> Void)?
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return without modifiers = send; Shift+Return = newline; Command+Return = send
        if event.keyCode == 36 {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) || flags.contains(.command) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general

        if let rawPngData = pb.data(forType: .png) {
            onPasteImage?(rawPngData)
            return
        }
        if let rawJpegData = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            onPasteImage?(rawJpegData)
            return
        }
        if let rawHeicData = pb.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            onPasteImage?(rawHeicData)
            return
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            onPasteImage?(pngData)
            return
        }

        super.paste(sender)
    }
}
#endif
