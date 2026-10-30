import Foundation

/// Centralized access to App Group UserDefaults for cross-target data sharing (iOS, WatchOS, Widgets, macOS).
public final class GroupDefaults: @unchecked Sendable {
    public static let shared = GroupDefaults()
    
#if os(macOS)
    public static let suiteName = "7LZ9ZT2Z5B.group.com.intellidream.daily"
    public static let legacySuiteName = "group.com.intellidream.daily"
#else
    public static let suiteName = "group.com.intellidream.daily"
    public static let legacySuiteName = "group.com.intellidream.daily"
#endif
    public let userDefaults: UserDefaults
    
    public init() {
        self.userDefaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        
        #if os(macOS)
        // Seamlessly migrate legacy data from un-prefixed suite to Team-prefixed suite in macOS App Sandbox
        if let legacy = UserDefaults(suiteName: Self.legacySuiteName) {
            let legacyDict = legacy.dictionaryRepresentation()
            for (k, v) in legacyDict {
                if !k.hasPrefix("Apple") && !k.hasPrefix("NS") && !k.hasPrefix("AK") && !k.hasPrefix("com.apple") {
                    if self.userDefaults.object(forKey: k) == nil {
                        self.userDefaults.set(v, forKey: k)
                    }
                }
            }
        }
        #endif
    }
    
    // MARK: - AppSettings Storage
    
    private let settingsKey = "dayone_app_settings"
    
    public func loadSettings() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey) else {
            return AppSettings()
        }
        do {
            let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
            return decoded
        } catch {
            return AppSettings()
        }
    }
    
    public func saveSettings(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: settingsKey)
        } catch {
            print("[GroupDefaults] Failed to encode settings: \(error)")
        }
    }
    
    // MARK: - Guest Flag
    
    private let isGuestKey = "dayone_is_guest_mode"
    
    public var isGuestMode: Bool {
        get { userDefaults.bool(forKey: isGuestKey) || UserDefaults.standard.bool(forKey: isGuestKey) }
        set {
            userDefaults.set(newValue, forKey: isGuestKey)
            UserDefaults.standard.set(newValue, forKey: isGuestKey)
        }
    }
    
    // MARK: - Token Mirroring (convenience fallback alongside Keychain)
    
    public func setTokenMirror(accessToken: String?, refreshToken: String?, userId: String?) {
        userDefaults.set(accessToken, forKey: "supabase_access_token")
        userDefaults.set(refreshToken, forKey: "supabase_refresh_token")
        userDefaults.set(userId, forKey: "supabase_user_id")
    }
    
    public func clearTokenMirror() {
        userDefaults.removeObject(forKey: "supabase_access_token")
        userDefaults.removeObject(forKey: "supabase_refresh_token")
        userDefaults.removeObject(forKey: "supabase_user_id")
    }
}
