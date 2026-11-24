#if os(iOS)
import SwiftUI
import UIKit

struct EmailLoginView: View {
    var binding = false
    var onBound: (LoginMethods) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model: EmailAuthModel
    @State private var operation: Task<Void, Never>?
    @State private var showHelp = false
    @FocusState private var focused: Field?
    private enum Field { case email, code }

    init(binding: Bool = false, onBound: @escaping (LoginMethods) -> Void = { _ in }) {
        self.binding = binding; self.onBound = onBound
        // Binding belongs to the session that opened the form, never a later login.
        let session = APIClient.shared.token
        _model = StateObject(wrappedValue: EmailAuthModel(send: { email in
            if binding, APIClient.shared.token != session { throw CancellationError() }
            return try await APIClient.shared.sendEmailCode(email: email, binding: binding)
        }, verify: { challenge, code in
            guard APIClient.shared.token == session else { throw CancellationError() }
            if binding {
                let result = try await APIClient.shared.bindEmail(challengeId: challenge, code: code)
                guard APIClient.shared.token == session else { throw CancellationError() }
                return .bound(result)
            }
            let result = try await APIClient.shared.verifyEmailCode(challengeId: challenge, code: code,
                deviceId: UIDevice.current.identifierForVendor?.uuidString)
            guard APIClient.shared.token == session else { throw CancellationError() }
            return .signedIn(result)
        }))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(model.hasChallenge ? "email_auth.check_code" : binding ? "email_auth.add_email" : "email_auth.email_title")
                    .font(.title.bold()).accessibilityAddTraits(.isHeader)
                if model.hasChallenge { codeFields } else { emailFields }
                if let error = model.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("email-error")
                }
                Button(action: submit) {
                    HStack(spacing: 10) {
                        if model.isBusy { ProgressView().tint(scheme == .dark ? .black : .white) }
                        Text(model.isBusy ? (model.isSending ? "email_auth.sending" : "email_auth.verifying") : (model.hasChallenge ? (binding ? "email_auth.verify_bind" : "email_auth.login") : "email_auth.send"))
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(scheme == .dark ? .black : .white)
                    .background(scheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy || (model.hasChallenge && !model.canVerify) || (!model.hasChallenge && model.resendSeconds > 0))
                .opacity(model.isBusy || (model.hasChallenge && !model.canVerify) ? 0.5 : 1)
                .accessibilityIdentifier("email-submit")
                if model.hasChallenge {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        HStack {
                            Button {
                                operation = Task { await model.sendCode() }
                            } label: {
                                Text(model.resendSeconds > 0 ? String(format: String(syncaLocalized: "email_auth.resend_wait"), model.resendSeconds) : String(syncaLocalized: "email_auth.resend"))
                            }
                            .disabled(model.isBusy || model.resendSeconds > 0)
                            .accessibilityIdentifier("email-resend")
                            Spacer(minLength: 12)
                            Button("email_auth.help") { showHelp = true }
                        }.font(.subheadline).frame(minHeight: 44)
                    }
                } else {
                    if binding {
                        Text("email_auth.bind_description")
                            .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else { legalLinks }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if model.resendSeconds > 0 {
                            Text(String(format: String(syncaLocalized: "email_auth.resend_wait"), model.resendSeconds))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
        .toolbar {
            if !binding { ToolbarItem(placement: .cancellationAction) { Button("common.close") { operation?.cancel(); model.cancel(); dismiss() } } }
        }
        .alert(Text("email_auth.help"), isPresented: $showHelp) {
            Button("common.ok", role: .cancel) {}
        } message: { Text("email_auth.help_text") }
        .onChange(of: model.hasChallenge) { hasChallenge in
            focused = hasChallenge ? .code : .email
        }
        .onChange(of: model.challenge?.challengeId) { value in
            if value != nil { announce(String(syncaLocalized: "email_auth.sent_to") + " " + model.sentEmail, success: true) }
        }
        .onChange(of: model.errorMessage) { value in if let value { announce(value, success: false) } }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in model.objectWillChange.send() }
        .onDisappear { operation?.cancel(); model.cancel() }
    }

    private var emailFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("email_auth.email").font(.subheadline)
            TextField("email_auth.email", text: $model.email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).onSubmit { if !model.isBusy { submit() } }
                .focused($focused, equals: .email)
                .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .disabled(model.isBusy).accessibilityIdentifier("email-address")
        }
    }
    private var codeFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("email_auth.sent_to").foregroundStyle(.secondary)
                Text(model.sentEmail).textSelection(.enabled)
            }.font(.callout)
            Button("email_auth.change_email") {
                operation?.cancel(); model.changeEmail()
            }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("email-change")
            TextField("email_auth.code", text: $model.code)
                .textContentType(.oneTimeCode).keyboardType(.numberPad).focused($focused, equals: .code)
                .font(.title2.monospacedDigit()).padding(14)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: model.code) { value in
                    let clean = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                    if clean != value { model.code = clean }
                }
                .disabled(model.isBusy).accessibilityIdentifier("email-code")
        }
    }
    private var legalLinks: some View {
        Text(signupAgreement)
            .font(.footnote).foregroundStyle(.secondary).tint(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("email-signup-agreement")
    }

    private var signupAgreement: AttributedString {
        // One localized paragraph; links wrap naturally with the surrounding copy.
        let format = String(syncaLocalized: "email_auth.signup_agreement")
        let terms = String(syncaLocalized: "access.terms_link_title")
        let privacy = String(syncaLocalized: "access.privacy_policy_link_title")
        var paragraph = AttributedString(String(format: format, terms, privacy))
        for (title, url) in [(terms, AppLinks.termsOfUseURL), (privacy, AppLinks.privacyPolicyURL)] {
            if let range = paragraph.range(of: title) {
                paragraph[range].link = url
                paragraph[range].underlineStyle = .single
            }
        }
        return paragraph
    }
    private func submit() {
        guard !model.isBusy else { return }
        focused = nil
        operation = Task {
            if model.hasChallenge {
                await model.verifyCode { result in
                    switch result {
                    case .signedIn(let response): AuthService.shared.completeLogin(response)
                    case .bound(let methods):
                        APIClient.shared.setCurrentUserEmail(methods.email)
                        onBound(methods); dismiss()
                    }
                    announce(AppLocalization.string(binding ? "email_auth.bound" : "email_auth.logged_in"), success: true)
                }
            } else { await model.sendCode() }
        }
    }
    private func announce(_ text: String, success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
#endif
