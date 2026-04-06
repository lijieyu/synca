import SwiftUI

#if os(macOS)
import AppKit

/// A selectable text view for macOS designed specifically to act as an overlay
/// in a ZStack. It relies entirely on the SwiftUI frame for sizing and
/// only provides selection and link-clicking capabilities.
struct MacSelectableText: NSViewRepresentable {
    let attributedText: NSAttributedString
    let color: Color
    let font: Font

    func makeNSView(context: Context) -> CustomContextMenuTextView {
        let textView = CustomContextMenuTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        
        // Zero out padding so it aligns exactly with the underlying invisible SwiftUI Text
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        
        // Fills the SwiftUI-provided bounds perfectly
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        
        return textView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: CustomContextMenuTextView, context: Context) {
        if nsView.textStorage?.string != attributedText.string {
            nsView.textStorage?.setAttributedString(attributedText)
        } else {
            nsView.textStorage?.setAttributedString(attributedText)
        }
        nsView.textColor = NSColor(color)
        nsView.font = NSFont.systemFont(ofSize: 13) // SwiftUI .body roughly maps to 13pt
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            } else if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }
}

class CustomContextMenuTextView: NSTextView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in self.trackingAreas { self.removeTrackingArea(area) }
        let options: NSTrackingArea.Options = [.cursorUpdate, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else {
            NSCursor.iBeam.set()
            return
        }
        
        let point = self.convert(event.locationInWindow, from: nil)
        let textContainerPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        
        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(for: textContainerPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        
        if charIndex < (self.textStorage?.length ?? 0) {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            
            if glyphRect.contains(textContainerPoint) {
                let attribute = self.textStorage?.attribute(.link, at: charIndex, effectiveRange: nil)
                if attribute != nil {
                    NSCursor.pointingHand.set()
                    return
                }
            }
        }
        
        NSCursor.iBeam.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Default to I-Beam for the entire view to match macOS standard
        self.addCursorRect(self.bounds, cursor: .iBeam)
        
        guard
            let textStorage,
            let layoutManager,
            let textContainer
        else { return }

        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                self.addCursorRect(rect, cursor: .pointingHand)
            }
        }
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        // By returning nil, we tell the system this responder does not provide any data
        // for macOS Services. This forces the OS to omit the "Services" (服务) context menu item.
        return nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Returning nil allows the right-click event to bubble up to the SwiftUI container,
        // which handles the consistent card-level context menu.
        return nil
    }
}

#else
// Dummy view for iOS to maintain cross-platform compilation
struct MacSelectableText: View {
    let attributedText: NSAttributedString
    let color: Color
    let font: Font
    var body: some View { EmptyView() }
}
#endif

