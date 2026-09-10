import SwiftUI
import DailyCore

/// Signature Liquid Glass User Header banner displaying date, greeting, interactive avatar, and quick access.
public struct HeaderGreetingView: View {
    @ObservedObject private var authService = AuthService.shared
    private let onAvatarTapped: () -> Void
    
    public init(onAvatarTapped: @escaping () -> Void = {}) {
        self.onAvatarTapped = onAvatarTapped
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 22, padding: 16) {
            HStack(alignment: .center, spacing: 14) {
                // Interactive Glass Avatar Button
                Button {
                    onAvatarTapped()
                } label: {
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
                            .frame(width: 46, height: 46)
                        
                        if let avatarUrl = authService.currentUser?.avatarUrl, let url = URL(string: avatarUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable()
                                        .scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(Circle())
                                default:
                                    defaultAvatarGlyph
                                }
                            }
                        } else {
                            defaultAvatarGlyph
                        }
                    }
                    .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                // Greeting & Calendar Context
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                        .tracking(0.8)
                    
                    let firstName = authService.currentUser?.firstName ?? "Friend"
                    Text("Hi, \(firstName)!")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Spacer()

                // Quick Settings Action Button
                Button {
                    onAvatarTapped()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var defaultAvatarGlyph: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [ThemeColors.accentBlue.opacity(0.4), ThemeColors.accentCyan.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 42, height: 42)
            .overlay {
                let initial = String(authService.currentUser?.firstName.prefix(1) ?? "G").uppercased()
                Text(initial)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
    }
}
