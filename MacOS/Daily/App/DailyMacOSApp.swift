import SwiftUI
import DailyCore
import AppKit

@main
struct DailyMacOSApp: App {
    @ObservedObject private var settingsService = SettingsService.shared
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
                    // Open TagDoS or quick memo
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        
        // Persistent MenuBarExtra Companion (Quick Drop-down)
        MenuBarExtra("DayOne", systemImage: "sparkles") {
            MenuBarCompanionView(onOpenFullApp: { requestedTab in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            })
            .preferredColorScheme(colorScheme)
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
