import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct FeedbackAttachment: Identifiable, Equatable {
    let id = UUID()
    let data: Data
}

struct FeedbackComposerView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss

    @State private var content = ""
    @State private var email = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachments: [FeedbackAttachment] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didAttemptEmailSeed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    feedbackSectionTitle("feedback.content_title")
                    feedbackTextEditor

                    feedbackSectionTitle("feedback.images_title")
                    imageAttachmentSection

                    feedbackSectionTitle("feedback.email_title")
                    emailField

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle(String(localized: "feedback.title", bundle: .main))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submitFeedback() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("feedback.submit", bundle: .main)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .task {
                await seedEmailIfNeeded()
            }
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 520, idealHeight: 620)
    }

    private var feedbackTextEditor: some View {
        ZStack(alignment: .topLeading) {
            #if os(macOS)
            MacFeedbackTextEditor(text: $content)
                .frame(height: 180)
            #else
            TextEditor(text: $content)
                .frame(minHeight: 180)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            #endif

            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("feedback.content_placeholder", bundle: .main)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(editorBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var imageAttachmentSection: some View {
        let currentAttachments = attachments
        let currentRemainingAttachmentSlots = remainingAttachmentSlots
        let currentEditorBackground = editorBackground

        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: currentRemainingAttachmentSlots,
                matching: .images
            ) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                    Text(currentAttachments.isEmpty ? String(localized: "feedback.add_images", bundle: .main) : String(localized: "feedback.add_more_images", bundle: .main))
                }
                .font(.body.weight(.medium))
                .foregroundStyle(currentRemainingAttachmentSlots > 0 ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(currentEditorBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(currentRemainingAttachmentSlots == 0 || isSubmitting)
            .onChange(of: photoItems) { items in
                guard !items.isEmpty else { return }
                Task { await loadSelectedPhotos(items) }
            }

            if !attachments.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                    ForEach(attachments) { attachment in
                        attachmentPreview(attachment)
                    }
                }
            }

            Text(String(format: String(localized: "feedback.images_limit", bundle: .main), attachments.count, 3))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func attachmentPreview(_ attachment: FeedbackAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = platformImage(from: attachment.data) {
                    platformImageView(from: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(height: 88)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    private var emailField: some View {
        Group {
            #if os(iOS)
            TextField(String(localized: "feedback.email_placeholder", bundle: .main), text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
            #else
            TextField("", text: $email, prompt: Text("feedback.email_placeholder", bundle: .main).foregroundColor(.secondary))
                .textFieldStyle(.plain)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(editorBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var canSubmit: Bool {
        !trimmedContent.isEmpty && isValidEmail(trimmedEmail) && !isSubmitting
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var remainingAttachmentSlots: Int {
        max(0, 3 - attachments.count)
    }

    private var editorBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }

    @ViewBuilder
    private func feedbackSectionTitle(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.headline)
    }

    private func seedEmailIfNeeded() async {
        guard !didAttemptEmailSeed else { return }
        didAttemptEmailSeed = true

        if email.isEmpty, let storedEmail = api.currentUserEmail, !storedEmail.isEmpty {
            email = storedEmail
            return
        }

        guard email.isEmpty, api.isAuthenticated else { return }

        do {
            _ = try await api.getAccessStatus()
        } catch {
            return
        }

        if email.isEmpty, let storedEmail = api.currentUserEmail, !storedEmail.isEmpty {
            email = storedEmail
        }
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        let slots = remainingAttachmentSlots
        guard slots > 0 else {
            photoItems = []
            return
        }

        for item in items.prefix(slots) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                attachments.append(FeedbackAttachment(data: data))
            }
        }

        photoItems = []
    }

    private func submitFeedback() async {
        errorMessage = nil

        guard !trimmedContent.isEmpty else {
            errorMessage = String(localized: "feedback.error_content_required", bundle: .main)
            return
        }

        guard trimmedContent.count <= 2000 else {
            errorMessage = String(format: String(localized: "feedback.error_content_too_long", bundle: .main), 2000)
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = String(localized: "feedback.error_email_required", bundle: .main)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await api.submitFeedback(
                content: trimmedContent,
                email: trimmedEmail,
                imageDatas: attachments.map(\.data)
            )
            NotificationCenter.default.post(name: .syncaFeedbackSubmitted, object: nil)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "feedback.submit_failed", bundle: .main)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Notification.Name {
    static let syncaFeedbackSubmitted = Notification.Name("syncaFeedbackSubmitted")
}

#if os(macOS)
private struct MacFeedbackTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.textColor
        textView.insertionPointColor = NSColor.textColor
        textView.typingAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            NSAttributedString.Key.foregroundColor: NSColor.textColor,
        ]
        textView.textContainerInset = NSSize(width: 12, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.updateLayout(for: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.typingAttributes = [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                NSAttributedString.Key.foregroundColor: NSColor.textColor,
            ]
        }
        context.coordinator.updateLayout(for: textView, in: scrollView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            if let scrollView = textView.enclosingScrollView {
                updateLayout(for: textView, in: scrollView)
            }
        }

        @MainActor
        func updateLayout(for textView: NSTextView, in scrollView: NSScrollView) {
            let contentWidth = max(0, scrollView.contentSize.width)
            textView.textContainer?.containerSize = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)

            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = max(layoutManager.usedRect(for: textContainer).height, 0)
            let targetHeight = max(scrollView.contentSize.height, ceil(usedHeight + textView.textContainerInset.height * 2))
            textView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: targetHeight)
        }
    }
}
#endif

#if canImport(UIKit)
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif

private func platformImage(from data: Data) -> PlatformImage? {
    PlatformImage(data: data)
}

private func platformImageView(from image: PlatformImage) -> Image {
    #if canImport(UIKit)
    return Image(uiImage: image)
    #else
    return Image(nsImage: image)
    #endif
}
