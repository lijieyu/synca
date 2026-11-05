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
    private static let textLimit = 2000

    init(message: SyncaMessage) {
        self.message = message
        _draft = State(initialValue: message.textContent ?? "")
    }

    private var hasChanges: Bool { draft != (message.textContent ?? "") }
    private var canSave: Bool {
        hasChanges && !isSaving && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.utf16.count <= Self.textLimit
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $draft)
                    .font(.body)
                    .focused($isFocused)
                    .accessibilityLabel(Text("message_edit.content"))
                    .disabled(isSaving)
                    .frame(minHeight: 180)
                Text("\(draft.utf16.count) / \(Self.textLimit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(draft.utf16.count > Self.textLimit ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(16)
            .navigationTitle(Text("message_edit.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { cancel() }.disabled(isSaving)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().accessibilityLabel(Text("message_edit.saving")) }
                        else { Text("common.save") }
                    }
                    .disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
            .confirmationDialog("message_edit.discard_title", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("message_edit.discard", role: .destructive) { dismiss() }
                Button("message_edit.keep", role: .cancel) { }
            }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 340, idealHeight: 420)
        #endif
        .onAppear { isFocused = true }
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
            announce(String(localized: "message_edit.saved"), success: true)
            dismiss()
        } catch {
            let message: String
            switch error {
            case APIError.textEditConflict, APIError.textEditUnavailable: message = error.localizedDescription
            default: message = String(localized: "message_edit.failed")
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
