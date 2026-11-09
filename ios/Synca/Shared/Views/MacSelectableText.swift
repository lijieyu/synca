import SwiftUI

#if os(macOS)
import AppKit

/// The same AppKit layout draws and measures selectable body text and links.
struct MacSelectableText: NSViewRepresentable {
    let attributedText: NSAttributedString
    let color: Color
    let font: Font
    var maximumNumberOfLines: Int = 0
    var contextMenuActions: [MacMessageMenuAction] = []

    func makeNSView(context: Context) -> CustomContextMenuTextView {
        let textView = CustomContextMenuTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        
        // Match the text column without an independent measurement view.
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
        nsView.contextMenuActions = contextMenuActions
        nsView.textContainer?.maximumNumberOfLines = maximumNumberOfLines
        nsView.textContainer?.lineBreakMode = maximumNumberOfLines == 0 ? .byWordWrapping : .byTruncatingTail
        let textColor = NSColor(color)
        guard context.coordinator.attributedText?.isEqual(to: attributedText) != true
            || nsView.textColor != textColor else { return }
        context.coordinator.attributedText = attributedText.copy() as? NSAttributedString
        nsView.textStorage?.setAttributedString(attributedText)
        nsView.textColor = textColor
        nsView.font = NSFont.preferredFont(forTextStyle: .body)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CustomContextMenuTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let manager = nsView.layoutManager, let container = nsView.textContainer else { return nil }
        nsView.setFrameSize(NSSize(width: width, height: nsView.frame.height))
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).maxY))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var attributedText: NSAttributedString?

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
    var contextMenuActions: [MacMessageMenuAction] = []
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
        MacMessageMenuAction.makeMenu(contextMenuActions)
    }

}

/// Both AppKit text and the SwiftUI row render the same current message actions.
@MainActor
final class MacMessageMenuAction: NSObject {
    let title: String?
    let symbol: String?
    let image: NSImage?
    let isSelected: Bool
    let children: [MacMessageMenuAction]
    let isEnabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    init(_ title: String? = nil, symbol: String? = nil, assetName: String? = nil, image: NSImage? = nil, isSelected: Bool = false, children: [MacMessageMenuAction] = [], isEnabled: Bool = true, isDestructive: Bool = false, action: @escaping () -> Void = {}) {
        self.title = title
        self.symbol = symbol
        if let assetName, let assetImage = NSImage(named: assetName)?.copy() as? NSImage {
            assetImage.size = NSSize(width: 16, height: 16)
            assetImage.isTemplate = true
            self.image = assetImage
        } else {
            self.image = image
        }
        self.isSelected = isSelected
        self.children = children
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.action = action
    }

    static func makeMenu(_ actions: [MacMessageMenuAction]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in actions {
            guard let title = action.title else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: #selector(invokeMenuAction), keyEquivalent: "")
            item.target = action
            item.representedObject = action // NSMenuItem's target is weak.
            item.isEnabled = action.isEnabled
            item.state = action.isSelected ? .on : .off
            item.image = action.image ?? action.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            if #available(macOS 27.0, *), action.image?.isTemplate == false {
                item.preferredImageVisibility = .visible
            }
            if !action.children.isEmpty { item.submenu = makeMenu(action.children) }
            menu.addItem(item)
        }
        return menu
    }

    @objc func invokeMenuAction() { action() }
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

