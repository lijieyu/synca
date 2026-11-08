import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MessageTextEditorView: View {
    let message: SyncaMessage
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDiscardConfirmation = false
    @FocusState private var isFocused: Bool
    private static let textLimit = MessageTextPolicy.maximumCharacters

    init(message: SyncaMessage) {
        self.message = message
        _draft = State(initialValue: message.textContent ?? "")
    }

    private var hasChanges: Bool { draft != (message.textContent ?? "") }
    private var canSave: Bool {
        hasChanges && !isSaving && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.count <= Self.textLimit
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "message_edit.title", onClose: cancel)
                .disabled(isSaving)
            Divider()
            editorContent.padding(20)
            Divider()
            HStack(spacing: 8) {
                Spacer()
                cancelButton
                saveButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 420, idealWidth: 520, minHeight: 340, idealHeight: 420)
        .modifier(discardConfirmation)
        .interactiveDismissDisabled(hasChanges || isSaving)
        #else
        NavigationStack {
            editorContent
                .padding(16)
                .navigationTitle(Text("message_edit.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { saveButton }
                }
                .modifier(discardConfirmation)
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .onAppear { isFocused = true }
        #endif
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
            MacPlainTextEditor(text: $draft, isEditable: !isSaving, focusesOnAppear: true, horizontalTextInset: 0)
                .accessibilityLabel(Text("message_edit.content"))
                .frame(minHeight: 180)
            #else
            TextEditor(text: $draft)
                .font(.body)
                .focused($isFocused)
                .accessibilityLabel(Text("message_edit.content"))
                .disabled(isSaving)
                .frame(minHeight: 180)
            #endif
            Text("\(draft.count) / \(Self.textLimit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(draft.count > Self.textLimit ? Color.red : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(errorMessage)
            }
        }
    }

    private var cancelButton: some View {
        Button("common.cancel", role: .cancel) { cancel() }
            .disabled(isSaving)
            #if os(macOS)
            .buttonStyle(.bordered)
            .foregroundStyle(.primary)
            #endif
            .keyboardShortcut(.cancelAction)
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            if isSaving { ProgressView().accessibilityLabel(Text("message_edit.saving")) }
            else { Text("common.save") }
        }
        .disabled(!canSave)
        .tint(.syncaPurple)
        #if os(macOS)
        .buttonStyle(MacPrimaryActionButtonStyle())
        #endif
        .keyboardShortcut("s", modifiers: .command)
    }

    private var discardConfirmation: some ViewModifier {
        TextEditDiscardConfirmation(isPresented: $showDiscardConfirmation, onDiscard: { dismiss() })
    }

    private func cancel() {
        guard !isSaving else { return }
        if hasChanges { showDiscardConfirmation = true } else { dismiss() }
    }

    @MainActor private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SyncManager.shared.updateMessageText(message, textContent: draft)
            announce(String(syncaLocalized: "message_edit.saved"), success: true)
            dismiss()
        } catch {
            let message: String
            switch error {
            case APIError.textEditConflict, APIError.textEditUnavailable: message = error.localizedDescription
            default: message = String(syncaLocalized: "message_edit.failed")
            }
            errorMessage = message
            announce(message, success: false)
        }
    }

    @MainActor private func announce(_ message: String, success: Bool) {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        UIAccessibility.post(notification: .announcement, argument: message)
        #elseif os(macOS)
        NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        #endif
    }
}

private struct TextEditDiscardConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let onDiscard: () -> Void
    func body(content: Content) -> some View {
        content.confirmationDialog("message_edit.discard_title", isPresented: $isPresented, titleVisibility: .visible) {
            Button("message_edit.discard", role: .destructive, action: onDiscard)
            Button("message_edit.keep", role: .cancel) { }
        }
    }
}

#if os(macOS)
/// Explicit content-aligned sheet titles avoid the navigation toolbar's leading reserved space.
struct MacSheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.close"))
            .help(Text("common.close"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Keep the primary action identifiable when macOS renders an inactive sheet.
struct MacPrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                isEnabled ? Color.syncaPurple : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .opacity(configuration.isPressed && isEnabled ? 0.8 : 1)
    }
}
#endif
