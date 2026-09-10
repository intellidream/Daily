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
}
