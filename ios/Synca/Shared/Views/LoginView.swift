import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @StateObject private var authService = AuthService.shared
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo area
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)

                Text("Synca")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text("跨端灵感同步")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Sign in button
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
                    HStack(spacing: 8) {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18))
                        Text("通过 Apple 登录")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(authService.isSigningIn)

                if authService.isSigningIn {
                    ProgressView()
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #endif
        .alert("登录失败", isPresented: $showError) {
            Button("好的") {}
        } message: {
            Text(authService.errorMessage ?? "请稍后重试")
        }
    }
}
