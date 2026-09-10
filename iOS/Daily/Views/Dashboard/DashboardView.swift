import SwiftUI
import DailyCore

public struct DashboardView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    
    private let onNavigateToWeather: () -> Void
    private let onNavigateToNews: () -> Void
    private let onNavigateToHealth: () -> Void
    private let onNavigateToHabits: () -> Void
    private let onNavigateToSettings: () -> Void
    
    public init(
        onNavigateToWeather: @escaping () -> Void = {},
        onNavigateToNews: @escaping () -> Void = {},
        onNavigateToHealth: @escaping () -> Void = {},
        onNavigateToHabits: @escaping () -> Void = {},
        onNavigateToSettings: @escaping () -> Void = {}
    ) {
        self.onNavigateToWeather = onNavigateToWeather
        self.onNavigateToNews = onNavigateToNews
        self.onNavigateToHealth = onNavigateToHealth
        self.onNavigateToHabits = onNavigateToHabits
        self.onNavigateToSettings = onNavigateToSettings
    }

    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Greeting
                HeaderGreetingView(onAvatarTapped: onNavigateToSettings)
                
                // --- Real-time Weather Widget Card ---
                WeatherDashboardCard(onTap: onNavigateToWeather)
                
                // --- Health & Telemetry Live Widget Card ---
                Button {
                    onNavigateToHealth()
                } label: {
                    GlassCard(cornerRadius: 20, padding: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Health & Telemetry", systemImage: "heart.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(ThemeColors.accentPink)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("Open Hub")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(ThemeColors.accentPink)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.accentPink)
                                }
                            }
                            
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("STEPS")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                    Text("\(healthService.totalStepsToday)")
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
                                    Text(healthService.averageBpm > 0 ? "\(Int(healthService.averageBpm)) bpm" : "--")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(ThemeColors.accentPink)
                                }
                                
                                Divider()
                                    .frame(height: 32)
                                    .background(Color.white.opacity(0.15))
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SLEEP")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.fgMutedDark)
                                    Text(healthService.primarySleepSession?.totalAsleepFormatted ?? "--")
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // --- Habits & Hydration Live Widget Card ---
                HabitsDashboardCard(onTap: onNavigateToHabits)
                
                // --- Live News Feed Widget Card ---

                Button {
                    onNavigateToNews()
                } label: {
                    GlassCard(cornerRadius: 20, padding: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("News & Briefings", systemImage: "newspaper.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(ThemeColors.accentCyan)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text("Explore Feeds")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(ThemeColors.accentCyan)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.accentCyan)
                                }
                            }
                            
                            if let top = newsService.topHeadline {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(top.title)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        
                                        HStack(spacing: 6) {
                                            Text(top.publicationName ?? "Briefing")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(ThemeColors.accentBlue)
                                            Text("•")
                                                .font(.system(size: 9))
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                            Text(top.relativeTimeFormatted)
                                                .font(.system(size: 11))
                                                .foregroundColor(ThemeColors.fgMutedDark)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if let imgStr = top.imageUrl, let url = URL(string: imgStr) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable()
                                                    .scaledToFill()
                                                    .frame(width: 58, height: 58)
                                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                            default:
                                                EmptyView()
                                            }
                                        }
                                    }
                                }
                            } else {
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
                }
                .buttonStyle(.plain)
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
