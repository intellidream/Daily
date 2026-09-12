import SwiftUI
import DailyCore

/// 7-day and 30-day historical evolution charts and statistics catalog.
public struct HealthTrendsView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    private let displayedMetrics: [HealthMetricType] = [
        .steps,
        .sleepDuration,
        .heartRate,
        .activeEnergy,
        .hrvSdnn,
        .weight
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            ForEach(displayedMetrics) { metric in
                let points = healthService.historicalTrends[metric] ?? []
                trendCard(for: metric, points: points)
            }
        }
    }
    
    // MARK: - Trend Visualizer Card
    
    private func trendCard(for metric: HealthMetricType, points: [DailyMetricTrendPoint]) -> some View {
        GlassCard(cornerRadius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: metric.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7-DAY EVOLUTION")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text(metric.displayName)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
                
                // Daily Capsule Bars Chart
                if !points.isEmpty {
                    dailyCapsuleBarChart(for: metric, points: points)
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // Stats Grid (AVG, HIGH, LOW, TOTAL/LATEST)
                statsGrid(for: metric, points: points)
            }
        }
    }
    
    // MARK: - Daily Capsule Bar Chart
    
    private func dailyCapsuleBarChart(for metric: HealthMetricType, points: [DailyMetricTrendPoint]) -> some View {
        let maxVal = max(1.0, points.map(\.value).max() ?? 1.0)
        let minVal = points.map(\.value).min() ?? 0.0
        
        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(points) { pt in
                VStack(spacing: 8) {
                    // Capsule Bar
                    GeometryReader { geo in
                        let h = geo.size.height
                        // Normalized height
                        let normalizedHeight: CGFloat = isFluctuatingMetric(metric)
                            ? max(h * 0.15, (((pt.value - minVal) / max(1.0, maxVal - minVal)) * (h * 0.75)) + (h * 0.15))
                            : max(h * 0.1, (pt.value / maxVal) * h)
                        
                        VStack {
                            Spacer()
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            ThemeColors.accentCyan,
                                            ThemeColors.accentBlue
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: pt.value > 0 ? normalizedHeight : 4)
                                .opacity(pt.value > 0 ? (pt.isCompleteDay ? 1.0 : 0.6) : 0.2)
                        }
                    }
                    .frame(height: 120)
                    
                    // Day Label
                    Text(pt.dayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(pt.isCompleteDay ? .white.opacity(0.85) : ThemeColors.fgMutedDark)
                }
            }
        }
        .frame(height: 155)
    }
    
    // MARK: - Stats Grid
    
    private func statsGrid(for metric: HealthMetricType, points: [DailyMetricTrendPoint]) -> some View {
        let values = points.map(\.value).filter { $0 > 0 }
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let high = values.max() ?? 0
        let low = values.min() ?? 0
        let latest = points.last?.value ?? 0
        let isCumulative = !isFluctuatingMetric(metric)
        let totalOrLatest = isCumulative ? values.reduce(0, +) : latest
        
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statItem(label: "AVERAGE", value: formatStat(avg, for: metric))
            statItem(label: "HIGH", value: formatStat(high, for: metric))
            statItem(label: "LOW", value: formatStat(low, for: metric))
            statItem(label: isCumulative ? "TOTAL" : "LATEST", value: formatStat(totalOrLatest, for: metric))
        }
    }
    
    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ThemeColors.fgMutedDark)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
    
    private func formatStat(_ val: Double, for metric: HealthMetricType) -> String {
        guard val > 0 else { return "--" }
        switch metric {
        case .steps, .activeEnergy, .heartRate, .hrvSdnn:
            return "\(Int(round(val)))"
        case .sleepDuration:
            let h = Int(val) / 60
            let m = Int(val) % 60
            return "\(h)h \(m)m"
        case .weight:
            return String(format: "%.1f", val)
        default:
            return String(format: "%.1f", val)
        }
    }
    
    private func isFluctuatingMetric(_ m: HealthMetricType) -> Bool {
        m == .heartRate || m == .hrvSdnn || m == .weight
    }
}
