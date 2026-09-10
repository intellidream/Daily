import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

public struct GlassButtonStyle: ButtonStyle {
    public enum Variant {
        case primary
        case secondary
        case destructive
        case plain
    }
    
    public var variant: Variant
    public var cornerRadius: CGFloat
    
    public init(variant: Variant = .secondary, cornerRadius: CGFloat = 12) {
        self.variant = variant
        self.cornerRadius = cornerRadius
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                background(isPressed: configuration.isPressed)
            }
            .overlay {
                border
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && SettingsService.shared.settings.hapticsEnabled {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            }
    }
    
    @ViewBuilder
    private func background(isPressed: Bool) -> some View {
        switch variant {
        case .primary:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
                .opacity(isPressed ? 0.85 : 1.0)
        case .secondary:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(isPressed ? 0.22 : 0.14))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .destructive:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ThemeColors.error.opacity(isPressed ? 0.35 : 0.22))
        case .plain:
            Color.clear
        }
    }
    
    @ViewBuilder
    private var border: some View {
        if variant == .secondary {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ThemeColors.glassDarkBorder, lineWidth: 1)
        } else if variant == .destructive {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(ThemeColors.error.opacity(0.4), lineWidth: 1)
        }
    }
}
