import SwiftUI
import DailyCore

public struct AccountSettingsSection: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var showSignOutConfirmation: Bool = false
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Account")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                if let profile = authService.currentUser {
                    HStack(spacing: 14) {
                        // Avatar View with glowing border
                        ZStack {
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 54, height: 54)
                            
                            if let avatarUrl = profile.avatarUrl, let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .clipShape(Circle())
                                    default:
                                        defaultAvatarCircle(profile: profile)
                                    }
                                }
                            } else {
                                defaultAvatarCircle(profile: profile)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.fullName ?? "Hi, \(profile.firstName)!")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            if let email = profile.email {
                                Text(email)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            } else if profile.provider == .guest {
                                Text("Guest Mode (Local Only)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ThemeColors.warning)
                            }
                            
                            // Provider badge
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(profile.provider == .guest ? ThemeColors.warning : ThemeColors.success)
                                    .frame(width: 6, height: 6)
                                Text(profile.provider.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .padding(.top, 2)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.15))
                    
                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(profile.provider == .guest ? "Sign In with an Account" : "Sign Out")
                        }
                        .foregroundColor(profile.provider == .guest ? ThemeColors.accentBlue : ThemeColors.error)
                    }
                    .buttonStyle(GlassButtonStyle(variant: profile.provider == .guest ? .secondary : .destructive, cornerRadius: 10))
                    .confirmationDialog("Are you sure you want to sign out?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                        Button(profile.provider == .guest ? "Exit Guest Mode" : "Sign Out", role: .destructive) {
                            Task {
                                await authService.signOut()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func defaultAvatarCircle(profile: UserProfile) -> some View {
        Circle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 48, height: 48)
            .overlay {
                Text(String(profile.firstName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
    }
}
