import SwiftUI
import DailyCore

/// Dedicated card presenting clinical, evidence-based sleep hygiene tips tailored to the current session.
public struct SleepAdviceCard: View {
    public let tips: [SleepActionableTip]
    
    public init(tips: [SleepActionableTip]) {
        self.tips = tips
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#FFD600"))
                    Text("ACTIONABLE SLEEP HYGIENE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    Spacer()
                    Text("AASM Clinical Science")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                // Tips List
                VStack(spacing: 12) {
                    ForEach(tips) { tip in
                        tipRow(tip: tip)
                    }
                }
            }
        }
    }
    
    private func tipRow(tip: SleepActionableTip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Category Icon Badge
            Image(systemName: tip.category.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: tip.category.hexColor))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color(hex: tip.category.hexColor).opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tip.category.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: tip.category.hexColor))
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text(tip.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Text(tip.advice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(tip.scientificRationale)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
