import SwiftUI
import DailyCore
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MacOSWindowManager.shared.activateMainWindow()
        return true
    }
}

@main
struct DailyMacOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        // Primary Liquid Glass Window (Single-instance window)
        Window("DayOne", id: "main") {
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
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .tagdos)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Dashboard") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .dashboard)
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Finances & Markets") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .finances)
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("TagDoS Notes & Tasks") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .tagdos)
                }
                .keyboardShortcut("3", modifiers: .command)
                
                Button("Health & Vitals") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .health)
                }
                .keyboardShortcut("4", modifiers: .command)
                
                Button("Habits & Cravings") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .habits)
                }
                .keyboardShortcut("5", modifiers: .command)
                
                Button("Weather & Forecast") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .weather)
                }
                .keyboardShortcut("6", modifiers: .command)
                
                Button("News & Articles") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .news)
                }
                .keyboardShortcut("7", modifiers: .command)
                
                Divider()
                
                Button("DayOne Glance Companion") {
                    MacOSWindowManager.shared.activateGlanceWindow()
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
        
        // On-demand Glance Floating Window (Accessible via ⌘0, Menu Bar, or Navigate menu)
        Window("DayOne Glance", id: "glance") {
            MenuBarCompanionView(
                onOpenFullApp: { requestedTab in
                    MacOSWindowManager.shared.closeGlanceWindow()
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: requestedTab)
                },
                onExitApp: {
                    NSApplication.shared.terminate(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        exit(0)
                    }
                }
            )
            .preferredColorScheme(colorScheme)
            .frame(width: 360, height: 580)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Persistent MenuBarExtra Companion (Quick Drop-down)
        MenuBarExtra {
            MenuBarCompanionView(
                onOpenFullApp: { requestedTab in
                    MacOSWindowManager.shared.closeGlanceWindow()
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: requestedTab)
                },
                onExitApp: {
                    NSApplication.shared.terminate(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        exit(0)
                    }
                }
            )
            .preferredColorScheme(colorScheme)
            .frame(width: 360, height: 580)
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
