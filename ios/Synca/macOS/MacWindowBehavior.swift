import AppKit
import SwiftUI

@MainActor
final class MacWindowBehaviorController: NSObject, NSWindowDelegate {
    static let shared = MacWindowBehaviorController()

    private let autosaveName = "SyncaMainWindow"
    private let accessoryIdentifier = NSUserInterfaceItemIdentifier("synca.titlebar.accessory")

    func configure(window: NSWindow) {
        window.delegate = self
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        installTitlebarAccessoryIfNeeded(on: window)
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

    private func installTitlebarAccessoryIfNeeded(on window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == accessoryIdentifier }) else {
            return
        }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = accessoryIdentifier
        accessory.layoutAttribute = .left

        let hostingView = NSHostingView(rootView: MacTitlebarIdentityView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 190, height: 28)
        accessory.view = hostingView

        window.addTitlebarAccessoryViewController(accessory)
    }
}

private struct MacTitlebarIdentityView: View {
    @ObservedObject private var accessManager = AccessManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Text("Synca")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let status = accessManager.status {
                Button {
                    accessManager.showAccessCenter = true
                } label: {
                    HeaderAccessBadge(status: status)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 190, alignment: .leading)
        .padding(.leading, 10)
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
