import SwiftUI
import DailyCore
import AppKit

public struct GlassButtonStyle: ButtonStyle {
    public enum Variant {
        case primary
        case secondary
        case destructive
        case plain
    }
    
    public var variant: Variant
    public var cornerRadius: CGFloat
    
    @State private var isHovered: Bool = false
    
    public init(variant: Variant = .secondary, cornerRadius: CGFloat = 12) {
        self.variant = variant
        self.cornerRadius = cornerRadius
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                background(isPressed: configuration.isPressed)
            }
            .overlay {
                border
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && SettingsService.shared.settings.hapticsEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
            }
    }
    
    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch variant {
        case .primary:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
                .opacity(isPressed ? 0.8 : (isHovered ? 0.95 : 0.9))
                .shadow(color: ThemeColors.accentCyan.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 8 : 4, x: 0, y: 2)
        case .secondary:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isPressed ? 0.25 : (isHovered ? 0.20 : 0.14)))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .destructive:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ThemeColors.error.opacity(isPressed ? 0.40 : (isHovered ? 0.32 : 0.22)))
        case .plain:
            Color.clear
        }
    }
    
    @ViewBuilder
    private var border: some View {
        if variant == .secondary {
            if isHovered {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1)
            }
        } else if variant == .destructive {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ThemeColors.error.opacity(isHovered ? 0.6 : 0.4), lineWidth: 1)
        }
    }
}
