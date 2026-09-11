import SwiftUI
import DailyCore

public struct RootView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var selectedTab: NavigationTab = .dashboard
    
    public init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-startTabNews") {
            self._selectedTab = State(initialValue: .news)
        } else if args.contains("-startTabSettings") {
            self._selectedTab = State(initialValue: .settings)
        } else if args.contains("-startTabHabits") {
            self._selectedTab = State(initialValue: .habits)
        }
    }

    
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
        .onOpenURL { url in
            let target = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                switch target {
                case "dashboard": selectedTab = .dashboard
                case "weather": selectedTab = .weather
                case "news": selectedTab = .news
                case "health": selectedTab = .health
                case "habits": selectedTab = .habits
                case "settings": selectedTab = .settings
                default: break
                }
            }
        }
    }
}
