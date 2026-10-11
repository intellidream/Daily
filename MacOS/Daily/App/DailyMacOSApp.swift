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
        }
        
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
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                if menuBarDisplayModeRaw == MenuBarDisplayMode.iconAndWeather.rawValue {
                    if let temp = weatherService.currentWeather?.main.temp {
                        Text("\(Int(round(temp)))°")
                    }
                } else if menuBarDisplayModeRaw == MenuBarDisplayMode.iconAndVitals.rawValue {
                    if let bpm = healthService.latestBpm ?? (healthService.restingBpm > 0 ? healthService.restingBpm : nil) {
                        Text("♥\(Int(round(bpm)))")
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
    
    private var colorScheme: ColorScheme? {
        switch settingsService.settings.theme {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
