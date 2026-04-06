import AuthenticationServices
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published var isSigningIn = false
    @Published var errorMessage: String?

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func signInWithApple() async throws -> AuthResponse {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        let authorization = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorization, Error>) in
            self.continuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            #if os(macOS)
            controller.presentationContextProvider = self
            #endif
            
            // Using a standard Task on @MainActor instead of detached helps keep the context 
            // synchronized with the UI while still allowing the call to be asynchronous.
            Task {
                controller.performRequests()
            }
        }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.missingCredentials
        }

        let deviceId: String?
        #if os(iOS)
        deviceId = UIDevice.current.identifierForVendor?.uuidString
        #else
        deviceId = nil
        #endif

        let response = try await APIClient.shared.loginWithApple(
            idToken: idToken,
            deviceId: deviceId
        )

        APIClient.shared.setToken(response.token, userId: response.user.id)
        APIClient.shared.setCurrentUserEmail(response.user.email)
        AccessManager.shared.apply(response.accessStatus)
        await PushTokenManager.shared.uploadCachedTokenIfPossible()
        _ = try? await PurchaseManager.shared.syncLatestTransactions()

        return response
    }

    func signOut() {
        APIClient.shared.clearToken()
        PushTokenManager.shared.clearUploadedSessionMarker()
        AccessManager.shared.clear()
    }
}

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

#if os(macOS)
extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}
#endif

enum AuthError: LocalizedError {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return String(localized: "auth.missing_credentials", bundle: .main)
        }
    }
}
