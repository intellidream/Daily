import XCTest
@testable import DailyCore

final class SleepGuidanceTests: XCTestCase {
    
    func testOptimalSleepSessionEvaluation() {
        let start = Date()
        let end = start.addingTimeInterval(8 * 3600) // 8 hours
        
        let stages: [SleepStageRecord] = [
            SleepStageRecord(stageType: .deep, startTime: start, endTime: start.addingTimeInterval(1.8 * 3600)), // 1.8h deep (22.5%)
            SleepStageRecord(stageType: .rem, startTime: start.addingTimeInterval(1.8 * 3600), endTime: start.addingTimeInterval(3.6 * 3600)), // 1.8h rem (22.5%)
            SleepStageRecord(stageType: .light, startTime: start.addingTimeInterval(3.6 * 3600), endTime: start.addingTimeInterval(7.6 * 3600)), // 4.0h light (50%)
            SleepStageRecord(stageType: .awake, startTime: start.addingTimeInterval(7.6 * 3600), endTime: end) // 0.4h awake
        ]
        
        let session = SleepSession(startTime: start, endTime: end, isNap: false, stages: stages, sourceDevice: "Apple Watch Ultra 2", hasGranularHypnogram: true)
        
        let result = SleepAnalysisEngine.shared.analyze(session: session)
        
        XCTAssertEqual(result.verdict.status, .optimal)
        XCTAssertGreaterThanOrEqual(result.verdict.readinessScore, 85)
        XCTAssertEqual(result.verdict.physicalRepairRating, "High")
        XCTAssertEqual(result.verdict.cognitiveRestoreRating, "High")
        XCTAssertFalse(result.tips.isEmpty)
        XCTAssertFalse(result.aiContext.suggestedPrompts.isEmpty)
    }
    
    func testDisruptedSleepProducesDeficitAndActionableTips() {
        let start = Date()
        let end = start.addingTimeInterval(5 * 3600) // 5 hours
        
        let stages: [SleepStageRecord] = [
            SleepStageRecord(stageType: .deep, startTime: start, endTime: start.addingTimeInterval(0.3 * 3600)), // very low deep (6%)
            SleepStageRecord(stageType: .light, startTime: start.addingTimeInterval(0.3 * 3600), endTime: start.addingTimeInterval(3.0 * 3600)),
            SleepStageRecord(stageType: .awake, startTime: start.addingTimeInterval(3.0 * 3600), endTime: start.addingTimeInterval(3.5 * 3600)),
            SleepStageRecord(stageType: .awake, startTime: start.addingTimeInterval(4.0 * 3600), endTime: start.addingTimeInterval(4.5 * 3600)),
            SleepStageRecord(stageType: .awake, startTime: start.addingTimeInterval(4.8 * 3600), endTime: end)
        ]
        
        let session = SleepSession(startTime: start, endTime: end, isNap: false, stages: stages, sourceDevice: "Amazfit Balance", hasGranularHypnogram: true)
        
        let result = SleepAnalysisEngine.shared.analyze(session: session)
        
        XCTAssertEqual(result.verdict.status, .deficit)
        XCTAssertLessThanOrEqual(result.verdict.readinessScore, 60)
        XCTAssertEqual(result.verdict.physicalRepairRating, "Low")
        
        // Ensure cool bedroom and breathing tips are generated
        let tipCategories = Set(result.tips.map { $0.category })
        XCTAssertTrue(tipCategories.contains(.environment) || tipCategories.contains(.windDown))
    }
}
