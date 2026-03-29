import SwiftUI

#if os(macOS)
import AppKit

/// A selectable, read-only text view for macOS that allows for a custom context menu
/// while retaining the ability to select text.
struct SelectableTextView: NSViewRepresentable {
    let text: String
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = CustomMenuTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        
        // Setup text container for wrapping
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 400, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        // Remove padding to match SwiftUI Text
        textView.textContainerInset = NSSize.zero
        textView.textContainer?.lineFragmentPadding = 0
        
        textView.onCopy = onCopy
        textView.onDelete = onDelete
        
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        nsView.string = text
        nsView.textColor = NSColor(color)
        
        // Match font - basic mapping for now
        nsView.font = NSFont.systemFont(ofSize: 14)
        
        // Trigger re-layout for height calculation
        nsView.invalidateIntrinsicContentSize()
    }
}

class CustomMenuTextView: NSTextView {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    // #21: Report correct size to SwiftUI
    override var intrinsicContentSize: NSSize {
        guard let container = textContainer, let manager = layoutManager else { return .zero }
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)
        return NSSize(width: usedRect.width, height: usedRect.height)
    }

    // #21: Ensure we can become first responder for selection to work
    override var acceptsFirstResponder: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        let copyItem = NSMenuItem(title: "拷贝", action: #selector(copyFullText(_:)), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "删除", action: #selector(triggerDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        return menu
    }

    @objc func copyFullText(_ sender: Any?) {
        if self.selectedRange().length > 0 {
            self.copy(sender)
        } else if let onCopy = onCopy {
            onCopy()
        }
    }

    @objc func triggerDelete(_ sender: Any?) {
        onDelete?()
    }
}
#else
import SwiftUI
// Dummy view for non-macOS targets to keep the name in scope
struct SelectableTextView: View {
    let text: String
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void
    var body: some View { EmptyView() }
}
#endif
