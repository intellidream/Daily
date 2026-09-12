import SwiftUI
import DailyCore

@main
struct DailyApp: App {
    @ObservedObject private var settingsService = SettingsService.shared
    
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
                .onOpenURL { url in
                    // In case OAuth redirect is handled via external safari rather than ASWebAuthenticationSession
                    print("[DailyApp] Received external URL: \(url)")
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
