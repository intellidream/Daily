import Foundation
import Testing
@testable import DailyCore

@Suite("Dashboard Layout & Widget Models Tests")
struct DashboardLayoutTests {
    @Test("Widget Size Matrix Dimensions")
    func testWidgetSizeDimensions() {
        #expect(DashboardWidgetSize.small.columnSpan == 1)
        #expect(DashboardWidgetSize.small.rowSpan == 1)
        
        #expect(DashboardWidgetSize.wide.columnSpan == 2)
        #expect(DashboardWidgetSize.wide.rowSpan == 1)
        
        #expect(DashboardWidgetSize.tall.columnSpan == 1)
        #expect(DashboardWidgetSize.tall.rowSpan == 2)
        
        #expect(DashboardWidgetSize.large.columnSpan == 2)
        #expect(DashboardWidgetSize.large.rowSpan == 2)
    }
    
    @Test("Default Dashboard Layout Configuration")
    func testDefaultLayout() {
        let defaults = DashboardWidgetConfig.defaultLayout
        #expect(defaults.count == 4)
        #expect(defaults.map(\.id) == ["weather", "news", "health", "habits"])
        #expect(defaults.allSatisfy { $0.size == .wide && $0.isVisible })
    }
    
    @Test("AppSettings JSON Round-Trip with Custom Dashboard Widgets")
    func testAppSettingsRoundTripWithWidgets() throws {
        var settings = AppSettings()
        settings.dashboardWidgets = [
            DashboardWidgetConfig(id: "weather", size: .small),
            DashboardWidgetConfig(id: "health", size: .small),
            DashboardWidgetConfig(id: "news", size: .tall),
            DashboardWidgetConfig(id: "habits", size: .large)
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppSettings.self, from: data)
        
        #expect(decoded.dashboardWidgets.count == 4)
        #expect(decoded.dashboardWidgets[0].size == .small)
        #expect(decoded.dashboardWidgets[1].size == .small)
        #expect(decoded.dashboardWidgets[2].size == .tall)
        #expect(decoded.dashboardWidgets[3].size == .large)
    }
    
    @Test("Legacy AppSettings JSON Graceful Fallback to Default Widgets")
    func testLegacyAppSettingsFallback() throws {
        // Legacy JSON without `dashboardWidgets` key
        let legacyJson = """
        {
            "theme": "dark",
            "glassIntensity": "medium",
            "hapticsEnabled": true
        }
        """
        let data = legacyJson.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        
        #expect(decoded.dashboardWidgets.count == 4)
        #expect(decoded.dashboardWidgets == DashboardWidgetConfig.defaultLayout)
    }
}
