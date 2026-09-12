import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Interactive Habits Widget card displayed on the main Dashboard.
public struct HabitsDashboardCard: View {
    public let onTap: () -> Void
    
    @ObservedObject private var habitsService = HabitsService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    public init(onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
    }
    
    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }
    
    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                // Header & Hub Link
                HStack {
                    Button {
                        onTap()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text("Habits & Cravings")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button {
                        onTap()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open Hub")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                // Live Metrics Dual Tile (Bubbles + Smokes) with Progress Rings
                HStack(spacing: 12) {
                    // Bubbles Metric & Ring
                    let waterGoal = max(habitsService.waterGoalMl, 1.0)
                    let waterProgress = min(max(habitsService.totalWaterMlToday / waterGoal, 0.0), 1.0)
                    let isWaterGoalMet = habitsService.totalWaterMlToday >= habitsService.waterGoalMl
                    
                    HStack(spacing: 10) {
                        // Cute Circular Progress Ring
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(waterProgress))
                                .stroke(
                                    LinearGradient(
                                        colors: isWaterGoalMet
                                            ? [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")]
                                            : [ThemeColors.accentCyan, Color(hex: "#0077B6")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .shadow(color: ThemeColors.accentCyan.opacity(waterProgress > 0 ? 0.35 : 0), radius: 3)
                            
                            Image(systemName: isWaterGoalMet ? "checkmark" : "drop.fill")
                                .font(.system(size: isWaterGoalMet ? 12 : 13, weight: .bold))
                                .foregroundColor(isWaterGoalMet ? Color(hex: "#00FFB2") : ThemeColors.accentCyan)
                        }
                        .frame(width: 38, height: 38)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BUBBLES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text("\(Int(habitsService.totalWaterMlToday))")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("/ \(Int(habitsService.waterGoalMl)) ml")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                        .frame(height: 32)
                        .background(Color.white.opacity(0.15))
                    
                    // Smokes Metric & Ring
                    let smokesBaseline = max(Double(habitsService.smokesBaselineCount), 1.0)
                    let smokesProgress = min(max(Double(habitsService.totalSmokesToday) / smokesBaseline, 0.0), 1.0)
                    let isSmokesOverLimit = habitsService.totalSmokesToday > habitsService.smokesBaselineCount
                    let isSmokesWarning = habitsService.totalSmokesToday >= Int(Double(habitsService.smokesBaselineCount) * 0.8)
                    
                    HStack(spacing: 10) {
                        // Cute Circular Progress Ring
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(smokesProgress))
                                .stroke(
                                    LinearGradient(
                                        colors: isSmokesOverLimit
                                            ? [Color(hex: "#FF3B30"), Color(hex: "#FF9500")]
                                            : (isSmokesWarning
                                                ? [Color(hex: "#FFB800"), Color(hex: "#FF9500")]
                                                : [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .shadow(
                                    color: (isSmokesOverLimit ? Color(hex: "#FF3B30") : Color(hex: "#00FFB2")).opacity(smokesProgress > 0 ? 0.35 : 0),
                                    radius: 3
                                )
                            
                            Image(systemName: isSmokesOverLimit ? "exclamationmark" : "flame.fill")
                                .font(.system(size: isSmokesOverLimit ? 12 : 13, weight: .bold))
                                .foregroundColor(
                                    isSmokesOverLimit
                                        ? Color(hex: "#FF3B30")
                                        : (isSmokesWarning ? Color(hex: "#FFB800") : Color(hex: "#00FFB2"))
                                )
                        }
                        .frame(width: 38, height: 38)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SMOKES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text("\(habitsService.totalSmokesToday)")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(
                                        isSmokesOverLimit
                                            ? Color(hex: "#FF3B30")
                                            : (isSmokesWarning ? Color(hex: "#FFB800") : Color(hex: "#00FFB2"))
                                    )
                                Text("/ \(habitsService.smokesBaselineCount) max")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: habitsService.totalWaterMlToday)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: habitsService.totalSmokesToday)
                
                // Quick Add Glass Action Chips (5 Compact Chips)
                HStack(spacing: 6) {
                    // 300 Water
                    Button {
                        triggerHaptic()
                        habitsService.logWater(preset: .largeWater)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9))
                            Text("300")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(ThemeColors.accentCyan.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // 150 Water
                    Button {
                        triggerHaptic()
                        habitsService.logWater(preset: .smallWater)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9))
                            Text("150")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(ThemeColors.accentCyan.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // 100 Coffee
                    Button {
                        triggerHaptic()
                        habitsService.logWater(preset: .coffee)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 9))
                            Text("100")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#F59E0B"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#F59E0B").opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color(hex: "#F59E0B").opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer(minLength: 0)
                    
                    // Cigarette
                    Button {
                        triggerHaptic()
                        habitsService.logSmoke(preset: .cigarette)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                            Text("Cig")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#EF4444"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#EF4444").opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color(hex: "#EF4444").opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Heated
                    Button {
                        triggerHaptic()
                        habitsService.logSmoke(preset: .heated)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("Heat")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#3B82F6"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#3B82F6").opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color(hex: "#3B82F6").opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
