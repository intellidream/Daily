import SwiftUI
import DailyCore
import Charts

/// Intraday Heart Rate curve and 4-zone intensity distribution view.
public struct HeartRateCurveView: View {
    @ObservedObject private var healthService = HealthDataService.shared
    @State private var selectedPoint: IntradayHeartRatePoint? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // 1. Hero Heart Rate Card
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HEART RATE TODAY")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(ThemeColors.accentCyan)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(Int(healthService.averageBpm))")
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("BPM AVG")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                        
                        Spacer()
                        
                        // Resting HR Pill
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.circle.fill")
                                    .foregroundColor(ThemeColors.accentPink)
                                    .font(.system(size: 12))
                                Text("Resting HR")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            Text("\(Int(healthService.restingBpm)) bpm")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Selected Point Callout
                    if let pt = selectedPoint {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(hex: pt.zone.hexColor))
                                .frame(width: 8, height: 8)
                            Text("\(Int(pt.bpm)) BPM")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("at \(formatTime(pt.timestamp))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                            Spacer()
                            Text(pt.zone.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: pt.zone.hexColor))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    
                    // Intraday Heart Rate Curve
                    if !healthService.intradayHeartRate.isEmpty {
                        chartView
                            .frame(height: 140)
                    } else {
                        Text("No intraday heart rate telemetry available for this day.")
                            .font(.system(size: 12))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 30)
                    }
                    
                    // Range Callouts
                    HStack {
                        Text("Min: \(Int(healthService.minBpm)) bpm")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: HeartRateZone.resting.hexColor))
                        Spacer()
                        Text("Max: \(Int(healthService.maxBpm)) bpm")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: HeartRateZone.peak.hexColor))
                    }
                }
            }
            
            // 2. Heart Rate Intensity Zones Card
            GlassCard(cornerRadius: 18, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("HEART RATE ZONES")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    // Multi-Segment Zone Bar
                    zoneSegmentBar
                    
                    // Zone Grid
                    VStack(spacing: 8) {
                        zoneRow(zone: .peak, count: healthService.heartRateZones[.peak] ?? 0)
                        zoneRow(zone: .cardio, count: healthService.heartRateZones[.cardio] ?? 0)
                        zoneRow(zone: .fatBurn, count: healthService.heartRateZones[.fatBurn] ?? 0)
                        zoneRow(zone: .resting, count: healthService.heartRateZones[.resting] ?? 0)
                    }
                }
            }
        }
    }
    
    // MARK: - Chart View
    
    @ViewBuilder
    private var chartView: some View {
        if #available(iOS 16.0, *) {
            Chart(healthService.intradayHeartRate) { pt in
                AreaMark(
                    x: .value("Time", pt.timestamp),
                    y: .value("BPM", pt.bpm)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            ThemeColors.accentCyan.opacity(0.35),
                            ThemeColors.accentCyan.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                LineMark(
                    x: .value("Time", pt.timestamp),
                    y: .value("BPM", pt.bpm)
                )
                .foregroundStyle(ThemeColors.accentCyan)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: max(35, healthService.minBpm - 5)...min(220, healthService.maxBpm + 10))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(ThemeColors.fgMutedDark)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel()
                        .foregroundStyle(ThemeColors.fgMutedDark)
                }
            }
        } else {
            // Fallback for older targets
            Rectangle()
                .fill(Color.white.opacity(0.05))
        }
    }
    
    // MARK: - Zone Bar & Rows
    
    private var zoneSegmentBar: some View {
        GeometryReader { geo in
            let total = max(1, healthService.heartRateZones.values.reduce(0, +))
            let w = geo.size.width
            
            HStack(spacing: 2) {
                ForEach([HeartRateZone.resting, .fatBurn, .cardio, .peak], id: \.self) { z in
                    let cnt = healthService.heartRateZones[z] ?? 0
                    if cnt > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: z.hexColor))
                            .frame(width: max(4, (Double(cnt) / Double(total)) * w))
                    }
                }
            }
        }
        .frame(height: 12)
    }
    
    private func zoneRow(zone: HeartRateZone, count: Int) -> some View {
        let total = max(1, healthService.heartRateZones.values.reduce(0, +))
        let pct = Int(round((Double(count) / Double(total)) * 100))
        
        return HStack {
            Circle()
                .fill(Color(hex: zone.hexColor))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(zone.rawValue)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Text(zone.bpmRangeText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
            
            Spacer()
            
            Text("\(pct)%")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
