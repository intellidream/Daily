import SwiftUI
import DailyCore

public struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var settingsService = SettingsService.shared
    
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var useLiveMaterial: Bool
    
    public init(cornerRadius: CGFloat = 16, padding: CGFloat = 16, useLiveMaterial: Bool = false) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.useLiveMaterial = useLiveMaterial
    }
    
    private var isDark: Bool {
        switch settingsService.settings.theme {
        case .system: return systemColorScheme == .dark
        case .dark: return true
        case .light: return false
        }
    }
    
    private var fillOpacity: Double {
        let intensity = settingsService.settings.glassIntensity.blurOpacity
        return isDark ? intensity : intensity * 0.8
    }
    
    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                if useLiveMaterial {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            isDark
                            ? Color.white.opacity(fillOpacity)
                            : Color.black.opacity(fillOpacity)
                        )
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(
                                    isDark ? ThemeColors.glassDarkBorder : ThemeColors.glassLightBorder,
                                    lineWidth: 1
                                )
                        }
                        .shadow(
                            color: isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.08),
                            radius: 12,
                            x: 0,
                            y: 6
                        )
                } else {
                    // High-performance Acrylic Glass Surface (Zero offscreen blurs, 120 FPS hardware-composited)
                    ZStack {
                        // Base dark/light tinted acrylic foundation
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                isDark
                                ? Color(hex: "080F1E").opacity(0.72)
                                : Color.white.opacity(0.85)
                            )
                        
                        // Specular translucent surface wash matching user's glass intensity setting
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                    ? [Color.white.opacity(fillOpacity * 0.75), Color.white.opacity(fillOpacity * 0.35)]
                                    : [Color.black.opacity(fillOpacity * 0.08), Color.black.opacity(fillOpacity * 0.02)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                isDark ? ThemeColors.glassDarkBorder : ThemeColors.glassLightBorder,
                                lineWidth: 1
                            )
                    }
                    // Direct vector shape shadow (CoreAnimation hardware shadow path without offscreen rasterization)
                    .shadow(
                        color: isDark ? Color.black.opacity(0.28) : Color.black.opacity(0.06),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                }
            }
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, padding: CGFloat = 16, useLiveMaterial: Bool = false) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, padding: padding, useLiveMaterial: useLiveMaterial))
    }
}

public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let useLiveMaterial: Bool
    private let content: Content
    
    public init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        useLiveMaterial: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.useLiveMaterial = useLiveMaterial
        self.content = content()
    }
    
    public var body: some View {
        content
            .liquidGlass(cornerRadius: cornerRadius, padding: padding, useLiveMaterial: useLiveMaterial)
    }
}
