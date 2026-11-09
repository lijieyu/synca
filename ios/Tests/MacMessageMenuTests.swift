import AppKit
import SwiftUI

@main
struct MenuCheck {
    @MainActor static func main() {
        let view = CustomContextMenuTextView()
        view.isEditable = false
        view.isSelectable = true
        var didCopy = false
        view.contextMenuActions = [
            .init("Copy", symbol: "doc.on.doc") { didCopy = true },
            .init(),
            .init("Complete", isEnabled: false),
            .init("Delete", isDestructive: true)
        ]
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let menu = view.menu(for: event)!
        precondition(menu.items.map(\.title) == ["Copy", "", "Complete", "Delete"])
        precondition(menu.items[1].isSeparatorItem)
        precondition(!menu.items[2].isEnabled)
        view.contextMenuActions = []
        let retainedAction = menu.items[0].representedObject as! MacMessageMenuAction
        retainedAction.invokeMenuAction()
        precondition(didCopy)
        precondition(view.isSelectable && !view.isEditable)
        var changed = false
        let swatch = NSImage(size: NSSize(width: 8, height: 8))
        swatch.isTemplate = false
        let submenu = MacMessageMenuAction.makeMenu([
            .init("Category", symbol: "tag", children: [
                .init("Current", image: swatch, isSelected: true),
                .init("Other", image: swatch) { changed = true }
            ])
        ]).items[0].submenu!
        precondition(submenu.items[0].state == .on && submenu.items[1].state == .off)
        precondition(submenu.items[0].image?.isTemplate == false)
        if #available(macOS 27.0, *) {
            precondition(submenu.items[0].preferredImageVisibility == .visible)
        }
        (submenu.items[1].representedObject as! MacMessageMenuAction).invokeMenuAction()
        precondition(changed)
        print("PASS: category submenu checkmarks, original color image, selection callback;")
        print("PASS: business menu order, separator, disabled state, action lifetime, selectable text")
    }
}
