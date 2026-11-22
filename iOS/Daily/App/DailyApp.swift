import SwiftUI
import UserNotifications
import DailyCore
#if canImport(WidgetKit)
import WidgetKit
#endif

private final class DailyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = DailyNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let deepLink = response.notification.request.content.userInfo["deepLink"] as? String
        if let deepLink, let url = URL(string: deepLink) {
            Task { @MainActor in
                if deepLink.lowercased().contains("tagdos") {
                    TagdosStore.shared.handleDeepLink(url: url)
                    NotificationCenter.default.post(name: .dailySelectTab, object: NavigationTab.tagdos)
                }
            }
        }
        completionHandler()
    }
}

@main
struct DailyApp: App {
    @ObservedObject private var settingsService = SettingsService.shared
    @Environment(\.scenePhase) private var scenePhase
    
    public init() {
        UNUserNotificationCenter.current().delegate = DailyNotificationDelegate.shared

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
