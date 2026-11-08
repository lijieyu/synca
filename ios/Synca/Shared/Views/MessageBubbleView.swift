import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MessageBubbleView: View {
    let message: SyncaMessage
    let categories: [SyncaMessageCategory]
    var showsSeparator: Bool = true
    var isUpdatingCompletion: Bool = false
    var onEdit: (() -> Void)? = nil
    let onClear: () -> Void
    let onDelete: () -> Void
    let onCategoryChange: ((String) -> Void)?
    let onImageTap: () -> Void
    let onImageLoaded: () -> Void

    @State private var copied = false
    @State private var isTextExpanded = false
    @State private var saveStatus: SaveStatus = .none
    @State private var showDeleteConfirm = false
    @State private var photoSaveError: String?
    @State private var loadID = UUID() // #1: 重显失败图片的关键

    private var messageText: String {
        message.textContent ?? ""
    }

    private var fileName: String {
        message.fileName ?? String(syncaLocalized: "message_file.attachment")
    }

    private var fileSizeText: String {
        guard let fileSize = message.fileSize else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }

    private var fileExtensionText: String {
        URL(fileURLWithPath: fileName).pathExtension.uppercased()
    }

    #if os(iOS)
    private var linkedAttributedText: AttributedString {
        Self.makeLinkedAttributedText(
            from: messageText,
            baseColor: message.isCleared ? UIColor.secondaryLabel : UIColor.label
        )
    }

    private var linkedNSAttributedText: NSAttributedString {
        Self.makeLinkedIOSAttributedText(
            from: messageText,
            baseColor: message.isCleared ? .secondaryLabel : .label
        )
    }
    #endif

    #if os(macOS)
    private var linkedNSAttributedText: NSAttributedString {
        Self.makeLinkedNSAttributedText(
            from: messageText,
            baseColor: message.isCleared ? .secondaryLabelColor : .labelColor
        )
    }
    #endif

    enum SaveStatus {
        case none, saving, success, error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Content
            Group {
                if message.type != .text && message.isAttachmentExpired {
                    Label("storage.expired", systemImage: "clock.badge.xmark").foregroundStyle(.secondary)
                } else {
                switch message.type {
                case .text:
                    textContent
                case .image:
                    imageContent
                case .file:
                    fileContent
                }
                }
            }

            if message.type != .text, !message.isAttachmentExpired, let expiry = message.attachmentExpiryDate {
                Text("\(String(syncaLocalized: "storage.expires")): \(expiry.formatted(.dateTime.year().month().day().hour().minute().locale(AppLocalization.locale)))")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

                if let categoryName = message.categoryName, let categoryId = message.categoryId {
                    Text("·")
                        .font(.caption2)
                    categoryMenu(name: message.categoryIsDefault == true ? String(syncaLocalized: "message_category.default_badge") : categoryName, categoryId: categoryId)
                }

                Spacer()

                // #6: Actions row (Always visible)
                HStack(spacing: actionSpacing) {
                    if message.type == .image && !message.isAttachmentExpired {
                        downloadImageButton
                        copyImageButton
                    } else if message.type == .file && !message.isAttachmentExpired {
                        downloadFileButton
                    }
                    if message.type == .text {
                        #if os(macOS)
                        if message.canEditText, let onEdit {
                            Button(action: onEdit) { Image("EditOutline").resizable().frame(width: 16, height: 16) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("message_edit.title"))
                                .help(Text("message_edit.title"))
                        }
                        #endif
                        copyTextButton
                    }
                    #if os(macOS)
                    Button { showDeleteConfirm = true } label: {
                        Image("DeleteOutline").resizable().frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.delete"))
                    .help(Text("common.delete"))
                    #endif
                    clearButton
                }
            }
            .foregroundStyle(message.isCleared ? .tertiary : .secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { if showsSeparator { Divider().opacity(0.6) } }
        .contextMenu { messageContextMenu }
        .alert("image_preview.save_failed", isPresented: Binding(
            get: { photoSaveError != nil }, set: { if !$0 { photoSaveError = nil } }
        )) {
            Button("common.ok", role: .cancel) { photoSaveError = nil }
        } message: { Text(photoSaveError ?? "") }
        .alert(Text("message_bubble.delete_confirm_title", bundle: .main), isPresented: $showDeleteConfirm) {
            Button("common.cancel", role: .cancel) {}
            Button("common.delete", role: .destructive) {
                onDelete()
            }
        } message: {
            let suffix = message.type == .image ? String(syncaLocalized: "message_bubble.delete_image_suffix", bundle: .main) : ""
            Text(String(syncaLocalized: "message_bubble.delete_confirm_message", bundle: .main).replacingOccurrences(of: "%@", with: suffix))
        }
    }

    private var cardBackground: Color {
        Color.syncaCardBackground
    }

    @ViewBuilder
    private func categoryMenu(name: String, categoryId: String) -> some View {
        if let onCategoryChange, !categories.isEmpty {
            Menu {
                ForEach(categories) { category in
                    Toggle(isOn: Binding(
                        get: { category.id == categoryId },
                        set: { selected in if selected { onCategoryChange(category.id) } }
                    )) {
                        Label {
                            Text(category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name)
                        } icon: {
                            Image("Category-\(category.color.rawValue)").renderingMode(.original)
                        }
                    }
                }
            } label: {
                categoryBadge(name: name, hasMenu: true)
            }
            .menuStyle(.borderlessButton)
            .tint(message.isCleared ? Color.secondary : Color.primary)
            .foregroundStyle(message.isCleared ? Color.secondary : Color.primary)
            .fixedSize()
        } else {
            categoryBadge(name: name, hasMenu: false)
        }
    }

    private func categoryBadge(name: String, hasMenu: Bool) -> some View {
        HStack(spacing: 2) {
            Text(name)
                .font(.caption2)
            #if os(iOS)
            if hasMenu {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.top, 1)
            }
            #endif
        }
        .foregroundStyle(message.isCleared ? .tertiary : .secondary)
    }

    // MARK: - Subviews
    
    private var textContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isTextExpanded {
                #if os(macOS)
                ZStack(alignment: .topLeading) {
                    Text(messageText).font(.body).fixedSize(horizontal: false, vertical: true)
                        .hidden().allowsHitTesting(false)
                    MacSelectableText(attributedText: linkedNSAttributedText,
                                      color: message.isCleared ? .secondary : .primary, font: .body)
                }
                #else
                LinkTextView(attributedText: linkedNSAttributedText)
                #endif
            } else {
                Text(AttributedString(linkedNSAttributedText)).font(.body).lineLimit(6)
                    .textSelection(.enabled)
                    .foregroundStyle(message.isCleared ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { geometry in
                        Color.clear.onAppear { updateTextOverflow(width: geometry.size.width) }
                            .onChange(of: geometry.size.width) { updateTextOverflow(width: $0) }
                            .onChange(of: dynamicTypeSize) { _ in updateTextOverflow(width: geometry.size.width) }
                            .onChange(of: messageText) { _ in updateTextOverflow(width: geometry.size.width) }
                    })
            }
            if textOverflows || isTextExpanded {
                Button(isTextExpanded ? "message_bubble.show_less" : "message_bubble.show_more") {
                    isTextExpanded.toggle()
                }.font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor)
                    .padding(.vertical, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var textOverflows = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private func updateTextOverflow(width: CGFloat) {
        guard width > 0 else { return }
        #if os(iOS)
        let font = UIFont.preferredFont(forTextStyle: .body)
        #else
        let font = NSFont.preferredFont(forTextStyle: .body)
        #endif
        let size = (messageText as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        textOverflows = size.height > (font.ascender - font.descender + font.leading) * 6 + 1
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        if message.type == .text {
            if message.canEditText, let onEdit {
                Button(action: onEdit) { Label("message_edit.title", image: "EditOutline") }
            }
            Button {
                copyText(messageText)
            } label: {
                Label("common.copy", image: "CopyOutline")
            }
            
            Divider()
            
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("common.delete", image: "DeleteOutline")
            }
        } else if !message.isAttachmentExpired, message.type == .image, let urlString = message.imageUrl, let url = URL(string: urlString) {
            Button {
                self.copyImage(from: url)
            } label: {
                Label("common.copy", image: "CopyOutline")
            }

            Button {
                Task { await self.saveImage(from: url) }
            } label: {
                Label("common.save", image: "DownloadOutline")
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
                Label("common.delete", image: "DeleteOutline")
            }
        } else if !message.isAttachmentExpired, message.type == .file, let urlString = message.fileUrl, let url = URL(string: urlString) {
            Button {
                Task { await self.saveFile(from: url, suggestedFileName: fileName) }
            } label: {
                Label("common.save", image: "DownloadOutline")
            }

            #if os(macOS)
            Button {
                self.showInFinder(url: url, suggestedFileName: fileName)
            } label: {
                Label("message_bubble.show_in_finder", systemImage: "folder")
            }

            Button {
                Task { await self.saveFileAs(from: url, suggestedFileName: fileName) }
            } label: {
                Label("message_bubble.save_as", systemImage: "folder.badge.plus")
            }
            #endif

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("common.delete", image: "DeleteOutline")
            }
        } else if message.isAttachmentExpired {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("common.delete", image: "DeleteOutline")
            }
        }
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
                            .contextMenu { messageContextMenu }
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

    private var fileContent: some View {
        Button {
            guard let urlString = message.fileUrl, let url = URL(string: urlString) else { return }
            Task { await openFile(from: url, suggestedFileName: fileName) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImageNameForFile)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(fileName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(message.isCleared ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        if !fileExtensionText.isEmpty {
                            Text(fileExtensionText)
                        }
                        if !fileSizeText.isEmpty {
                            Text(fileSizeText)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Buttons
    
    @ViewBuilder
    private var copyActionIcon: some View {
        if copied {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .medium))
        } else {
            Image("CopyOutline").resizable().frame(width: 16, height: 16)
        }
    }

    private var actionTargetSize: CGFloat {
        #if os(iOS)
        44
        #else
        18
        #endif
    }
    private var actionSpacing: CGFloat {
        #if os(iOS)
        0
        #else
        22
        #endif
    }

    private var copyTextButton: some View {
        Button {
            copyText(messageText)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        } label: {
            copyActionIcon
                .frame(width: actionTargetSize, height: actionTargetSize).contentShape(Rectangle())
                .foregroundStyle(copied ? .green : .secondary)
                .accessibilityLabel(Text(copied ? "message_bubble.copied" : "common.copy"))
        }
        .buttonStyle(.plain)
    }

    private var copyImageButton: some View {
        Button {
            if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                self.copyImage(from: url)
            }
        } label: {
            copyActionIcon
                .frame(width: actionTargetSize, height: actionTargetSize).contentShape(Rectangle())
                .foregroundStyle(copied ? .green : .secondary)
                .accessibilityLabel(Text(copied ? "message_bubble.copied" : "common.copy"))
        }
        .buttonStyle(.plain)
    }

    private var downloadImageButton: some View {
        Button {
            if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                Task { await self.saveImage(from: url) }
            }
        } label: {
            saveIconLabel
                .frame(width: actionTargetSize, height: actionTargetSize).contentShape(Rectangle())
                .accessibilityLabel(Text("common.save"))
        }
        .buttonStyle(.plain)
        .disabled(saveStatus == .saving)
    }

    private var downloadFileButton: some View {
        Button {
            guard let urlString = message.fileUrl, let url = URL(string: urlString) else { return }
            Task { await saveFile(from: url, suggestedFileName: fileName) }
        } label: {
            saveIconLabel
                .frame(width: actionTargetSize, height: actionTargetSize).contentShape(Rectangle())
                .accessibilityLabel(Text("common.save"))
        }
        .buttonStyle(.plain)
        .disabled(saveStatus == .saving)
    }

    private var saveIconLabel: some View {
        Group {
            switch saveStatus {
            case .none:
                Image("DownloadOutline").resizable().frame(width: 16, height: 16)
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

    private var clearButton: some View {
        Button {
            onClear()
        } label: {
            Image(systemName: message.isCleared ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: actionTargetSize, height: actionTargetSize).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingCompletion)
        .accessibilityLabel(Text(message.isCleared ? "message_bubble.mark_incomplete" : "message_bubble.mark_complete"))
        .help(Text(message.isCleared ? "message_bubble.mark_incomplete" : "message_bubble.mark_complete"))
    }

    private var systemImageNameForFile: String {
        switch fileExtensionText.lowercased() {
        case "pdf":
            return "doc.richtext"
        case "xls", "xlsx", "csv":
            return "tablecells"
        case "ppt", "pptx":
            return "chart.bar.doc.horizontal"
        case "zip":
            return "archivebox"
        default:
            return "doc"
        }
    }

    // MARK: - Helper Methods
    
    private func copyText(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIAccessibility.post(notification: .announcement, argument: String(syncaLocalized: "message_bubble.copied"))
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    private func copyImage(from url: URL) {
        guard !message.isAttachmentExpired, (try? APIClient.shared.attachmentSession(for: url)) != nil else { return }
        if let cachedData = ImageCache.getCachedData(for: url, authorizationToken: APIClient.shared.token) {
            finishCopyingImage(cachedData, operationID: nil)
            return
        }

        let operationID = SyncManager.shared.beginProgressFeedback(
            String(syncaLocalized: "message_bubble.copying_image", bundle: .main)
        )
        Task {
            do {
                let data = try await ImageCache.loadData(
                    for: url,
                    authorizationToken: APIClient.shared.token
                )
                finishCopyingImage(data, operationID: operationID)
            } catch {
                SyncManager.shared.showErrorFeedback(
                    String(syncaLocalized: "message_bubble.copy_image_failed", bundle: .main),
                    for: operationID
                )
                print("Copy image failed: \(error)")
            }
        }
    }

    private func finishCopyingImage(_ data: Data, operationID: UUID?) {
        guard ImageClipboard.write(data) else {
            SyncManager.shared.showErrorFeedback(
                String(syncaLocalized: "message_bubble.copy_image_failed", bundle: .main),
                for: operationID
            )
            print("Copy image failed: unsupported image data")
            return
        }

        SyncManager.shared.showSuccessFeedback(
            String(syncaLocalized: "message_bubble.image_copied", bundle: .main),
            for: operationID
        )
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func saveImage(from url: URL) async {
        #if os(macOS)
        if SettingsManager.shared.asksForDownloadLocation { await saveImageAs(from: url); return }
        #endif
        guard saveStatus != .saving else { return }
        saveStatus = .saving
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: url.lastPathComponent)
            #if os(iOS)
            try await PhotoLibrarySaver.saveImage(at: localURL)
            PhotoLibrarySaver.announce(success: true)
            withAnimation { saveStatus = .success }
            #elseif os(macOS)
            let defaultURL = SettingsManager.shared.macOSDefaultSavePath ??
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let fileURL = try SettingsManager.shared.withSecurityScopedAccess(to: defaultURL) {
                let destination = AttachmentFileName.availableURL(in: defaultURL, suggestedName: url.lastPathComponent)
                try FileManager.default.copyItem(at: localURL, to: destination)
                return destination
            }
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            withAnimation { saveStatus = .success }
            #endif
        } catch {
            print("Save image failed: \(error)")
            
            #if os(macOS)
            if SaveFailurePresentation.requiresFolderAuthorization(error) {
                saveStatus = .none
                requestMacSaveFolderAuthorization {
                    Task { await self.saveImage(from: url) }
                }
            } else {
                saveStatus = .error
                showMacSaveFailedAlert(error: error, messageKey: "message_bubble.save_image_failed_message")
            }
            #else
            saveStatus = .error
            photoSaveError = (error as? PhotoLibrarySaver.SaveError)?.localizedDescription
                ?? String(syncaLocalized: "photo_save.failed", bundle: .main)
            PhotoLibrarySaver.announce(success: false)
            #endif
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }

    private func saveFile(from url: URL, suggestedFileName: String) async {
        #if os(macOS)
        if SettingsManager.shared.asksForDownloadLocation { await saveFileAs(from: url, suggestedFileName: suggestedFileName); return }
        #endif
        saveStatus = .saving
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: suggestedFileName)
            #if os(iOS)
            presentShareSheet(for: localURL)
            withAnimation { saveStatus = .success }
            #elseif os(macOS)
            let defaultURL = SettingsManager.shared.macOSDefaultSavePath ?? 
                FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let saveURL = try SettingsManager.shared.withSecurityScopedAccess(to: defaultURL) {
                let destination = AttachmentFileName.availableURL(in: defaultURL, suggestedName: suggestedFileName)
                try FileManager.default.copyItem(at: localURL, to: destination)
                return destination
            }
            NSWorkspace.shared.activateFileViewerSelecting([saveURL])
            withAnimation { saveStatus = .success }
            #endif
        } catch {
            print("Save file failed: \(error)")
            
            #if os(macOS)
            if SaveFailurePresentation.requiresFolderAuthorization(error) {
                saveStatus = .none
                requestMacSaveFolderAuthorization {
                    Task { await self.saveFile(from: url, suggestedFileName: suggestedFileName) }
                }
            } else {
                saveStatus = .error
                showMacSaveFailedAlert(error: error, messageKey: "message_bubble.save_file_failed_message")
            }
            #else
            saveStatus = .error
            #endif
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }

    private func openFile(from url: URL, suggestedFileName: String) async {
        let needsDownload = !AttachmentCache.isCached(url, suggestedFileName: suggestedFileName)
        if needsDownload {
            saveStatus = .saving
        }
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: suggestedFileName)
            #if os(iOS)
            presentShareSheet(for: localURL)
            #elseif os(macOS)
            NSWorkspace.shared.open(localURL)
            #endif
            if needsDownload {
                withAnimation { saveStatus = .success }
            }
        } catch {
            print("Open file failed: \(error)")
            saveStatus = .error
        }

        if needsDownload || saveStatus == .error {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                saveStatus = .none
            }
        }
    }

    #if os(macOS)
    @MainActor
    private func showMacSaveFailedAlert(error: Error, messageKey: String) {
        let alert = NSAlert()
        alert.messageText = String(syncaLocalized: "message_bubble.save_failed_title", bundle: .main)
        alert.informativeText = AppLocalization.string(messageKey)
            .replacingOccurrences(of: "%@", with: error.localizedDescription)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(syncaLocalized: "common.ok", bundle: .main))
        alert.runModal()
    }

    @MainActor
    private func requestMacSaveFolderAuthorization(retry: @escaping () -> Void) {
        let defaultFolder = SettingsManager.shared.macOSDefaultSavePath?.lastPathComponent
            ?? String(syncaLocalized: "message_bubble.save_default_folder", bundle: .main)
        let alert = NSAlert()
        alert.messageText = String(syncaLocalized: "message_bubble.save_authorization_title", bundle: .main)
        alert.informativeText = String(syncaLocalized: "message_bubble.save_authorization_message", bundle: .main)
            .replacingOccurrences(of: "%@", with: defaultFolder)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(syncaLocalized: "message_bubble.save_authorize_button", bundle: .main))
        alert.addButton(withTitle: String(syncaLocalized: "common.cancel", bundle: .main))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.message = String(syncaLocalized: "message_bubble.save_authorization_panel_message", bundle: .main)
        openPanel.prompt = String(syncaLocalized: "message_bubble.save_authorization_panel_prompt", bundle: .main)
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.directoryURL = SettingsManager.shared.macOSDefaultSavePath
        if openPanel.runModal() == .OK, let folderURL = openPanel.url {
            SettingsManager.shared.setMacOSDefaultSavePath(folderURL)
            retry()
        }
    }

    private func showInFinder(url: URL) {
        Task {
            if let localURL = try? await downloadToTemp(url: url) {
                NSWorkspace.shared.activateFileViewerSelecting([localURL])
            }
        }
    }

    private func showInFinder(url: URL, suggestedFileName: String) {
        Task {
            let needsDownload = !AttachmentCache.isCached(url, suggestedFileName: suggestedFileName)
            if needsDownload {
                saveStatus = .saving
            }
            do {
                let localURL = try await downloadToLocalFile(url: url, suggestedFileName: suggestedFileName)
                NSWorkspace.shared.activateFileViewerSelecting([localURL])
                if needsDownload {
                    withAnimation { saveStatus = .success }
                }
            } catch {
                print("Show in Finder failed: \(error)")
                saveStatus = .error
            }

            if needsDownload || saveStatus == .error {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    saveStatus = .none
                }
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
        try await downloadToLocalFile(url: url, suggestedFileName: url.lastPathComponent)
    }

    private func downloadToLocalFile(url: URL, suggestedFileName: String) async throws -> URL {
        guard !message.isAttachmentExpired else { throw APIError.attachmentExpired }
        _ = try APIClient.shared.attachmentSession(for: url)
        if let cachedURL = AttachmentCache.cachedFileURL(for: url, suggestedFileName: suggestedFileName) {
            return cachedURL
        }

        let downloadURL = try await APIClient.shared.downloadAttachment(from: url)
        defer { try? FileManager.default.removeItem(at: downloadURL) }
        guard !message.isAttachmentExpired else { throw APIError.attachmentExpired }
        return try AttachmentCache.saveDownloadedFile(downloadURL, for: url, suggestedFileName: suggestedFileName)
    }

    private func saveImageAs(from url: URL) async {
        guard saveStatus != .saving else { return }
        saveStatus = .saving
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: url.lastPathComponent)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = url.lastPathComponent
                panel.title = String(syncaLocalized: "message_bubble.save_as", bundle: .main)
                panel.prompt = String(syncaLocalized: "common.save", bundle: .main)
                panel.canCreateDirectories = true
                if let defaultDirectory = SettingsManager.shared.macOSDefaultSavePath {
                    panel.directoryURL = defaultDirectory
                }

                if panel.runModal() == .OK, let saveURL = panel.url {
                    let parentURL = saveURL.deletingLastPathComponent()
                    SettingsManager.shared.setMacOSDefaultSavePath(parentURL)
                    do {
                        try? FileManager.default.removeItem(at: saveURL)
                        try FileManager.default.copyItem(at: localURL, to: saveURL)
                        NSWorkspace.shared.activateFileViewerSelecting([saveURL])
                        withAnimation { self.saveStatus = .success }
                    } catch {
                        print("Save Image As copy failed: \(error)")
                        withAnimation { self.saveStatus = .error }
                    }
                }
            }
        } catch {
            print("Save Image As failed: \(error)")
            await MainActor.run { saveStatus = .error }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }

    private func saveFileAs(from url: URL, suggestedFileName: String) async {
        guard saveStatus != .saving else { return }
        saveStatus = .saving
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: suggestedFileName)
            await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = suggestedFileName
                panel.title = String(syncaLocalized: "message_bubble.save_as", bundle: .main)
                panel.prompt = String(syncaLocalized: "common.save", bundle: .main)
                panel.canCreateDirectories = true
                if let defaultDirectory = SettingsManager.shared.macOSDefaultSavePath {
                    panel.directoryURL = defaultDirectory
                }

                if panel.runModal() == .OK, let saveURL = panel.url {
                    let parentURL = saveURL.deletingLastPathComponent()
                    SettingsManager.shared.setMacOSDefaultSavePath(parentURL)
                    do {
                        try? FileManager.default.removeItem(at: saveURL)
                        try FileManager.default.copyItem(at: localURL, to: saveURL)
                        NSWorkspace.shared.activateFileViewerSelecting([saveURL])
                        withAnimation { self.saveStatus = .success }
                    } catch {
                        print("Save File As copy failed: \(error)")
                        withAnimation { self.saveStatus = .error }
                    }
                }
            }
        } catch {
            print("Save File As failed: \(error)")
            await MainActor.run { saveStatus = .error }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }
    #endif

    #if os(iOS)
    private func downloadToLocalFile(url: URL, suggestedFileName: String) async throws -> URL {
        guard !message.isAttachmentExpired else { throw APIError.attachmentExpired }
        _ = try APIClient.shared.attachmentSession(for: url)
        if let cachedURL = AttachmentCache.cachedFileURL(for: url, suggestedFileName: suggestedFileName) {
            return cachedURL
        }

        let downloadURL = try await APIClient.shared.downloadAttachment(from: url)
        defer { try? FileManager.default.removeItem(at: downloadURL) }
        guard !message.isAttachmentExpired else { throw APIError.attachmentExpired }
        return try AttachmentCache.saveDownloadedFile(downloadURL, for: url, suggestedFileName: suggestedFileName)
    }

    @MainActor
    private func presentShareSheet(for url: URL) {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController,
            let presenter = root.topMostPresentedViewController()
        else { return }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY - 44,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }
    #endif
}

