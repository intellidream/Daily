import SwiftUI

@main
struct DailyWatchApp: App {
    // Initialize our WCSessionManager on app start
    @StateObject private var sessionManager = WatchSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Force evaluation of the singleton immediately on launch
        _ = WatchSessionManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Eagerly try to flush any offline habits logged while disconnected
                OfflineSyncManager.shared.processQueue()
            }
        }
    }
}
