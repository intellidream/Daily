import SwiftUI
import DailyCore
import AppKit

@main
struct DailyMacOSApp: App {
    @ObservedObject private var settingsService = SettingsService.shared
    @ObservedObject private var weatherService = WeatherService.shared
    @ObservedObject private var healthService = HealthDataService.shared
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayModeRaw: String = MenuBarDisplayMode.iconAndWeather.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    
    public init() {
        // macOS operates in 100% remote consumer mode for health vitals
        // (no local HealthKit daemon on macOS; telemetry arrives via Supabase sync)
        HealthDataService.shared.localDataProvider = nil
        
        // Eagerly trigger initial sync from Supabase
        Task { @MainActor in
            SmartLedgerStore.shared.reloadFromStorage()
            HabitsService.shared.reloadFromLocalStorage()
            await HabitsService.shared.flushOfflineQueue()
            await HabitsService.shared.loadDataForSelectedDate()
            await HealthDataService.shared.refreshIfStale()
            await WeatherService.shared.refreshWeather()
        }
    }
    
    var body: some Scene {
        // Primary Liquid Glass Window
        WindowGroup(id: "main") {
            RootView()
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 440, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("Quick Note in TagDoS") {
                    if let url = URL(string: "daily://tagdos") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Dashboard") {
                    if let url = URL(string: "daily://dashboard") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Finances & Markets") {
                    if let url = URL(string: "daily://finances") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("TagDoS Notes & Tasks") {
                    if let url = URL(string: "daily://tagdos") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("Health & Vitals") {
                    if let url = URL(string: "daily://health") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Button("Habits & Cravings") {
                    if let url = URL(string: "daily://habits") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("5", modifiers: .command)
                
                Button("Weather & Forecast") {
                    if let url = URL(string: "daily://weather") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("6", modifiers: .command)
                
                Button("News & Articles") {
                    if let url = URL(string: "daily://news") { NSWorkspace.shared.open(url) }
                }
                .keyboardShortcut("7", modifiers: .command)
                
                Divider()
                
                Button("DayOne Glance Companion") {
                    openWindow(id: "glance")
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Button("Sync with Cloud") {
                    Task { @MainActor in
                        await HabitsService.shared.flushOfflineQueue()
                        await HabitsService.shared.loadDataForSelectedDate()
                        await HealthDataService.shared.refreshIfStale()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        
        // On-demand Glance Floating Window (Accessible via ⌘0, Dashboard, or Navigate menu)
        Window("DayOne Glance", id: "glance") {
            MenuBarCompanionView(onOpenFullApp: { requestedTab in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                if let tab = requestedTab, let url = URL(string: "daily://\(tab.rawValue)") {
                    NSWorkspace.shared.open(url)
                }
            })
            .preferredColorScheme(colorScheme)
            .frame(width: 360, height: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Persistent MenuBarExtra Companion (Quick Drop-down)
        MenuBarExtra {
            MenuBarCompanionView(onOpenFullApp: { requestedTab in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                if let tab = requestedTab, let url = URL(string: "daily://\(tab.rawValue)") {
                    NSWorkspace.shared.open(url)
                }
            })
            .preferredColorScheme(colorScheme)
            .frame(width: 360, height: 560)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }
    
    @ViewBuilder
    private var menuBarLabel: some View {
        switch menuBarDisplayModeRaw {
        case MenuBarDisplayMode.monochrome.rawValue, MenuBarDisplayMode.iconOnly.rawValue:
            Image(systemName: "sparkles")
        case MenuBarDisplayMode.weather.rawValue:
            let iconName = WeatherConditionHelper.sfSymbol(for: weatherService.currentWeather?.weather.first?.icon ?? "01d")
            HStack(spacing: 3) {
                Image(systemName: iconName)
                if let temp = weatherService.currentWeather?.main.temp {
                    Text("\(Int(round(temp)))°")
                }
            }
        case MenuBarDisplayMode.heartRate.rawValue:
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                if let bpm = healthService.latestBpm ?? (healthService.restingBpm > 0 ? healthService.restingBpm : nil) {
                    Text("\(Int(round(bpm)))")
                }
            }
        case MenuBarDisplayMode.iconAndVitals.rawValue:
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                if let bpm = healthService.latestBpm ?? (healthService.restingBpm > 0 ? healthService.restingBpm : nil) {
                    Text("♥\(Int(round(bpm)))")
                }
            }
        case MenuBarDisplayMode.iconAndWeather.rawValue, _:
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                if let temp = weatherService.currentWeather?.main.temp {
                    Text("\(Int(round(temp)))°")
                }
            }
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch settingsService.settings.theme {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
