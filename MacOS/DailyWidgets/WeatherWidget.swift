import WidgetKit
import SwiftUI
import DailyCore

public struct WeatherEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WeatherWidgetSnapshot

    public init(date: Date, snapshot: WeatherWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct WeatherTimelineProvider: TimelineProvider {
    public func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: Date(), snapshot: WeatherWidgetSnapshot.placeholder)
    }

    public func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchWeatherSnapshot()
        completion(WeatherEntry(date: Date(), snapshot: snapshot.hasData ? snapshot : WeatherWidgetSnapshot.placeholder))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        let snapshot = WidgetDataCoordinator.shared.fetchWeatherSnapshot()
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let entry = WeatherEntry(date: currentDate, snapshot: snapshot.hasData ? snapshot : WeatherWidgetSnapshot.placeholder)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

public struct WeatherWidgetView: View {
    public let entry: WeatherEntry
    @Environment(\.widgetFamily) var family

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            case .systemLarge:
                largeView
            default:
                mediumView
            }
        }
        .containerBackground(WidgetColors.bgGradient, for: .widget)
        .widgetURL(URL(string: "daily://weather"))
    }

    // MARK: - Small (1x1)
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: City + Condition Icon
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.snapshot.cityName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(entry.snapshot.conditionText)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: WeatherConditionHelper.sfSymbol(for: entry.snapshot.iconCode))
                    .font(.system(size: 20))
                    .foregroundColor(WidgetColors.accentCyan)
            }

            Spacer(minLength: 2)

            // Large Current Temperature
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(round(entry.snapshot.temp)))°")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }

            // High / Low + Feels Like
            HStack(spacing: 6) {
                Text("H:\(Int(round(entry.snapshot.tempMax)))°")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Text("L:\(Int(round(entry.snapshot.tempMin)))°")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "humidity.fill")
                        .font(.system(size: 8))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("\(entry.snapshot.humidityPercent)%")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(4)
    }

    // MARK: - Medium (2x1)
    private var mediumView: some View {
        HStack(spacing: 12) {
            // Left Hero Block
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 9))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text(entry.snapshot.cityName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(round(entry.snapshot.temp)))°")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Image(systemName: WeatherConditionHelper.sfSymbol(for: entry.snapshot.iconCode))
                        .font(.system(size: 20))
                        .foregroundColor(WidgetColors.accentCyan)
                }

                Text(entry.snapshot.conditionText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(WidgetColors.fgMuted)
                    .lineLimit(1)

                Spacer(minLength: 2)

                HStack(spacing: 6) {
                    Text("H:\(Int(round(entry.snapshot.tempMax)))° L:\(Int(round(entry.snapshot.tempMin)))°")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    Text("·")
                        .foregroundColor(WidgetColors.fgMuted)
                    Text("\(Int(round(entry.snapshot.windSpeed))) \(entry.snapshot.windUnit)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }
            }
            .frame(width: 125, alignment: .leading)

            Divider()
                .background(Color.white.opacity(0.12))

            // Right Block: Hourly Forecast
            VStack(alignment: .leading, spacing: 4) {
                Text("HOURLY FORECAST")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)

                Spacer(minLength: 2)

                HStack(spacing: 0) {
                    let items = entry.snapshot.hourly.isEmpty ? WeatherWidgetSnapshot.placeholder.hourly : entry.snapshot.hourly
                    ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 3) {
                            Text(item.timeLabel)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(WidgetColors.fgMuted)

                            Image(systemName: WeatherConditionHelper.sfSymbol(for: item.iconCode))
                                .font(.system(size: 14))
                                .foregroundColor(WidgetColors.accentCyan)
                                .frame(height: 18)

                            if item.popPercent > 0 {
                                Text("\(item.popPercent)%")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundColor(WidgetColors.accentBlue)
                            } else {
                                Text(" ")
                                    .font(.system(size: 8))
                            }

                            Text("\(Int(round(item.temp)))°")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Spacer(minLength: 2)
            }
        }
        .padding(4)
    }

    // MARK: - Large (2x2)
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(WidgetColors.accentCyan)
                        Text(entry.snapshot.cityName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text(entry.snapshot.conditionText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(WidgetColors.fgMuted)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(round(entry.snapshot.temp)))°")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Image(systemName: WeatherConditionHelper.sfSymbol(for: entry.snapshot.iconCode))
                        .font(.system(size: 22))
                        .foregroundColor(WidgetColors.accentCyan)
                }
            }

            // Metrics row
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Text("High:")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(WidgetColors.fgMuted)
                    Text("\(Int(round(entry.snapshot.tempMax)))°")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                HStack(spacing: 3) {
                    Text("Low:")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(WidgetColors.fgMuted)
                    Text("\(Int(round(entry.snapshot.tempMin)))°")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                HStack(spacing: 3) {
                    Text("Feels:")
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(WidgetColors.fgMuted)
                    Text("\(Int(round(entry.snapshot.feelsLike)))°")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "wind")
                        .font(.system(size: 9))
                        .foregroundColor(WidgetColors.accentCyan)
                    Text("\(Int(round(entry.snapshot.windSpeed))) \(entry.snapshot.windUnit)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Hourly Timeline
            VStack(alignment: .leading, spacing: 4) {
                Text("HOURLY FORECAST")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)

                HStack(spacing: 0) {
                    let items = entry.snapshot.hourly.isEmpty ? WeatherWidgetSnapshot.placeholder.hourly : entry.snapshot.hourly
                    ForEach(Array(items.prefix(5).enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 2.5) {
                            Text(item.timeLabel)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(WidgetColors.fgMuted)

                            Image(systemName: WeatherConditionHelper.sfSymbol(for: item.iconCode))
                                .font(.system(size: 13))
                                .foregroundColor(WidgetColors.accentCyan)
                                .frame(height: 16)

                            if item.popPercent > 0 {
                                Text("\(item.popPercent)%")
                                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                    .foregroundColor(WidgetColors.accentBlue)
                            } else {
                                Text(" ")
                                    .font(.system(size: 7.5))
                            }

                            Text("\(Int(round(item.temp)))°")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            // 5-Day Forecast
            VStack(alignment: .leading, spacing: 3) {
                Text("5-DAY OUTLOOK")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(WidgetColors.accentCyan)

                let daily = entry.snapshot.daily.isEmpty ? WeatherWidgetSnapshot.placeholder.daily : entry.snapshot.daily
                ForEach(Array(daily.prefix(4).enumerated()), id: \.offset) { _, d in
                    HStack(spacing: 6) {
                        Text(d.dayName)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 42, alignment: .leading)

                        Image(systemName: WeatherConditionHelper.sfSymbol(for: d.iconCode))
                            .font(.system(size: 11))
                            .foregroundColor(WidgetColors.accentCyan)
                            .frame(width: 18)

                        if d.popPercent > 0 {
                            Text("\(d.popPercent)%")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundColor(WidgetColors.accentBlue)
                                .frame(width: 26, alignment: .leading)
                        } else {
                            Spacer()
                                .frame(width: 26)
                        }

                        Text("\(Int(round(d.tempMin)))°")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(WidgetColors.fgMuted)
                            .frame(width: 24, alignment: .trailing)

                        // Temperature bar
                        GeometryReader { barGeo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 3)
                                Capsule()
                                    .fill(LinearGradient(colors: [WidgetColors.accentCyan, WidgetColors.accentAmber], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: barGeo.size.width * 0.7, height: 3)
                            }
                            .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 10)

                        Text("\(Int(round(d.tempMax)))°")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
        .padding(4)
    }
}

public struct WeatherWidget: Widget {
    public let kind: String = "com.intellidream.daily.WeatherWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeatherTimelineProvider()) { entry in
            WeatherWidgetView(entry: entry)
        }
        .configurationDisplayName("Weather & Forecast")
        .description("Real-time local weather, atmospheric conditions, hourly precipitation timeline, and 5-day outlook.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge
        ])
    }
}
