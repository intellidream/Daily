import SwiftUI
import DailyCore

/// 7-day and 30-day historical evolution charts and statistics catalog.
public struct HealthTrendsView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    @State private var selectedMetric: HealthMetricType = .steps
    
    private let availableTrendMetrics: [HealthMetricType] = [
        .steps,
        .sleepDuration,
        .heartRate,
        .hrvSdnn,
        .activeEnergy,
        .weight
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // 1. Metric Selector Horizontal Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableTrendMetrics) { metric in
                        let isSelected = selectedMetric == metric
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                selectedMetric = metric
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: metric.systemImage)
                                    .font(.system(size: 12))
                                Text(metric.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .background(
                                Capsule()
                                    .fill(isSelected ? ThemeColors.accentBlue.opacity(0.7) : Color.white.opacity(0.08))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isSelected ? ThemeColors.accentCyan : Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // 2. Trend Visualizer Card
            let points = healthService.historicalTrends[selectedMetric] ?? []
            GlassCard(cornerRadius: 22, padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7-DAY EVOLUTION")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                            Text(selectedMetric.displayName)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    
                    // Daily Capsule Bars Chart
                    if !points.isEmpty {
                        dailyCapsuleBarChart(points: points)
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.08))
                    
                    // Stats Grid (AVG, HIGH, LOW, TOTAL/LATEST)
                    statsGrid(points: points)
                }
            }
        }
    }
    
    // MARK: - Daily Capsule Bar Chart
    
    private func dailyCapsuleBarChart(points: [DailyMetricTrendPoint]) -> some View {
        let maxVal = max(1.0, points.map(\.value).max() ?? 1.0)
        let minVal = points.map(\.value).min() ?? 0.0
        
        return HStack(alignment: .bottom, spacing: 12) {
            ForEach(points) { pt in
                VStack(spacing: 8) {
                    // Capsule Bar
                    GeometryReader { geo in
                        let h = geo.size.height
                        // Normalized height
                        let normalizedHeight: CGFloat = isFluctuatingMetric(selectedMetric)
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
                                .frame(height: normalizedHeight)
                                .opacity(pt.isCompleteDay ? 1.0 : 0.45)
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
    
    private func statsGrid(points: [DailyMetricTrendPoint]) -> some View {
        let values = points.map(\.value)
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let high = values.max() ?? 0
        let low = values.min() ?? 0
        let latest = points.last?.value ?? 0
        let isCumulative = !isFluctuatingMetric(selectedMetric)
        let totalOrLatest = isCumulative ? values.reduce(0, +) : latest
        
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statItem(label: "AVERAGE", value: formatStat(avg))
            statItem(label: "HIGH", value: formatStat(high))
            statItem(label: "LOW", value: formatStat(low))
            statItem(label: isCumulative ? "TOTAL" : "LATEST", value: formatStat(totalOrLatest))
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
    
    private func formatStat(_ val: Double) -> String {
        switch selectedMetric {
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
