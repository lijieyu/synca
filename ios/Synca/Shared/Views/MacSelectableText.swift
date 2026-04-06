import SwiftUI

#if os(macOS)
import AppKit

/// A selectable text view for macOS designed specifically to act as an overlay
/// in a ZStack. It relies entirely on the SwiftUI frame for sizing and
/// only provides the custom context menu and selection capabilities.
struct MacSelectableText: NSViewRepresentable {
    let attributedText: NSAttributedString
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void

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
        
        textView.onCopy = onCopy
        textView.onDelete = onDelete
        
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
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in self.trackingAreas { self.removeTrackingArea(area) }
        let options: NSTrackingArea.Options = [.mouseMoved, .cursorUpdate, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        self.updateCursor(with: event)
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        self.updateCursor(with: event)
    }

    private func updateCursor(with event: NSEvent) {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        
        let point = self.convert(event.locationInWindow, from: nil)
        
        // Adjust for any text container insets if they were not zero
        let textContainerPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        
        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(for: textContainerPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        
        // Ensure the charIndex is valid and actually within the glyph rect to avoid hover-hand near end of lines
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
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: String(localized: "common.copy", bundle: .main), action: #selector(handleCopy(_:)), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Ensure no plugins or system additions are allowed on this specific menu
        menu.allowsContextMenuPlugIns = false
        
        let deleteItem = NSMenuItem(title: String(localized: "common.delete", bundle: .main), action: #selector(handleDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        return menu
    }

    @objc func handleCopy(_ sender: Any?) {
        if self.selectedRange().length > 0 {
            self.copy(sender)
        } else {
            onCopy?()
        }
    }

    @objc func handleDelete(_ sender: Any?) {
        onDelete?()
    }
}

#else
// Dummy view for iOS to maintain cross-platform compilation
struct MacSelectableText: View {
    let attributedText: NSAttributedString
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void
    var body: some View { EmptyView() }
}
#endif
