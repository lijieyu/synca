import AppKit
import SwiftUI

@MainActor
final class MacWindowBehaviorController: NSObject, NSWindowDelegate {
    static let shared = MacWindowBehaviorController()

    private let autosaveName = "SyncaMainWindow"

    func configure(window: NSWindow) {
        window.delegate = self
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
    }

    func restoreMainWindow() {
        guard let window = NSApp.windows.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }
}

struct MacWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                MacWindowBehaviorController.shared.configure(window: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                MacWindowBehaviorController.shared.configure(window: window)
            }
        }
    }
}
