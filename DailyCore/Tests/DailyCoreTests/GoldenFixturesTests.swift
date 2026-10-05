import Testing
import Foundation
@testable import DailyCore

@Suite("Canonical Health Engine Golden Fixtures Tests")
struct GoldenFixturesTests {
    
    struct FixtureExpected: Codable {
        let steps: Int?
        let activeKcal: Double?
        let sleepAsleepS: Int?
        let sleepScore: Int?
        let stressAvg: Int?
        let rhr: Int?
        let hrvSdnn: Double?
        let primarySleepDevice: String?
        let sleepQualityRating: String?
        let napCount: Int
        
        enum CodingKeys: String, CodingKey {
            case steps
            case activeKcal = "active_kcal"
            case sleepAsleepS = "sleep_asleep_s"
            case sleepScore = "sleep_score"
            case stressAvg = "stress_avg"
            case rhr
            case hrvSdnn = "hrv_sdnn"
            case primarySleepDevice = "primary_sleep_device"
            case sleepQualityRating = "sleep_quality_rating"
            case napCount = "nap_count"
        }
    }
    
    struct FixtureInput: Codable {
        let userId: String
        let targetDate: String
        let tzOffsetMin: Int
        let telemetry: [HealthTelemetryRecord]
        
        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case targetDate = "target_date"
            case tzOffsetMin = "tz_offset_min"
            case telemetry
        }
    }
    
    struct GoldenFixtureFile: Codable {
        let name: String
        let description: String
        let input: FixtureInput
        let expected: FixtureExpected
    }
    
    private func loadFixtures() -> [GoldenFixtureFile] {
        let currentFileUrl = URL(fileURLWithPath: #filePath)
        // Climb: DailyCoreTests -> Tests -> DailyCore -> Source/Daily -> HealthSpec/fixtures
        let repoRoot = currentFileUrl
            .deletingLastPathComponent() // Tests/DailyCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // DailyCore
            .deletingLastPathComponent() // Source/Daily (or Daily repo root)
        
        let fixturesDir = repoRoot.appendingPathComponent("HealthSpec/fixtures")
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let jsonFiles = files.filter { $0.pathExtension == "json" }
        var loaded: [GoldenFixtureFile] = []
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let container = try d.singleValueContainer()
            let str = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: str) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date: \(str)")
        }
        
        for file in jsonFiles {
            if let data = try? Data(contentsOf: file),
               let fixture = try? decoder.decode(GoldenFixtureFile.self, from: data) {
                loaded.append(fixture)
            }
        }
        
        return loaded.sorted { $0.name < $1.name }
    }
    
    @Test("All Golden Fixtures pass with zero mathematical divergence")
    func testGoldenFixturesParity() throws {
        let fixtures = loadFixtures()
        #expect(!fixtures.isEmpty, "Should load at least one golden fixture from HealthSpec/fixtures")
        
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        for fixture in fixtures {
            guard let targetDate = isoFormatter.date(from: fixture.input.targetDate) else {
                Issue.record("Invalid target date: \(fixture.input.targetDate)")
                continue
            }
            
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(secondsFromGMT: fixture.input.tzOffsetMin * 60) ?? .current
            
            // 1. Sleep
            let sleepResult = SleepClusteringEngine.clusterSleep(
                targetDate: targetDate,
                telemetry: fixture.input.telemetry
            )
            
            let primary = sleepResult.primarySession
            let actualSleepS = primary.map { Int($0.asleepSeconds) }
            let actualSleepScore = primary?.sleepScore
            let actualDevice = primary?.sourceDevice
            let actualQuality = primary?.sleepQualityRating
            let actualNaps = sleepResult.naps.count
            
            #expect(actualSleepS == fixture.expected.sleepAsleepS, "[\(fixture.name)] sleep_asleep_s mismatch: expected \(String(describing: fixture.expected.sleepAsleepS)), got \(String(describing: actualSleepS))")
            #expect(actualSleepScore == fixture.expected.sleepScore, "[\(fixture.name)] sleep_score mismatch: expected \(String(describing: fixture.expected.sleepScore)), got \(String(describing: actualSleepScore))")
            #expect(actualDevice == fixture.expected.primarySleepDevice, "[\(fixture.name)] primary_sleep_device mismatch: expected \(String(describing: fixture.expected.primarySleepDevice)), got \(String(describing: actualDevice))")
            if fixture.expected.sleepQualityRating != nil {
                #expect(actualQuality == fixture.expected.sleepQualityRating, "[\(fixture.name)] sleep_quality_rating mismatch")
            }
            #expect(actualNaps == fixture.expected.napCount, "[\(fixture.name)] nap_count mismatch: expected \(fixture.expected.napCount), got \(actualNaps)")
            
            // 2. Steps & Activity
            let stepResult = HealthDataService.calculateDailySteps(
                targetDate: targetDate,
                telemetry: fixture.input.telemetry,
                calendar: cal
            )
            
            let expectedSteps = fixture.expected.steps ?? 0
            #expect(stepResult.totalSteps == expectedSteps, "[\(fixture.name)] steps mismatch: expected \(expectedSteps), got \(stepResult.totalSteps)")
            
            if let expKcal = fixture.expected.activeKcal {
                #expect(abs(stepResult.activeCalories - expKcal) < 1.0, "[\(fixture.name)] active_kcal mismatch: expected \(expKcal), got \(stepResult.activeCalories)")
            }
        }
    }
}
