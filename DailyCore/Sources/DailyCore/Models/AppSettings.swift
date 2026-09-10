import Foundation

/// Application-wide user preferences and settings, mirroring the WinUI AppSettings schema
/// and synchronized across Apple platforms (iOS, macOS, and watchOS) via App Groups.
public struct AppSettings: Codable, Equatable, Sendable {
    // MARK: - Appearance & Tactile Glass
    public var theme: AppTheme = .dark
    public var glassIntensity: GlassIntensity = .medium
    public var hapticsEnabled: Bool = true
    
    // MARK: - Weather Preferences
    public var weatherAlwaysAutoLocation: Bool = false
    public var weatherUnitSystem: WeatherUnitSystem = .metric
    public var weatherWindUnit: String = "m/s"
    public var weatherPressureUnit: String = "hpa"
    public var weatherShowSunrise: Bool = true
    public var weatherShowHumidity: Bool = true
    
    // MARK: - Health & Vitals
    public var healthMockDataEnabled: Bool = false
    public var healthSleepTargetHours: Double = 8.0
    
    // MARK: - Habits Tracking
    public var habitsWaterTargetLiters: Double = 2.0
    public var habitsRemindersEnabled: Bool = true
    
    // MARK: - News Configuration
    public var newsAutoRefreshOnStartup: Bool = true
    public var newsShowImages: Bool = true
    public var newsMediumUsername: String? = nil
    
    // MARK: - Cloud & Sync
    public var cloudSyncEnabled: Bool = true
    public var lastSyncTimestamp: Date? = nil
    
    public init() {}
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case dark = "dark"
    case light = "light"
    
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

public enum GlassIntensity: String, Codable, CaseIterable, Sendable {
    case subtle = "subtle"
    case medium = "medium"
    case high = "high"
    
    public var displayName: String {
        switch self {
        case .subtle: return "Subtle"
        case .medium: return "Medium"
        case .high: return "Prominent"
        }
    }
    
    public var blurOpacity: Double {
        switch self {
        case .subtle: return 0.12
        case .medium: return 0.20
        case .high: return 0.32
        }
    }
}

public enum WeatherUnitSystem: String, Codable, CaseIterable, Sendable {
    case metric = "metric"
    case imperial = "imperial"
    
    public var displayName: String {
        switch self {
        case .metric: return "Metric (°C, m/s)"
        case .imperial: return "Imperial (°F, mph)"
        }
    }
    
    public var temperatureSymbol: String {
        switch self {
        case .metric: return "°C"
        case .imperial: return "°F"
        }
    }
}
