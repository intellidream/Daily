import SwiftUI
import DailyCore

/// Modular Health & Vitals Card on the main Dashboard.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct HealthDashboardCard: View {
    @ObservedObject private var healthService = HealthDataService.shared
    
    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
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
            .dashboardCardFrame(for: size)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small (1x1) Compact Vitals Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Health", systemImage: "heart.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentPink)
                
                Spacer()
                
                if healthService.averageBpm > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("\(Int(healthService.averageBpm))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentPink)
                    }
                }
            }
            
            Spacer(minLength: 2)

            // Steps Glance with Walk Icon
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3.5) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(ThemeColors.accentPink)
                    Text("STEPS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                Text("\(healthService.totalStepsToday)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Progress Bar towards 10,000 steps
            let progress = min(Double(healthService.totalStepsToday) / 10000.0, 1.0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [ThemeColors.accentPink, ThemeColors.accentCyan], startPoint: .leading, endPoint: .trailing))
                    .scaleEffect(x: CGFloat(progress), y: 1.0, anchor: .leading)
            }
            .frame(height: 5)
            
            Spacer(minLength: 2)

            // Sleep Duration & Active Calories Footer
            HStack {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10))
                    .foregroundColor(ThemeColors.accentCyan)
                Text(healthService.primarySleepSession?.totalAsleepFormatted ?? "--")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                
                Spacer()

                if healthService.totalActiveCalories > 0 {
                    HStack(spacing: 2.5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(ThemeColors.accentOrange)
                        Text("\(Int(healthService.totalActiveCalories)) kcal")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Wide (2x1) Standard 3-Column Split
    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Health & Vitals", systemImage: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentPink)
                Spacer()
                HStack(spacing: 4) {
                    Text("Open Hub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentPink)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentPink)
                }
            }
            
            HStack(spacing: 16) {
                // Steps with walk & calories icons
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("STEPS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text("\(healthService.totalStepsToday)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if healthService.totalActiveCalories > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8))
                                .foregroundColor(ThemeColors.accentOrange)
                            Text("\(Int(healthService.totalActiveCalories)) kcal")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                
                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.15))
                
                // Heart Rate with ECG & Resting HR icons
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("HEART RATE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text(healthService.averageBpm > 0 ? "\(Int(healthService.averageBpm)) bpm" : "--")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPink)
                    if healthService.restingBpm > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundColor(ThemeColors.accentPink.opacity(0.85))
                            Text("Rest \(Int(healthService.restingBpm))")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                
                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.15))
                
                // Sleep with Moon & Efficiency icons
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("SLEEP")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text(healthService.primarySleepSession?.totalAsleepFormatted ?? "--")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    if let session = healthService.primarySleepSession {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                                .foregroundColor(ThemeColors.accentCyan.opacity(0.85))
                            Text("\(session.efficiencyPercent)% eff")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tall (1x2) Vertical Health Tower
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Health", systemImage: "heart.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ThemeColors.accentPink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(ThemeColors.accentPink)
            }

            // Steps Tile with Ring & Calories
            HStack(spacing: 10) {
                let stepProgress = min(Double(healthService.totalStepsToday) / 10000.0, 1.0)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(stepProgress))
                        .stroke(
                            LinearGradient(colors: [ThemeColors.accentPink, ThemeColors.accentCyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentPink)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("STEPS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text("\(healthService.totalStepsToday)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if healthService.totalActiveCalories > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8))
                                .foregroundColor(ThemeColors.accentOrange)
                            Text("\(Int(healthService.totalActiveCalories)) kcal")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Heart Rate Section with ECG & Resting Icons
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("HEART RATE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Spacer()
                    if healthService.restingBpm > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 7.5))
                                .foregroundColor(ThemeColors.accentPink.opacity(0.85))
                            Text("Rest \(Int(healthService.restingBpm))")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                Text(healthService.averageBpm > 0 ? "\(Int(healthService.averageBpm)) bpm" : "--")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentPink)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Sleep Section with Moon & Efficiency Icons
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("SLEEP")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Spacer()
                    if let session = healthService.primarySleepSession {
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7.5))
                                .foregroundColor(ThemeColors.accentCyan.opacity(0.85))
                            Text("\(session.efficiencyPercent)% eff")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                Text(healthService.primarySleepSession?.totalAsleepFormatted ?? "--")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
                
                if let session = healthService.primarySleepSession {
                    HStack(spacing: 3) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 8.5))
                            .foregroundColor(ThemeColors.accentCyan.opacity(0.7))
                        Text("\(session.bedtimeFormatted) - \(session.wakeTimeFormatted)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Extended Biometrics Hub
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Health & Biometrics", systemImage: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentPink)
                Spacer()
                HStack(spacing: 4) {
                    Text("Vitals Hub")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentPink)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.accentPink)
                }
            }

            // Primary 3-Metric Row with icons & secondary info
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("STEPS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text("\(healthService.totalStepsToday)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if healthService.totalActiveCalories > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(ThemeColors.accentOrange)
                            Text("\(Int(healthService.totalActiveCalories)) kcal")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentPink)
                        Text("AVG BPM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text(healthService.averageBpm > 0 ? "\(Int(healthService.averageBpm)) bpm" : "--")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentPink)
                    if healthService.restingBpm > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundColor(ThemeColors.accentPink.opacity(0.85))
                            Text("Rest \(Int(healthService.restingBpm))")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("SLEEP")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Text(healthService.primarySleepSession?.totalAsleepFormatted ?? "--")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    if let session = healthService.primarySleepSession {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                                .foregroundColor(ThemeColors.accentCyan.opacity(0.85))
                            Text("\(session.efficiencyPercent)% eff")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // Secondary Biometrics Grid (HRV, SpO2, Resting HR, Sleep Score)
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    let hrvVal = healthService.currentVitals[.hrvSdnn]?.value
                    vitalsTile(
                        icon: "waveform.path.ecg",
                        title: "HRV (SDNN)",
                        value: hrvVal != nil ? "\(Int(round(hrvVal!))) ms" : "--",
                        color: ThemeColors.accentPurple
                    )
                    
                    let spo2Val = healthService.currentVitals[.oxygenSaturation]?.value
                    vitalsTile(
                        icon: "lungs.fill",
                        title: "BLOOD OXYGEN",
                        value: spo2Val != nil ? "\(Int(round(spo2Val!)))%" : "--",
                        color: ThemeColors.accentBlue
                    )
                }
                
                HStack(spacing: 12) {
                    let rhrVal = healthService.currentVitals[.restingHeartRate]?.value
                    vitalsTile(
                        icon: "heart.circle.fill",
                        title: "RESTING HR",
                        value: rhrVal != nil ? "\(Int(round(rhrVal!))) bpm" : "--",
                        color: ThemeColors.accentPink
                    )
                    
                    let sleepScore = healthService.primarySleepSession?.sleepScore
                    vitalsTile(
                        icon: "bed.double.fill",
                        title: "SLEEP SCORE",
                        value: sleepScore != nil ? "\(sleepScore!)" : "--",
                        color: ThemeColors.accentCyan
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func vitalsTile(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension HealthDashboardCard: Equatable {
    public static func == (lhs: HealthDashboardCard, rhs: HealthDashboardCard) -> Bool {
        lhs.size == rhs.size &&
        lhs.healthService.totalStepsToday == rhs.healthService.totalStepsToday &&
        lhs.healthService.totalActiveCalories == rhs.healthService.totalActiveCalories &&
        lhs.healthService.averageBpm == rhs.healthService.averageBpm &&
        lhs.healthService.restingBpm == rhs.healthService.restingBpm &&
        lhs.healthService.primarySleepSession?.id == rhs.healthService.primarySleepSession?.id
    }
}
