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
        } else if args.contains("-startTabHealth") || args.contains("-testSleepStudio") {
            self._selectedTab = State(initialValue: .health)
        } else if args.contains("-startTabFinances") {
            self._selectedTab = State(initialValue: .finances)
        } else if args.contains("-startTabTagdos") {
            self._selectedTab = State(initialValue: .tagdos)
        }
        
        if args.contains("-testMixedDashboard") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "news", size: .small),
                    DashboardWidgetConfig(id: "health", size: .wide),
                    DashboardWidgetConfig(id: "habits", size: .wide),
                    DashboardWidgetConfig(id: "finances", size: .wide)
                ]
            }
        } else if args.contains("-testFinancesSmall") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "finances", size: .small),
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "news", size: .wide),
                    DashboardWidgetConfig(id: "health", size: .wide),
                    DashboardWidgetConfig(id: "habits", size: .wide)
                ]
            }
        } else if args.contains("-testTallDashboard") || args.contains("-testFinancesTall") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "finances", size: .tall),
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "news", size: .small),
                    DashboardWidgetConfig(id: "health", size: .wide),
                    DashboardWidgetConfig(id: "habits", size: .wide)
                ]
            }
        } else if args.contains("-testLargeDashboard") || args.contains("-testFinancesLarge") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "finances", size: .large),
                    DashboardWidgetConfig(id: "weather", size: .wide),
                    DashboardWidgetConfig(id: "news", size: .wide),
                    DashboardWidgetConfig(id: "health", size: .wide),
                    DashboardWidgetConfig(id: "habits", size: .wide)
                ]
            }
        } else if args.contains("-testDefaultDashboard") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = DashboardWidgetConfig.defaultLayout
            }
        } else if args.contains("-testTagdosTop") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "tagdos_notes", size: .wide),
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "news", size: .small),
                    DashboardWidgetConfig(id: "health", size: .wide),
                    DashboardWidgetConfig(id: "habits", size: .wide),
                    DashboardWidgetConfig(id: "finances", size: .wide)
                ]
            }
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
                                    onNavigateToFinances: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .finances
                                        }
                                    },
                                    onNavigateToSettings: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .settings
                                        }
                                    },
                                    onNavigateToTagdos: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                            selectedTab = .tagdos
                                        }
                                    }
                                )
                            case .weather:
                                WeatherDetailView(onNavigateBack: navigateToDashboard)
                            case .news:
                                NewsFeedView(onNavigateBack: navigateToDashboard)
                            case .health:
                                HealthMainView(onNavigateBack: navigateToDashboard)
                            case .habits:
                                HabitsMainView(onNavigateBack: navigateToDashboard)
                            case .finances:
                                FinancesMainView(onNavigateBack: navigateToDashboard)
                            case .tagdos:
                                TagdosNotesHubView(onNavigateBack: navigateToDashboard)
                            case .settings:
                                SettingsView(onNavigateBack: navigateToDashboard)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .applyIf(selectedTab != .dashboard) { view in
                            view.simultaneousGesture(
                                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                                    .onEnded { value in
                                        let startX = value.startLocation.x
                                        let translationX = value.translation.width
                                        let translationY = value.translation.height
                                        
                                        // Edge swipe right: started within 50pt of left edge, dragged right > 60pt, horizontally dominant
                                        if startX <= 50 && translationX > 60 && abs(translationX) > abs(translationY) * 1.3 {
                                            #if canImport(UIKit)
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            #endif
                                            navigateToDashboard()
                                        }
                                    }
                            )
                        }
                        
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
            let fullPath = "\(url.host ?? "")/\(url.path)".trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if fullPath.contains("bubble") || fullPath.contains("water") {
                    selectedTab = .habits
                    HabitsService.shared.activeHabit = .water
                } else if fullPath.contains("smoke") {
                    selectedTab = .habits
                    HabitsService.shared.activeHabit = .smokes
                } else if fullPath.contains("money") {
                    selectedTab = .finances
                    FinanceService.shared.activeSubTab = .money
                } else if fullPath.contains("stock") {
                    selectedTab = .finances
                    FinanceService.shared.activeSubTab = .stocks
                } else if fullPath.contains("world") {
                    selectedTab = .finances
                    FinanceService.shared.activeSubTab = .world
                } else if fullPath.contains("sleep") {
                    selectedTab = .health
                    HealthDataService.shared.activeSubTab = .sleep
                } else if fullPath.contains("tagdos") {
                    selectedTab = .tagdos
                } else {
                    switch fullPath {
                    case "dashboard": selectedTab = .dashboard
                    case "weather": selectedTab = .weather
                    case "news": selectedTab = .news
                    case "health": selectedTab = .health
                    case "habits": selectedTab = .habits
                    case "finances": selectedTab = .finances
                    case "tagdos": selectedTab = .tagdos
                    case "settings": selectedTab = .settings
                    default: break
                    }
                }
            }
        }
    }
    
    private func navigateToDashboard() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedTab = .dashboard
        }
    }
}

fileprivate extension View {
    @ViewBuilder
    func applyIf<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
