import SwiftUI
import DailyCore
import AuthenticationServices
import CryptoKit

public struct LoginView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var currentAppleNonce: String?
    
    public init() {}
    
    public var body: some View {
        LiquidGlassBackground {
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                
                // Header Branding matching WinUI
                VStack(spacing: 4) {
                    // Gem / Sparkle App Icon
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        ThemeColors.accentCyan.opacity(0.35),
                                        ThemeColors.accentBlue.opacity(0.1),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 6,
                                    endRadius: 36
                                )
                            )
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .padding(.bottom, 2)
                    
                    Text("DayOne")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Your personal dashboard")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                .padding(.bottom, 24)
                
                // Translucent Liquid Glass Login Card
                GlassCard(cornerRadius: 20, padding: 20) {
                    VStack(spacing: 16) {
                        VStack(spacing: 4) {
                            Text("Welcome")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Sign in to sync your data across devices")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(ThemeColors.fgMutedDark)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                        
                        if authService.isLoading {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .tint(ThemeColors.accentCyan)
                                    .scaleEffect(1.1)
                                
                                Text(authService.statusMessage.isEmpty ? "Connecting..." : authService.statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .frame(height: 90)
                        } else {
                            VStack(spacing: 10) {
                                // 1. Google Sign-In Button (matching WinUI style)
                                Button {
                                    triggerGoogleSignIn()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "g.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(ThemeColors.accentBlue)
                                        
                                        Text("Sign in with Google")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.black)
                                    }
                                }
                                .buttonStyle(GlassButtonStyle(variant: .primary, cornerRadius: 12))
                                
                                // 2. Sign in with Apple Button (Native iOS & Supabase Auth)
                                SignInWithAppleButton(.signIn) { request in
                                    let nonce = randomNonceString()
                                    currentAppleNonce = nonce
                                    request.requestedScopes = [.fullName, .email]
                                    request.nonce = sha256(nonce)
                                } onCompletion: { result in
                                    handleAppleSignInResult(result)
                                }
                                .signInWithAppleButtonStyle(.white)
                                .frame(height: 48)
                                .cornerRadius(12)
                            }
                        }
                        
                        // Error message
                        if let error = authService.errorMessage {
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ThemeColors.error)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // Skip Button (matching WinUI SkipButton_Click)
                Button {
                    authService.continueAsGuest()
                } label: {
                    Text("Continue without signing in")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(ThemeColors.fgMutedDark)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .disabled(authService.isLoading)
                
                Spacer(minLength: 20)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Handlers
    
    private func triggerGoogleSignIn() {
        #if canImport(UIKit)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootWindow = windowScene.windows.first else {
            return
        }
        
        Task {
            _ = await authService.signInWithGoogle(presentationAnchor: rootWindow)
        }
        #endif
    }
    
    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let idTokenData = appleIDCredential.identityToken,
                  let idTokenString = String(data: idTokenData, encoding: .utf8),
                  let nonce = currentAppleNonce else {
                return
            }
            
            Task {
                _ = await authService.signInWithApple(
                    idToken: idTokenString,
                    nonce: nonce,
                    fullName: appleIDCredential.fullName
                )
            }
            
        case .failure(let error):
            print("[LoginView] Apple Sign In failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Crypto Nonce Utilities for Apple Sign-In
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
