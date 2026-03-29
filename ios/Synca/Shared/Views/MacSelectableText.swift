import SwiftUI

#if os(macOS)
import AppKit

/// A selectable text view for macOS designed specifically to act as an overlay
/// in a ZStack. It relies entirely on the SwiftUI frame for sizing and
/// only provides the custom context menu and selection capabilities.
struct MacSelectableText: NSViewRepresentable {
    let text: String
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
        
        textView.onCopy = onCopy
        textView.onDelete = onDelete
        
        return textView
    }

    func updateNSView(_ nsView: CustomContextMenuTextView, context: Context) {
        nsView.string = text
        nsView.textColor = NSColor(color)
        nsView.font = NSFont.systemFont(ofSize: 13) // SwiftUI .body roughly maps to 13pt
    }
}

class CustomContextMenuTextView: NSTextView {
    var onCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        // By returning nil, we tell the system this responder does not provide any data
        // for macOS Services. This forces the OS to omit the "Services" (服务) context menu item.
        return nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "拷贝", action: #selector(handleCopy(_:)), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Ensure no plugins or system additions are allowed on this specific menu
        menu.allowsContextMenuPlugIns = false
        
        let deleteItem = NSMenuItem(title: "删除", action: #selector(handleDelete(_:)), keyEquivalent: "")
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
    let text: String
    let color: Color
    let font: Font
    let onCopy: () -> Void
    let onDelete: () -> Void
    var body: some View { EmptyView() }
}
#endif
