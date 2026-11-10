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

    @State private var contentHeight: CGFloat = 400
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var content = ""
    @State private var email = ""
    @State private var initialEmail = ""
    @State private var showDiscardConfirmation = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachments: [FeedbackAttachment] = []
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didAttemptEmailSeed = false

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                MacSheetHeader(title: "feedback.title", onClose: cancel)
                    .disabled(isSubmitting)
                Divider()
                feedbackContent.disabled(isSubmitting)
                Divider()
                HStack(spacing: 8) {
                    Spacer()
                    cancelButton
                    submitButton
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            #else
            NavigationStack {
                feedbackContent
                    .disabled(isSubmitting)
                    .navigationTitle(String(syncaLocalized: "feedback.title", bundle: .main))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { cancelButton }
                        ToolbarItem(placement: .confirmationAction) { submitButton }
                    }
            }
            #endif
        }
        .task { await seedEmailIfNeeded() }
        .interactiveDismissDisabled(hasChanges || isSubmitting)
        .confirmationDialog("feedback.discard_title", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("feedback.discard", role: .destructive) { dismiss() }
            Button("feedback.keep_editing", role: .cancel) { }
        }
        #if os(macOS)
        .frame(width: min(480, (NSScreen.main?.visibleFrame.width ?? 580) - 80), height: min(contentHeight + 125, (NSScreen.main?.visibleFrame.height ?? 860) - 100))
        #else
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + 60), .large])
        #endif
    }

    private var feedbackContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    feedbackSectionTitle("feedback.content_title")
                    feedbackTextEditor
                }
                VStack(alignment: .leading, spacing: 8) {
                    feedbackSectionTitle("feedback.images_title")
                    imageAttachmentSection
                }
                VStack(alignment: .leading, spacing: 8) {
                    feedbackSectionTitle("feedback.email_title")
                    emailField
                }
                DeveloperSocialLink(title: "developer_social.contact")
                    .padding(.top, 4)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(20)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
            })
        }
        .scrollIndicators(.hidden)
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
    }

    private var cancelButton: some View {
        Button("common.cancel", action: cancel)
            .disabled(isSubmitting)
            #if os(macOS)
            .buttonStyle(.bordered)
            .foregroundStyle(.primary)
            .keyboardShortcut(.cancelAction)
            #endif
    }

    private var submitButton: some View {
        Button { Task { await submitFeedback() } } label: {
            if isSubmitting { ProgressView().controlSize(.small) }
            else { Text("feedback.submit", bundle: .main).fontWeight(.semibold) }
        }
        .disabled(!canSubmit)
        #if os(macOS)
        .buttonStyle(MacPrimaryActionButtonStyle())
        #endif
    }

    private var feedbackTextEditor: some View {
        ZStack(alignment: .topLeading) {
            #if os(macOS)
            MacPlainTextEditor(text: $content)
                .frame(height: 150)
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
                    Text(currentAttachments.isEmpty ? String(syncaLocalized: "feedback.add_images", bundle: .main) : String(syncaLocalized: "feedback.add_more_images", bundle: .main))
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

            Text(String(format: String(syncaLocalized: "feedback.images_limit", bundle: .main), attachments.count, 3))
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
            TextField(String(syncaLocalized: "feedback.email_placeholder", bundle: .main), text: $email)
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

    private var hasChanges: Bool {
        !content.isEmpty || email != initialEmail || !attachments.isEmpty || !photoItems.isEmpty
    }

    private func cancel() {
        guard !isSubmitting else { return }
        if hasChanges { showDiscardConfirmation = true } else { dismiss() }
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
            initialEmail = storedEmail
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
            initialEmail = storedEmail
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
        guard !isSubmitting else { return }
        errorMessage = nil

        guard !trimmedContent.isEmpty else {
            errorMessage = String(syncaLocalized: "feedback.error_content_required", bundle: .main)
            return
        }

        guard trimmedContent.count <= 2000 else {
            errorMessage = String(format: String(syncaLocalized: "feedback.error_content_too_long", bundle: .main), 2000)
            return
        }

        guard isValidEmail(trimmedEmail) else {
            errorMessage = String(syncaLocalized: "feedback.error_email_required", bundle: .main)
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await api.submitFeedback(
                content: trimmedContent,
                email: trimmedEmail,
                imageDatas: attachments.map(\.data),
                deviceModel: DeviceInfo.displayModelName,
                osVersion: DeviceInfo.osVersionString,
                appVersion: DeviceInfo.appVersionString
            )
            NotificationCenter.default.post(name: .syncaFeedbackSubmitted, object: nil)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(syncaLocalized: "feedback.submit_failed", bundle: .main)
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return email.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}



#if os(macOS)
struct MacPlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable = true
    var focusesOnAppear = false
    var horizontalTextInset: CGFloat = 12
    var verticalTextInset: CGFloat = 16

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = MacPlainTextScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

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
        textView.textContainerInset = NSSize(width: horizontalTextInset, height: verticalTextInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.string = text
        textView.isEditable = isEditable
        if focusesOnAppear {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        scrollView.documentView = textView
        scrollView.updateTextLayout()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.typingAttributes = [
                NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                NSAttributedString.Key.foregroundColor: NSColor.textColor,
            ]
        }
        (scrollView as? MacPlainTextScrollView)?.updateTextLayout()
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
                (scrollView as? MacPlainTextScrollView)?.updateTextLayout()
            }
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

/// A secondary external contact route, shared by About and Feedback on both platforms.
struct DeveloperSocialLink: View {
    let title: LocalizedStringKey

    var body: some View {
        Link(destination: AppLinks.developerProfileURL) {
            HStack(spacing: 12) {
                Text(verbatim: "小红书")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(red: 237 / 255, green: 53 / 255, blue: 75 / 255), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text("developer_social.external"))
    }
}
