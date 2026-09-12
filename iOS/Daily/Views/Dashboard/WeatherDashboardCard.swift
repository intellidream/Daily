import SwiftUI
import DailyCore

/// Liquid Glass Weather Card on the main Dashboard displaying real-time atmospheric telemetry.
/// Adaptively renders across Small (1x1), Wide (2x1), Tall (1x2), and Large (2x2) modular sizes.
public struct WeatherDashboardCard: View {
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    
    public let size: DashboardWidgetSize
    private let onTap: () -> Void

    public init(size: DashboardWidgetSize = .wide, onTap: @escaping () -> Void = {}) {
        self.size = size
        self.onTap = onTap
    }

    private var unitSymbol: String {
        settingsService.settings.weatherUnitSystem.temperatureSymbol
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
            .frame(maxWidth: .infinity, maxHeight: size == .wide ? nil : .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Small (1x1) Compact Glance
    @ViewBuilder
    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with mini symbol and location
            HStack(alignment: .center) {
                if let weather = weatherService.currentWeather,
                   let condition = weather.weather.first {
                    Image(systemName: WeatherConditionHelper.sfSymbol(for: condition.icon))
                        .renderingMode(.original)
                        .font(.system(size: 16))
                } else {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 14))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                
                Spacer()
                
                Text(weatherService.currentLocationName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 2)

            if let weather = weatherService.currentWeather {
                let temp = Int(round(weather.main.temp))
                let tempMin = Int(round(weather.main.tempMin))
                let tempMax = Int(round(weather.main.tempMax))
                let desc = weather.weather.first?.description.capitalized ?? "Clear"

                HStack(alignment: .top, spacing: 2) {
                    Text("\(temp)")
                        .font(.system(size: 38, weight: .thin, design: .rounded))
                    Text("°")
                        .font(.system(size: 22, weight: .light, design: .rounded))
                }
                .foregroundColor(.white)
                
                Text(desc)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("H: \(tempMax)° · L: \(tempMin)°")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(ThemeColors.fgMutedDark)
            } else if weatherService.isLoading {
                ProgressView()
                    .tint(ThemeColors.accentCyan)
                Text("Loading...")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
            } else {
                Text("--°")
                    .font(.system(size: 36, weight: .thin, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                Text("Tap to load")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Wide (2x1) Standard Full Card
    @ViewBuilder
    private var wideContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack {
                Label("Weather", systemImage: "cloud.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(weatherService.currentLocationName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            if let weather = weatherService.currentWeather {
                let condition = weather.weather.first
                let iconCode = condition?.icon ?? "01d"
                let sfSymbol = WeatherConditionHelper.sfSymbol(for: iconCode)
                let desc = condition?.description.capitalized ?? "Clear"
                let temp = Int(round(weather.main.temp))
                let tempMin = Int(round(weather.main.tempMin))
                let tempMax = Int(round(weather.main.tempMax))

                HStack(alignment: .center, spacing: 16) {
                    HStack(alignment: .top, spacing: 2) {
                        Text("\(temp)")
                            .font(.system(size: 48, weight: .thin, design: .rounded))
                        Text("°")
                            .font(.system(size: 28, weight: .light, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .fixedSize()

                    VStack(alignment: .leading, spacing: 3) {
                        Text(desc)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("H: \(tempMax)\(unitSymbol) · L: \(tempMin)\(unitSymbol)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Spacer()

                    Image(systemName: sfSymbol)
                        .renderingMode(.original)
                        .font(.system(size: 36))
                }
            } else if weatherService.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(ThemeColors.accentCyan)
                    Text("Updating atmospheric conditions...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.vertical, 8)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text("--°")
                        .font(.system(size: 48, weight: .thin, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tap to load weather")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        Text("Real-time telemetry")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Tall (1x2) Vertical Forecast Tower
    @ViewBuilder
    private var tallContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Weather")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ThemeColors.accentCyan)
                }
                .fixedSize()
                Spacer(minLength: 4)
                Text(weatherService.currentLocationName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ThemeColors.fgMutedDark)
                    .lineLimit(1)
            }

            if let weather = weatherService.currentWeather {
                let temp = Int(round(weather.main.temp))
                let condition = weather.weather.first
                let sfSymbol = WeatherConditionHelper.sfSymbol(for: condition?.icon ?? "01d")
                let desc = condition?.description.capitalized ?? "Clear"

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .top, spacing: 1) {
                            Text("\(temp)")
                                .font(.system(size: 34, weight: .thin, design: .rounded))
                            Text("°")
                                .font(.system(size: 20, weight: .light, design: .rounded))
                        }
                        .foregroundColor(.white)
                        
                        Text(desc)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: sfSymbol)
                        .renderingMode(.original)
                        .font(.system(size: 28))
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                Text("HOURLY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)

                // 4-Hour Vertical Micro-List
                let hourlyItems = Array(weatherService.hourlyForecasts.prefix(4))
                if !hourlyItems.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(hourlyItems) { item in
                            let hourStr = formatHour(from: item.dtTxt ?? "")
                            let itemIcon = WeatherConditionHelper.sfSymbol(for: item.weather.first?.icon ?? "01d")
                            let itemTemp = Int(round(item.main.temp))

                            HStack {
                                Text(hourStr)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                    .frame(width: 38, alignment: .leading)
                                
                                Spacer()
                                
                                Image(systemName: itemIcon)
                                    .renderingMode(.original)
                                    .font(.system(size: 14))
                                
                                Spacer()
                                
                                Text("\(itemTemp)°")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                } else {
                    Text("No hourly data")
                        .font(.system(size: 11))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }

                Spacer(minLength: 0)

                // Bottom telemetry tags
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "humidity")
                            .font(.system(size: 9))
                            .foregroundColor(ThemeColors.accentCyan)
                        Text("\(weather.main.humidity)%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "wind")
                            .font(.system(size: 9))
                            .foregroundColor(ThemeColors.accentBlue)
                        Text("\(Int(round(weather.wind?.speed ?? 0))) \(settingsService.settings.weatherWindUnit)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                Spacer()
                Text("Tap to load weather")
                    .font(.system(size: 12))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Large (2x2) Extended Weather Station
    @ViewBuilder
    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label("Weather Station", systemImage: "cloud.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text(weatherService.currentLocationName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ThemeColors.fgMutedDark)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ThemeColors.fgMutedDark)
                }
            }

            if let weather = weatherService.currentWeather {
                let condition = weather.weather.first
                let sfSymbol = WeatherConditionHelper.sfSymbol(for: condition?.icon ?? "01d")
                let desc = condition?.description.capitalized ?? "Clear"
                let temp = Int(round(weather.main.temp))
                let tempMin = Int(round(weather.main.tempMin))
                let tempMax = Int(round(weather.main.tempMax))

                // Hero Row
                HStack(alignment: .center, spacing: 16) {
                    HStack(alignment: .top, spacing: 2) {
                        Text("\(temp)")
                            .font(.system(size: 52, weight: .thin, design: .rounded))
                        Text("°")
                            .font(.system(size: 30, weight: .light, design: .rounded))
                    }
                    .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(desc)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("High: \(tempMax)\(unitSymbol) · Low: \(tempMin)\(unitSymbol)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(ThemeColors.fgMutedDark)
                    }

                    Spacer()

                    Image(systemName: sfSymbol)
                        .renderingMode(.original)
                        .font(.system(size: 44))
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                // Horizontal Hourly Carousel
                VStack(alignment: .leading, spacing: 8) {
                    Text("HOURLY FORECAST")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(ThemeColors.fgMutedDark)

                    let hourlyItems = Array(weatherService.hourlyForecasts.prefix(6))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(hourlyItems) { item in
                                let hour = formatHour(from: item.dtTxt ?? "")
                                let icon = WeatherConditionHelper.sfSymbol(for: item.weather.first?.icon ?? "01d")
                                let t = Int(round(item.main.temp))

                                VStack(spacing: 6) {
                                    Text(hour)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                    
                                    Image(systemName: icon)
                                        .renderingMode(.original)
                                        .font(.system(size: 16))
                                    
                                    Text("\(t)°")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                // Atmospheric Gauge Grid
                HStack(spacing: 12) {
                    telemetryBadge(icon: "humidity.fill", title: "HUMIDITY", value: "\(weather.main.humidity)%")
                    telemetryBadge(icon: "wind", title: "WIND", value: "\(Int(round(weather.wind?.speed ?? 0))) \(settingsService.settings.weatherWindUnit)")
                    telemetryBadge(icon: "barometer", title: "PRESSURE", value: "\(weather.main.pressure) hPa")
                }
            } else {
                Spacer()
                Text("Tap to load weather station telemetry")
                    .font(.system(size: 13))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func telemetryBadge(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(ThemeColors.fgMutedDark)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatHour(from dtTxt: String) -> String {
        // "2026-09-13 15:00:00" -> "15:00"
        let parts = dtTxt.split(separator: " ")
        if parts.count == 2 {
            let timeParts = parts[1].split(separator: ":")
            if timeParts.count >= 2 {
                return "\(timeParts[0]):\(timeParts[1])"
            }
        }
        return "Now"
    }
}
