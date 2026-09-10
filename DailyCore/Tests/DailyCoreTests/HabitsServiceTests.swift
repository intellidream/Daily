import Testing
import Foundation
@testable import DailyCore

@Suite("Habits Service & Models Tests")
struct HabitsServiceTests {
    
    @Test("Water Presets Validation")
    func testWaterPresets() {
        #expect(WaterPreset.smallWater.defaultAmountMl == 150)
        #expect(WaterPreset.largeWater.defaultAmountMl == 300)
        #expect(WaterPreset.glass.defaultAmountMl == 250)
        #expect(WaterPreset.bottle.defaultAmountMl == 500)
        #expect(WaterPreset.coffee.defaultAmountMl == 100)
        #expect(WaterPreset.tea.defaultAmountMl == 250)
        
        #expect(WaterPreset.smallWater.hydrationFactor == 1.0)
        #expect(WaterPreset.coffee.hydrationFactor == 0.80)
        #expect(WaterPreset.tea.hydrationFactor == 0.95)
    }
    
    @Test("Smoke Presets Validation")
    func testSmokePresets() {
        #expect(SmokePreset.cigarette.defaultCount == 1)
        #expect(SmokePreset.heated.defaultCount == 1)
        #expect(SmokePreset.rolled.defaultCount == 1)
        #expect(SmokePreset.cigarillo.defaultCount == 1)
        #expect(SmokePreset.allCases.count == 4)
    }
    
    @Test("Smokes Financials & Avoided Cigarettes Calculations")
    func testSmokesFinancials() {
        let settings = SmokesSettings(
            quitStartDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
            baselineCigsPerDay: 20,
            cigsPerPack: 20,
            costPerPack: 26.50,
            currency: "RON"
        )
        
        #expect(settings.costPerCig == 1.325)
        
        let daysTracked = 10
        let expectedCeiling = daysTracked * settings.baselineCigsPerDay // 200
        let actualSmoked = 40
        let avoided = expectedCeiling - actualSmoked // 160
        let moneySaved = Double(avoided) * settings.costPerCig // 160 * 1.325 = 212.0
        
        let metrics = SmokesFinancialMetrics(
            moneySaved: moneySaved,
            cigsAvoided: avoided,
            daysTracked: daysTracked,
            costPerCig: settings.costPerCig,
            lastSmokeDate: Date().addingTimeInterval(-3600),
            timeSinceLastSmoke: 3600
        )
        
        #expect(metrics.cigsAvoided == 160)
        #expect(abs(metrics.moneySaved - 212.0) < 0.001)
        #expect(metrics.formattedMoneySaved == "+212.00")
        #expect(metrics.formattedTimeSinceLastSmoke == "1h 0m ago")
    }
    
    @Test("Habit Log Record Metadata Parsing")
    func testMetadataParsing() {
        let waterLog = HabitLogRecord(
            habitType: "water",
            value: 300,
            unit: "ml",
            metadata: "{\"drink\":\"Large Water\"}"
        )
        #expect(waterLog.drinkType == "Large Water")
        
        let smokeLog = HabitLogRecord(
            habitType: "smokes",
            value: 1,
            unit: "cigs",
            metadata: "{\"type\":\"Heated Tobacco\"}"
        )
        #expect(smokeLog.smokeType == "Heated Tobacco")
    }
    
    @Test("Offline Queue JSON Round-Trip Serialization")
    func testOfflineQueueSerialization() throws {
        let log = HabitLogRecord(
            id: UUID(),
            habitType: "water",
            value: 250,
            unit: "ml",
            loggedAt: Date(),
            metadata: "{\"drink\":\"Glass\"}"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode([log])
        
        let decoder = JSONDecoder()
        let decodedLogs = try decoder.decode([HabitLogRecord].self, from: data)
        
        #expect(decodedLogs.count == 1)
        #expect(decodedLogs[0].id == log.id)
        #expect(decodedLogs[0].value == 250)
        #expect(decodedLogs[0].drinkType == "Glass")
    }
    
    @Test("Habits Guidance Protocol Validation")
    func testHabitsGuidanceProtocols() {
        // Circadian slots
        #expect(HabitsGuidance.circadianSlots.count == 5)
        #expect(HabitsGuidance.circadianSlots[0].title == "Morning Kickstart")
        #expect(HabitsGuidance.circadianSlots[0].recommendedVolumeMl == 450)
        
        // 4Ds Craving Protocol
        #expect(HabitsGuidance.fourDsCravingProtocol.count == 4)
        let letters = HabitsGuidance.fourDsCravingProtocol.map { $0.letter }
        #expect(letters == ["D", "D", "D", "D"])
        let actions = HabitsGuidance.fourDsCravingProtocol.map { $0.action }
        #expect(actions == ["Delay", "Deep Breathe", "Drink Water", "Distract"])
        
        // Recovery milestones
        #expect(HabitsGuidance.recoveryMilestones.count == 6)
        #expect(HabitsGuidance.recoveryMilestones[0].timeframe == "20 Minutes")
        #expect(HabitsGuidance.recoveryMilestones[5].timeframe == "1 Year")
    }
}
