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
                    let habitsRolledOver = HabitsService.shared.checkMidnightRolloverIfNeeded()
                    let healthRolledOver = HealthDataService.shared.checkMidnightRolloverIfNeeded()
                    let rolloverState = WidgetDataCoordinator.shared.consumePendingWidgetRolloverReload()
                    let effectiveDayRollover = habitsRolledOver || healthRolledOver || rolloverState.dayChanged
                    HabitsService.shared.reloadFromLocalStorage()
                    await HabitsService.shared.flushOfflineQueue()
                    await HabitsService.shared.loadDataForSelectedDate(forceRefresh: effectiveDayRollover)
                    await HealthDataService.shared.refreshIfStale()
                    await WeatherService.shared.refreshWeatherIfStale()
                    await SmartBriefingService.shared.syncForForegroundTransition(dayOrSlotChanged: effectiveDayRollover || rolloverState.slotChanged)
                    #if canImport(WidgetKit)
                    if effectiveDayRollover {
                        WidgetCenter.shared.reloadAllTimelines()
                    } else if rolloverState.slotChanged {
                        WidgetDataCoordinator.shared.reloadTimelines(kinds: [WidgetDataCoordinator.WidgetKind.combined])
                    }
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
