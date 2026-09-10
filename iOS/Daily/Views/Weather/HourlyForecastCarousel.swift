import SwiftUI
import DailyCore

/// Horizontal scrolling Liquid Glass carousel displaying 24-hour predictive weather intervals.
public struct HourlyForecastCarousel: View {
    public let items: [ForecastItem]
    public let unitSymbol: String

    public init(items: [ForecastItem], unitSymbol: String = "°") {
        self.items = items
        self.unitSymbol = unitSymbol
    }

    private let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()

    public var body: some View {
        GlassCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Text("24-HOUR FORECAST")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(0.8)
                }

                // Horizontal Carousel
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let isNow = index == 0
                            let iconCode = item.weather.first?.icon ?? "01d"
                            let sfSymbol = WeatherConditionHelper.sfSymbol(for: iconCode)
                            let timeLabel = isNow ? "Now" : hourFormatter.string(from: item.date).lowercased()
                            let tempValue = Int(round(item.main.temp))
                            let popValue = Int(round((item.pop ?? 0) * 100))

                            VStack(spacing: 10) {
                                Text(timeLabel)
                                    .font(.system(size: 13, weight: isNow ? .bold : .medium, design: .rounded))
                                    .foregroundColor(isNow ? ThemeColors.accentCyan : .white.opacity(0.8))

                                Image(systemName: sfSymbol)
                                    .renderingMode(.original)
                                    .font(.system(size: 22))
                                    .frame(height: 24)

                                if popValue > 0 {
                                    HStack(spacing: 2) {
                                        Image(systemName: "drop.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(ThemeColors.accentBlue)
                                        Text("\(popValue)%")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundColor(ThemeColors.accentBlue)
                                    }
                                } else {
                                    Spacer()
                                        .frame(height: 14)
                                }

                                Text("\(tempValue)\(unitSymbol)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background {
                                if isNow {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(ThemeColors.accentCyan.opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(ThemeColors.accentCyan.opacity(0.4), lineWidth: 1)
                                        )
                                } else {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
