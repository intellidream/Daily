import SwiftUI
import DailyCore

public struct RootView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var selectedTab: NavigationTab = .dashboard
    
    public init() {}

    
    public var body: some View {
        Group {
            switch authService.sessionState {
            case .initializing:
                LiquidGlassBackground {
                    VStack(spacing: 24) {
                        Image("LaunchLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .shadow(color: ThemeColors.accentCyan.opacity(0.35), radius: 24, x: 0, y: 6)
                        
                        ProgressView()
                            .tint(ThemeColors.accentCyan)
                            .scaleEffect(1.1)
                    }
                }
                
            case .unauthenticated:
                LoginView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 1.05))
                    ))
                
            case .authenticated, .guest:
                LiquidGlassBackground {
                    ZStack(alignment: .bottom) {
                        // Active tab content
                        Group {
                            switch selectedTab {
                            case .dashboard:
                                DashboardView(
                                    onNavigateToWeather: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .weather
                                        }
                                    },
                                    onNavigateToNews: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .news
                                        }
                                    },
                                    onNavigateToHealth: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .health
                                        }
                                    },
                                    onNavigateToHabits: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .habits
                                        }
                                    },
                                    onNavigateToSettings: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .settings
                                        }
                                    }
                                )
                            case .weather:
                                WeatherDetailView()
                            case .news:
                                NewsFeedView()
                            case .health:
                                HealthMainView()
                            case .habits:
                                HabitsMainView()
                            case .settings:
                                SettingsView()
                            }
                        }

                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        // Floating Liquid Glass Navigation Capsule
                        FloatingGlassCapsule(selectedTab: $selectedTab)
                            .padding(.bottom, 24)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.05)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.sessionState.isAuthenticatedOrGuest)
    }
}
