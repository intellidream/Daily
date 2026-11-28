import SwiftUI
import DailyCore
import AppKit
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
private final class MacOSLifecycleCoordinator {
    static let shared = MacOSLifecycleCoordinator()
    private var isStarted = false
    private var activeSyncTask: Task<Void, Never>?
    private var lastLifecycleSyncAt: Date = .distantPast
    private var observerTokens: [NSObjectProtocol] = []
    private var workspaceObserverTokens: [NSObjectProtocol] = []

    func start() {
        guard !isStarted else { return }
        isStarted = true

        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncIfNeeded(force: false)
                }
            }
        )
        observerTokens.append(
            NotificationCenter.default.addObserver(
                forName: .NSCalendarDayChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncIfNeeded(force: true)
                }
            }
        )
        workspaceObserverTokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncIfNeeded(force: true)
                }
            }
        )
    }

    func syncIfNeeded(force: Bool = false, initialBoot: Bool = false) async {
        if let existing = activeSyncTask {
            await existing.value
            if !force { return }
        }

        let now = Date()
        let habitsRolledOver = HabitsService.shared.checkMidnightRolloverIfNeeded()
        let healthRolledOver = HealthDataService.shared.checkMidnightRolloverIfNeeded()
        let rolloverState = WidgetDataCoordinator.shared.consumePendingWidgetRolloverReload()
        let effectiveDayRollover = habitsRolledOver || healthRolledOver || rolloverState.dayChanged
        let shouldForceNetwork = force || effectiveDayRollover

        if !initialBoot && !shouldForceNetwork && !rolloverState.slotChanged && now.timeIntervalSince(lastLifecycleSyncAt) < 15 {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastLifecycleSyncAt = Date()

            SmartLedgerStore.shared.reloadFromStorage()
            HabitsService.shared.reloadFromLocalStorage()
            TagdosStore.shared.loadFromStorage()
            TagdosStore.shared.syncWithWidgets()
            if initialBoot {
                HabitsService.shared.saveDailyTotals()
            }
            await HabitsService.shared.flushOfflineQueue()
            await HabitsService.shared.loadDataForSelectedDate(forceRefresh: shouldForceNetwork)
            if initialBoot || shouldForceNetwork {
                await TagdosStore.shared.syncWithSupabase()
                await PrismStore.shared.syncWithSupabase()
            }
            if force {
                await HealthDataService.shared.loadDataForSelectedDate(forceRefresh: true)
                await WeatherService.shared.refreshWeather(force: true)
            } else {
                await HealthDataService.shared.refreshIfStale()
                if initialBoot {
                    await WeatherService.shared.refreshWeather()
                } else {
                    await WeatherService.shared.refreshWeatherIfStale()
                }
            }
            await SmartBriefingService.shared.syncForForegroundTransition(
                dayOrSlotChanged: effectiveDayRollover || rolloverState.slotChanged
            )

            #if canImport(WidgetKit)
            if effectiveDayRollover {
                WidgetCenter.shared.reloadAllTimelines()
            } else if rolloverState.slotChanged {
                WidgetDataCoordinator.shared.reloadTimelines(kinds: [WidgetDataCoordinator.WidgetKind.combined])
            }
            #endif
        }
        activeSyncTask = task
        await task.value
        if activeSyncTask == task {
            activeSyncTask = nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MacOSWindowManager.shared.activateMainWindow()
        return true
    }

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
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .tagdos)
                }
            }
        }
        completionHandler()
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
        LoreenFontRegistry.registerIfNeeded()
        // macOS operates in 100% remote consumer mode for health vitals
        // (no local HealthKit daemon on macOS; telemetry arrives via Supabase sync)
        HealthDataService.shared.localDataProvider = nil
        
        // Start cross-process Darwin notification listener for widget quick logging
        WidgetDarwinMutationListener.shared.startListening()
        MacOSLifecycleCoordinator.shared.start()
        
        // Eagerly trigger initial sync from Supabase and hydrate widget snapshots
        Task { @MainActor in
            await MacOSLifecycleCoordinator.shared.syncIfNeeded(force: false, initialBoot: true)
        }
    }
    
    var body: some Scene {
        // Primary Liquid Glass Window (Single-instance window)
        Window("DayOne", id: "main") {
            RootView()
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 440, minHeight: 650)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { @MainActor in
                            await MacOSLifecycleCoordinator.shared.syncIfNeeded(force: false)
                        }
                    }
                }
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
                
                Button("Cosmos & Night Sky") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .cosmos)
                }
                .keyboardShortcut("8", modifiers: .command)
                
                Button("Open Cosmos Observatory Window...") {
                    openWindow(id: "cosmos")
                }
                .keyboardShortcut("8", modifiers: [.command, .option])

                Button("Prism & Web Studio") {
                    MacOSWindowManager.shared.activateMainWindow(selectingTab: .prism)
                }
                .keyboardShortcut("9", modifiers: .command)

                Button("Open Prism Pop-Out Window...") {
                    PrismWindowManager.shared.openPopOutWindow()
                }
                .keyboardShortcut("9", modifiers: [.command, .option])
                
                Divider()
                
                Button("DayOne Glance Companion") {
                    MacOSWindowManager.shared.activateGlanceWindow()
                }
                .keyboardShortcut("0", modifiers: .command)
                
                Button("Sync with Cloud") {
                    Task { @MainActor in
                        await MacOSLifecycleCoordinator.shared.syncIfNeeded(force: true)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                if settingsService.settings.loreenVeilUnlocked {
                    Divider()

                    Button(settingsService.settings.loreenVeilEnabled ? "Disable Loreen Veil" : "Enable Loreen Veil") {
                        settingsService.update { $0.loreenVeilEnabled.toggle() }
                        #if canImport(WidgetKit)
                        WidgetCenter.shared.reloadTimelines(ofKind: WidgetDataCoordinator.WidgetKind.tagdos)
                        #endif
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                }
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
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Dedicated Cosmos Observatory Window (Can be detached to secondary monitor or full-screen observation)
        Window("Cosmos Observatory", id: "cosmos") {
            CosmosDetailView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)

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
        case MenuBarDisplayMode.iconAndCosmos.rawValue:
            let lat = weatherService.currentWeather?.coord?.lat ?? 44.4323
            let lon = weatherService.currentWeather?.coord?.lon ?? 26.1063
            let moon = AstronomyService.shared.moonPhase(observer: (lat, lon))
            let cond = AstronomyService.shared.evaluateStargazingConditions(
                observer: (lat, lon),
                cloudCoverTotal: weatherService.currentWeather?.clouds?.all,
                cloudCoverLow: nil,
                cloudCoverMid: nil,
                cloudCoverHigh: nil,
                bortleClass: CosmosCatalogService.shared.bortleClass(latitude: lat, longitude: lon)
            )
            HStack(spacing: 3) {
                Image(systemName: moon.quarter.sfSymbol)
                Text("\(cond.score)")
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
    
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "daily" else { return }
        let host = url.host ?? ""
        let path = url.path.lowercased()
        
        let targetTab: NavigationTab
        if host == "habits" || path.contains("habits") {
            targetTab = .habits
        } else if host == "finances" || path.contains("finances") || path.contains("money") {
            targetTab = .finances
        } else if host == "health" || path.contains("health") || path.contains("sleep") || path.contains("stress") {
            targetTab = .health
        } else if host == "weather" || path.contains("weather") {
            targetTab = .weather
        } else if host == "cosmos" || path.contains("cosmos") {
            targetTab = .cosmos
        } else if host == "tagdos" || path.contains("tagdos") {
            TagdosStore.shared.handleDeepLink(url: url)
            targetTab = .tagdos
        } else if host == "news" || path.contains("news") {
            targetTab = .news
        } else if host == "prism" || path.contains("prism") {
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let targetUrl = comps.queryItems?.first(where: { $0.name == "url" })?.value,
               !targetUrl.isEmpty {
                PrismStore.shared.requestOpenInPrism(url: targetUrl)
            }
            targetTab = .prism
        } else {
            targetTab = .dashboard
        }
        
        MacOSWindowManager.shared.activateMainWindow(selectingTab: targetTab)
    }
}
