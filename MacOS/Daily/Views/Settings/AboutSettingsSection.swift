import SwiftUI
import DailyCore

public struct AboutSettingsSection: View {
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 10, x: 0, y: 4)
                
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
