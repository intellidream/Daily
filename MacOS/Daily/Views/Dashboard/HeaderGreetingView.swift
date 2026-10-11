import SwiftUI
import DailyCore

/// Signature Liquid Glass User Header banner displaying date, greeting, interactive avatar, and quick access.
public struct HeaderGreetingView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var briefingService = SmartBriefingService.shared
    private let onAvatarTapped: () -> Void
    private let onCustomizeTapped: (() -> Void)?
    private let onBriefingTapped: (() -> Void)?
    
    @State private var isPulsingAura: Bool = false
    @State private var isBriefingPulsing: Bool = false
    
    public init(
        onAvatarTapped: @escaping () -> Void = {},
        onCustomizeTapped: (() -> Void)? = nil,
        onBriefingTapped: (() -> Void)? = nil
    ) {
        self.onAvatarTapped = onAvatarTapped
        self.onCustomizeTapped = onCustomizeTapped
        self.onBriefingTapped = onBriefingTapped
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
    
    private var formattedDate: String {
        Self.dateFormatter.string(from: Date())
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Interactive Glass Avatar Button with glow and live status dot
            Button {
                triggerHaptic()
                onAvatarTapped()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [ThemeColors.accentCyan, ThemeColors.accentBlue, ThemeColors.accentPurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 48, height: 48)
                        
                        if let avatarUrl = authService.currentUser?.avatarUrl, let url = URL(string: avatarUrl) {
                            CachedAsyncImage(url: url) { image in
                                image.resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                            } placeholder: {
                                defaultAvatarGlyph
                            }
                        } else {
                            defaultAvatarGlyph
                        }
                    }
                    .shadow(color: ThemeColors.accentCyan.opacity(0.4), radius: 10, x: 0, y: 2)
                    
                    // Live Sync Status Dot
                    Circle()
                        .fill(ThemeColors.success)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(hex: "030609"), lineWidth: 2))
                        .shadow(color: ThemeColors.success.opacity(0.8), radius: 3)
                        .offset(x: 1, y: 1)
                }
            }
            .buttonStyle(.plain)

            // Greeting & Calendar Context (Tapping triggers Smart Briefing)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    // Micro date badge pill
                    HStack(spacing: 4) {
                        Circle()
                            .fill(ThemeColors.accentCyan)
                            .frame(width: 4.5, height: 4.5)
                            .shadow(color: ThemeColors.accentCyan, radius: 2)
                        
                        Text(formattedDate.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(ThemeColors.accentCyan.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(ThemeColors.accentCyan.opacity(0.25), lineWidth: 0.8)
                    )

                    // Ambient Briefing Sparkle Indicator (Pulsing when unread)
                    if onBriefingTapped != nil && briefingService.hasBriefingAvailable {
                        Button {
                            triggerHaptic()
                            briefingService.markBriefingAsRead()
                            onBriefingTapped?()
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                                .shadow(
                                    color: ThemeColors.accentCyan.opacity(briefingService.hasUnreadBrief ? (isBriefingPulsing ? 0.95 : 0.3) : 0.2),
                                    radius: briefingService.hasUnreadBrief && isBriefingPulsing ? 8 : 2
                                )
                                .scaleEffect(briefingService.hasUnreadBrief && isBriefingPulsing ? 1.18 : 1.0)
                                .opacity(briefingService.hasUnreadBrief ? 1.0 : 0.8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                let firstName = authService.currentUser?.firstName ?? "Friend"
                Text("Hi, \(firstName)!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let onBriefing = onBriefingTapped {
                    triggerHaptic()
                    briefingService.markBriefingAsRead()
                    onBriefing()
                }
            }
            
            Spacer()
                .contentShape(Rectangle())
                .onTapGesture {
                    if let onBriefing = onBriefingTapped {
                        triggerHaptic()
                        briefingService.markBriefingAsRead()
                        onBriefing()
                    }
                }

            HStack(spacing: 8) {
                // Customize Dashboard Action Button
                if let onCustomize = onCustomizeTapped {
                    Button {
                        triggerHaptic()
                        onCustomize()
                    } label: {
                        Image(systemName: "slider.horizontal.2.square")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color(hex: "080F1E").opacity(0.72))
                                    .overlay(Circle().fill(Color.white.opacity(0.08)))
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                // Quick Settings Action Button with Glass styling
                Button {
                    triggerHaptic()
                    onAvatarTapped()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(hex: "080F1E").opacity(0.72))
                                .overlay(Circle().fill(Color.white.opacity(0.08)))
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            heroGlassBackdrop
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            if let onBriefing = onBriefingTapped {
                triggerHaptic()
                briefingService.markBriefingAsRead()
                onBriefing()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isBriefingPulsing = true
            }
        }
    }
    
    private var heroGlassBackdrop: some View {
        ZStack {
            // 1. Acrylic dark glass base
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: "080F1E").opacity(0.75))
            
            // 2. Translucent aurora mesh wash (cyan to indigo to violet aura)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: ThemeColors.accentCyan.opacity(0.14), location: 0.0),
                            .init(color: ThemeColors.accentBlue.opacity(0.08), location: 0.45),
                            .init(color: ThemeColors.glowPurple.opacity(0.07), location: 0.85),
                            .init(color: Color.white.opacity(0.03), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 3. Subtle radial specular glow centered near avatar with gentle ambient breathing
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            ThemeColors.accentCyan.opacity(briefingService.hasUnreadBrief ? (isBriefingPulsing ? 0.32 : 0.16) : (isPulsingAura ? 0.25 : 0.14)),
                            ThemeColors.accentBlue.opacity(briefingService.hasUnreadBrief ? (isBriefingPulsing ? 0.14 : 0.05) : (isPulsingAura ? 0.09 : 0.03)),
                            Color.clear
                        ],
                        center: .init(x: 0.15, y: 0.35),
                        startRadius: 10,
                        endRadius: 150
                    )
                )
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: isPulsingAura)
        }
        .onAppear {
            isPulsingAura = true
        }
        .overlay {
            // 4. Specular multi-stop glowing glass border
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: briefingService.hasUnreadBrief && isBriefingPulsing ? ThemeColors.accentCyan.opacity(0.85) : Color.white.opacity(0.55), location: 0.0),
                            .init(color: ThemeColors.accentCyan.opacity(briefingService.hasUnreadBrief && isBriefingPulsing ? 0.75 : 0.45), location: 0.3),
                            .init(color: ThemeColors.accentBlue.opacity(0.25), location: 0.6),
                            .init(color: Color.white.opacity(0.12), location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: briefingService.hasUnreadBrief && isBriefingPulsing ? 1.5 : 1.2
                )
        }
        .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 5)
        .shadow(color: ThemeColors.accentCyan.opacity(0.10), radius: 16, x: 0, y: 6)
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }
    
    private var defaultAvatarGlyph: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [ThemeColors.accentBlue.opacity(0.5), ThemeColors.accentCyan.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 44, height: 44)
            .overlay {
                let initial = String(authService.currentUser?.firstName.prefix(1) ?? "G").uppercased()
                Text(initial)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
    }
}
