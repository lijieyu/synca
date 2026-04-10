import SwiftUI

#if os(macOS)
import AppKit

struct MacInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let isSending: Bool
    let onPasteImage: (Data) -> Void
    var onSubmit: (() -> Void)? = nil

    private static var textFont: NSFont {
        NSFont.preferredFont(forTextStyle: .body)
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: textFont,
            .foregroundColor: NSColor.textColor,
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onPasteImage: onPasteImage, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> ClickForwardingScrollView {
        let scrollView = ClickForwardingScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = PasteAwareMacTextView()
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.onSubmit = onSubmit
        textView.isEditable = !isSending
        textView.isSelectable = !isSending
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        // Let SwiftUI own the field surface so AppKit doesn't create an inner nested background.
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = Self.textFont
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.typingAttributes = Self.textAttributes
        // Vertical inset is set in recalculateHeight so min-height fields center the line optically.
        textView.textContainerInset = NSSize(width: 0, height: 5)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        // Allow the document view to grow beyond the visible field height so NSScrollView can scroll once capped.
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        Self.applyPlainTextStyle(to: textView)

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
        textView.isEditable = !isSending
        textView.isSelectable = !isSending
        scrollView.syncTextViewWidthAndContainer()
        // Do not overwrite the text view while IME composition is active (e.g. Chinese input).
        if !textView.hasMarkedText(), textView.string != text {
            // Use replaceCharacters instead of string= to preserve typingAttributes
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            textView.textStorage?.replaceCharacters(in: fullRange, with: text)
        }
        Self.applyPlainTextStyle(to: textView)
        // Defer binding updates to the next run loop so AppKit sizing doesn't mutate SwiftUI state during view updates.
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
    }

    private static func applyPlainTextStyle(to textView: NSTextView) {
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        textView.font = textFont
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.defaultParagraphStyle = .default
        textView.typingAttributes = textAttributes
        textView.textStorage?.setAttributes(textAttributes, range: fullRange)
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
            guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
            lm.ensureLayout(for: tc)
            let font = textView.font ?? MacInputTextView.textFont
            let lineH = lm.defaultLineHeight(for: font)
            // Empty (or not yet laid out) usedRect is often 0; using line height keeps padding + caret position stable after clear/send.
            var usedHeight = lm.usedRect(for: tc).height
            if textView.string.isEmpty {
                usedHeight = lineH
            }

            let minFieldH: CGFloat = 34
            let maxFieldH: CGFloat = 104
            let minSidePad: CGFloat = 4

            let naturalH = usedHeight + 2 * minSidePad
            let fieldH: CGFloat
            if naturalH <= maxFieldH {
                fieldH = max(minFieldH, ceil(naturalH))
            } else {
                fieldH = maxFieldH
            }

            // Split extra height equally above/below the laid-out text so single-line fields don’t look top-heavy.
            let verticalPad: CGFloat
            if fieldH >= usedHeight {
                verticalPad = max(minSidePad, (fieldH - usedHeight) / 2)
            } else {
                verticalPad = minSidePad
            }

            textView.textContainerInset = NSSize(width: 0, height: verticalPad)
            lm.ensureLayout(for: tc)

            var f = textView.frame
            f.size.height = ceil(max(fieldH, usedHeight + 2 * verticalPad))
            textView.frame = f
            if abs(height - fieldH) > 0.5 {
                height = fieldH
            }

            let selection = textView.selectedRange()
            let textLength = (textView.string as NSString).length
            let clampedLocation = min(selection.location, textLength)
            let clampedLength = min(selection.length, max(0, textLength - clampedLocation))
            textView.scrollRangeToVisible(NSRange(location: clampedLocation, length: clampedLength))
            textView.updateInsertionPointStateAndRestartTimer(true)
        }
    }
}

/// Forwards mouse clicks to the inner NSTextView so SwiftUI doesn't swallow them.
final class ClickForwardingScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { false }

    override func layout() {
        super.layout()
        syncTextViewWidthAndContainer()
    }

    override func keyDown(with event: NSEvent) {
        if let textView = documentView as? PasteAwareMacTextView {
            window?.makeFirstResponder(textView)
            textView.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v",
           let textView = documentView as? PasteAwareMacTextView {
            window?.makeFirstResponder(textView)
            textView.paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
        }
        super.mouseDown(with: event)
    }

    /// SwiftUI often gives the scroll view a width before AppKit propagates it to the text container; width 0 breaks drawing and typing.
    func syncTextViewWidthAndContainer() {
        guard let textView = documentView as? NSTextView else { return }
        let w = contentView.bounds.width
        guard w > 0 else { return }
        var f = textView.frame
        f.size.width = w
        textView.frame = f
        let inset = textView.textContainerInset.width * 2
        let containerW = max(1, w - inset)
        textView.textContainer?.containerSize = NSSize(width: containerW, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: w, height: 0)
        textView.maxSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }
}

final class PasteAwareMacTextView: NSTextView {
    var onPasteImage: ((Data) -> Void)?
    var onSubmit: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Plain Return / keypad Enter = send; any modifier (Shift, Command, Option, Control) = newline.
        if event.keyCode == 36 || event.keyCode == 76 {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasModifier = flags.contains(.shift) || flags.contains(.command)
                || flags.contains(.option) || flags.contains(.control)
            if hasModifier {
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
