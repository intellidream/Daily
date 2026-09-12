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
    public var newsMediumReadingListUrl: String? = nil
    
    // MARK: - Cloud & Sync
    public var cloudSyncEnabled: Bool = true
    public var lastSyncTimestamp: Date? = nil
    
    // MARK: - Dashboard Layout
    public var dashboardWidgets: [DashboardWidgetConfig] = DashboardWidgetConfig.defaultLayout
    
    public init() {}
    
    enum CodingKeys: String, CodingKey {
        case theme, glassIntensity, hapticsEnabled
        case weatherAlwaysAutoLocation, weatherUnitSystem, weatherWindUnit, weatherPressureUnit, weatherShowSunrise, weatherShowHumidity
        case healthMockDataEnabled, healthSleepTargetHours
        case habitsWaterTargetLiters, habitsRemindersEnabled
        case newsAutoRefreshOnStartup, newsShowImages, newsMediumUsername, newsMediumReadingListUrl
        case cloudSyncEnabled, lastSyncTimestamp
        case dashboardWidgets
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try c.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
        self.glassIntensity = try c.decodeIfPresent(GlassIntensity.self, forKey: .glassIntensity) ?? .medium
        self.hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        self.weatherAlwaysAutoLocation = try c.decodeIfPresent(Bool.self, forKey: .weatherAlwaysAutoLocation) ?? false
        self.weatherUnitSystem = try c.decodeIfPresent(WeatherUnitSystem.self, forKey: .weatherUnitSystem) ?? .metric
        self.weatherWindUnit = try c.decodeIfPresent(String.self, forKey: .weatherWindUnit) ?? "m/s"
        self.weatherPressureUnit = try c.decodeIfPresent(String.self, forKey: .weatherPressureUnit) ?? "hpa"
        self.weatherShowSunrise = try c.decodeIfPresent(Bool.self, forKey: .weatherShowSunrise) ?? true
        self.weatherShowHumidity = try c.decodeIfPresent(Bool.self, forKey: .weatherShowHumidity) ?? true
        self.healthMockDataEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthMockDataEnabled) ?? false
        self.healthSleepTargetHours = try c.decodeIfPresent(Double.self, forKey: .healthSleepTargetHours) ?? 8.0
        self.habitsWaterTargetLiters = try c.decodeIfPresent(Double.self, forKey: .habitsWaterTargetLiters) ?? 2.0
        self.habitsRemindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .habitsRemindersEnabled) ?? true
        self.newsAutoRefreshOnStartup = try c.decodeIfPresent(Bool.self, forKey: .newsAutoRefreshOnStartup) ?? true
        self.newsShowImages = try c.decodeIfPresent(Bool.self, forKey: .newsShowImages) ?? true
        self.newsMediumUsername = try c.decodeIfPresent(String.self, forKey: .newsMediumUsername)
        self.newsMediumReadingListUrl = try c.decodeIfPresent(String.self, forKey: .newsMediumReadingListUrl)
        self.cloudSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .cloudSyncEnabled) ?? true
        self.lastSyncTimestamp = try c.decodeIfPresent(Date.self, forKey: .lastSyncTimestamp)
        
        let loadedWidgets = try c.decodeIfPresent([DashboardWidgetConfig].self, forKey: .dashboardWidgets)
        if let loadedWidgets = loadedWidgets, !loadedWidgets.isEmpty {
            self.dashboardWidgets = loadedWidgets
        } else {
            self.dashboardWidgets = DashboardWidgetConfig.defaultLayout
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(theme, forKey: .theme)
        try c.encode(glassIntensity, forKey: .glassIntensity)
        try c.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try c.encode(weatherAlwaysAutoLocation, forKey: .weatherAlwaysAutoLocation)
        try c.encode(weatherUnitSystem, forKey: .weatherUnitSystem)
        try c.encode(weatherWindUnit, forKey: .weatherWindUnit)
        try c.encode(weatherPressureUnit, forKey: .weatherPressureUnit)
        try c.encode(weatherShowSunrise, forKey: .weatherShowSunrise)
        try c.encode(weatherShowHumidity, forKey: .weatherShowHumidity)
        try c.encode(healthMockDataEnabled, forKey: .healthMockDataEnabled)
        try c.encode(healthSleepTargetHours, forKey: .healthSleepTargetHours)
        try c.encode(habitsWaterTargetLiters, forKey: .habitsWaterTargetLiters)
        try c.encode(habitsRemindersEnabled, forKey: .habitsRemindersEnabled)
        try c.encode(newsAutoRefreshOnStartup, forKey: .newsAutoRefreshOnStartup)
        try c.encode(newsShowImages, forKey: .newsShowImages)
        try c.encodeIfPresent(newsMediumUsername, forKey: .newsMediumUsername)
        try c.encodeIfPresent(newsMediumReadingListUrl, forKey: .newsMediumReadingListUrl)
        try c.encode(cloudSyncEnabled, forKey: .cloudSyncEnabled)
        try c.encodeIfPresent(lastSyncTimestamp, forKey: .lastSyncTimestamp)
        try c.encode(dashboardWidgets, forKey: .dashboardWidgets)
    }
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
