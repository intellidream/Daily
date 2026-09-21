import SwiftUI
import DailyCore

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
                    HabitsService.shared.reloadFromLocalStorage()
                    await HabitsService.shared.flushOfflineQueue()
                    await HabitsService.shared.loadDataForSelectedDate()
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
