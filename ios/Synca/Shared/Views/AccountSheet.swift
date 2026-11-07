import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss

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
        .frame(width: 480, height: min(760, (NSScreen.main?.visibleFrame.height ?? 860) - 100))

        #else
        NavigationStack {
            sheetContent
                .navigationTitle(Text("account.and_plan"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { closeButton }
                }
        }
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
                    HStack(alignment: .top, spacing: 14) {
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
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .multilineTextAlignment(.leading)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                AccessCenterView(embedded: true)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 16) {
                    Button(role: .destructive) {
                        runAfterDismiss(onRequestDeleteAccount)
                    } label: {
                        accountActionRow(
                            title: String(syncaLocalized: "account.delete_action", bundle: .main),
                            systemImage: "person.crop.circle.badge.xmark",
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        runAfterDismiss(onRequestLogout)
                    } label: {
                        accountActionRow(
                            title: String(syncaLocalized: "message_list.sign_out", bundle: .main),
                            systemImage: "rectangle.portrait.and.arrow.right",
                            tint: .primary
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func accountActionRow(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)

            Spacer(minLength: 0)

        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
