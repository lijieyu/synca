import SwiftUI

#if os(macOS)
import AppKit

/// A selectable, wrapping text view for macOS that uses NSTextField (Label mode)
/// to ensure perfect SwiftUI height/width calculation, while providing a pure
/// (customized) context menu without system clutter.
struct MacSelectableText: NSViewRepresentable {
    let text: String
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> CustomContextMenuTextField {
        // wrappingLabelWithString is the magic that tells AppKit to treat this
        // as a multi-line auto-sizing label, communicating the correct intrinsic size to SwiftUI.
        let textField = CustomContextMenuTextField(wrappingLabelWithString: text)
        textField.isSelectable = true
        textField.isEditable = false
        textField.drawsBackground = false
        
        // Let SwiftUI control the width but respect the vertical content size
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        textField.onCopy = onCopy
        textField.onDelete = onDelete
        
        return textField
    }

    func updateNSView(_ nsView: CustomContextMenuTextField, context: Context) {
        nsView.stringValue = text
        nsView.textColor = NSColor(color)
        
        // Sync basic font style - maps directly to macOS body font size for consistency
        nsView.font = NSFont.systemFont(ofSize: 14)
    }
}

class CustomContextMenuTextField: NSTextField {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        
        let copyItem = NSMenuItem(title: "拷贝", action: #selector(handleCopy(_:)), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = NSMenuItem(title: "删除", action: #selector(handleDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        return menu
    }

    @objc func handleCopy(_ sender: Any?) {
        // If the user selected some text, copy only the selection.
        // Otherwise, invoke the onCopy callback to copy the entire message content.
        if let editor = self.currentEditor(), editor.selectedRange.length > 0 {
            editor.copy(sender)
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
    let text: String
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void
    var body: some View { EmptyView() }
}
#endif
