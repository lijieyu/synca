import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
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

    var body: some View {
        ZStack {
            #if os(iOS)
            Color.black.ignoresSafeArea()
            #else
            Color.black
            #endif

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
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = 1.0
                                            lastScale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
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
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        #endif
                        .onTapGesture {
                            withAnimation { showControls.toggle() }
                        }
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }

                case .failure:
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                        Text("图片加载失败")
                    }
                    .foregroundStyle(.white.opacity(0.6))

                case .empty:
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)

                @unknown default:
                    EmptyView()
                }
            }

            // Controls overlay
            if showControls {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        #if os(macOS)
                        .keyboardShortcut(.escape, modifiers: [])
                        #endif
                    }
                    Spacer()

                    // Bottom toolbar
                    HStack(spacing: 32) {
                        Button {
                            Task { await saveImage() }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 20))
                                #if os(iOS)
                                Text("保存")
                                    .font(.caption2)
                                #else
                                Text("保存到下载")
                                    .font(.caption2)
                                #endif
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
    }

    private func saveImage() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            #if os(iOS)
            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            #elseif os(macOS)
            if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let filename = imageURL.lastPathComponent
                let fileURL = downloadsURL.appendingPathComponent(filename)
                try data.write(to: fileURL)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
            #endif
        } catch {
            print("Save image failed: \(error)")
        }
    }
}
