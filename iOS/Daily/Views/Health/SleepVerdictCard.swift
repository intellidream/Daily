import SwiftUI
import DailyCore

/// Dedicated card presenting the biological sleep recovery verdict and physical/cognitive readiness.
public struct SleepVerdictCard: View {
    public let verdict: SleepRecoveryVerdict
    
    public init(verdict: SleepRecoveryVerdict) {
        self.verdict = verdict
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header & Readiness Badge
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: verdict.status.systemIcon)
                            .foregroundColor(Color(hex: verdict.status.hexColor))
                            .font(.system(size: 13, weight: .bold))
                        Text(verdict.status.displayName.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(Color(hex: verdict.status.hexColor))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(hex: verdict.status.hexColor).opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(hex: verdict.status.hexColor).opacity(0.3), lineWidth: 1)
                    )
                    
                    Spacer()
                    
                    // Energy / Readiness Score Pill
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("\(verdict.readinessScore)% Readiness")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                }
                
                // Headline
                Text(verdict.headline)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Narrative Synthesis
                Text(verdict.narrative)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // 3 Recovery Pillars
                HStack(spacing: 12) {
                    pillarItem(title: "Physical Repair", rating: verdict.physicalRepairRating, icon: "figure.strengthtraining.traditional")
                    pillarItem(title: "Cognitive Rest", rating: verdict.cognitiveRestoreRating, icon: "brain.head.profile")
                    pillarItem(title: "Continuity", rating: verdict.sleepContinuityRating, icon: "waveform.path.ecg")
                }
            }
        }
    }
    
    private func pillarItem(title: String, rating: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(pillarColor(for: rating))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Text(rating)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(pillarColor(for: rating))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func pillarColor(for rating: String) -> Color {
        switch rating.lowercased() {
        case "high", "continuous":
            return ThemeColors.accentCyan
        case "adequate":
            return Color(hex: "#00E676") // Green
        default:
            return Color(hex: "#FFB300") // Amber
        }
    }
}
