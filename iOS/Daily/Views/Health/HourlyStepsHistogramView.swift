import SwiftUI
import DailyCore
import Charts

/// 24-hour hourly step cadence histogram and activity hours counter.
public struct HourlyStepsHistogramView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STEP CADENCE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(healthService.totalStepsToday)")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("STEPS")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    
                    Spacer()
                    
                    // Active Hours Callout
                    let activeHours = healthService.hourlySteps.filter { $0.steps >= 250 }.count
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Active Hours")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("\(activeHours) of 12 hrs")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(ThemeColors.accentCyan)
                    }
                }
                
                // 24-Hour Cadence Bar Chart
                if #available(iOS 16.0, *) {
                    Chart(healthService.hourlySteps) { bucket in
                        BarMark(
                            x: .value("Hour", bucket.hour),
                            y: .value("Steps", bucket.steps)
                        )
                        .foregroundStyle(
                            bucket.steps >= 1000
                                ? ThemeColors.accentCyan
                                : (bucket.steps >= 250 ? ThemeColors.accentBlue : Color.white.opacity(0.18))
                        )
                        .cornerRadius(3)
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                            if let hour = value.as(Int.self) {
                                AxisValueLabel {
                                    Text(String(format: "%02d:00", hour))
                                        .font(.system(size: 9))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { _ in
                            AxisValueLabel()
                                .font(.system(size: 9))
                                .foregroundStyle(ThemeColors.fgMutedDark)
                        }
                    }
                    .frame(height: 110)
                }
                
                // Peak Hour Callout
                if let peak = healthService.hourlySteps.max(by: { $0.steps < $1.steps }), peak.steps > 0 {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
                            .font(.system(size: 11))
                        Text("Peak activity at \(peak.hourFormatted):")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        Text("\(peak.steps) steps")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
        }
    }
}
