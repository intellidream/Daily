import SwiftUI
import DailyCore
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
struct DailyApp: App {
    @ObservedObject private var settingsService = SettingsService.shared
    @Environment(\.scenePhase) private var scenePhase
    
    public init() {
        // Wire native Apple HealthKit provider into HealthDataService
        HealthDataService.shared.localDataProvider = HealthKitManager.shared
        
        // Eagerly initiate HealthKit authorization on launch
        Task {
            _ = await HealthKitManager.shared.ensureAuthorized()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(colorScheme)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { @MainActor in
                    SmartLedgerStore.shared.reloadFromStorage()
                    TagdosStore.shared.loadFromStorage()
                    TagdosStore.shared.syncWithWidgets()
                    _ = HabitsService.shared.checkMidnightRolloverIfNeeded()
                    HealthDataService.shared.checkMidnightRolloverIfNeeded()
                    HabitsService.shared.reloadFromLocalStorage()
                    await HabitsService.shared.flushOfflineQueue()
                    await HabitsService.shared.loadDataForSelectedDate()
                    await HealthDataService.shared.refreshIfStale()
                    #if canImport(WidgetKit)
                    WidgetCenter.shared.reloadAllTimelines()
                    #endif
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
