import SwiftUI
import DailyCore

public struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var settingsService = SettingsService.shared
    
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    
    public init(cornerRadius: CGFloat = 16, padding: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        self.padding = padding
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
            }
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
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content
    
    public init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    public var body: some View {
        content
            .liquidGlass(cornerRadius: cornerRadius, padding: padding)
    }
}
