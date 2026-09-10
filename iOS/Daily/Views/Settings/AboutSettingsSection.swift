import SwiftUI
import DailyCore

public struct AboutSettingsSection: View {
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [ThemeColors.accentCyan.opacity(0.3), ThemeColors.accentBlue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [ThemeColors.accentCyan, ThemeColors.accentBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("DayOne for iOS")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Native Dashboard & Ambient Glass Experience")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    Text("Version 1.0.0")
                    Text("•")
                    Text("Build 2026.1")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ThemeColors.fgMutedDark.opacity(0.7))
                
                Text("© 2026 IntellIdream inc. All rights reserved.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(ThemeColors.fgMutedDark.opacity(0.5))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
