import SwiftUI
import DailyCore

/// Signature DayOne background rendering a rich vertical gradient with subtle radial glow highlights.
public struct LiquidGlassBackground<Content: View>: View {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var settingsService = SettingsService.shared
    
    private let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    private var isDark: Bool {
        switch settingsService.settings.theme {
        case .system: return systemColorScheme == .dark
        case .dark: return true
        case .light: return false
        }
    }
    
    public var body: some View {
        ZStack {
            if isDark {
                // Multi-stop deep vertical gradient
                LinearGradient(
                    stops: [
                        .init(color: ThemeColors.bgStop0, location: 0.0),
                        .init(color: ThemeColors.bgStop1, location: 0.35),
                        .init(color: ThemeColors.bgStop2, location: 0.65),
                        .init(color: ThemeColors.bgStop3, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Ambient radial glow matching WinUI LoginGlow
                RadialGradient(
                    colors: [
                        ThemeColors.accentBlue.opacity(0.14),
                        ThemeColors.accentCyan.opacity(0.04),
                        Color.clear
                    ],
                    center: .init(x: 0.5, y: 0.25),
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()
                .blendMode(.screen)
                
            } else {
                // Light mode warm sand paper tint
                ThemeColors.lightBgColor.ignoresSafeArea()
                
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.6),
                        Color.clear
                    ],
                    center: .init(x: 0.5, y: 0.25),
                    startRadius: 40,
                    endRadius: 320
                )
                .ignoresSafeArea()
            }
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
