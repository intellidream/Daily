import Foundation
import Testing
@testable import DailyCore

struct DailyCoreTests {
    @Test func testAppSettingsDefaults() async throws {
        let settings = AppSettings()
        #expect(settings.theme == .dark)
        #expect(settings.weatherUnitSystem == .metric)
        #expect(settings.healthSleepTargetHours == 8.0)
    }
    
    @Test func testUserProfileFirstNameExtraction() async throws {
        let profile1 = UserProfile(id: "1", fullName: "Mihai Popescu")
        #expect(profile1.firstName == "Mihai")
        
        let profile2 = UserProfile(id: "2", email: "john.doe@example.com")
        #expect(profile2.firstName == "John")
        
        let guest = UserProfile.guest
        #expect(guest.firstName == "Guest")
    }
    
    @Test func testWatchPlatformProperties() async throws {
        #expect(WatchPlatform.watchOS.displayName == "Apple Watch")
        #expect(WatchPlatform.watchOS.shortDisplayName == "Apple")
        #expect(WatchPlatform.watchOS.systemImage == "applewatch")
        
        #expect(WatchPlatform.wearOS.displayName == "Wear OS")
        #expect(WatchPlatform.harmonyOS.displayName == "HarmonyOS")
        #expect(WatchPlatform.zeppOS.displayName == "Zepp OS")
    }
    
    @Test func testAppSettingsWatchSyncFrequency() async throws {
        var settings = AppSettings()
        #expect(settings.watchSyncFrequency == 15)
        
        settings.watchSyncFrequency = 30
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.watchSyncFrequency == 30)
    }
    
    @Test func testPairedWatchDecoding() async throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "user_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "platform": "zeppos",
            "device_name": "Amazfit Balance",
            "paired_at": "2026-09-16T18:30:00Z",
            "is_active": true
        }
        """.data(using: .utf8)!
        
        let watch = try JSONDecoder().decode(PairedWatch.self, from: json)
        #expect(watch.id == "11111111-2222-3333-4444-555555555555")
        #expect(watch.platformType == WatchPlatform.zeppOS)
        #expect(watch.displayTitle == "Amazfit Balance")
        #expect(watch.isActive == true)
        #expect(watch.pairedAt != nil)
    }
    
    @Test @MainActor func testOrbitServiceInvalidPinValidation() async throws {
        let service = OrbitWatchService()
        let result = await service.pairWatch(pin: "123", platform: .watchOS)
        #expect(result == false)
        #expect(service.pairingError?.contains("6-digit") == true)
    }
}
