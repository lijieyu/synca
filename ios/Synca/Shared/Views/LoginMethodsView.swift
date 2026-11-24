#if os(iOS)
import SwiftUI
import AuthenticationServices
import UIKit

struct LoginMethodsView: View {
    @State private var methods: LoginMethods?
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var operation: Task<Void, Never>?
    @State private var authorizer = AppleBindingAuthorization()
    @State private var window: UIWindow?
    private let session = APIClient.shared.token

    var body: some View {
        Form {
            Section {
                if let methods {
                    HStack {
                        Label("Apple", systemImage: "apple.logo")
                        Spacer(minLength: 16)
                        if methods.apple { Text("email_auth.linked").foregroundStyle(.secondary) }
                        else {
                            Button("email_auth.bind", action: bindApple)
                                .disabled(isBusy).accessibilityLabel(Text("email_auth.bind") + Text(" Apple"))
                                .accessibilityIdentifier("bind-apple")
                        }
                    }.frame(minHeight: 32)
                    if let email = methods.email {
                        HStack(spacing: 16) {
                            Label("email_auth.email_label", systemImage: "envelope")
                                .labelStyle(.titleAndIcon)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                            Text(email).font(.subheadline).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                .accessibilityLabel(email)
                        }.frame(minHeight: 32)
                    } else {
                        NavigationLink {
                            EmailLoginView(binding: true) { result in
                                self.methods = result
                            }
                        } label: {
                            HStack {
                                Label("email_auth.email_label", systemImage: "envelope")
                                Spacer(minLength: 16)
                                Text("email_auth.bind").foregroundStyle(.secondary)
                            }
                        }.disabled(isBusy).accessibilityIdentifier("bind-email")
                    }
                } else if !isBusy && errorMessage != nil {
                    Button("email_auth.retry") { load() }
                } else { ProgressView().accessibilityLabel(Text("email_auth.loading")) }
            } footer: { Text("email_auth.methods_hint") }
            if isBusy && methods != nil {
                Section { ProgressView("email_auth.apple_wait") }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            }
        }
        .navigationTitle(Text("email_auth.methods"))
        .navigationBarTitleDisplayMode(.inline).tint(.primary)
        .background(BindingWindowReader { window = $0 }.frame(width: 0, height: 0))
        .onAppear { load() }
        .onDisappear { operation?.cancel(); authorizer.cancel() }
    }

    private func load() {
        operation?.cancel()
        operation = Task {
            isBusy = true; errorMessage = nil
            defer { if !Task.isCancelled { isBusy = false } }
            do {
                guard APIClient.shared.token == session else { return }
                let result = try await APIClient.shared.getLoginMethods()
                guard !Task.isCancelled, APIClient.shared.token == session else { return }
                methods = result
            } catch { show(error) }
        }
    }
    private func bindApple() {
        guard !isBusy else { return }
        operation = Task {
            isBusy = true; errorMessage = nil
            defer { if !Task.isCancelled { isBusy = false } }
            do {
                guard APIClient.shared.token == session else { return }
                let challenge = try await APIClient.shared.appleBindingChallenge()
                try Task.checkCancellation()
                guard APIClient.shared.token == session else { return }
                let idToken = try await authorizer.authorize(nonce: challenge.nonce, window: window)
                try Task.checkCancellation()
                guard APIClient.shared.token == session else { return }
                let result = try await APIClient.shared.bindApple(challengeId: challenge.challengeId, idToken: idToken)
                guard !Task.isCancelled, APIClient.shared.token == session else { return }
                methodsChanged(result)
            } catch { show(error, apple: true) }
        }
    }
    private func methodsChanged(_ value: LoginMethods) {
        methods = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: String(syncaLocalized: "email_auth.bound"))
    }
    private func show(_ error: Error, apple: Bool = false) {
        guard !Task.isCancelled, APIClient.shared.token == session, !(error is CancellationError) else { return }
        let nsError = error as NSError
        guard !(nsError.domain == ASAuthorizationErrorDomain && nsError.code == ASAuthorizationError.canceled.rawValue) else { return }
        if apple, let failure = error as? EmailAuthFailure, ["invalid_code", "code_expired"].contains(failure.code) {
            errorMessage = String(syncaLocalized: "email_auth.errors.apple_auth_failed")
        } else { errorMessage = (error as? EmailAuthFailure)?.localizedDescription ?? String(syncaLocalized: "email_auth.errors.generic") }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIAccessibility.post(notification: .announcement, argument: errorMessage)
    }
}

/// A separate authorization request: binding must never call the Apple login/session replacement path.
@MainActor final class AppleBindingAuthorization: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<String, Error>?
    private var anchor: UIWindow?
    private var requestID = UUID()
    private let performRequests: (ASAuthorizationController) -> Void
    init(performRequests: @escaping (ASAuthorizationController) -> Void = { $0.performRequests() }) {
        self.performRequests = performRequests
        super.init()
    }

    func authorize(nonce: String, window: UIWindow?) async throws -> String {
        guard continuation == nil, let window else { throw EmailAuthFailure(code: "apple_auth_failed") }
        let identifier = UUID(); requestID = identifier
        anchor = window
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.email]
                request.nonce = nonce
                let controller = ASAuthorizationController(authorizationRequests: [request])
                self.controller = controller
                controller.delegate = self; controller.presentationContextProvider = self
                performRequests(controller)
            }
        } onCancel: { Task { @MainActor in if self.requestID == identifier { self.cancel() } } }
    }
    func cancel() {
        requestID = UUID()
        let pending = continuation; continuation = nil
        let active = controller; controller = nil; anchor = nil; active?.cancel()
        pending?.resume(throwing: CancellationError())
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor ?? UIWindow() }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        let pending = continuation; continuation = nil; self.controller = nil; anchor = nil
        guard let credentials = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credentials.identityToken, let token = String(data: data, encoding: .utf8) else {
            pending?.resume(throwing: AuthError.missingCredentials); return
        }
        pending?.resume(returning: token)
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard controller === self.controller else { return }
        let pending = continuation; continuation = nil; self.controller = nil; anchor = nil
        pending?.resume(throwing: error)
    }
}
private struct BindingWindowReader: UIViewRepresentable {
    var onWindow: (UIWindow?) -> Void
    func makeUIView(context: Context) -> WindowView {
        let view = WindowView(); view.onWindow = onWindow; return view
    }
    func updateUIView(_ view: WindowView, context: Context) { view.onWindow = onWindow }
    final class WindowView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            let current = window
            DispatchQueue.main.async { [weak self] in self?.onWindow?(current) }
        }
    }
}
#endif
