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
        #expect(metrics.moneySavedFormatted == "+212.00 RON")
        #expect(metrics.lifeRegainedFormatted == "29h 20m")
        #expect(metrics.formattedTimeSinceLastSmoke == "1h 0m ago")
        
        let usdMetrics = SmokesFinancialMetrics(
            moneySaved: 50.0,
            cigsAvoided: 25,
            daysTracked: 5,
            costPerCig: 2.0,
            currency: "USD"
        )
        #expect(usdMetrics.moneySavedFormatted == "+50.00 USD")
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
    
    @Test("Multiplier Logging and Display Formatting")
    func testMultiplierLoggingAndDisplay() {
        let coffeeLog = HabitLogRecord(
            habitType: "water",
            value: 200,
            unit: "ml",
            metadata: "{\"drink\":\"Coffee\",\"multiplier\":\"2\",\"base_value\":\"100\"}"
        )
        #expect(coffeeLog.multiplier == 2)
        #expect(coffeeLog.displayTitleWithMultiplier == "2× Coffee (+200 ml)")
        #expect(coffeeLog.specificIconName == "cup.and.saucer.fill")
        #expect(coffeeLog.specificIconColorHex == "#F59E0B")
        
        let smokeLog = HabitLogRecord(
            habitType: "smokes",
            value: 3,
            unit: "cigs",
            metadata: "{\"type\":\"Cigarette\",\"multiplier\":\"3\",\"base_value\":\"1\"}"
        )
        #expect(smokeLog.multiplier == 3)
        #expect(smokeLog.displayTitleWithMultiplier == "3× Cigarette (+3)")
        #expect(smokeLog.specificIconName == "flame.fill")
        #expect(smokeLog.specificIconColorHex == "#EF4444")
    }
    
    @Test("Specific Icons & Colors for Beverage and Tobacco Types")
    func testSpecificIconsAndColors() {
        let teaLog = HabitLogRecord(
            habitType: "water",
            value: 250,
            unit: "ml",
            metadata: "{\"drink\":\"Tea\"}"
        )
        #expect(teaLog.specificIconName == "mug.fill")
        #expect(teaLog.specificIconColorHex == "#10B981")
        
        let bottleLog = HabitLogRecord(
            habitType: "water",
            value: 500,
            unit: "ml",
            metadata: "{\"drink\":\"Bottle\"}"
        )
        #expect(bottleLog.specificIconName == "waterbottle.fill")
        
        let cigaretteLog = HabitLogRecord(
            habitType: "smokes",
            value: 1,
            unit: "cigs",
            metadata: "{\"type\":\"Cigarette\"}"
        )
        #expect(cigaretteLog.specificIconName == "flame.fill")
        #expect(cigaretteLog.specificIconColorHex == "#EF4444")
        
        let cigarilloLog = HabitLogRecord(
            habitType: "smokes",
            value: 1,
            unit: "cigs",
            metadata: "{\"type\":\"Cigarillo\"}"
        )
        #expect(cigarilloLog.specificIconName == "flame")
        #expect(cigarilloLog.specificIconColorHex == "#A855F7")
        
        let heatedLog = HabitLogRecord(
            habitType: "smokes",
            value: 1,
            unit: "cigs",
            metadata: "{\"type\":\"Heated Tobacco\"}"
        )
        #expect(heatedLog.specificIconName == "bolt.fill")
        #expect(heatedLog.specificIconColorHex == "#3B82F6")
        
        let rolledLog = HabitLogRecord(
            habitType: "smokes",
            value: 1,
            unit: "cigs",
            metadata: "{\"type\":\"Rolled\"}"
        )
        #expect(rolledLog.specificIconName == "leaf.fill")
        #expect(rolledLog.specificIconColorHex == "#F97316")
    }
    
    @Test("User Preferences Record JSON Decoding")
    func testUserPreferencesDecoding() throws {
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789abc",
            "smokes_baseline": 15,
            "smokes_pack_size": 20,
            "smokes_pack_cost": 27.50,
            "smokes_currency": "RON",
            "smokes_quit_date": "2026-01-01T00:00:00Z",
            "water_goal": 2500.0
        }
        """
        let data = json.data(using: .utf8)!
        let pref = try JSONDecoder().decode(UserPreferencesRecord.self, from: data)
        #expect(pref.smokes_baseline == 15)
        #expect(pref.smokes_pack_size == 20)
        #expect(pref.smokes_pack_cost == 27.50)
        #expect(pref.smokes_currency == "RON")
        #expect(pref.water_goal == 2500.0)
    }
    
    @Test("Habits Consistency Row Decoding & Date Normalization")
    func testHabitsConsistencyRowDecoding() throws {
        let json = """
        [
            {"day": "2026-09-01", "total_value": 2400.0, "log_count": 8},
            {"day": "2026-09-02T00:00:00Z", "total_value": 15, "log_count": 5}
        ]
        """
        let data = json.data(using: .utf8)!
        let rows = try JSONDecoder().decode([HabitsConsistencyRow].self, from: data)
        #expect(rows.count == 2)
        #expect(rows[0].normalizedDayKey == "2026-09-01")
        #expect(rows[0].total_value.value == 2400.0)
        #expect(rows[0].log_count == 8)
        #expect(rows[1].normalizedDayKey == "2026-09-02")
        #expect(rows[1].total_value.value == 15.0)
        
        // FlexibleDouble encoding round-trip
        let encoded = try JSONEncoder().encode(rows[0])
        let decoded = try JSONDecoder().decode(HabitsConsistencyRow.self, from: encoded)
        #expect(decoded.day == "2026-09-01")
        #expect(decoded.total_value.value == 2400.0)
    }
    
    @Test("Habit Date Parser Date-Only String Parsing")
    func testHabitDateParserYMD() {
        let parsed = HabitDateParser.parse("2026-09-01")
        #expect(parsed != nil)
    }
}

