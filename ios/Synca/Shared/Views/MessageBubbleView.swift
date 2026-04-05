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
    let onImageTap: () -> Void
    let onImageLoaded: () -> Void

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
                HStack(spacing: 22) {
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
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(message.isCleared
                          ? Color.syncaMintLight
                          : cardBackground)
                
                if message.isCleared {
                    // Subtle mint glow for processed
                    Circle()
                        .fill(Color.syncaMint.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                        .offset(x: 40, y: -20)
                }
            }
            .shadow(color: .black.opacity(message.isCleared ? 0.02 : 0.04), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(message.isCleared 
                        ? Color.syncaMint.opacity(0.3) 
                        : Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .opacity(message.isCleared ? 0.95 : 1.0)
        .alert(Text("message_bubble.delete_confirm_title", bundle: .main), isPresented: $showDeleteConfirm) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                onDelete()
            }
        } message: {
            let suffix = message.type == .image ? String(localized: "message_bubble.delete_image_suffix", bundle: .main) : ""
            Text(String(localized: "message_bubble.delete_confirm_message", bundle: .main).replacingOccurrences(of: "%@", with: suffix))
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
        ZStack(alignment: .topLeading) {
            // Invisible native Text to guarantee perfect SwiftUI auto-layout height & wrapping
            Text(message.textContent ?? "")
                .font(.body)
                .lineLimit(nil)
                .opacity(0)
            
            // AppKit Text overlay for selection and custom context menu
            MacSelectableText(
                text: message.textContent ?? "",
                color: message.isCleared ? Color.secondary : Color.primary,
                font: .body,
                onCopy: { copyText(message.textContent ?? "") },
                onDelete: { showDeleteConfirm = true }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        Text(message.textContent ?? "")
            .font(.body)
            .foregroundStyle(message.isCleared ? Color.primary.opacity(0.6) : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                Button {
                    copyText(message.textContent ?? "")
                } label: {
                    Label("common.copy", systemImage: "doc.on.doc")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("common.delete", systemImage: "trash")
                }
            }
        #endif
    }

    private var imageContent: some View {
        Group {
            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                CachedAsyncImage(url: url, onSuccess: onImageLoaded) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: 320, maxHeight: 450, alignment: .leading)
                            .onTapGesture { onImageTap() }
                            .contextMenu {
                                Button {
                                    self.copyImage(from: url)
                                } label: {
                                    Label("common.copy", systemImage: "doc.on.doc")
                                }

                                Button {
                                    Task { await self.saveImage(from: url) }
                                } label: {
                                    Label("common.save", systemImage: "square.and.arrow.down")
                                }

                                #if os(macOS)
                                Button { self.openWithPreview(url: url) } label: { Label("message_bubble.open_with_preview", systemImage: "eye") }
                                Button { self.showInFinder(url: url) } label: { Label("message_bubble.show_in_finder", systemImage: "folder") }

                                Button {
                                    Task { await self.saveImageAs(from: url) }
                                } label: {
                                    Label("message_bubble.save_as", systemImage: "folder.badge.plus")
                                }
                                #endif
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    showDeleteConfirm = true
                                } label: {
                                    Label("common.delete", systemImage: "trash")
                                }
                            }
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text("message_bubble.load_failed_retry", bundle: .main)
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var copyImageButton: some View {
        Button {
            if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                self.copyImage(from: url)
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(copied ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var downloadImageButton: some View {
        Button {
            if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                Task { await self.saveImage(from: url) }
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
            .font(.system(size: 16))
        }
        .buttonStyle(.plain)
        .disabled(saveStatus == .saving)
    }

    private var clearButton: some View {
        Button {
            onClear()
        } label: {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var checkFillIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(Color.green.opacity(0.8))
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
            alert.messageText = String(localized: "message_bubble.save_failed_title", bundle: .main)
            alert.informativeText = String(localized: "message_bubble.save_failed_message", bundle: .main).replacingOccurrences(of: "%@", with: error.localizedDescription)
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "common.ok", bundle: .main))
            alert.runModal()
            #endif
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
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
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.title = String(localized: "message_bubble.choose_save_directory", bundle: .main)
            panel.prompt = String(localized: "message_bubble.save_to_directory", bundle: .main)
            
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
