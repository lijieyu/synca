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

                Text("灵感记录 即刻同步")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tracking(0.3)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    Task {
                        do {
                            _ = try await authService.signInWithApple()
                        } catch {
                            if (error as NSError).code != 1001 { // User cancelled
                                authService.errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    }
                } label: {
                    ZStack {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("通过 Apple 登录")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .opacity(authService.isSigningIn ? 0 : 1)

                        if authService.isSigningIn {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(signInForegroundColor)
                        }
                    }
                    .foregroundStyle(signInForegroundColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(signInBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(signInBorderColor, lineWidth: colorScheme == .dark ? 1 : 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(authService.isSigningIn)
                .opacity(authService.isSigningIn ? 0.92 : 1)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .background(backgroundColor.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 420)
        #endif
        .alert("登录失败", isPresented: $showError) {
            Button("好的") {}
        } message: {
            Text(authService.errorMessage ?? "请稍后重试")
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

    private var signInBackgroundColor: Color {
        .black
    }

    private var signInForegroundColor: Color {
        colorScheme == .dark ? .white : .white
    }

    private var signInBorderColor: Color {
        .clear
    }
}
