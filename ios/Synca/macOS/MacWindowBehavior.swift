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

    func configure(window: NSWindow, isAuthenticated: Bool) {
        window.delegate = self
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        installToolbarIfNeeded(on: window)
        window.toolbarStyle = .unified

        if isAuthenticated {
            window.titleVisibility = .hidden
            window.title = ""
            installTitlebarAccessoryIfNeeded(on: window)
            installControlsAccessoryIfNeeded(on: window)
        } else {
            window.titleVisibility = .visible
            window.title = "Synca"
            removeTitlebarAccessories(from: window)
        }
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

    private func removeTitlebarAccessories(from window: NSWindow) {
        let removableIndexes = window.titlebarAccessoryViewControllers.indices.filter { index in
            let identifier = window.titlebarAccessoryViewControllers[index].identifier
            return identifier == accessoryIdentifier || identifier == controlsAccessoryIdentifier
        }

        removableIndexes.sorted(by: >).forEach { index in
            window.removeTitlebarAccessoryViewController(at: index)
        }
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
                controlsWidth: 212,
                titleFontSize: 17,
                leadingPadding: 18,
                verticalPadding: 6,
                controlsTrailingPadding: 18,
                controlsSpacing: 14,
                iconFontSize: 17,
                menuIconFontSize: 18,
                iconFrame: 34
            )
        } else {
            return MacTitlebarMetrics(
                height: 40,
                identityWidth: 212,
                controlsWidth: 204,
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
    @ObservedObject private var settings = SettingsManager.shared
    let metrics: MacTitlebarMetrics

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: metrics.controlsSpacing) {
                Button {
                    settings.setMessageListLayoutMode(settings.messageListLayoutMode == .single ? .tiled : .single)
                } label: {
                    titlebarIcon(settings.messageListLayoutMode == .single ? "square.grid.2x2" : "rectangle.split.3x1")
                }
                .buttonStyle(.plain)

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
                        NotificationCenter.default.post(name: .syncaRequestAccount, object: nil)
                    } label: {
                        Label("account.section_title", systemImage: "person.crop.circle")
                    }

                    Button {
                        NotificationCenter.default.post(name: .syncaRequestCategoryManager, object: nil)
                    } label: {
                        Label("message_list.manage_categories", systemImage: "tag")
                    }

                    Button {
                        NotificationCenter.default.post(name: .syncaRequestFeedbackComposer, object: nil)
                    } label: {
                        Label("message_list.feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    }

                    Button {
                        NotificationCenter.default.post(name: .syncaRequestAbout, object: nil)
                    } label: {
                        Label("message_list.about", systemImage: "info.circle")
                    }

                } label: {
                    Color.clear
                        .frame(width: metrics.iconFrame, height: metrics.iconFrame)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: metrics.iconFrame, height: metrics.iconFrame)
                .overlay(alignment: .center) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: metrics.menuIconFontSize, weight: .regular))
                        .allowsHitTesting(false)
                }
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
}

struct MacWindowAccessor: NSViewRepresentable {
    let isAuthenticated: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                MacWindowBehaviorController.shared.configure(window: window, isAuthenticated: isAuthenticated)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                MacWindowBehaviorController.shared.configure(window: window, isAuthenticated: isAuthenticated)
            }
        }
    }
}
