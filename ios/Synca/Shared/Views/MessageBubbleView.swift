import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MessageBubbleView: View {
    let message: SyncaMessage
    let onClear: () -> Void

    @State private var showImagePreview = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Content
            Group {
                switch message.type {
                case .text:
                    textContent
                case .image:
                    imageContent
                }
            }

            // Metadata row
            HStack {
                Text(message.displayDate)
                    .font(.caption2)

                if let device = message.sourceDevice, !device.isEmpty {
                    Text("·")
                        .font(.caption2)
                    Text(device)
                        .font(.caption2)
                }

                Spacer()

                if !message.isCleared {
                    Button {
                        onClear()
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.gray.opacity(0.3))
                }
            }
            .foregroundStyle(message.isCleared ? .tertiary : .secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(message.isCleared
                      ? Color.gray.opacity(0.08)
                      : cardBackground)
                .shadow(color: .black.opacity(message.isCleared ? 0 : 0.04), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(message.isCleared ? 0 : 0.15), lineWidth: 0.5)
        )
        .opacity(message.isCleared ? 0.6 : 1.0)
        #if os(iOS)
        .fullScreenCover(isPresented: $showImagePreview) {
            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                ImagePreviewView(imageURL: url)
            }
        }
        #else
        .sheet(isPresented: $showImagePreview) {
            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                ImagePreviewView(imageURL: url)
                    .frame(minWidth: 400, minHeight: 400)
            }
        }
        #endif
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(.controlBackgroundColor)
        #endif
    }

    // MARK: - Text Content

    private var textContent: some View {
        Text(message.textContent ?? "")
            .font(.body)
            .foregroundStyle(message.isCleared ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    copyText(message.textContent ?? "")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
    }

    // MARK: - Image Content

    private var imageContent: some View {
        Group {
            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 260, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { showImagePreview = true }
                            .contextMenu {
                                Button {
                                    Task { await saveImage(from: url) }
                                } label: {
                                    #if os(iOS)
                                    Label("保存到相册", systemImage: "square.and.arrow.down")
                                    #else
                                    Label("保存到下载", systemImage: "square.and.arrow.down")
                                    #endif
                                }
                            }
                    case .failure:
                        Label("图片加载失败", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 200, height: 100)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .empty:
                        ProgressView()
                            .frame(width: 200, height: 100)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private func copyText(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func saveImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if os(iOS)
            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
            #elseif os(macOS)
            // Save to Downloads folder
            if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let filename = url.lastPathComponent
                let fileURL = downloadsURL.appendingPathComponent(filename)
                try data.write(to: fileURL)
                // Open in Finder
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
            #endif
        } catch {
            print("Save image failed: \(error)")
        }
    }
}
