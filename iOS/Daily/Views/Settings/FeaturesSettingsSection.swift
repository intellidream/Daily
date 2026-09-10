import SwiftUI
import DailyCore

public struct FeaturesSettingsSection: View {
    @ObservedObject private var settingsService = SettingsService.shared
    
    public init() {}
    
    public var body: some View {
        GlassCard(cornerRadius: 18, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(ThemeColors.accentCyan)
                    Text("Features Configuration")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                // --- Weather ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("WEATHER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Toggle(isOn: Binding(
                        get: { settingsService.settings.weatherAlwaysAutoLocation },
                        set: { val in settingsService.update { $0.weatherAlwaysAutoLocation = val } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Location Detection")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text("Always detect current coordinates on startup")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    .tint(ThemeColors.accentBlue)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Measurement Units")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeColors.fgMutedDark)
                        
                        Picker("Unit System", selection: Binding(
                            get: { settingsService.settings.weatherUnitSystem },
                            set: { val in settingsService.update { $0.weatherUnitSystem = val } }
                        )) {
                            ForEach(WeatherUnitSystem.allCases, id: \.self) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // --- Health ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("HEALTH & VITALS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Toggle(isOn: Binding(
                        get: { settingsService.settings.healthMockDataEnabled },
                        set: { val in settingsService.update { $0.healthMockDataEnabled = val } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mock Health Store")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text("Simulate vitals history for development")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                    }
                    .tint(ThemeColors.accentBlue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Target Sleep Duration")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.1fh", settingsService.settings.healthSleepTargetHours))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { settingsService.settings.healthSleepTargetHours },
                                set: { val in
                                    let rounded = (val * 2).rounded() / 2
                                    settingsService.update { $0.healthSleepTargetHours = rounded }
                                }
                            ),
                            in: 6.0...10.0,
                            step: 0.5
                        )
                        .tint(ThemeColors.accentBlue)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // --- Habits ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("HABITS & HYDRATION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Daily Hydration Target")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.2fL", settingsService.settings.habitsWaterTargetLiters))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(ThemeColors.accentCyan)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { settingsService.settings.habitsWaterTargetLiters },
                                set: { val in
                                    let rounded = (val * 4).rounded() / 4
                                    settingsService.update { $0.habitsWaterTargetLiters = rounded }
                                }
                            ),
                            in: 1.0...4.0,
                            step: 0.25
                        )
                        .tint(ThemeColors.accentBlue)
                    }
                    
                    Toggle(isOn: Binding(
                        get: { settingsService.settings.habitsRemindersEnabled },
                        set: { val in settingsService.update { $0.habitsRemindersEnabled = val } }
                    )) {
                        Text("Habit Logging Reminders")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .tint(ThemeColors.accentBlue)
                }
                
                Divider()
                    .background(Color.white.opacity(0.15))
                
                // --- News ---
                VStack(alignment: .leading, spacing: 10) {
                    Text("NEWS READER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(ThemeColors.accentCyan)
                    
                    Toggle(isOn: Binding(
                        get: { settingsService.settings.newsAutoRefreshOnStartup },
                        set: { val in settingsService.update { $0.newsAutoRefreshOnStartup = val } }
                    )) {
                        Text("Auto-Refresh on Launch")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .tint(ThemeColors.accentBlue)
                    
                    Toggle(isOn: Binding(
                        get: { settingsService.settings.newsShowImages },
                        set: { val in settingsService.update { $0.newsShowImages = val } }
                    )) {
                        Text("Display Article Cover Images")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .tint(ThemeColors.accentBlue)
                }
            }
        }
    }
}
