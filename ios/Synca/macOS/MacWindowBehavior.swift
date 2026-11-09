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
        window.titlebarAppearsTransparent = isAuthenticated
        if isAuthenticated {
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
        } else {
            window.styleMask.remove(.fullSizeContentView)
            installToolbarIfNeeded(on: window)
            window.toolbarStyle = .unified
        }

        if isAuthenticated {
            window.titleVisibility = .hidden
            window.title = ""
            removeTitlebarAccessories(from: window)
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
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
    let metrics: MacTitlebarMetrics

    var body: some View {
        HStack(spacing: 8) {
            Text("Synca")
                .font(.system(size: metrics.titleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
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

                    Link(destination: AppLinks.aiConnectionURL) {
                        Label("message_list.connect_ai", systemImage: "sparkles")
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

/// Only the blank header background initiates a window drag; SwiftUI buttons stay interactive.
struct MacWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragAreaView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragAreaView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "None": break
                case "Minimize": window.performMiniaturize(nil)
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

/// Propagates measured sheet content changes to AppKit on macOS versions that
/// retain the initial NSHostingView sheet size. Never resizes the main window.
struct MacSheetSizeObserver: NSViewRepresentable {
    let contentSize: NSSize

    func makeNSView(context: Context) -> SheetSizeView {
        let view = SheetSizeView()
        view.requestedContentSize = contentSize
        return view
    }

    func updateNSView(_ view: SheetSizeView, context: Context) {
        view.requestedContentSize = contentSize
        view.scheduleResize()
    }

    final class SheetSizeView: NSView {
        var requestedContentSize: NSSize = .zero
        private var resizeScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResize()
        }

        override func layout() {
            super.layout()
            scheduleResize()
        }

        func scheduleResize() {
            guard !resizeScheduled else { return }
            resizeScheduled = true
            // Updating AppKit after the SwiftUI layout pass avoids a recursive
            // layout and ensures the window has been attached as a sheet.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                self.resizeSheetIfNeeded()
            }
        }

        private func resizeSheetIfNeeded() {
            guard let window, let parent = window.sheetParent,
                  requestedContentSize.width > 0, requestedContentSize.height > 0,
                  requestedContentSize.width.isFinite, requestedContentSize.height.isFinite else { return }
            let screen = window.screen ?? parent.screen ?? NSScreen.main
            guard let visibleFrame = screen?.visibleFrame else { return }
            let desired = NSSize(
                width: min(requestedContentSize.width, max(1, visibleFrame.width - 80)),
                height: min(requestedContentSize.height, max(1, visibleFrame.height - 100))
            )
            let current = window.contentRect(forFrameRect: window.frame).size
            guard abs(current.width - desired.width) > 1 || abs(current.height - desired.height) > 1 else { return }
            window.setContentSize(desired)
        }
    }
}

/// AppKit owns cursor rectangles and tracking so SwiftUI hover updates cannot
/// replace the resize cursor while the pointer is resting on the divider.
struct MacSidebarResizeHandle: NSViewRepresentable {
    var onBegin: () -> Void
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void
    var onReset: () -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HandleView { HandleView(callbacks: self) }
    func updateNSView(_ view: HandleView, context: Context) { view.callbacks = self }

    final class HandleView: NSView {
        var callbacks: MacSidebarResizeHandle
        private var startX: CGFloat?
        init(callbacks: MacSidebarResizeHandle) { self.callbacks = callbacks; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .cursorUpdate, .mouseEnteredAndExited], owner: self))
            window?.invalidateCursorRects(for: self)
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
        override func mouseEntered(with event: NSEvent) { callbacks.onHover(true); NSCursor.resizeLeftRight.set() }
        override func mouseExited(with event: NSEvent) {
            callbacks.onHover(false)
            if startX == nil { window?.invalidateCursorRects(for: self) }
        }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { callbacks.onReset(); return }
            startX = event.locationInWindow.x
            callbacks.onBegin()
            NSCursor.resizeLeftRight.set()
        }
        override func mouseDragged(with event: NSEvent) {
            guard let startX else { return }
            callbacks.onDrag(event.locationInWindow.x - startX)
            NSCursor.resizeLeftRight.set()
        }
        override func mouseUp(with event: NSEvent) {
            if startX != nil { callbacks.onEnd() }
            startX = nil
            window?.invalidateCursorRects(for: self)
        }
    }
}

/// Same single text bubble silhouette as the Web feedback entry.
struct MacFeedbackIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 22, y: 17))
        p.addQuadCurve(to: CGPoint(x: 20, y: 19), control: CGPoint(x: 22, y: 19))
        p.addLine(to: CGPoint(x: 6.8, y: 19))
        p.addLine(to: CGPoint(x: 2, y: 22))
        p.addLine(to: CGPoint(x: 2, y: 5))
        p.addQuadCurve(to: CGPoint(x: 4, y: 3), control: CGPoint(x: 2, y: 3))
        p.addLine(to: CGPoint(x: 20, y: 3))
        p.addQuadCurve(to: CGPoint(x: 22, y: 5), control: CGPoint(x: 22, y: 3))
        p.closeSubpath()
        for (y, endX) in [(7.0, 15.0), (11.0, 17.0), (15.0, 13.0)] {
            p.move(to: CGPoint(x: 7, y: y)); p.addLine(to: CGPoint(x: endX, y: y))
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
