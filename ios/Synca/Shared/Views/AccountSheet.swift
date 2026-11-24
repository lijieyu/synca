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
    let onRequestDeleteAccount: () -> Void
    let onRequestLogout: () -> Void

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

    private func runAfterDismiss(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }

    var body: some View {
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(resolvedAccountEmail).font(.headline).textSelection(.enabled)
                    if isPrivateRelayEmail {
                        Label("account.email_hidden_title", systemImage: "eye.slash")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            Section {
                NavigationLink {
                    ScrollView { AccessCenterView(embedded: true).padding(20) }
                        .navigationTitle("access.center_title").navigationBarTitleDisplayMode(.inline)
                } label: {
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
                }
                .accessibilityIdentifier("account-plan")
            }
            if let storage = accessManager.status?.storage {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("storage.used").font(.subheadline)
                        Text("\(ByteCountFormatter.string(fromByteCount: storage.usedBytes, countStyle: .binary)) / \(ByteCountFormatter.string(fromByteCount: storage.limitBytes, countStyle: .binary))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        ProgressView(value: Double(min(max(0, storage.usedBytes), storage.limitBytes)), total: Double(max(1, storage.limitBytes)))
                            .accessibilityHidden(true)
                    }.padding(.vertical, 4).accessibilityElement(children: .combine)
                }
            }
            Section {
                Button("message_list.sign_out") {
                    if embedded { onRequestLogout() } else { runAfterDismiss(onRequestLogout) }
                }
                    .foregroundStyle(.primary).accessibilityIdentifier("account-signout")
            }
            Section {
                Button("account.delete_action", role: .destructive) {
                    if embedded { onRequestDeleteAccount() } else { runAfterDismiss(onRequestDeleteAccount) }
                }
                    .accessibilityIdentifier("account-delete")
            }
        }
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
            runAfterDismiss(onRequestDeleteAccount)
        } label: {
            Text("account.delete_action").foregroundStyle(.red).frame(minHeight: 44)
        }
        .buttonStyle(.plain)

        Button {
            runAfterDismiss(onRequestLogout)
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
