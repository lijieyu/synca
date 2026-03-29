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

    func makeNSView(context: Context) -> NSTextField {
        let textField = CustomMenuTextField(labelWithString: text)
        textField.isEditable = false
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        
        // Line wrapping configuration
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.lineBreakMode = .byWordWrapping
        
        // Set compression/hugging for SwiftUI layout
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        textField.onCopy = onCopy
        textField.onDelete = onDelete
        
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text
        nsView.textColor = NSColor(color)
        
        // Match font size - simplified for Mac body style
        nsView.font = NSFont.systemFont(ofSize: 14)
        
        // Notify layout changes
        nsView.invalidateIntrinsicContentSize()
    }
}

class CustomMenuTextField: NSTextField {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        // Copy selection or all
        let copyItem = NSMenuItem(title: "拷贝", action: #selector(copyOperation(_:)), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "删除", action: #selector(triggerDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        return menu
    }

    @objc func copyOperation(_ sender: Any?) {
        if let editor = self.currentEditor(), editor.selectedRange.length > 0 {
            editor.copy(sender)
        } else {
            onCopy?()
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
