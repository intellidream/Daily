import SwiftUI
import DailyCore

/// Dedicated full-featured Weather experience with tactile Liquid Glass styling,
/// real-time OpenWeatherMap data, 5-day forecast, and atmospheric metric tiles.
public struct WeatherDetailView: View {
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var settingsService = SettingsService.shared

    @State private var showingSearchSheet: Bool = false
    @State private var isSpinningRefresh: Bool = false

    public init() {}

    private var unitSymbol: String {
        settingsService.settings.weatherUnitSystem.temperatureSymbol
    }

    private var speedUnit: String {
        settingsService.settings.weatherUnitSystem == .metric ? "m/s" : "mph"
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    // Top Navigation & Location Bar
                    topLocationBar

                    // Content or Loading State
                    if let weather = weatherService.currentWeather {
                        // Hero Weather Card
                        heroWeatherCard(weather: weather)

                        // 24-Hour Forecast Carousel
                        if !weatherService.hourlyForecasts.isEmpty {
                            HourlyForecastCarousel(
                                items: weatherService.hourlyForecasts,
                                unitSymbol: unitSymbol
                            )
                        }

                        // 5-Day Forecast Card
                        if !weatherService.dailySummaries.isEmpty {
                            DailyForecastCard(
                                summaries: weatherService.dailySummaries,
                                unitSymbol: unitSymbol
                            )
                            .id("dailyForecast")
                        }

                        // 2x3 Atmospheric Metric Grid
                        atmosphericGrid(weather: weather)
                            .id("metricsGrid")

                    } else if weatherService.isLoading {
                        loadingPlaceholder
                    } else if let error = weatherService.errorMessage {
                        errorCard(message: error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 110) // Clear floating navigation capsule
            }
            .refreshable {
                await weatherService.refreshWeather(force: true)
            }
            .sheet(isPresented: $showingSearchSheet) {
                CitySearchSheet()
            }
            .task {
                if weatherService.currentWeather == nil {
                    await weatherService.refreshWeather()
                }
            }
        }
    }

    // MARK: - Top Location Bar

    private var topLocationBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(weatherService.currentLocationName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    // Location Source Badge
                    HStack(spacing: 3) {
                        Image(systemName: locationSourceIcon)
                            .font(.system(size: 9, weight: .bold))
                        Text(weatherService.locationSource.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(ThemeColors.accentCyan.opacity(0.18))
                    }
                }

                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            // Quick Actions
            HStack(spacing: 10) {
                // Auto-location restore button (if manual)
                if !weatherService.isAutoLocation {
                    Button {
                        Task {
                            await weatherService.resetToAutoLocation()
                        }
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                }

                // City Search Button
                Button {
                    showingSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }

                // Refresh Button
                Button {
                    Task {
                        isSpinningRefresh = true
                        await weatherService.refreshWeather(force: true)
                        withAnimation {
                            isSpinningRefresh = false
                        }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(weatherService.isLoading ? ThemeColors.accentCyan : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .rotationEffect(.degrees(isSpinningRefresh || weatherService.isLoading ? 360 : 0))
                        .animation(
                            isSpinningRefresh || weatherService.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: isSpinningRefresh || weatherService.isLoading
                        )
                }
            }
        }
    }

    private var locationSourceIcon: String {
        switch weatherService.locationSource {
        case .gps: return "location.fill"
        case .ip: return "wifi"
        case .manual: return "mappin"
        case .unknown: return "globe"
        }
    }

    // MARK: - Hero Weather Card

    private func heroWeatherCard(weather: WeatherResponse) -> some View {
        let condition = weather.weather.first
        let iconCode = condition?.icon ?? "01d"
        let sfSymbol = WeatherConditionHelper.sfSymbol(for: iconCode)
        let desc = condition?.description.capitalized ?? "Clear"
        let temp = Int(round(weather.main.temp))
        let feelsLike = Int(round(weather.main.feelsLike))
        let tempMin = Int(round(weather.main.tempMin))
        let tempMax = Int(round(weather.main.tempMax))

        return GlassCard(cornerRadius: 24, padding: 22) {
            VStack(spacing: 16) {
                // Top Condition Pill
                HStack {
                    Text(desc)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(ThemeColors.accentBlue)
                            Text("\(tempMin)°")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "#FFD166"))
                            Text("\(tempMax)°")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }

                // Middle Temperature & Hero Icon
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(temp)°")
                            .font(.system(size: 68, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize()

                        HStack(spacing: 6) {
                            Text("FEELS LIKE")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(0.6)
                            Text("\(feelsLike)\(unitSymbol)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }

                    Spacer()

                    // Glowing Ambient SF Symbol
                    ZStack {
                        Circle()
                            .fill(Color(hex: WeatherConditionHelper.conditionColorHex(for: iconCode)).opacity(0.25))
                            .frame(width: 80, height: 80)
                            .blur(radius: 20)

                        Image(systemName: sfSymbol)
                            .renderingMode(.original)
                            .font(.system(size: 64))
                    }
                }
            }
        }
    }

    // MARK: - Atmospheric Metrics Grid (2x3)

    private func atmosphericGrid(weather: WeatherResponse) -> some View {
        let windSpeed = weather.wind?.speed ?? 0
        let windDir = weather.wind?.cardinalDirection ?? "N/A"
        let humidity = weather.main.humidity
        let pressure = weather.main.pressure
        let visibilityKm = Double(weather.visibility ?? 10000) / 1000.0
        let clouds = weather.clouds?.all ?? 0

        let sunriseDate = weather.sys?.sunrise.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sunsetDate = weather.sys?.sunset.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let sunriseStr = sunriseDate.map { timeFormatter.string(from: $0) } ?? "--:--"
        let sunsetStr = sunsetDate.map { timeFormatter.string(from: $0) } ?? "--:--"

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            AtmosphericMetricTile(
                iconName: "wind",
                title: "Wind",
                value: String(format: "%.1f", windSpeed),
                unit: speedUnit,
                subtitle: "Direction: \(windDir)",
                accentColor: ThemeColors.accentCyan
            )

            AtmosphericMetricTile(
                iconName: "humidity.fill",
                title: "Humidity",
                value: "\(humidity)",
                unit: "%",
                subtitle: humidity > 65 ? "High moisture" : (humidity < 35 ? "Dry air" : "Comfortable"),
                accentColor: ThemeColors.accentBlue
            )

            AtmosphericMetricTile(
                iconName: "gauge.with.dots.needle.bottom.50percent",
                title: "Pressure",
                value: "\(pressure)",
                unit: "hPa",
                subtitle: pressure >= 1013 ? "High pressure" : "Low pressure",
                accentColor: Color(hex: "#7FF0D5")
            )

            AtmosphericMetricTile(
                iconName: "eye.fill",
                title: "Visibility",
                value: String(format: "%.0f", visibilityKm),
                unit: "km",
                subtitle: visibilityKm >= 10 ? "Clear view" : "Reduced visibility",
                accentColor: Color(hex: "#A0B2C6")
            )

            AtmosphericMetricTile(
                iconName: "cloud.fill",
                title: "Clouds",
                value: "\(clouds)",
                unit: "%",
                subtitle: clouds > 70 ? "Overcast skies" : (clouds > 30 ? "Partly cloudy" : "Clear skies"),
                accentColor: Color(hex: "#90A4AE")
            )

            AtmosphericMetricTile(
                iconName: "sun.max.fill",
                title: "Sun Schedule",
                value: sunriseStr,
                unit: "↑",
                subtitle: "Sunset: \(sunsetStr) ↓",
                accentColor: Color(hex: "#FFD166")
            )
        }
    }

    // MARK: - Loading & Error States

    private var loadingPlaceholder: some View {
        GlassCard(cornerRadius: 24, padding: 32) {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(ThemeColors.accentCyan)
                    .scaleEffect(1.4)
                Text("Fetching live atmospheric telemetry...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func errorCard(message: String) -> some View {
        GlassCard(cornerRadius: 24, padding: 24) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: "#FFB74D"))
                Text("Unable to Load Weather")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task {
                        await weatherService.refreshWeather(force: true)
                    }
                }
                .padding(.top, 6)
                .foregroundColor(ThemeColors.accentCyan)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
