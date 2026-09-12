import Foundation

/// Supported sizes for modular dashboard widgets on iOS, matching WinUI tile dimensions.
public enum DashboardWidgetSize: String, Codable, CaseIterable, Sendable {
    case small = "1x1"
    case wide  = "2x1"
    case tall  = "1x2"
    case large = "2x2"
    
    /// Number of columns occupied in a 2-column grid.
    public var columnSpan: Int {
        switch self {
        case .small, .tall: return 1
        case .wide, .large: return 2
        }
    }
    
    /// Number of row units occupied.
    public var rowSpan: Int {
        switch self {
        case .small, .wide: return 1
        case .tall, .large: return 2
        }
    }
    
    /// Human-readable label for UI pickers.
    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .wide:  return "Wide"
        case .tall:  return "Tall"
        case .large: return "Large"
        }
    }
    
    /// SF Symbol icon representing the aspect ratio.
    public var iconName: String {
        switch self {
        case .small: return "square"
        case .wide:  return "rectangle"
        case .tall:  return "rectangle.portrait"
        case .large: return "square.inset.filled"
        }
    }
}

/// Identifiers for standard dashboard widgets.
public enum DashboardWidgetType: String, Codable, CaseIterable, Sendable {
    case weather = "weather"
    case news    = "news"
    case health  = "health"
    case habits  = "habits"
    
    public var title: String {
        switch self {
        case .weather: return "Weather & Atmosphere"
        case .news:    return "News & Briefings"
        case .health:  return "Health & Vitals"
        case .habits:  return "Habits & Cravings"
        }
    }
    
    public var iconName: String {
        switch self {
        case .weather: return "cloud.sun.fill"
        case .news:    return "newspaper.fill"
        case .health:  return "heart.fill"
        case .habits:  return "drop.fill"
        }
    }
}

/// Configuration entry for a single widget on the personal dashboard.
public struct DashboardWidgetConfig: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var size: DashboardWidgetSize
    public var isVisible: Bool
    
    public init(id: String, size: DashboardWidgetSize = .wide, isVisible: Bool = true) {
        self.id = id
        self.size = size
        self.isVisible = isVisible
    }
    
    public var widgetType: DashboardWidgetType? {
        DashboardWidgetType(rawValue: id)
    }
    
    /// Default factory dashboard layout: all 4 primary widgets in wide (2x1) format.
    public static var defaultLayout: [DashboardWidgetConfig] {
        [
            DashboardWidgetConfig(id: DashboardWidgetType.weather.rawValue, size: .wide, isVisible: true),
            DashboardWidgetConfig(id: DashboardWidgetType.news.rawValue, size: .wide, isVisible: true),
            DashboardWidgetConfig(id: DashboardWidgetType.health.rawValue, size: .wide, isVisible: true),
            DashboardWidgetConfig(id: DashboardWidgetType.habits.rawValue, size: .wide, isVisible: true)
        ]
    }
}
