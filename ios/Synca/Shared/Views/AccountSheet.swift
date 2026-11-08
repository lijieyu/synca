import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss

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
        NavigationStack {
            sheetContent
                .navigationTitle(Text("account.and_plan"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { closeButton }
                }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + 60), .large])
        #endif
    }

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
                        #if os(macOS)
                        Image(systemName: "person.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                        #else
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                        #endif

                        VStack(alignment: .leading, spacing: 4) {

                            if isPrivateRelayEmail {
                                Label {
                                    Text("account.email_hidden_title", bundle: .main)
                                } icon: {
                                    Image(systemName: "eye.slash.fill")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            } else {
                                Text(resolvedAccountEmail)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                }
                .padding(.vertical, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Divider() }

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
