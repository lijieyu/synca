import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ImagePreviewView: View {
    let imageURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true
    @State private var loadID = UUID() // 重试加载
    @State private var saveStatus: SaveStatus = .none

    enum SaveStatus {
        case none, saving, success, error
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        #if os(iOS)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in scale = lastScale * value }
                                .onEnded { _ in 
                                    lastScale = scale
                                    if scale < 1.0 { resetZoom() }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        #endif
                        .onTapGesture {
                            withAnimation { showControls.toggle() }
                        }
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.0 { resetZoom() }
                                else { scale = 2.5; lastScale = 2.5 }
                            }
                        }
                        .contextMenu {
                            Button { copyImage(from: imageURL) } label: { Label("拷贝", systemImage: "doc.on.doc") }
                            Button { Task { await saveImage(from: imageURL) } } label: { Label("保存", systemImage: "square.and.arrow.down") }
                            #if os(macOS)
                            Button { Task { await saveImageAs(from: imageURL) } } label: { Label("另存为...", systemImage: "folder.badge.plus") }
                            #endif
                        }

                case .failure:
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text("图片加载失败")
                        Button("点击重试") {
                            loadID = UUID()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.2))
                    }
                    .foregroundStyle(.white)

                case .empty:
                    ProgressView().tint(.white).scaleEffect(1.5)

                @unknown default: EmptyView()
                }
            }
            .id(loadID)

            // Controls overlay
            if showControls {
                VStack {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(20)
                        #if os(macOS)
                        .keyboardShortcut(.escape, modifiers: [])
                        #endif
                    }
                    Spacer()

                    // Bottom toolbar
                    HStack(spacing: 32) {
                        Button {
                            Task { await saveImage(from: imageURL) }
                        } label: {
                            HStack {
                                Group {
                                    switch saveStatus {
                                    case .none:
                                        Image(systemName: "square.and.arrow.down")
                                        Text("下载到本地")
                                    case .saving:
                                        ProgressView().tint(.white)
                                        Text("正在保存...")
                                    case .success:
                                        Image(systemName: "checkmark")
                                        Text("保存成功")
                                    case .error:
                                        Image(systemName: "xmark.circle")
                                        Text("保存失败")
                                    }
                                }
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(saveStatus == .error ? Color.red.opacity(0.6) : Color.black.opacity(0.4))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(saveStatus == .saving)
                    }
                    .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.3)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

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
            } catch { print("Copy image failed: \(error)") }
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
            } else {
                saveStatus = .error
            }
            #elseif os(macOS)
            let defaultURL = SettingsManager.shared.macOSDefaultSavePath ?? 
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let fileURL = defaultURL.appendingPathComponent(url.lastPathComponent)
            try data.write(to: fileURL)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            saveStatus = .success
            #endif
        } catch { 
            print("Save image failed: \(error)") 
            saveStatus = .error
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }
    
    #if os(macOS)
    private func saveImageAs(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.title = "选择保存目录"
            panel.prompt = "保存到此目录"
            if panel.runModal() == .OK, let selectedURL = panel.url {
                SettingsManager.shared.macOSDefaultSavePath = selectedURL
                let fileURL = selectedURL.appendingPathComponent(url.lastPathComponent)
                try data.write(to: fileURL)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                saveStatus = .success
            }
        } catch { print("Save As failed: \(error)") }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }
    #endif
}
