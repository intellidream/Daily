import SwiftUI
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

public struct DashboardView: View {
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var showingCustomizeSheet = false
    
    private let onNavigateToWeather: () -> Void
    private let onNavigateToNews: () -> Void
    private let onNavigateToHealth: () -> Void
    private let onNavigateToHabits: () -> Void
    private let onNavigateToFinances: () -> Void
    private let onNavigateToSettings: () -> Void
    
    public init(
        onNavigateToWeather: @escaping () -> Void = {},
        onNavigateToNews: @escaping () -> Void = {},
        onNavigateToHealth: @escaping () -> Void = {},
        onNavigateToHabits: @escaping () -> Void = {},
        onNavigateToFinances: @escaping () -> Void = {},
        onNavigateToSettings: @escaping () -> Void = {}
    ) {
        self.onNavigateToWeather = onNavigateToWeather
        self.onNavigateToNews = onNavigateToNews
        self.onNavigateToHealth = onNavigateToHealth
        self.onNavigateToHabits = onNavigateToHabits
        self.onNavigateToFinances = onNavigateToFinances
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Header Greeting with Customize & Settings shortcuts
                HeaderGreetingView(
                    onAvatarTapped: onNavigateToSettings,
                    onCustomizeTapped: { showingCustomizeSheet = true }
                )
                
                // Native Coalesced Row-Grid Architecture (100% 120 FPS ProMotion stability)
                let visibleWidgets = settingsService.settings.dashboardWidgets.filter(\.isVisible)
                let rows = DashboardRowBuilder.buildRows(from: visibleWidgets)
                
                VStack(spacing: 14) {
                    ForEach(rows) { row in
                        dashboardRowView(row: row, allWidgets: visibleWidgets)
                    }
                }
            }
            .padding(.top, 14) // Standard Apple HIG breathing room below Dynamic Island / status bar
            .padding(.horizontal, 20)
            .padding(.bottom, 110) // Leave room for FloatingGlassCapsule
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable {
            async let w: () = WeatherService.shared.refreshWeather(force: true)
            async let h: () = HealthDataService.shared.loadDataForSelectedDate(forceRefresh: true)
            async let hab: () = HabitsService.shared.loadDataForSelectedDate(forceRefresh: true)
            async let n: () = NewsService.shared.loadFeed(NewsService.shared.selectedFeed, forceRefresh: true)
            async let f: () = FinanceService.shared.loadFinanceData(forceRefresh: true)
            _ = await (w, h, hab, n, f)
        }
        .task {
            async let w: () = WeatherService.shared.currentWeather == nil ? WeatherService.shared.refreshWeather() : ()
            async let h: () = HealthDataService.shared.loadDataForSelectedDate()
            async let hab: () = HabitsService.shared.loadDataForSelectedDate()
            async let n: () = NewsService.shared.articles.isEmpty ? NewsService.shared.loadFeed(NewsService.shared.selectedFeed) : ()
            async let f: () = FinanceService.shared.loadFinanceData()
            _ = await (w, h, hab, n, f)
        }
        .sheet(isPresented: $showingCustomizeSheet) {
            CustomizeDashboardSheet()
        }
    }

    // MARK: - Row Rendering
    @ViewBuilder
    private func dashboardRowView(row: DashboardRow, allWidgets: [DashboardWidgetConfig]) -> some View {
        switch row {
        case .full(let config):
            widgetItemView(config: config, allWidgets: allWidgets)
            
        case .pair(let left, let right):
            HStack(spacing: 14) {
                widgetItemView(config: left, allWidgets: allWidgets)
                    .frame(maxWidth: .infinity)
                widgetItemView(config: right, allWidgets: allWidgets)
                    .frame(maxWidth: .infinity)
            }
            
        case .tallWithSmalls(let tall, let smalls):
            HStack(alignment: .top, spacing: 14) {
                widgetItemView(config: tall, allWidgets: allWidgets)
                    .frame(maxWidth: .infinity)
                
                VStack(spacing: 14) {
                    ForEach(smalls, id: \.id) { small in
                        widgetItemView(config: small, allWidgets: allWidgets)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
        case .singleSmall(let config):
            HStack(spacing: 14) {
                widgetItemView(config: config, allWidgets: allWidgets)
                    .frame(maxWidth: .infinity)
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func widgetItemView(config: DashboardWidgetConfig, allWidgets: [DashboardWidgetConfig]) -> some View {
        let index = allWidgets.firstIndex(where: { $0.id == config.id }) ?? 0
        widgetView(for: config)
            .contextMenu {
                widgetContextMenu(config: config, index: index, totalCount: allWidgets.count)
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
        case DashboardWidgetType.finances.rawValue:
            FinancesDashboardCard(size: config.size, onTap: onNavigateToFinances)
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
