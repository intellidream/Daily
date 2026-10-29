import SwiftUI
import DailyCore

public struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var authService = AuthService.shared
    @State private var selectedTab: NavigationTab = .dashboard
    @State private var isCosmosNavExpanded: Bool = false
    
    public init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-startTabCosmos") {
            self._selectedTab = State(initialValue: .cosmos)
        } else if args.contains("-startTabNews") {
            self._selectedTab = State(initialValue: .news)
        } else if args.contains("-startTabSettings") {
            self._selectedTab = State(initialValue: .settings)
        } else if args.contains("-startTabHabits") {
            self._selectedTab = State(initialValue: .habits)
        } else if args.contains("-startTabHealth") || args.contains("-testSleepStudio") || args.contains("-healthSubTabStress") || args.contains("-healthSubTabTrends") {
            self._selectedTab = State(initialValue: .health)
        } else if args.contains("-startTabFinances") {
            self._selectedTab = State(initialValue: .finances)
        } else if args.contains("-startTabTagdos") {
            self._selectedTab = State(initialValue: .tagdos)
        } else if args.contains("-startTabSettings") || args.contains("-testOrbit") {
            self._selectedTab = State(initialValue: .settings)
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
        } else if args.contains("-testHealthTall") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "health", size: .tall),
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "news", size: .small),
                    DashboardWidgetConfig(id: "finances", size: .wide)
                ]
            }
        } else if args.contains("-testHealthLarge") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "health", size: .large),
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "news", size: .small)
                ]
            }
        } else if args.contains("-testHealthWidgetsAllSizes") {
            AuthService.shared.continueAsGuest()
            SettingsService.shared.update { s in
                s.dashboardWidgets = [
                    DashboardWidgetConfig(id: "health", size: .small),
                    DashboardWidgetConfig(id: "weather", size: .small),
                    DashboardWidgetConfig(id: "health", size: .wide),
                    DashboardWidgetConfig(id: "health", size: .large)
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
                    GeometryReader { geometry in
                        let isFoldable = horizontalSizeClass == .regular || geometry.size.width >= 600
                        
                        if isFoldable {
                            if selectedTab == .cosmos {
                                fullSurfaceCosmosView
                            } else {
                                foldableDualPaneView
                            }
                        } else {
                            standardCompactPhoneView
                        }
                    }
                }
                .onChange(of: selectedTab) { _, newTab in
                    if newTab != .cosmos {
                        isCosmosNavExpanded = false
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
                } else if fullPath.contains("stress") {
                    selectedTab = .health
                    HealthDataService.shared.activeSubTab = .stress
                } else if fullPath.contains("tagdos") {
                    selectedTab = .tagdos
                } else if fullPath.contains("cosmos") || fullPath.contains("sky") || fullPath.contains("astronomy") {
                    selectedTab = .cosmos
                } else if fullPath.contains("summary") || fullPath.contains("briefing") {
                    selectedTab = .dashboard
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        SmartBriefingService.shared.isBriefingPresented = true
                    }
                } else {
                    switch fullPath {
                    case "dashboard": selectedTab = .dashboard
                    case "weather": selectedTab = .weather
                    case "cosmos": selectedTab = .cosmos
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
    
    // MARK: - Standard Single-Screen Compact Layout (iPhone 16 Pro, standard phones, folded Duo)
    @ViewBuilder
    private var standardCompactPhoneView: some View {
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
                        onNavigateToCosmos: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab = .cosmos
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
                    WeatherDetailView(
                        onNavigateBack: navigateToDashboard,
                        onNavigateToCosmos: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab = .cosmos
                            }
                        }
                    )
                case .cosmos:
                    CosmosDetailView(
                        onNavigateBack: navigateToDashboard,
                        onNavigateToWeather: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab = .weather
                            }
                        }
                    )
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
            .applyIf(selectedTab != .dashboard && selectedTab != .cosmos) { view in
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
            
            // Floating Liquid Glass Navigation Capsule (auto-retracted into corner bubble in Cosmos Observatory)
            if selectedTab == .cosmos {
                cosmosNavigationOverlay
            } else {
                FloatingGlassCapsule(selectedTab: $selectedTab)
                    .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Full-Surface Unfolded / Tablet Cosmos Observatory (58% Sky Dome / 42% Observatory Deck)
    @ViewBuilder
    private var fullSurfaceCosmosView: some View {
        ZStack(alignment: .bottom) {
            CosmosDetailView(
                onNavigateBack: navigateToDashboard,
                onNavigateToWeather: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = .weather
                    }
                },
                allowSplitDeckByDefault: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            cosmosNavigationOverlay
        }
    }
    
    @ViewBuilder
    private var cosmosNavigationOverlay: some View {
        if isCosmosNavExpanded {
            HStack(spacing: 8) {
                FloatingGlassCapsule(selectedTab: $selectedTab)
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isCosmosNavExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.65)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCosmosNavExpanded = true
                }
            } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(ThemeColors.accentCyan)
                    .frame(width: 42, height: 40)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.72))
                            .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.38), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand Navigation Bar")
            .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16)
            .padding(.bottom, 22)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
    
    // MARK: - Adaptive Dual-Pane Foldable Layout (iPhone Duo unfolded & expanded displays)
    @ViewBuilder
    private var foldableDualPaneView: some View {
        HStack(spacing: 0) {
            // --- 1. Master Pane (Left): Dashboard in single column & Anchored Capsule ---
            ZStack(alignment: .bottom) {
                DashboardView(
                    forceSingleColumn: true,
                    onNavigateToWeather: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedTab = .weather
                        }
                    },
                    onNavigateToCosmos: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedTab = .cosmos
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
                
                // Option A: Floating Glass Capsule anchored at bottom of Master pane
                FloatingGlassCapsule(selectedTab: $selectedTab)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            
            // --- 2. Subtle Crease / Hinge Divider ---
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .edgesIgnoringSafeArea(.vertical)
            
            // --- 3. Detail Pane (Right): Companion or Embedded Hub ---
            VStack(spacing: 0) {
                if selectedTab != .dashboard {
                    FoldableDragHandle {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedTab = .dashboard
                        }
                    }
                }
                
                Group {
                    switch selectedTab {
                    case .dashboard:
                        DailyFoldableCompanionPane(
                            onOpenHub: { tab in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedTab = tab
                                }
                            },
                            onOpenBriefing: {
                                SmartBriefingService.shared.isBriefingPresented = true
                            }
                        )
                    case .weather:
                        WeatherDetailView(
                            onNavigateBack: navigateToDashboard,
                            onNavigateToCosmos: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedTab = .cosmos
                                }
                            }
                        )
                    case .cosmos:
                        CosmosDetailView(
                            onNavigateBack: navigateToDashboard,
                            onNavigateToWeather: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    selectedTab = .weather
                                }
                            }
                        )
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
                                let translationX = value.translation.width
                                let translationY = value.translation.height
                                
                                // Edge swipe right on detail pane: returns to Companion
                                if translationX > 60 && abs(translationX) > abs(translationY) * 1.3 {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    navigateToDashboard()
                                }
                            }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, 12)
            .padding(.trailing, 16)
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
