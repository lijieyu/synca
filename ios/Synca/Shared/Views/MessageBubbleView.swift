import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MessageBubbleView: View {
    let message: SyncaMessage
    let onClear: () -> Void
    let onDelete: () -> Void

    @State private var showImagePreview = false
    @State private var copied = false
    @State private var saveStatus: SaveStatus = .none
    @State private var showDeleteConfirm = false
    @State private var loadID = UUID() // #1: 重显失败图片的关键

    enum SaveStatus {
        case none, saving, success, error
    }

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

                // #6: Actions row (Always visible)
                HStack(spacing: 16) {
                    if message.type == .image {
                        downloadImageButton
                        copyImageButton
                    }
                    if message.type == .text {
                        copyTextButton
                    }
                    
                    if !message.isCleared {
                        clearButton
                    } else {
                        checkFillIcon
                    }
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
                ImagePreviewView(imageURL: url, onDelete: message.isCleared ? nil : onClear)
            }
        }
        #else
        .sheet(isPresented: $showImagePreview) {
            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                ImagePreviewView(imageURL: url, onDelete: message.isCleared ? nil : onClear)
                    .frame(minWidth: 400, minHeight: 400)
            }
        }
        #endif
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("此操作将从云端永久抹除此记录\(message.type == .image ? "和图片文件" : "")，且不可撤销。")
        }
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    // MARK: - Subviews
    
    private var textContent: some View {
        #if os(macOS)
        SelectableTextView(
            text: message.textContent ?? "",
            color: message.isCleared ? Color.secondary : Color.primary,
            font: .body,
            onCopy: { copyText(message.textContent ?? "") },
            onDelete: { showDeleteConfirm = true }
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        Text(message.textContent ?? "")
            .font(.body)
            .foregroundStyle(message.isCleared ? .secondary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    copyText(message.textContent ?? "")
                } label: {
                    Label("拷贝", systemImage: "doc.on.doc")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        #endif
    }

    private var imageContent: some View {
        Group {
            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 240, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { showImagePreview = true }
                            .contextMenu {
                                Button {
                                    copyImage(from: url)
                                } label: {
                                    Label("拷贝", systemImage: "doc.on.doc")
                                }
                                
                                Button {
                                    Task { await saveImage(from: url) }
                                } label: {
                                    Label("保存", systemImage: "square.and.arrow.down")
                                }
                                
                                #if os(macOS)
                                Button {
                                    Task { await saveImageAs(from: url) }
                                } label: {
                                    Label("另存为...", systemImage: "folder.badge.plus")
                                }
                                #endif
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    showDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("加载失败，点击重试")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 200, height: 100).background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            loadID = UUID() // 更新外部 ID 触发重新渲染
                        }
                    case .empty:
                        ProgressView().frame(width: 200, height: 100).background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    @unknown default: EmptyView()
                    }
                }
                .id(loadID)
            }
        }
    }

    // MARK: - Buttons
    
    private var copyTextButton: some View {
        Button {
            copyText(message.textContent ?? "")
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var copyImageButton: some View {
        Button {
            if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                copyImage(from: url)
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var downloadImageButton: some View {
        Button {
            if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                Task { await saveImage(from: url) }
            }
        } label: {
            Group {
                switch saveStatus {
                case .none:
                    Image(systemName: "square.and.arrow.down")
                        .foregroundStyle(.secondary)
                case .saving:
                    ProgressView().scaleEffect(0.6)
                case .success:
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                case .error:
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .disabled(saveStatus == .saving)
    }

    private var clearButton: some View {
        Button {
            onClear()
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var checkFillIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(Color.gray.opacity(0.3))
    }

    // MARK: - Helper Methods
    
    private func copyText(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    private func copyImage(from url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                #if os(iOS)
                if let image = UIImage(data: data) {
                    UIPasteboard.general.image = image
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                #elseif os(macOS)
                if let image = NSImage(data: data) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
                #endif
            } catch {
                print("Copy image failed: \(error)")
            }
        }
    }

    private func saveImage(from url: URL) async {
        saveStatus = .saving
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if os(iOS)
            if let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                withAnimation { saveStatus = .success }
            } else {
                saveStatus = .error
            }
            #elseif os(macOS)
            let defaultURL = SettingsManager.shared.macOSDefaultSavePath ?? 
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let fileURL = defaultURL.appendingPathComponent(url.lastPathComponent)
            try data.write(to: fileURL)
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            withAnimation { saveStatus = .success }
            #endif
        } catch {
            print("Save image failed: \(error)")
            saveStatus = .error
            
            #if os(macOS)
            let alert = NSAlert()
            alert.messageText = "保存失败"
            alert.informativeText = "无法将图片保存到指定目录: \(error.localizedDescription)\n\n极大可能是由于权限不足，您可以尝试“另存为”以重新授权。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.runModal()
            #endif
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
            panel.allowsMultipleSelection = false
            panel.title = "选择保存目录"
            panel.prompt = "保存到此目录"
            
            if panel.runModal() == .OK, let selectedURL = panel.url {
                SettingsManager.shared.macOSDefaultSavePath = selectedURL
                let fileURL = selectedURL.appendingPathComponent(url.lastPathComponent)
                try data.write(to: fileURL)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                withAnimation { saveStatus = .success }
            }
        } catch {
            print("Save Image As failed: \(error)")
            saveStatus = .error
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }
    #endif
}
