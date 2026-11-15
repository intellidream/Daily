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
    
    @Test("Water Preset Cross-Platform Matching & Color Resolution")
    func testWaterPresetMatching() {
        // Exact raw values
        #expect(WaterPreset.matching("Small Water") == .smallWater)
        #expect(WaterPreset.matching("Large Water") == .largeWater)
        #expect(WaterPreset.matching("Coffee") == .coffee)
        
        // Android and shorthand display names
        #expect(WaterPreset.matching("Small") == .smallWater)
        #expect(WaterPreset.matching("Large") == .largeWater)
        #expect(WaterPreset.matching("small") == .smallWater)
        #expect(WaterPreset.matching("large") == .largeWater)
        #expect(WaterPreset.matching("Glass") == .glass)
        #expect(WaterPreset.matching("Bottle") == .bottle)
        
        // Romanian and alias names
        #expect(WaterPreset.matching("pahar") == .glass)
        #expect(WaterPreset.matching("sticla") == .bottle)
        #expect(WaterPreset.matching("apa") == .largeWater)
        #expect(WaterPreset.matching("apă") == .largeWater)
        #expect(WaterPreset.matching("espresso") == .coffee)
        #expect(WaterPreset.matching("ceai") == .tea)
        
        // Colors should match blue/cyan tones for water
        #expect(WaterPreset.matching("Small")?.hexColor == "#38BDF8")
        #expect(WaterPreset.matching("Large")?.hexColor == "#00E5FF")
        #expect(WaterPreset.matching("Coffee")?.hexColor == "#F59E0B")
    }

    @Test("Atomic Habits Widget Bridge Overrides Stale UserDefaults (N-1 Lag Prevention)")
    func testAtomicBridgeOverridesStaleDefaults() throws {
        let suiteName = "test.daily.bridge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let bridgeURL = tempDir.appendingPathComponent("daily_habits_widget_bridge_v1.json")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        let todayKey = df.string(from: Date())

        // Simulate stale cfprefsd cache still holding N-1 (4 smokes, 750ml water)
        defaults.set(4, forKey: "cached_smokes_total")
        defaults.set(750, forKey: "cached_water_total")
        defaults.set(todayKey, forKey: "cached_habits_date")
        defaults.set("20", forKey: "smokes_baseline")
        defaults.set("2000", forKey: "water_goal")

        let now = Date()
        let latestSmoke = HabitLogRecord(
            id: UUID(),
            habitType: "smokes",
            value: 1,
            unit: "cigs",
            loggedAt: now,
            metadata: "{\"type\":\"Cigarette\"}"
        )
        let priorSmokes = HabitLogRecord(
            id: UUID(),
            habitType: "smokes",
            value: 4,
            unit: "cigs",
            loggedAt: now.addingTimeInterval(-600),
            metadata: "{\"type\":\"Cigarette\"}"
        )
        let waterLog = HabitLogRecord(
            id: UUID(),
            habitType: "water",
            value: 1000,
            unit: "ml",
            loggedAt: now,
            metadata: "{\"drink\":\"Water\"}"
        )

        let bridgeState = HabitsWidgetBridgeState(
            dateKey: todayKey,
            waterTotalMl: 1000,
            waterGoalMl: 2500,
            waterLogs: [waterLog],
            smokesTotal: 5,
            smokesBaseline: 15,
            smokesLogs: [latestSmoke, priorSmokes],
            deletedIds: [],
            updatedAt: now
        )
        WidgetDataCoordinator.shared.writeHabitsBridgeState(bridgeState, bridgeFileURL: bridgeURL)

        let smokesSnapshot = WidgetDataCoordinator.shared.fetchSmokesSnapshot(bridgeFileURL: bridgeURL, defaults: defaults)
        #expect(smokesSnapshot.todayTotal == 5)
        #expect(smokesSnapshot.cigsCount == 5)
        #expect(smokesSnapshot.baseline == 15)
        #expect(smokesSnapshot.lastSmokeDate != nil)

        let bubblesSnapshot = WidgetDataCoordinator.shared.fetchBubblesSnapshot(bridgeFileURL: bridgeURL, defaults: defaults)
        #expect(bubblesSnapshot.todayMl == 1000)
        #expect(bubblesSnapshot.goalMl == 2500)
        #expect(bubblesSnapshot.waterMl == 1000)
    }

    @Test("Atomic Habits Widget Bridge Filters Deleted Logs & Ignores Stale Dates")
    func testAtomicBridgeTombstonesAndDateRollover() throws {
        let suiteName = "test.daily.bridge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let bridgeURL = tempDir.appendingPathComponent("daily_habits_widget_bridge_v1.json")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        let todayKey = df.string(from: Date())

        let deletedId = UUID()
        let activeId = UUID()
        let bridgeWithTombstone = HabitsWidgetBridgeState(
            dateKey: todayKey,
            waterTotalMl: 250,
            waterGoalMl: 2000,
            waterLogs: [],
            smokesTotal: 1,
            smokesBaseline: 20,
            smokesLogs: [
                HabitLogRecord(id: deletedId, habitType: "smokes", value: 1, unit: "cigs", loggedAt: Date(), metadata: "{\"type\":\"Heated Tobacco\"}"),
                HabitLogRecord(id: activeId, habitType: "smokes", value: 1, unit: "cigs", loggedAt: Date(), metadata: "{\"type\":\"Cigarette\"}")
            ],
            deletedIds: [deletedId.uuidString],
            updatedAt: Date()
        )
        WidgetDataCoordinator.shared.writeHabitsBridgeState(bridgeWithTombstone, bridgeFileURL: bridgeURL)

        let smokesSnapshot = WidgetDataCoordinator.shared.fetchSmokesSnapshot(bridgeFileURL: bridgeURL, defaults: defaults)
        #expect(smokesSnapshot.todayTotal == 1)
        #expect(smokesSnapshot.cigsCount == 1)
        #expect(smokesSnapshot.heatedCount == 0)

        // Now verify stale yesterday bridge + yesterday cached defaults reset cleanly to 0 for Today
        defaults.set(9, forKey: "cached_smokes_total")
        defaults.set("2020-01-01", forKey: "cached_habits_date")
        let staleBridge = HabitsWidgetBridgeState(
            dateKey: "2020-01-01",
            waterTotalMl: 1500,
            waterGoalMl: 2000,
            waterLogs: [],
            smokesTotal: 9,
            smokesBaseline: 20,
            smokesLogs: [],
            deletedIds: [],
            updatedAt: Date()
        )
        WidgetDataCoordinator.shared.writeHabitsBridgeState(staleBridge, bridgeFileURL: bridgeURL)

        let rolledOverSnapshot = WidgetDataCoordinator.shared.fetchSmokesSnapshot(bridgeFileURL: bridgeURL, defaults: defaults)
        #expect(rolledOverSnapshot.todayTotal == 0)
    }
}