#if os(iOS)
private extension UIViewController {
    func topMostPresentedViewController() -> UIViewController? {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController()
        }
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostPresentedViewController()
        }
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostPresentedViewController()
        }
        return self
    }
}
#endif

private extension MessageBubbleView {
    #if os(iOS)
    static func makeLinkedAttributedText(from text: String, baseColor: UIColor) -> AttributedString {
        let mutable = makeLinkedIOSAttributedText(
            from: text,
            baseColor: baseColor
        )
        return (try? AttributedString(mutable, including: \.uiKit)) ?? AttributedString(text)
    }
    #endif

    #if os(iOS)
    static func makeLinkedIOSAttributedText(from text: String, baseColor: UIColor) -> NSAttributedString {
        let mutable = NSMutableAttributedString(string: text)
        mutable.addAttributes(
            [
                .foregroundColor: baseColor,
                .font: UIFont.preferredFont(forTextStyle: .body)
            ],
            range: NSRange(location: 0, length: mutable.length)
        )

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: mutable.length)
            detector.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let result, let url = result.url else { return }
                mutable.addAttributes(
                    [
                        .link: url,
                        .foregroundColor: UIColor.link,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: result.range
                )
            }
        }

        return mutable
    }
    #endif

    #if os(macOS)
    static func makeLinkedNSAttributedText(from text: String, baseColor: NSColor) -> NSAttributedString {
        let mutable = NSMutableAttributedString(string: text)
        mutable.addAttributes(
            [
                .foregroundColor: baseColor,
                .font: NSFont.systemFont(ofSize: 13)
            ],
            range: NSRange(location: 0, length: mutable.length)
        )

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: mutable.length)
            detector.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
                guard let result, let url = result.url else { return }
                mutable.addAttributes(
                    [
                        .link: url,
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: result.range
                )
            }
        }

        return mutable
    }
    #endif
}
// MARK: - LinkTextView Implementation

#if os(iOS)
private struct InternalLinkTextView: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = []
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText != attributedText {
            uiView.attributedText = attributedText
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        guard targetWidth > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: targetWidth, height: ceil(fittingSize.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            UIApplication.shared.open(url)
            return false
        }
    }
}
#endif



/// A cross-platform wrapper for a linkable text view.
struct LinkTextView: View {
    let attributedText: NSAttributedString

    var body: some View {
        #if os(iOS)
        InternalLinkTextView(attributedText: attributedText)
        #else
        EmptyView()
        #endif
    }
}
