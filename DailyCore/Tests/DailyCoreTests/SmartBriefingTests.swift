import Testing
import Foundation
@testable import DailyCore

@Suite("Smart Briefing Models & Service Tests")
struct SmartBriefingTests {

    @Test("BriefingTimeSlot hour resolution across 24 hours")
    func testTimeSlotResolution() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Morning: 5:00 - 11:59
        let morningDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 7, minute: 30))!
        #expect(BriefingTimeSlot.current(for: morningDate, calendar: cal) == .morning)

        // Intraday: 12:00 - 16:59
        let intradayDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 13, minute: 15))!
        #expect(BriefingTimeSlot.current(for: intradayDate, calendar: cal) == .intraday)

        // Evening: 17:00 - 21:59
        let eveningDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 19, minute: 45))!
        #expect(BriefingTimeSlot.current(for: eveningDate, calendar: cal) == .evening)

        // Nightly: 22:00 - 04:59
        let nightlyDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 23, minute: 10))!
        #expect(BriefingTimeSlot.current(for: nightlyDate, calendar: cal) == .nightly)

        let lateNightDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 2, minute: 0))!
        #expect(BriefingTimeSlot.current(for: lateNightDate, calendar: cal) == .nightly)
    }

    @Test("SmartBriefingNarrative concatenated text joins sections with double newlines")
    func testNarrativeConcatenation() {
        let narrative = SmartBriefingNarrative(
            greeting: "Good morning, Mihai!",
            weatherText: "22°C and sunny.",
            healthText: "Great recovery with 8.0h sleep.",
            habitsText: "1.2L of water logged.",
            financeText: "Net worth steady.",
            tagdosText: "3 streams active.",
            newsText: "Tech stocks gain.",
            outroText: "Make today count."
        )

        let fullText = narrative.fullConcatenatedText
        #expect(fullText.contains("Good morning, Mihai!"))
        #expect(fullText.contains("22°C and sunny."))
        #expect(fullText.contains("Great recovery with 8.0h sleep."))
        #expect(fullText.contains("Make today count."))
        #expect(narrative.structuredSections.count == 6)
    }

    @Test("Tier 1 Local Synthesizer produces empathetic habit and recovery narrative")
    @MainActor
    func testLocalSynthesizerEmpathy() {
        let service = SmartBriefingService.shared

        let metrics = SmartBriefingMetrics(
            weatherTemp: 21.4,
            weatherCondition: "Clear Sky",
            weatherCity: "Bucharest",
            sleepScore: 88,
            sleepDurationHours: 8.2,
            restingBpm: 60.0,
            totalStepsToday: 4200,
            waterMlToday: 1500,
            waterGoalMl: 2000,
            smokesToday: 3,
            smokesBaseline: 10,
            netWorth: 15400,
            daySpend: 120,
            activeStreamCount: 4,
            activeMemoCount: 2,
            topNewsTitle: "Global Markets Advance"
        )

        let narrative = service.synthesizeLocalNarrative(
            slot: .morning,
            userName: "Mihai",
            metrics: metrics,
            activeStreams: ["Work", "Fitness", "Personal", "Code"]
        )

        #expect(narrative.greeting.contains("Good morning, Mihai!"))
        #expect(narrative.weatherText.contains("Clear Sky"))
        #expect(narrative.healthText.contains("88/100"))
        // Check smoking reduction constructive empathy:
        #expect(narrative.habitsText.contains("safely maintaining below your daily baseline"))
        #expect(narrative.habitsText.contains("1.5L / 2.0L"))
        #expect(narrative.tagdosText.contains("4 mental streams active"))
    }

    @Test("Data hash sensitivity across metric variations")
    @MainActor
    func testDataHashSensitivity() {
        let service = SmartBriefingService.shared

        var m1 = SmartBriefingMetrics(
            weatherTemp: 20.0,
            sleepScore: 80,
            totalStepsToday: 2000,
            waterMlToday: 1000,
            smokesToday: 2,
            netWorth: 10000
        )

        let h1 = service.computeDataHash(slot: .morning, metrics: m1, streamCount: 3)
        let h2 = service.computeDataHash(slot: .morning, metrics: m1, streamCount: 3)
        #expect(h1 == h2)

        // Slot change changes hash
        let hIntraday = service.computeDataHash(slot: .intraday, metrics: m1, streamCount: 3)
        #expect(h1 != hIntraday)

        // Steps increase beyond bucket changes hash
        m1.totalStepsToday = 3500
        let hStepsChanged = service.computeDataHash(slot: .morning, metrics: m1, streamCount: 3)
        #expect(h1 != hStepsChanged)
    }

    @Test("AppSettings includes smart briefing defaults and persists to JSON")
    func testAppSettingsSmartBriefing() throws {
        var settings = AppSettings()
        #expect(settings.smartBriefingEnabled == true)
        #expect(settings.smartBriefingAutoMorning == true)
        #expect(settings.geminiApiKey == nil)

        settings.geminiApiKey = "test_key_123"
        settings.smartBriefingAutoMorning = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.smartBriefingEnabled == true)
        #expect(decoded.smartBriefingAutoMorning == false)
        #expect(decoded.geminiApiKey == "test_key_123")
    }
}
