import AppKit
import SwiftUI

@MainActor
final class MacWindowBehaviorController: NSObject, NSWindowDelegate {
    static let shared = MacWindowBehaviorController()

    private let autosaveName = "SyncaMainWindow"
    private let toolbarIdentifier = NSToolbar.Identifier("synca.window.toolbar")
    private let accessoryIdentifier = NSUserInterfaceItemIdentifier("synca.titlebar.accessory")
    private let controlsAccessoryIdentifier = NSUserInterfaceItemIdentifier("synca.titlebar.controls")

    func configure(window: NSWindow) {
        window.delegate = self
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        installToolbarIfNeeded(on: window)
        window.toolbarStyle = .unified
        installTitlebarAccessoryIfNeeded(on: window)
        installControlsAccessoryIfNeeded(on: window)
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

    private func installToolbarIfNeeded(on window: NSWindow) {
        guard window.toolbar == nil else { return }

        let toolbar = NSToolbar(identifier: toolbarIdentifier)
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.sizeMode = .regular
        window.toolbar = toolbar
    }

    private func installTitlebarAccessoryIfNeeded(on window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == accessoryIdentifier }) else {
            return
        }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = accessoryIdentifier
        accessory.layoutAttribute = .left

        let hostingView = NSHostingView(rootView: MacTitlebarIdentityView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 190, height: 34)
        accessory.view = hostingView

        window.addTitlebarAccessoryViewController(accessory)
    }

    private func installControlsAccessoryIfNeeded(on window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: { $0.identifier == controlsAccessoryIdentifier }) else {
            return
        }

        let accessory = NSTitlebarAccessoryViewController()
        accessory.identifier = controlsAccessoryIdentifier
        accessory.layoutAttribute = .right

        let hostingView = NSHostingView(rootView: MacTitlebarControlsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 154, height: 34)
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
        .padding(.leading, 14)
        .padding(.vertical, 2)
    }
}

private struct MacTitlebarControlsView: View {
    @ObservedObject private var syncManager = SyncManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await syncManager.refresh() }
            } label: {
                titlebarIcon("arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isRefreshing)

            Button {
                NotificationCenter.default.post(name: .syncaRequestClearAll, object: nil)
            } label: {
                titlebarIcon("trash")
            }
            .buttonStyle(.plain)
            .disabled(syncManager.messages.filter { $0.isCleared }.isEmpty)

            Menu {
                Button {
                    NotificationCenter.default.post(name: .syncaRequestFeedbackComposer, object: nil)
                } label: {
                    Label("message_list.feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }

                Button {
                    showAboutOnMac()
                } label: {
                    Label("message_list.about", systemImage: "info.circle")
                }

                Button(role: .destructive) {
                    NotificationCenter.default.post(name: .syncaRequestSignOut, object: nil)
                } label: {
                    Label("message_list.sign_out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                titlebarIcon("ellipsis.circle")
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .frame(width: 154, alignment: .trailing)
        .padding(.trailing, 26)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func titlebarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .regular))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    private func showAboutOnMac() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "message_list.about", bundle: .main)
        alert.informativeText = String(format: String(localized: "message_list.about_message", bundle: .main), version, build)
        alert.addButton(withTitle: String(localized: "message_list.got_it", bundle: .main))
        alert.runModal()
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
