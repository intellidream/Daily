import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

public struct DashboardView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var newsService = NewsService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    
    @State private var showingCustomizeSheet = false
    
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

    private func triggerHaptic() {
        if settingsService.settings.hapticsEnabled {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Greeting with Customize & Settings shortcuts
                HeaderGreetingView(
                    onAvatarTapped: onNavigateToSettings,
                    onCustomizeTapped: { showingCustomizeSheet = true }
                )
                
                // Modular 2-Column Mathematical Bin-Packing Dashboard
                let visibleWidgets = settingsService.settings.dashboardWidgets.filter(\.isVisible)
                ModularDashboardLayout(spacing: 16, unitHeight: 165) {
                    ForEach(Array(visibleWidgets.enumerated()), id: \.element.id) { index, config in
                        widgetView(for: config)
                            .widgetSpan(config.size)
                            .contextMenu {
                                widgetContextMenu(config: config, index: index, totalCount: visibleWidgets.count)
                            }
                    }
                }
            }
            .padding(.top, 14) // Standard Apple HIG breathing room below Dynamic Island / status bar
            .padding(.horizontal, 20)
            .padding(.bottom, 110) // Leave room for FloatingGlassCapsule
        }
        .refreshable {
            async let w: () = WeatherService.shared.refreshWeather(force: true)
            async let h: () = HealthDataService.shared.loadDataForSelectedDate(forceRefresh: true)
            async let hab: () = HabitsService.shared.loadDataForSelectedDate(forceRefresh: true)
            async let n: () = NewsService.shared.loadFeed(NewsService.shared.selectedFeed, forceRefresh: true)
            _ = await (w, h, hab, n)
        }
        .task {
            async let w: () = WeatherService.shared.currentWeather == nil ? WeatherService.shared.refreshWeather() : ()
            async let h: () = HealthDataService.shared.loadDataForSelectedDate()
            async let hab: () = HabitsService.shared.loadDataForSelectedDate()
            async let n: () = newsService.articles.isEmpty ? newsService.loadFeed(newsService.selectedFeed) : ()
            _ = await (w, h, hab, n)
        }
        .sheet(isPresented: $showingCustomizeSheet) {
            CustomizeDashboardSheet()
        }
    }

    // MARK: - Modular Widget Router
    @ViewBuilder
    private func widgetView(for config: DashboardWidgetConfig) -> some View {
        switch config.id {
        case DashboardWidgetType.weather.rawValue:
            WeatherDashboardCard(size: config.size, onTap: onNavigateToWeather)
        case DashboardWidgetType.news.rawValue:
            NewsDashboardCard(size: config.size, onTap: onNavigateToNews)
        case DashboardWidgetType.health.rawValue:
            HealthDashboardCard(size: config.size, onTap: onNavigateToHealth)
        case DashboardWidgetType.habits.rawValue:
            HabitsDashboardCard(size: config.size, onTap: onNavigateToHabits)
        default:
            EmptyView()
        }
    }

    // MARK: - Instant Context Menu (Resize & Reorder)
    @ViewBuilder
    private func widgetContextMenu(config: DashboardWidgetConfig, index: Int, totalCount: Int) -> some View {
        Section("Widget Size") {
            ForEach(DashboardWidgetSize.allCases, id: \.self) { size in
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        updateWidgetSize(id: config.id, newSize: size)
                    }
                } label: {
                    HStack {
                        Text(size.displayName)
                        if config.size == size {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        
        Section("Order") {
            if index > 0 {
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        moveWidget(fromIndex: index, toIndex: index - 1)
                    }
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            
            if index < totalCount - 1 {
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        moveWidget(fromIndex: index, toIndex: index + 1)
                    }
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
        
        Section {
            Button {
                showingCustomizeSheet = true
            } label: {
                Label("Customize Dashboard...", systemImage: "slider.horizontal.2.square")
            }
        }
    }

    private func updateWidgetSize(id: String, newSize: DashboardWidgetSize) {
        settingsService.update { settings in
            if let idx = settings.dashboardWidgets.firstIndex(where: { $0.id == id }) {
                settings.dashboardWidgets[idx].size = newSize
            }
        }
    }

    private func moveWidget(fromIndex: Int, toIndex: Int) {
        settingsService.update { settings in
            guard fromIndex >= 0 && fromIndex < settings.dashboardWidgets.count,
                  toIndex >= 0 && toIndex < settings.dashboardWidgets.count else { return }
            settings.dashboardWidgets.swapAt(fromIndex, toIndex)
        }
    }
}
