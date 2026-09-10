import SwiftUI
import DailyCore

/// Liquid Glass Weather Card on the main Dashboard displaying real-time telemetry
/// and navigating to the full Weather experience when tapped.
public struct WeatherDashboardCard: View {
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var settingsService = SettingsService.shared
    private let onTap: () -> Void

    public init(onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
    }

    private var unitSymbol: String {
        settingsService.settings.weatherUnitSystem.temperatureSymbol
    }

    public var body: some View {
        Button(action: onTap) {
            GlassCard(cornerRadius: 20, padding: 20) {
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
        }
        .buttonStyle(.plain)
    }
}
