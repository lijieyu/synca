import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

struct MacInputTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let isSending: Bool
    var placeholder: String = ""
    var focusRequest: Int = 0
    let onPasteImage: (Data) -> Void
    let onPasteFile: (PendingFileUpload) -> Void
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
        Coordinator(text: $text, height: $height, onPasteImage: onPasteImage, onPasteFile: onPasteFile, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> MacInputContainerView {
        let container = MacInputContainerView()

        let textView = PasteAwareMacTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.onPasteFile = onPasteFile
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
        // Vertical inset is derived from the configured font in recalculateHeight.
        textView.textContainerInset = NSSize(width: 0, height: 5)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        // Allow the document view to grow beyond the visible field height so NSScrollView can scroll once capped.
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        Self.applyPlainTextStyle(to: textView)

        container.textView = textView
        container.documentView = textView
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
        return container
    }

    func updateNSView(_ container: MacInputContainerView, context: Context) {
        guard let textView = container.textView else { return }
        textView.placeholder = placeholder
        context.coordinator.onSubmit = onSubmit
        textView.onSubmit = onSubmit
        textView.onPasteImage = onPasteImage
        textView.onPasteFile = onPasteFile
        textView.isEditable = !isSending
        textView.isSelectable = !isSending
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            if focusRequest > 0, !isSending {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView, let window = textView.window,
                          window.attachedSheet == nil else { return }
                    let selection = textView.selectedRanges
                    window.makeFirstResponder(textView)
                    textView.selectedRanges = selection
                }
            }
        }
        container.layoutTextView()
        // Do not overwrite the text view while IME composition is active (e.g. Chinese input).
        if !textView.hasMarkedText(), textView.string != text {
            // Use replaceCharacters instead of string= to preserve typingAttributes
            let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
            textView.textStorage?.replaceCharacters(in: fullRange, with: text)
            Self.applyPlainTextStyle(to: textView)
        }
        // AppKit owns the attributes of active IME text and font fallback runs.
        // Restyling every SwiftUI update invalidates layout during composition.
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
        let onPasteFile: (PendingFileUpload) -> Void
        var onSubmit: (() -> Void)?
        var lastFocusRequest = 0

        init(text: Binding<String>, height: Binding<CGFloat>, onPasteImage: @escaping (Data) -> Void, onPasteFile: @escaping (PendingFileUpload) -> Void, onSubmit: (() -> Void)?) {
            _text = text
            _height = height
            self.onPasteImage = onPasteImage
            self.onPasteFile = onPasteFile
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
            // Include the extra empty line after Return so its caret is not clipped.
            let rawHeight = textView.string.isEmpty ? lineH : max(
                lm.usedRect(for: tc).maxY, lm.extraLineFragmentRect.maxY)
            let usedHeight = alignedTextHeight(rawHeight, in: textView)
            let minFieldH: CGFloat = 34
            let maxFieldH: CGFloat = 104
            // Derive the inset from the configured font, never from the current glyphs.
            // Re-centering each marked/committed run moves the entire line while typing.
            // AppKit floors fractional textContainerInset values. In Chinese system
            // language a nominal 16pt line can report 16.0063pt, producing an
            // 8.9968pt inset that becomes 8pt instead of the intended 9pt.
            let verticalPad = max(4, ((minFieldH - lm.defaultLineHeight(for: MacInputTextView.textFont)) / 2).rounded())
            let fieldH = min(maxFieldH, max(minFieldH, ceil(usedHeight + 2 * verticalPad)))

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

/// Quantize subpixel font-metric noise consistently for the field and document.
/// Otherwise ceil(16.0063) adds a spurious point and can trigger caret scrolling.
@MainActor
private func alignedTextHeight(_ height: CGFloat, in view: NSView) -> CGFloat {
    let scale = view.window?.backingScaleFactor ?? 1
    return (height * scale).rounded() / scale
}

/// A vertical-only scroll host: the document grows while SwiftUI caps the visible field.
final class MacInputContainerView: NSScrollView {
    weak var textView: PasteAwareMacTextView?
    private var layingOutText = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        // Leave scrollerStyle to the user's system preference.
    }
    override func layout() {
        super.layout()
        layoutTextView()
    }
    func layoutTextView() {
        guard !layingOutText, let textView, contentSize.width > 0,
              let manager = textView.layoutManager, let container = textView.textContainer else { return }
        layingOutText = true
        defer { layingOutText = false }
        let width = contentSize.width
        textView.minSize = NSSize(width: width, height: 0)
        textView.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.setFrameSize(NSSize(width: width, height: max(contentSize.height, textView.frame.height)))
        // Width tracking owns wrapping; never manually set a competing container width.
        manager.ensureLayout(for: container)
        let bottom = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
        textView.setFrameSize(NSSize(width: width, height: max(contentSize.height, ceil(alignedTextHeight(bottom, in: textView) + 2 * textView.textContainerInset.height))))
    }
}

final class PasteAwareMacTextView: NSTextView {
    // AppKit owns composition; a SwiftUI overlay can lag behind marked text.
    var placeholder = "" { didSet { if oldValue != placeholder { needsDisplay = true } } }
    var shouldDrawPlaceholder: Bool { string.isEmpty && !hasMarkedText() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard shouldDrawPlaceholder else { return }
        (placeholder as NSString).draw(at: NSPoint(x: textContainerOrigin.x + 2, y: textContainerOrigin.y),
            withAttributes: [.font: font ?? NSFont.preferredFont(forTextStyle: .body),
                             .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    var onPasteImage: ((Data) -> Void)?
    var onPasteFile: ((PendingFileUpload) -> Void)?
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
        // Candidate confirmation belongs to the input method, not the send shortcut.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
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

        if let fileURL = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            if let imageData = PendingFileUpload.imageData(from: fileURL) {
                onPasteImage?(imageData)
            } else if let pendingFile = PendingFileUpload.read(from: fileURL) {
                onPasteFile?(pendingFile)
            } else {
                NSSound.beep()
            }
            return
        }

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
