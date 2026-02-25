import SwiftUI

@main
struct DailyWatchApp: App {
    // Initialize our WCSessionManager on app start
    @StateObject private var sessionManager = WatchSessionManager.shared
    
    init() {
        // Force evaluation of the singleton immediately on launch
        _ = WatchSessionManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
