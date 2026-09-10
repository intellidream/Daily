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
                            Text("Habits & Daily Intake")
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
                
                // Live Metrics Dual Tile (Bubbles + Smokes)
                HStack(spacing: 16) {
                    // Water Metric
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HYDRATION (BUBBLES)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(Int(habitsService.totalWaterMlToday))")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("/ \(Int(habitsService.waterGoalMl)) ml")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    Divider()
                        .frame(height: 32)
                        .background(Color.white.opacity(0.15))
                    
                    // Smokes Metric
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SMOKES TODAY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(habitsService.totalSmokesToday)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(habitsService.totalSmokesToday <= habitsService.smokesBaselineCount ? Color(hex: "#00FFB2") : Color(hex: "#FF3B30"))
                            Text("/ \(habitsService.smokesBaselineCount) max")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                
                // Quick Add Glass Action Chips
                HStack(spacing: 8) {
                    Button {
                        triggerHaptic()
                        habitsService.logWater(amountMl: 150, drink: "Water")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 10))
                            Text("+150ml")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ThemeColors.accentCyan.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        triggerHaptic()
                        habitsService.logWater(amountMl: 300, drink: "Water")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 10))
                            Text("+300ml")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(ThemeColors.accentCyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(ThemeColors.accentCyan.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button {
                        triggerHaptic()
                        habitsService.logSmoke(type: "Cigarette")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                            Text("+1 Smoke")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#FFB800"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#FFB800").opacity(0.12))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(Color(hex: "#FFB800").opacity(0.3), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
