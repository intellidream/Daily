import SwiftUI
import DailyCore
import AppKit

/// Sleek desktop navigation header for the secondary/detail pane when an embedded Hub is active
/// in macOS Dual-Pane Workspace mode.
public struct FoldableDetailHeaderBar: View {
    public let title: String
    public let iconName: String
    public let onReturnToCoPilot: () -> Void
    
    public init(
        title: String,
        iconName: String,
        onReturnToCoPilot: @escaping () -> Void
    ) {
        self.title = title
        self.iconName = iconName
        self.onReturnToCoPilot = onReturnToCoPilot
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    onReturnToCoPilot()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Co-Pilot Overview")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(ThemeColors.accentCyan.opacity(0.12))
                        .overlay(
                            Capsule().stroke(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .help("Return to Co-Pilot Overview (Esc)")
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(ThemeColors.accentBlue)
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(Color.white.opacity(0.7))
            }
            
            Spacer()
            
            Button(action: {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    onReturnToCoPilot()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Close Hub (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
