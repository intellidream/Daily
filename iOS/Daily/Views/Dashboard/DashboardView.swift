import SwiftUI
import DailyCore

public struct DashboardView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var authService = AuthService.shared
    private let onNavigateToWeather: () -> Void
    private let onNavigateToSettings: () -> Void
    
    public init(
        onNavigateToWeather: @escaping () -> Void = {},
        onNavigateToSettings: @escaping () -> Void = {}
    ) {
        self.onNavigateToWeather = onNavigateToWeather
        self.onNavigateToSettings = onNavigateToSettings
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Greeting
                HeaderGreetingView(onAvatarTapped: onNavigateToSettings)
                
                // --- Real-time Weather Widget Card ---
                WeatherDashboardCard(onTap: onNavigateToWeather)
                
                // --- Health & Telemetry Widget Card Preview ---
                GlassCard(cornerRadius: 20, padding: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Health & Vitals", systemImage: "heart.text.square.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ThemeColors.accentBlue)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(ThemeColors.success)
                                    .frame(width: 6, height: 6)
                                Text("Ready for Sensor Sync")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("STEPS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text("7,420")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            
                            Divider()
                                .frame(height: 32)
                                .background(Color.white.opacity(0.15))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("HEART RATE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text("68 bpm")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            
                            Divider()
                                .frame(height: 32)
                                .background(Color.white.opacity(0.15))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SLEEP GOAL")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text(String(format: "%.1fh", settingsService.settings.healthSleepTargetHours))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(ThemeColors.accentCyan)
                            }
                        }
                    }
                }
                
                // --- News Feed Widget Card Preview ---
                GlassCard(cornerRadius: 20, padding: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("News & Briefings", systemImage: "newspaper.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(ThemeColors.accentCyan)
                            Spacer()
                            Text("Fast Path")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(ThemeColors.fgMutedDark)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apple Intelligence and Next-Gen Architecture")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            
                            HStack(spacing: 8) {
                                Text("TechCrunch")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(ThemeColors.accentBlue)
                                Text("•")
                                    .foregroundColor(ThemeColors.fgMutedDark)
                                Text("12m ago")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110) // Leave room for FloatingGlassCapsule
        }
        .task {
            if WeatherService.shared.currentWeather == nil {
                await WeatherService.shared.refreshWeather()
            }
        }
    }
}
