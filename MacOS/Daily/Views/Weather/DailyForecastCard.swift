import SwiftUI
import DailyCore

/// 5-Day outlook card featuring min-max temperature range tracks and condition icons.
public struct DailyForecastCard: View {
    public let summaries: [DailyForecastSummary]
    public let unitSymbol: String

    public init(summaries: [DailyForecastSummary], unitSymbol: String = "°") {
        self.summaries = summaries
        self.unitSymbol = unitSymbol
    }

    private var overallMin: Double {
        summaries.map { $0.tempMin }.min() ?? 0
    }

    private var overallMax: Double {
        let max = summaries.map { $0.tempMax }.max() ?? 30
        return max == overallMin ? max + 1 : max
    }

    public var body: some View {
        GlassCard(cornerRadius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Text("5-DAY FORECAST")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(0.8)
                }

                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Forecast Rows
                VStack(spacing: 12) {
                    ForEach(summaries) { summary in
                        HStack(spacing: 12) {
                            // Day Name
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.dayName)
                                    .font(.system(size: 15, weight: summary.dayName == "Today" ? .bold : .medium, design: .rounded))
                                    .foregroundColor(summary.dayName == "Today" ? ThemeColors.accentCyan : .white)
                                
                                Text(summary.dateFormatted)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .frame(width: 65, alignment: .leading)

                            // Condition Icon & Rain Pop
                            HStack(spacing: 4) {
                                Image(systemName: summary.sfSymbolName)
                                    .renderingMode(.original)
                                    .font(.system(size: 20))
                                    .frame(width: 24)
                                
                                if summary.popMax >= 0.15 {
                                    Text("\(Int(round(summary.popMax * 100)))%")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(ThemeColors.accentBlue)
                                        .frame(width: 32, alignment: .leading)
                                } else {
                                    Spacer()
                                        .frame(width: 32)
                                }
                            }

                            // Min Temp
                            Text("\(Int(round(summary.tempMin)))\(unitSymbol)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 36, alignment: .trailing)

                            // Temperature Range Gradient Bar
                            GeometryReader { geo in
                                let totalRange = overallMax - overallMin
                                let leftRatio = max(0, (summary.tempMin - overallMin) / totalRange)
                                let rightRatio = min(1, (summary.tempMax - overallMin) / totalRange)
                                let barWidth = geo.size.width
                                let startX = barWidth * leftRatio
                                let fillWidth = max(6, barWidth * (rightRatio - leftRatio))

                                ZStack(alignment: .leading) {
                                    // Track
                                    Capsule()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 5)

                                    // Active Temperature Range
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [ThemeColors.accentBlue, ThemeColors.accentCyan, Color(hex: "#FFD166")],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: fillWidth, height: 5)
                                        .offset(x: startX)
                                }
                                .frame(maxHeight: .infinity)
                            }
                            .frame(height: 14)

                            // Max Temp
                            Text("\(Int(round(summary.tempMax)))\(unitSymbol)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}
