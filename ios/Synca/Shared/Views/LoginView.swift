import SwiftUI
import AuthenticationServices
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct LoginView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showError = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image("LoginLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 8)

                Text("Synca")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text("app.slogan", bundle: .main)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
            }

            Spacer()

            VStack(spacing: 16) {
                AppleSignInButton(
                    isEnabled: !authService.isSigningIn,
                    colorScheme: colorScheme,
                    onCompletion: { result in
                        Task {
                            switch result {
                            case .success(let authorization):
                                do {
                                    _ = try await authService.handleAuthorization(authorization)
                                } catch {
                                    let nsError = error as NSError
                                    // ASAuthorizationError.canceled = 1001
                                    if nsError.domain == ASAuthorizationErrorDomain && nsError.code == 1001 {
                                        return
                                    }
                                    authService.errorMessage = error.localizedDescription
                                    showError = true
                                }
                            case .failure(let error):
                                let nsError = error as NSError
                                if nsError.domain == ASAuthorizationErrorDomain && nsError.code == 1001 {
                                    // User cancelled
                                } else {
                                    authService.errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        }
                    }
                )
                .id(colorScheme) // Ensure native component recreates on color scheme change
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .background(backgroundColor.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 420)
        #endif
        .alert(Text("login.failed", bundle: .main), isPresented: $showError) {
            Button("common.ok") {}
        } message: {
            Text(authService.errorMessage ?? String(localized: "login.failed_message"))
        }
    }

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return .black
        }
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}
