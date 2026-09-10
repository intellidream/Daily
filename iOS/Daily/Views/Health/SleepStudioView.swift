import SwiftUI
import DailyCore

/// Dedicated Sleep Studio visualizing nocturnal sleep architecture, 4-level hypnogram, and daytime naps.
public struct SleepStudioView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            if let session = healthService.primarySleepSession {
                // 1. Hero Sleep Score & Schedule Card
                heroSleepScoreCard(session: session)
                
                // 2. Clinical Hypnogram or Proportional Stage Bar
                hypnogramContainerCard(session: session)
                
                // 3. Sleep Architecture Breakdown Grid
                architectureMetricsGrid(session: session)
            } else {
                emptySleepCard
            }
            
            // 4. Daytime Naps Section
            if !healthService.daytimeNaps.isEmpty {
                daytimeNapsSection
            }
        }
    }
    
    // MARK: - Hero Sleep Score Card
    
    private func heroSleepScoreCard(session: SleepSession) -> some View {
        GlassCard(cornerRadius: 22, padding: 20) {
            VStack(spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("LAST NIGHT'S SLEEP")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                            
                            // Source Device Origin Chip
                            HStack(spacing: 4) {
                                Image(systemName: DeviceSource.from(name: session.sourceDevice).systemImage)
                                    .font(.system(size: 10))
                                Text(session.sourceDevice)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                        }
                        
                        Text(session.totalAsleepFormatted)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("\(session.timeInBedFormatted) in bed • \(session.efficiencyPercent)% efficiency")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    
                    Spacer()
                    
                    // Radial Score Ring
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 8)
                            .frame(width: 76, height: 76)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(session.sleepScore) / 100.0)
                            .stroke(
                                AngularGradient(
                                    colors: [ThemeColors.accentCyan, ThemeColors.accentBlue, ThemeColors.accentPurple],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 76, height: 76)
                        
                        VStack(spacing: 1) {
                            Text("\(session.sleepScore)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(session.sleepQualityRating)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Bedtime and Wake Time Schedule Row
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundColor(ThemeColors.accentPurple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bedtime")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(session.bedtimeFormatted)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "sun.horizon.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Wake Time")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text(session.wakeTimeFormatted)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(ThemeColors.accentCyan)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Restorative")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Text("\(session.restorativePercent)%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Hypnogram Container Card
    
    private func hypnogramContainerCard(session: SleepSession) -> some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(session.hasGranularHypnogram ? "SLEEP HYPNOGRAM" : "STAGE PROPORTIONS")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    Spacer()
                    if session.hasGranularHypnogram {
                        Text("Tap stage to inspect")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                }
                
                if session.hasGranularHypnogram {
                    SleepHypnogramView(session: session)
                } else {
                    stageProportionBar(session: session)
                }
                
                // Stage Legend Pills
                HStack(spacing: 12) {
                    legendPill(label: "Deep", colorHex: SleepStageType.deep.hexColor, val: session.deepFormatted, pct: session.deepPercent)
                    legendPill(label: "REM", colorHex: SleepStageType.rem.hexColor, val: session.remFormatted, pct: session.remPercent)
                    legendPill(label: "Light", colorHex: SleepStageType.light.hexColor, val: session.lightFormatted, pct: session.lightPercent)
                    legendPill(label: "Awake", colorHex: SleepStageType.awake.hexColor, val: session.awakeFormatted, pct: session.awakePercent)
                }
            }
        }
    }
    
    private func stageProportionBar(session: SleepSession) -> some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let total = max(1, session.deepSeconds + session.remSeconds + session.lightSeconds + session.awakeSeconds)
                
                HStack(spacing: 2) {
                    if session.deepSeconds > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: SleepStageType.deep.hexColor))
                            .frame(width: max(4, (session.deepSeconds / total) * w))
                    }
                    if session.remSeconds > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: SleepStageType.rem.hexColor))
                            .frame(width: max(4, (session.remSeconds / total) * w))
                    }
                    if session.lightSeconds > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: SleepStageType.light.hexColor))
                            .frame(width: max(4, (session.lightSeconds / total) * w))
                    }
                    if session.awakeSeconds > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: SleepStageType.awake.hexColor))
                            .frame(width: max(4, (session.awakeSeconds / total) * w))
                    }
                }
            }
            .frame(height: 18)
        }
    }
    
    private func legendPill(label: String, colorHex: String, val: String, pct: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: colorHex))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(label) \(pct)%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Text(val)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Architecture Metrics Grid
    
    private func architectureMetricsGrid(session: SleepSession) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricTile(title: "Deep Sleep", value: session.deepFormatted, subtitle: "\(session.deepPercent)% of sleep", icon: "moon.fill", tint: Color(hex: SleepStageType.deep.hexColor))
            metricTile(title: "REM Sleep", value: session.remFormatted, subtitle: "\(session.remPercent)% of sleep", icon: "sparkles", tint: Color(hex: SleepStageType.rem.hexColor))
            metricTile(title: "Light / Core", value: session.lightFormatted, subtitle: "\(session.lightPercent)% of sleep", icon: "bed.double", tint: Color(hex: SleepStageType.light.hexColor))
            metricTile(title: "Awakenings", value: "\(session.awakeCount) times", subtitle: "\(session.awakeFormatted) awake", icon: "eye.fill", tint: Color(hex: SleepStageType.awake.hexColor))
        }
    }
    
    private func metricTile(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(tint)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
                
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tint.opacity(0.85))
            }
        }
    }
    
    // MARK: - Daytime Naps Section
    
    private var daytimeNapsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                    .font(.system(size: 12))
                Text("DAYTIME NAPS (\(healthService.daytimeNaps.count))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(ThemeColors.accentCyan)
            }
            .padding(.leading, 4)
            
            ForEach(healthService.daytimeNaps) { nap in
                GlassCard(cornerRadius: 16, padding: 14) {
                    HStack {
                        Image(systemName: "powersleep")
                            .font(.system(size: 22))
                            .foregroundColor(ThemeColors.accentCyan)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(ThemeColors.accentCyan.opacity(0.12)))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nap Session")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(nap.timeRangeFormatted)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(nap.formattedDuration)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text(nap.sourceDevice)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptySleepCard: some View {
        GlassCard(cornerRadius: 20, padding: 32) {
            VStack(spacing: 12) {
                Image(systemName: "bed.double.slash")
                    .font(.system(size: 40))
                    .foregroundColor(ThemeColors.accentCyan.opacity(0.7))
                Text("No Sleep Data Recorded")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Wear your Apple Watch or Amazfit Balance overnight to view your sleep architecture and hypnogram.")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
