import Foundation
import Combine

/// Thread-safe settings manager for DayOne, persisting preferences across app lifecycles
/// and notifying UI subscribers when settings change.
@MainActor
public final class SettingsService: ObservableObject {
    public static let shared = SettingsService()
    
    @Published public private(set) var settings: AppSettings
    
    private let storage: GroupDefaults
    
    public init(storage: GroupDefaults = .shared) {
        self.storage = storage
        self.settings = storage.loadSettings()
    }
    
    /// Update settings in place and persist changes to AppGroup storage.
    public func update(_ mutator: (inout AppSettings) -> Void) {
        mutator(&settings)
        storage.saveSettings(settings)
    }
    
    /// Reset settings to their factory defaults.
    public func resetToDefaults() {
        settings = AppSettings()
        storage.saveSettings(settings)
    }
}
