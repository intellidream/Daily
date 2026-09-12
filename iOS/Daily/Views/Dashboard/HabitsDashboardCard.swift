import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Interactive Habits Widget card displayed on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct HabitsDashboardCard: View {
    public let size: DashboardWidgetSize
    public let onTap: () -> Void
    
    @ObservedObject private var habitsService = HabitsService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
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
        GlassCard(cornerRadius: 20, padding: size == .small ? 14 : 18) {
            switch size {
            case .small:
                smallContent
            case .wide:
                wideContent
            case .tall:
                tallContent
            case .large:
                largeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: size == .wide ? nil : .infinity)
    }

    // MARK: - Small (1x1) Compact Habits Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Habits")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button {
                    triggerHaptic()
                    habitsService.logWater(preset: .smallWater)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 8, weight: .bold))
                        Text("150")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(ThemeColors.accentCyan.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            
            Spacer(minLength: 2)

            // Water Progress Row
            let waterGoal = max(habitsService.waterGoalMl, 1.0)
            let waterProgress = min(max(habitsService.totalWaterMlToday / waterGoal, 0.0), 1.0)
            let isWaterGoalMet = habitsService.totalWaterMlToday >= habitsService.waterGoalMl

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 3)
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
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: isWaterGoalMet ? "checkmark" : "drop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isWaterGoalMet ? Color(hex: "#00FFB2") : ThemeColors.accentCyan)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("WATER")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text("\(Int(habitsService.totalWaterMlToday)) ml")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            Spacer(minLength: 2)

            // Smokes Progress Row
            let smokesBaseline = max(Double(habitsService.smokesBaselineCount), 1.0)
            let smokesProgress = min(max(Double(habitsService.totalSmokesToday) / smokesBaseline, 0.0), 1.0)
            let isSmokesOverLimit = habitsService.totalSmokesToday > habitsService.smokesBaselineCount
            let isSmokesWarning = habitsService.totalSmokesToday >= Int(Double(habitsService.smokesBaselineCount) * 0.8)

            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(smokesProgress))
                        .stroke(
                            LinearGradient(
                                colors: isSmokesOverLimit
                                    ? [Color(hex: "#FF3B30"), Color(hex: "#FF9500")]
                                    : (isSmokesWarning ? [Color(hex: "#FFB800"), Color(hex: "#FF9500")] : [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: isSmokesOverLimit ? "exclamationmark" : "flame.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isSmokesOverLimit ? Color(hex: "#FF3B30") : (isSmokesWarning ? Color(hex: "#FFB800") : Color(hex: "#00FFB2")))
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SMOKES")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text("\(habitsService.totalSmokesToday) / \(habitsService.smokesBaselineCount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(isSmokesOverLimit ? Color(hex: "#FF3B30") : .white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Wide (2x1) Standard Dual Ring Card
    @ViewBuilder
    private var wideContent: some View {
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
            
            // Quick Add Action Chips
            HStack(spacing: 6) {
                quickChip(title: "300", icon: "drop.fill", color: ThemeColors.accentCyan) {
                    habitsService.logWater(preset: .largeWater)
                }
                quickChip(title: "150", icon: "drop.fill", color: ThemeColors.accentCyan) {
                    habitsService.logWater(preset: .smallWater)
                }
                quickChip(title: "100", icon: "cup.and.saucer.fill", color: Color(hex: "#F59E0B")) {
                    habitsService.logWater(preset: .coffee)
                }
                
                Spacer(minLength: 0)
                
                quickChip(title: "Cig", icon: "flame.fill", color: Color(hex: "#EF4444")) {
                    habitsService.logSmoke(preset: .cigarette)
                }
                quickChip(title: "Heat", icon: "bolt.fill", color: Color(hex: "#3B82F6")) {
                    habitsService.logSmoke(preset: .heated)
                }
            }
        }
    }

    // MARK: - Tall (1x2) Vertical Habits Tower
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Habits")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ThemeColors.accentCyan)
            }

            // Hydration Section
            let waterGoal = max(habitsService.waterGoalMl, 1.0)
            let waterProgress = min(max(habitsService.totalWaterMlToday / waterGoal, 0.0), 1.0)
            let isWaterGoalMet = habitsService.totalWaterMlToday >= habitsService.waterGoalMl

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(waterProgress))
                        .stroke(
                            LinearGradient(
                                colors: isWaterGoalMet ? [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")] : [ThemeColors.accentCyan, Color(hex: "#0077B6")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: isWaterGoalMet ? "checkmark" : "drop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isWaterGoalMet ? Color(hex: "#00FFB2") : ThemeColors.accentCyan)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BUBBLES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text("\(Int(habitsService.totalWaterMlToday)) ml")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: 6) {
                quickChip(title: "+300", icon: "drop.fill", color: ThemeColors.accentCyan) {
                    habitsService.logWater(preset: .largeWater)
                }
                quickChip(title: "+150", icon: "drop.fill", color: ThemeColors.accentCyan) {
                    habitsService.logWater(preset: .smallWater)
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Smokes Section
            let smokesBaseline = max(Double(habitsService.smokesBaselineCount), 1.0)
            let smokesProgress = min(max(Double(habitsService.totalSmokesToday) / smokesBaseline, 0.0), 1.0)
            let isSmokesOverLimit = habitsService.totalSmokesToday > habitsService.smokesBaselineCount
            let isSmokesWarning = habitsService.totalSmokesToday >= Int(Double(habitsService.smokesBaselineCount) * 0.8)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(smokesProgress))
                        .stroke(
                            LinearGradient(
                                colors: isSmokesOverLimit
                                    ? [Color(hex: "#FF3B30"), Color(hex: "#FF9500")]
                                    : (isSmokesWarning ? [Color(hex: "#FFB800"), Color(hex: "#FF9500")] : [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")]),
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: isSmokesOverLimit ? "exclamationmark" : "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isSmokesOverLimit ? Color(hex: "#FF3B30") : (isSmokesWarning ? Color(hex: "#FFB800") : Color(hex: "#00FFB2")))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SMOKES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Text("\(habitsService.totalSmokesToday) / \(habitsService.smokesBaselineCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(isSmokesOverLimit ? Color(hex: "#FF3B30") : .white)
                }
            }

            HStack(spacing: 6) {
                quickChip(title: "+Cig", icon: "flame.fill", color: Color(hex: "#EF4444")) {
                    habitsService.logSmoke(preset: .cigarette)
                }
                quickChip(title: "+Heat", icon: "bolt.fill", color: Color(hex: "#3B82F6")) {
                    habitsService.logSmoke(preset: .heated)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Extended Habits Management
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Button {
                    onTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("Habits & Performance Hub")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Open Hub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
            }

            // Dual Progress Rings
            HStack(spacing: 20) {
                let waterGoal = max(habitsService.waterGoalMl, 1.0)
                let waterProgress = min(max(habitsService.totalWaterMlToday / waterGoal, 0.0), 1.0)
                let isWaterGoalMet = habitsService.totalWaterMlToday >= habitsService.waterGoalMl

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(waterProgress))
                            .stroke(
                                LinearGradient(
                                    colors: isWaterGoalMet ? [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")] : [ThemeColors.accentCyan, Color(hex: "#0077B6")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Image(systemName: isWaterGoalMet ? "checkmark" : "drop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isWaterGoalMet ? Color(hex: "#00FFB2") : ThemeColors.accentCyan)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("HYDRATION")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("\(Int(habitsService.totalWaterMlToday)) ml")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Goal: \(Int(habitsService.waterGoalMl)) ml")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                let smokesBaseline = max(Double(habitsService.smokesBaselineCount), 1.0)
                let smokesProgress = min(max(Double(habitsService.totalSmokesToday) / smokesBaseline, 0.0), 1.0)
                let isSmokesOverLimit = habitsService.totalSmokesToday > habitsService.smokesBaselineCount
                let isSmokesWarning = habitsService.totalSmokesToday >= Int(Double(habitsService.smokesBaselineCount) * 0.8)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(smokesProgress))
                            .stroke(
                                LinearGradient(
                                    colors: isSmokesOverLimit
                                        ? [Color(hex: "#FF3B30"), Color(hex: "#FF9500")]
                                        : (isSmokesWarning ? [Color(hex: "#FFB800"), Color(hex: "#FF9500")] : [Color(hex: "#00FFB2"), Color(hex: "#00E5FF")]),
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Image(systemName: isSmokesOverLimit ? "exclamationmark" : "flame.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isSmokesOverLimit ? Color(hex: "#FF3B30") : (isSmokesWarning ? Color(hex: "#FFB800") : Color(hex: "#00FFB2")))
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SMOKES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("\(habitsService.totalSmokesToday) / \(habitsService.smokesBaselineCount)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(isSmokesOverLimit ? Color(hex: "#FF3B30") : .white)
                        Text("Baseline: \(habitsService.smokesBaselineCount)")
                            .font(.system(size: 10))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Comprehensive Quick Actions Grid
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK INTAKE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)

                HStack(spacing: 8) {
                    quickChip(title: "+500 Bottle", icon: "waterbottle.fill", color: ThemeColors.accentCyan) {
                        habitsService.logWater(preset: .bottle)
                    }
                    quickChip(title: "+300 Water", icon: "drop.fill", color: ThemeColors.accentCyan) {
                        habitsService.logWater(preset: .largeWater)
                    }
                    quickChip(title: "+150 Water", icon: "drop.fill", color: ThemeColors.accentCyan) {
                        habitsService.logWater(preset: .smallWater)
                    }
                }

                HStack(spacing: 8) {
                    quickChip(title: "+100 Coffee", icon: "cup.and.saucer.fill", color: Color(hex: "#F59E0B")) {
                        habitsService.logWater(preset: .coffee)
                    }
                    quickChip(title: "+1 Cigarette", icon: "flame.fill", color: Color(hex: "#EF4444")) {
                        habitsService.logSmoke(preset: .cigarette)
                    }
                    quickChip(title: "+1 Heated", icon: "bolt.fill", color: Color(hex: "#3B82F6")) {
                        habitsService.logSmoke(preset: .heated)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func quickChip(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            triggerHaptic()
            action()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
