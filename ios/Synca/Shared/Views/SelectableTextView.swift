import SwiftUI

#if os(macOS)
import AppKit

/// A selectable, read-only text view for macOS that allows for a custom context menu
/// while retaining the ability to select text.
struct SelectableTextView: NSViewRepresentable {
    let text: String
    let color: NSColor
    let font: NSFont
    let onCopy: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = CustomMenuTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = color
        textView.font = font
        textView.onCopy = onCopy
        textView.onDelete = onDelete
        
        // Remove padding to match SwiftUI Text
        textView.textContainerInset = NSSize.zero
        textView.textContainer?.lineFragmentPadding = 0
        
        return textView
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        nsView.string = text
        nsView.textColor = color
        nsView.font = font
    }
}

class CustomMenuTextView: NSTextView {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

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
        // If there's a selection, copy that. Otherwise, copy the full text.
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
