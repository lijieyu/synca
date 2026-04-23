import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MessageBubbleView: View {
    let message: SyncaMessage
    let categories: [SyncaMessageCategory]
    let onClear: () -> Void
    let onDelete: () -> Void
    let onCategoryChange: ((String) -> Void)?
    let onImageTap: () -> Void
    let onImageLoaded: () -> Void

    @State private var copied = false
    @State private var saveStatus: SaveStatus = .none
    @State private var showDeleteConfirm = false
    @State private var loadID = UUID() // #1: 重显失败图片的关键

    private var messageText: String {
        message.textContent ?? ""
    }

    private var fileName: String {
        message.fileName ?? "Attachment"
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
                switch message.type {
                case .text:
                    textContent
                case .image:
                    imageContent
                case .file:
                    fileContent
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

                if let categoryName = message.categoryName, let categoryId = message.categoryId {
                    Text("·")
                        .font(.caption2)
                    categoryMenu(name: categoryName, categoryId: categoryId)
                }

                Spacer()

                // #6: Actions row (Always visible)
                HStack(spacing: 22) {
                    if message.type == .image {
                        downloadImageButton
                        copyImageButton
                    } else if message.type == .file {
                        downloadFileButton
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
                      ? Color.primary.opacity(0.05)
                      : cardBackground)
                .shadow(color: .black.opacity(message.isCleared ? 0.02 : 0.04), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(message.isCleared 
                        ? Color.secondary.opacity(0.22)
                        : Color.syncaCardBorder, lineWidth: 0.5)
        )
        .opacity(message.isCleared ? 0.95 : 1.0)
        .contextMenu { messageContextMenu }
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
        Color.syncaCardBackground
    }

    @ViewBuilder
    private func categoryMenu(name: String, categoryId: String) -> some View {
        if let onCategoryChange, !categories.isEmpty {
            Menu {
                ForEach(categories) { category in
                    Button {
                        onCategoryChange(category.id)
                    } label: {
                        Label(category.name, systemImage: category.id == categoryId ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                categoryBadge(name: name, color: message.categoryColor ?? .slate)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } else {
            categoryBadge(name: name, color: message.categoryColor ?? .slate)
        }
    }

    private func categoryBadge(name: String, color: MessageCategoryColor) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(categoryAccentColor(for: color))
                .frame(width: 6, height: 6)

            Text(name)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(categoryBackgroundColor(for: color))
        .clipShape(Capsule())
    }

    private func categoryBackgroundColor(for color: MessageCategoryColor) -> Color {
        switch color {
        case .sky:
            return Color.blue.opacity(0.16)
        case .mint:
            return Color.green.opacity(0.16)
        case .amber:
            return Color.orange.opacity(0.18)
        case .coral:
            return Color.red.opacity(0.16)
        case .violet:
            return Color.purple.opacity(0.18)
        case .slate:
            return Color.secondary.opacity(0.14)
        case .rose:
            return Color.pink.opacity(0.16)
        case .ocean:
            return Color.cyan.opacity(0.18)
        }
    }

    private func categoryAccentColor(for color: MessageCategoryColor) -> Color {
        switch color {
        case .sky:
            return .blue
        case .mint:
            return .green
        case .amber:
            return .orange
        case .coral:
            return .red
        case .violet:
            return .purple
        case .slate:
            return .secondary
        case .rose:
            return .pink
        case .ocean:
            return .cyan
        }
    }

    // MARK: - Subviews
    
    private var textContent: some View {
        #if os(macOS)
        ZStack(alignment: Alignment.topLeading) {
            // Invisible native Text to guarantee perfect SwiftUI auto-layout height & wrapping
            Text(messageText)
                .font(.body)
                .lineLimit(nil)
                .opacity(0)
                .allowsHitTesting(false)
            
            // AppKit Text overlay for selection and custom context menu
            MacSelectableText(
                attributedText: linkedNSAttributedText,
                color: message.isCleared ? Color.secondary : Color.primary,
                font: .body
            )
        }
        .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
        #else
        LinkTextView(attributedText: linkedNSAttributedText)
            .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
        #endif
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        if message.type == .text {
            Button {
                copyText(messageText)
            } label: {
                Label("common.copy", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("common.delete", systemImage: "trash")
            }
        } else if message.type == .image, let urlString = message.imageUrl, let url = URL(string: urlString) {
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
        } else if message.type == .file, let urlString = message.fileUrl, let url = URL(string: urlString) {
            Button {
                Task { await self.openFile(from: url, suggestedFileName: fileName) }
            } label: {
                Label("common.save", systemImage: "square.and.arrow.down")
            }

            #if os(macOS)
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
                Label("common.delete", systemImage: "trash")
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
    
    private var copyTextButton: some View {
        Button {
            copyText(messageText)
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
        Group {
            #if os(macOS)
            Menu {
                if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                    Button {
                        Task { await self.saveImage(from: url) }
                    } label: {
                        Label("common.save", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        Task { await self.saveImageAs(from: url) }
                    } label: {
                        Label("message_bubble.save_as", systemImage: "folder.badge.plus")
                    }
                }
            } label: {
                saveIconLabel
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(saveStatus == .saving)
            #else
            Button {
                if let urlStr = message.imageUrl, let url = URL(string: urlStr) {
                    Task { await self.saveImage(from: url) }
                }
            } label: {
                saveIconLabel
            }
            .buttonStyle(.plain)
            .disabled(saveStatus == .saving)
            #endif
        }
    }

    private var downloadFileButton: some View {
        Button {
            guard let urlString = message.fileUrl, let url = URL(string: urlString) else { return }
            Task { await openFile(from: url, suggestedFileName: fileName) }
        } label: {
            saveIconLabel
        }
        .buttonStyle(.plain)
        .disabled(saveStatus == .saving)
    }

    private var saveIconLabel: some View {
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
            .foregroundStyle(Color.secondary.opacity(0.85))
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
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif
    }

    private func copyImage(from url: URL) {
        Task {
            do {
                var request = URLRequest(url: url)
                if let token = APIClient.shared.token {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, _) = try await URLSession.shared.data(for: request)
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
            var request = URLRequest(url: url)
            if let token = APIClient.shared.token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: request)
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
            try SettingsManager.shared.withSecurityScopedAccess(to: defaultURL) {
                try data.write(to: fileURL, options: .atomic)
            }
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
            alert.addButton(withTitle: String(localized: "message_bubble.save_as", bundle: .main))
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                await saveImageAs(from: url)
                return
            }
            #endif
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }

    private func openFile(from url: URL, suggestedFileName: String) async {
        saveStatus = .saving
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: suggestedFileName)
            #if os(iOS)
            presentShareSheet(for: localURL)
            #elseif os(macOS)
            NSWorkspace.shared.open(localURL)
            #endif
            withAnimation { saveStatus = .success }
        } catch {
            print("Open file failed: \(error)")
            saveStatus = .error
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
        try await downloadToLocalFile(url: url, suggestedFileName: url.lastPathComponent)
    }

    private func downloadToLocalFile(url: URL, suggestedFileName: String) async throws -> URL {
        var request = URLRequest(url: url)
        if let token = APIClient.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFileName)
        try data.write(to: tempURL)
        return tempURL
    }

    private func saveImageAs(from url: URL) async {
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: url.lastPathComponent)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent
            panel.title = String(localized: "message_bubble.save_as", bundle: .main)
            panel.prompt = String(localized: "common.save", bundle: .main)
            panel.canCreateDirectories = true
            if let defaultDirectory = SettingsManager.shared.macOSDefaultSavePath {
                panel.directoryURL = defaultDirectory
            }

            if panel.runModal() == .OK, let saveURL = panel.url {
                let parentURL = saveURL.deletingLastPathComponent()
                SettingsManager.shared.setMacOSDefaultSavePath(parentURL)
                try SettingsManager.shared.withSecurityScopedAccess(to: parentURL) {
                    try FileManager.default.copyItem(at: localURL, to: saveURL)
                }
                NSWorkspace.shared.activateFileViewerSelecting([saveURL])
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

    private func saveFileAs(from url: URL, suggestedFileName: String) async {
        do {
            let localURL = try await downloadToLocalFile(url: url, suggestedFileName: suggestedFileName)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFileName
            panel.title = String(localized: "message_bubble.save_as", bundle: .main)
            panel.prompt = String(localized: "common.save", bundle: .main)
            panel.canCreateDirectories = true
            if let defaultDirectory = SettingsManager.shared.macOSDefaultSavePath {
                panel.directoryURL = defaultDirectory
            }

            if panel.runModal() == .OK, let saveURL = panel.url {
                let parentURL = saveURL.deletingLastPathComponent()
                SettingsManager.shared.setMacOSDefaultSavePath(parentURL)
                try SettingsManager.shared.withSecurityScopedAccess(to: parentURL) {
                    try? FileManager.default.removeItem(at: saveURL)
                    try FileManager.default.copyItem(at: localURL, to: saveURL)
                }
                NSWorkspace.shared.activateFileViewerSelecting([saveURL])
                withAnimation { saveStatus = .success }
            }
        } catch {
            print("Save File As failed: \(error)")
            saveStatus = .error
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = .none
        }
    }
    #endif

    #if os(iOS)
    private func downloadToLocalFile(url: URL, suggestedFileName: String) async throws -> URL {
        var request = URLRequest(url: url)
        if let token = APIClient.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFileName)
        try? FileManager.default.removeItem(at: tempURL)
        try data.write(to: tempURL)
        return tempURL
    }

    private func presentShareSheet(for url: URL) {
        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return }

        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(activity, animated: true)
    }
    #endif
}

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
