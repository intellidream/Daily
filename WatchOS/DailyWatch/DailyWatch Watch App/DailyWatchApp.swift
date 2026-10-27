import SwiftUI
import WatchKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                Task {
                    // Try to authorize HealthKit if we haven't
                    try? await HealthTelemetryManager.shared.requestAuthorization()
                    
                    // Determine if we need a deep sync (every 4 hours)
                    let lastDeepSync = UserDefaults.standard.double(forKey: "lastDeepSync")
                    let isDeepSync = Date().timeIntervalSince1970 - lastDeepSync >= 4 * 3600
                    
                    // Sync telemetry
                    await HealthTelemetryManager.shared.syncTelemetry(isDeepSync: isDeepSync)
                    
                    if isDeepSync {
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastDeepSync")
                    }
                    
                    // Also flush any offline habits
                    await OfflineSyncManager.shared.processQueue()
                    
                    // Schedule next task (respects the user's setting, defaults to 15 mins)
                    let syncFreq = UserDefaults.standard.integer(forKey: "WatchSyncFrequency")
                    let intervalMinutes = syncFreq > 0 ? syncFreq : 15
                    let nextDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
                    
                    WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: nextDate, userInfo: nil) { error in
                        if let error = error {
                            print("Error scheduling next refresh: \(error)")
                        }
                    }
                    
                    backgroundTask.setTaskCompletedWithSnapshot(false)
                }
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main
struct DailyWatchApp: App {
    @WKExtensionDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    
    // Initialize our WCSessionManager and WatchHabitStore on app start
    @StateObject private var sessionManager = WatchSessionManager.shared
    @StateObject private var habitStore = WatchHabitStore.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Force evaluation of singletons immediately on launch
        _ = WatchSessionManager.shared
        _ = WatchHabitStore.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Proactively refresh the Supabase session after watchOS sleep
                sessionManager.onAppBecameActive()
                
                // Try to ask for permissions on active if we haven't
                Task {
                    try? await HealthTelemetryManager.shared.requestAuthorization()
                }
                
                // Eagerly try to flush any offline habits and health data
                Task {
                    await OfflineSyncManager.shared.processQueue()
                    await habitStore.fetchFullSync()
                    
                    let lastDeepSync = UserDefaults.standard.double(forKey: "lastDeepSync")
                    let isDeepSync = Date().timeIntervalSince1970 - lastDeepSync >= 4 * 3600
                    
                    await HealthTelemetryManager.shared.syncTelemetry(isDeepSync: isDeepSync)
                    
                    if isDeepSync {
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastDeepSync")
                    }
                }
                
                // Ensure the background refresh loop is running
                let syncFreq = UserDefaults.standard.integer(forKey: "WatchSyncFrequency")
                let intervalMinutes = syncFreq > 0 ? syncFreq : 15
                let nextDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
                WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: nextDate, userInfo: nil) { _ in }
            }
        }
    }
}
