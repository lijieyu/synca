import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AccountSheet: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accessManager: AccessManager

    @State private var contentHeight: CGFloat = 400
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let accountEmail: String?
    let onDeleteAccount: () async throws -> Void
    let onLogout: () -> Void
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteSuccess = false
    @State private var deleteError: String?
    @State private var isDeletingAccount = false

    private var normalizedAccountEmail: String? {
        let trimmed = accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isPrivateRelayEmail: Bool {
        guard let normalizedAccountEmail else { return false }
        return normalizedAccountEmail.localizedCaseInsensitiveContains("privaterelay.appleid.com")
    }

    private var resolvedAccountEmail: String {
        normalizedAccountEmail
            ?? String(syncaLocalized: "account.email_unavailable", bundle: .main)
    }

    var body: some View {
        platformContent
            .disabled(isDeletingAccount)
            .interactiveDismissDisabled(isDeletingAccount)
            #if os(iOS)
            .navigationBarBackButtonHidden(isDeletingAccount)
            #endif
            .overlay {
                if isDeletingAccount { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .alert("message_list.logout_confirm_title", isPresented: $showLogoutConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("message_list.logout", role: .destructive, action: onLogout)
            } message: { Text("message_list.logout_confirm_message") }
            .alert("account.delete_confirm_title", isPresented: $showDeleteConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("account.delete_action", role: .destructive) { deleteAccount() }
            } message: { Text("account.delete_confirm_message") }
            .alert("account.delete_success_title", isPresented: $showDeleteSuccess) {
                Button("common.ok", action: onLogout)
            } message: { Text("account.delete_success_message") }
            .alert("account.delete_failed_title", isPresented: Binding(
                get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
            )) {
                Button("common.ok", role: .cancel) { deleteError = nil }
            } message: { Text(deleteError ?? String(syncaLocalized: "account.delete_failed_message")) }
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        Task { @MainActor in
            defer { isDeletingAccount = false }
            do {
                try await onDeleteAccount()
                showDeleteSuccess = true
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                #endif
            } catch {
                deleteError = (error as? LocalizedError)?.errorDescription
                    ?? String(syncaLocalized: "account.delete_failed_message")
                #if os(iOS)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                #endif
            }
        }
    }

    @ViewBuilder private var platformContent: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "account.and_plan")
            Divider()
            sheetContent

        }
        .frame(width: min(480, (NSScreen.main?.visibleFrame.width ?? 580) - 80), height: min(contentHeight + 57, (NSScreen.main?.visibleFrame.height ?? 860) - 100))

        #else
        if embedded { iosAccountContent } else {
        NavigationStack {
            iosAccountContent
                .navigationTitle(Text("account.and_plan"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { closeButton }
                }
        }
        .presentationDetents([.medium, .large])
        }
        #endif
    }

    #if os(iOS)
    private var iosAccountContent: some View {
        Form {
            Section {
                NavigationLink {
                    LoginMethodsView()
                } label: { Text("email_auth.methods") }
                .accessibilityIdentifier("account-login-methods")
                NavigationLink {
                    ScrollView { AccessCenterView(embedded: true).padding(20) }
                        .navigationTitle(accessManager.status?.unlimitedSource == "lifetime" || accessManager.status?.unlimitedSource == "subscription" ? String(syncaLocalized: "access.center_title") : "").navigationBarTitleDisplayMode(.inline)
                } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("account.current_plan")
                                Spacer(minLength: 12)
                                iosPlanName
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("account.current_plan")
                                iosPlanName
                            }
                        }
                        if let storage = accessManager.status?.storage {
                            VStack(alignment: .leading, spacing: 8) {
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        Text("storage.used")
                                        Spacer(minLength: 8)
                                        storageUsage(storage)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("storage.used")
                                        storageUsage(storage)
                                    }
                                }.font(.caption).foregroundStyle(.secondary)
                                ProgressView(value: Double(min(max(0, storage.usedBytes), storage.limitBytes)), total: Double(max(1, storage.limitBytes)))
                                    .tint(.secondary).accessibilityHidden(true)
                            }
                        }
                    }.padding(.vertical, 6)
                }
                .accessibilityIdentifier("account-plan")
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(resolvedAccountEmail).font(.headline).foregroundStyle(.primary)
                        .textSelection(.enabled)
                    if isPrivateRelayEmail {
                        Label("account.email_hidden_title", systemImage: "eye.slash")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.textCase(nil).padding(.bottom, 8)
            }
            Section {
                Button("message_list.sign_out") {
                    showLogoutConfirm = true
                }
                    .foregroundStyle(.primary).accessibilityIdentifier("account-signout")
                Button("account.delete_action", role: .destructive) {
                    showDeleteConfirm = true
                }
                    .accessibilityIdentifier("account-delete")
            }
        }
    }
    private func storageUsage(_ storage: StorageAllowance) -> some View {
        Text("\(ByteCountFormatter.string(fromByteCount: storage.usedBytes, countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: storage.limitBytes, countStyle: .binary))")
            .monospacedDigit()
    }
    @ViewBuilder
    private var iosPlanName: some View {
        if let status = accessManager.status {
            Text(status.isUnlimited ? "access.pro_name" : "access.free_title")
                .foregroundStyle(.secondary)
        }
    }
    #endif

    private var closeButton: some View {
        Button("common.close") { dismiss() }
            #if os(macOS)
            .buttonStyle(.bordered)
            .foregroundStyle(.primary)
            .keyboardShortcut(.cancelAction)
            #endif
    }

    private var sheetContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(resolvedAccountEmail)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                .textSelection(.enabled).multilineTextAlignment(.leading)
                            if let status = accessManager.status {
                                Text(status.isUnlimited ? "access.pro_name" : "access.free_title")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if isPrivateRelayEmail {
                                Label("account.email_hidden_title", systemImage: "eye.slash.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    if let storage = accessManager.status?.storage {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("storage.used")
                                Spacer(minLength: 8)
                                Text("\(ByteCountFormatter.string(fromByteCount: storage.usedBytes, countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: storage.limitBytes, countStyle: .binary))")
                                    .monospacedDigit()
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: Double(min(max(0, storage.usedBytes), storage.limitBytes)), total: Double(max(1, storage.limitBytes)))
                                .accessibilityHidden(true)
                        }.accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                AccessCenterView(embedded: true)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { accountActions }
                    VStack(alignment: .trailing, spacing: 12) { accountActions }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
            })
        }
        .scrollIndicators(.hidden)
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
    }

    @ViewBuilder
    private var accountActions: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Text("account.delete_action").foregroundStyle(.red).frame(minHeight: 44)
        }
        .buttonStyle(.plain)

        Button {
            showLogoutConfirm = true
        } label: {
            Text("message_list.sign_out").frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
