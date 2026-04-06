import AppKit
import SwiftUI

@MainActor
final class MacWindowBehaviorController: NSObject, NSWindowDelegate {
    static let shared = MacWindowBehaviorController()

    private let autosaveName = "SyncaMainWindow"
    private let toolbarIdentifier = NSToolbar.Identifier("synca.window.toolbar")
    private let accessoryIdentifier = NSUserInterfaceItemIdentifier("synca.titlebar.accessory")
    private let controlsAccessoryIdentifier = NSUserInterfaceItemIdentifier("synca.titlebar.controls")

    private var metrics: MacTitlebarMetrics {
        MacTitlebarMetrics.current
    }

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

        let hostingView = NSHostingView(rootView: MacTitlebarIdentityView(metrics: metrics))
        hostingView.frame = NSRect(x: 0, y: 0, width: metrics.identityWidth, height: metrics.height)
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

        let hostingView = NSHostingView(rootView: MacTitlebarControlsView(metrics: metrics))
        hostingView.frame = NSRect(x: 0, y: 0, width: metrics.controlsWidth, height: metrics.height)
        accessory.view = hostingView

        window.addTitlebarAccessoryViewController(accessory)
    }
}

private struct MacTitlebarMetrics {
    let height: CGFloat
    let identityWidth: CGFloat
    let controlsWidth: CGFloat
    let titleFontSize: CGFloat
    let leadingPadding: CGFloat
    let verticalPadding: CGFloat
    let controlsTrailingPadding: CGFloat
    let controlsSpacing: CGFloat
    let iconFontSize: CGFloat
    let menuIconFontSize: CGFloat
    let iconFrame: CGFloat

    static var current: MacTitlebarMetrics {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if majorVersion <= 15 {
            return MacTitlebarMetrics(
                height: 42,
                identityWidth: 224,
                controlsWidth: 188,
                titleFontSize: 17,
                leadingPadding: 18,
                verticalPadding: 6,
                controlsTrailingPadding: 18,
                controlsSpacing: 14,
                iconFontSize: 17,
                menuIconFontSize: 21,
                iconFrame: 34
            )
        } else {
            return MacTitlebarMetrics(
                height: 40,
                identityWidth: 212,
                controlsWidth: 176,
                titleFontSize: 16,
                leadingPadding: 18,
                verticalPadding: 5,
                controlsTrailingPadding: 16,
                controlsSpacing: 14,
                iconFontSize: 16,
                menuIconFontSize: 18,
                iconFrame: 32
            )
        }
    }
}

private struct MacTitlebarIdentityView: View {
    @ObservedObject private var accessManager = AccessManager.shared
    let metrics: MacTitlebarMetrics

    var body: some View {
        HStack(spacing: 8) {
            Text("Synca")
                .font(.system(size: metrics.titleFontSize, weight: .semibold))
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
        .frame(width: metrics.identityWidth, alignment: .leading)
        .padding(.leading, metrics.leadingPadding)
        .padding(.vertical, metrics.verticalPadding)
    }
}

private struct MacTitlebarControlsView: View {
    @ObservedObject private var syncManager = SyncManager.shared
    let metrics: MacTitlebarMetrics

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: metrics.controlsSpacing) {
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
                    titlebarMenuIcon("ellipsis.circle")
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .fixedSize()
            .padding(.trailing, metrics.controlsTrailingPadding)
            .padding(.vertical, metrics.verticalPadding)
        }
        .frame(width: metrics.controlsWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func titlebarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: metrics.iconFontSize, weight: .regular))
            .frame(width: metrics.iconFrame, height: metrics.iconFrame)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func titlebarMenuIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: metrics.menuIconFontSize, weight: .regular))
            .frame(width: metrics.iconFrame, height: metrics.iconFrame)
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
