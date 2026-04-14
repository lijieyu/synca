import SwiftUI
import AuthenticationServices

#if os(iOS)
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#elseif os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

/// A cross-platform native wrapper for ASAuthorizationAppleIDButton.
/// The standard SwiftUI SignInWithAppleButton often fails to render its background/border on macOS.
struct AppleSignInButton: PlatformViewRepresentable {
    var isEnabled: Bool
    var colorScheme: ColorScheme
    var onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    #if os(iOS)
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: appleButtonStyle)
        button.cornerRadius = 14
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.isEnabled = isEnabled
    }
    #elseif os(macOS)
    func makeNSView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: appleButtonStyle)
        button.cornerRadius = 14
        button.target = context.coordinator
        button.action = #selector(Coordinator.tapped)
        return button
    }

    func updateNSView(_ nsView: ASAuthorizationAppleIDButton, context: Context) {
        nsView.isEnabled = isEnabled
    }
    #endif

    private var appleButtonStyle: ASAuthorizationAppleIDButton.Style {
        // HIG: Use .white in dark mode, .black in light mode for maximum contrast and clear boundaries.
        colorScheme == .dark ? .white : .black
    }

    class Coordinator: NSObject {
        var onCompletion: (Result<ASAuthorization, Error>) -> Void

        init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        @objc func tapped() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            #if os(macOS)
            controller.presentationContextProvider = self
            #endif
            controller.performRequests()
        }
    }
}

extension AppleSignInButton.Coordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }
}

#if os(macOS)
extension AppleSignInButton.Coordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}
#endif
