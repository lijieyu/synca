import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ImagePreviewView: View {
    let messages: [SyncaMessage]
    @State private var currentIndex: Int
    var onDelete: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true
    @State private var loadID = UUID()
    @State private var saveStatus: SaveStatus = .none
    @State private var showDeleteConfirm = false
    #if os(macOS)
    @State private var keyMonitor: Any?
    #endif
    
    // Swipe to close & paging state
    @State private var backgroundOpacity: Double = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var horizontalOffset: CGFloat = 0
    @State private var isVerticalDrag = false
    @State private var hasDeterminedDirection = false

    enum SaveStatus {
        case none, saving, success, error
    }

    init(messages: [SyncaMessage], initialIndex: Int, onDelete: ((String) -> Void)? = nil) {
        self.messages = messages
        self._currentIndex = State(initialValue: initialIndex)
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            GeometryReader { geometry in
                let size = geometry.size
                
                HStack(spacing: 0) {
                    ForEach(0..<messages.count, id: \.self) { index in
                        if let urlString = messages[index].imageUrl, let url = URL(string: urlString) {
                            imagePage(url: url, size: size)
                                .frame(width: size.width, height: size.height)
                        }
                    }
                }
                .offset(x: -CGFloat(currentIndex) * size.width)
                .offset(x: horizontalOffset)
                .background(Color.black.opacity(0.001)) // Ensure full-screen touch area
                .highPriorityGesture(containerGesture(size: size))
            }
            .ignoresSafeArea()

            // UI Controls
            controlsOverlay
        }
        .onAppear {
            #if os(macOS)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 123 { // Left arrow
                    prevImage()
                    return nil
                } else if event.keyCode == 124 { // Right arrow
                    nextImage()
                    return nil
                }
                return event
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            #endif
        }
    }

    @ViewBuilder
    private func imagePage(url: URL, size: CGSize) -> some View {
        CachedAsyncImage(url: url, onSuccess: nil) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                    #if os(iOS)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 { resetZoom() }
                            }
                    )
                    #endif
                    #if os(iOS)
                    .onTapGesture {
                        withAnimation { dismiss() } // Click to close as requested
                    }
                    #endif
                    .onTapGesture(count: 2) {
                        if scale > 1.0 { resetZoom() }
                        else { 
                            withAnimation(.spring()) {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                    .contextMenu {
                        contextMenuItems(url: url)
                    }

            case .failure:
                failureView
            case .empty:
                ProgressView().tint(.white).scaleEffect(1.5)
            @unknown default: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func contextMenuItems(url: URL) -> some View {
        Button { copyImage(from: url) } label: { Label("common.copy", systemImage: "doc.on.doc") }
        Button { Task { await saveImage(from: url) } } label: { Label("common.save", systemImage: "square.and.arrow.down") }

        #if os(macOS)
        Button { openWithPreview(url: url) } label: { Label("message_bubble.open_with_preview", systemImage: "eye") }
        Button { showInFinder(url: url) } label: { Label("message_bubble.show_in_finder", systemImage: "folder") }
        Button { Task { await saveImageAs(from: url) } } label: { Label("message_bubble.save_as", systemImage: "folder.badge.plus") }
        #endif

        Divider()
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("common.delete", systemImage: "trash")
        }
    }

    private var controlsOverlay: some View {
        ZStack {
            // Top Bar
            VStack {
                HStack {
                    if messages.count > 1 {
                        Text("\(currentIndex + 1) / \(messages.count)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.5)))
                            .padding(.leading, 20)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.5)))
                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                    #if os(macOS)
                    .keyboardShortcut("w", modifiers: .command)
                    #endif
                }
                Spacer()
            }

            // macOS Navigation Arrows
            #if os(macOS)
            HStack {
                if currentIndex > 0 {
                    navButton(icon: "chevron.left") { prevImage() }
                        .padding(.leading, 20)
                }
                Spacer()
                if currentIndex < messages.count - 1 {
                    navButton(icon: "chevron.right") { nextImage() }
                        .padding(.trailing, 20)
                }
            }
            #endif

            // Bottom Toolbar
            VStack {
                Spacer()
                if let urlString = messages[currentIndex].imageUrl, let url = URL(string: urlString) {
                    Button {
                        Task { await saveImage(from: url) }
                    } label: {
                        HStack(spacing: 8) {
                            saveStatusIcon
                            Text(saveStatusText)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                    .disabled(saveStatus == .saving)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var saveStatusIcon: some View {
        switch saveStatus {
        case .none: Image(systemName: "square.and.arrow.down")
        case .saving: ProgressView().tint(.white)
        case .success: Image(systemName: "checkmark")
        case .error: Image(systemName: "xmark.circle")
        }
    }

    private var saveStatusText: String {
        switch saveStatus {
        case .none: return String(localized: "image_preview.download_to_local", bundle: .main)
        case .saving: return String(localized: "image_preview.saving", bundle: .main)
        case .success: return String(localized: "image_preview.save_success", bundle: .main)
        case .error: return String(localized: "image_preview.save_failed", bundle: .main)
        }
    }

    private func resetZoom() {
        withAnimation(.spring()) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
            dragOffset = .zero
            backgroundOpacity = 1.0
            horizontalOffset = 0
        }
    }

    private func containerGesture(size: CGSize) -> some Gesture {
        #if os(iOS)
        return DragGesture(minimumDistance: 3)
            .onChanged { value in
                if scale > 1.0 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    return
                }
                if !hasDeterminedDirection {
                    let h = abs(value.translation.width)
                    let v = abs(value.translation.height)
                    if v > h && value.translation.height > 5 {
                        isVerticalDrag = true
                    } else {
                        isVerticalDrag = false
                    }
                    hasDeterminedDirection = true
                }
                if isVerticalDrag {
                    let y = max(value.translation.height, 0)
                    dragOffset = CGSize(width: value.translation.width, height: y)
                    let progress = min(y / 400, 1)
                    backgroundOpacity = 1.0 - (progress * 0.8)
                    scale = 1.0 - (progress * 0.2)
                } else {
                    horizontalOffset = value.translation.width
                }
            }
            .onEnded { value in
                if scale > 1.0 {
                    lastOffset = offset
                } else if isVerticalDrag {
                    if value.translation.height > 120 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            backgroundOpacity = 0
                            dismiss()
                        }
                    } else {
                        resetZoom()
                    }
                } else {
                    let threshold = size.width / 5
                    if (value.translation.width < -threshold) && currentIndex < messages.count - 1 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentIndex += 1
                        }
                    } else if (value.translation.width > threshold) && currentIndex > 0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            currentIndex -= 1
                        }
                    }
                    withAnimation(.spring(response: 0.3)) {
                        horizontalOffset = 0
                    }
                }
                hasDeterminedDirection = false
                isVerticalDrag = false
            }
        #else
        return DragGesture().onChanged { _ in }.onEnded { _ in }
        #endif
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(.black.opacity(0.5)))
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func prevImage() {
        if currentIndex > 0 {
            withAnimation { currentIndex -= 1; resetZoom() }
        }
    }

    private func nextImage() {
        if currentIndex < messages.count - 1 {
            withAnimation { currentIndex += 1; resetZoom() }
        }
    }



    // MARK: - Actions (Modified for paging)
    
    private func copyImage(from url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                #if os(iOS)
                if let image = UIImage(data: data) { UIPasteboard.general.image = image }
                #elseif os(macOS)
                if let image = NSImage(data: data) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                }
                #endif
            } catch { print("Copy failed: \(error)") }
        }
    }

    private func saveImage(from url: URL) async {
        saveStatus = .saving
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if os(iOS)
            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                saveStatus = .success
            }
            #elseif os(macOS)
            let defaultURL = SettingsManager.shared.macOSDefaultSavePath ?? 
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let fileURL = defaultURL.appendingPathComponent(url.lastPathComponent)
            try data.write(to: fileURL)
            saveStatus = .success
            #endif
        } catch { saveStatus = .error }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = .none }
    }

    #if os(macOS)
    private func showInFinder(url: URL) {
        Task {
            if let localURL = try? await downloadToTemp(url: url) {
                NSWorkspace.shared.activateFileViewerSelecting([localURL])
            }
        }
    }
    
    private func openWithPreview(url: URL) {
        Task {
            if let localURL = try? await downloadToTemp(url: url) {
                NSWorkspace.shared.open(localURL)
            }
        }
    }

    private func downloadToTemp(url: URL) async throws -> URL {
        let (data, _) = try await URLSession.shared.data(from: url)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try data.write(to: tempURL)
        return tempURL
    }

    private func saveImageAs(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            if panel.runModal() == .OK, let saveURL = panel.url {
                try data.write(to: saveURL)
                saveStatus = .success
            }
        } catch { saveStatus = .error }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = .none }
    }
    #endif

    private var failureView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text("image_preview.load_failed")
            Button("image_preview.tap_to_retry") { loadID = UUID() }.buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
    }
}
