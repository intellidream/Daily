import SwiftUI
import WatchKit

class ExtensionDelegate: NSObject, WKExtensionDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let backgroundTask as WKApplicationRefreshBackgroundTask:
                Task {
                    // Flush any offline habit actions (Health is 100% consumer-only via companion iPhone BLE)
                    await OfflineSyncManager.shared.processQueue()
                    
                    // Schedule next task (respects the user's setting, defaults to 30 mins)
                    let syncFreq = UserDefaults.standard.integer(forKey: "WatchSyncFrequency")
                    let intervalMinutes = syncFreq > 0 ? syncFreq : 30
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
                
                // Eagerly flush any offline habits and refresh throttled habit state
                // (Health telemetry is synced exclusively through the companion iPhone over BLE)
                Task {
                    await OfflineSyncManager.shared.processQueue()
                    habitStore.fetchFullSync(force: false)
                }
                
                // Ensure the background refresh loop is running
                let syncFreq = UserDefaults.standard.integer(forKey: "WatchSyncFrequency")
                let intervalMinutes = syncFreq > 0 ? syncFreq : 30
                let nextDate = Date().addingTimeInterval(TimeInterval(intervalMinutes * 60))
                WKExtension.shared().scheduleBackgroundRefresh(withPreferredDate: nextDate, userInfo: nil) { _ in }
            }
        }
    }
}
