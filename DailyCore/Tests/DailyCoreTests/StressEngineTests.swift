import Testing
import Foundation
@testable import DailyCore

@Suite("Stress Engine & Models Tests")
struct StressEngineTests {
    
    @Test("HRV sigmoid transfer function responds monotonically")
    func testHrvSigmoidScoring() async throws {
        let baseline = 45.0
        
        // Very high HRV (e.g. 80ms) should yield low stress (< 25, Restful)
        let highHrvScore = StressAnalysisEngine.scoreFromHrv(hrv: 80.0, baseline: baseline)
        #expect(highHrvScore < 25.0)
        
        // Exact baseline HRV (45ms) should yield exactly 50 (neutral midpoint)
        let baselineScore = StressAnalysisEngine.scoreFromHrv(hrv: 45.0, baseline: baseline)
        #expect(abs(baselineScore - 50.0) < 0.1)
        
        // Very low HRV (e.g. 15ms) should yield high stress (> 75, High)
        let lowHrvScore = StressAnalysisEngine.scoreFromHrv(hrv: 15.0, baseline: baseline)
        #expect(lowHrvScore > 75.0)
    }
    
    @Test("Sedentary heart rate elevation contributes to stress score")
    func testSedentaryHeartRateElevation() async throws {
        let cal = Calendar.current
        let today = Date()
        
        // A day with elevated sedentary HR (90 bpm vs 60 bpm baseline) and low steps
        let restingBpm = 60.0
        let hrv = 30.0 // Suppressed HRV
        
        let hrPoints = [
            IntradayHeartRatePoint(timestamp: today, bpm: 92.0)
        ]
        let stepBuckets = [
            HourlyStepBucket(hour: cal.component(.hour, from: today), steps: 40) // Sedentary
        ]
        
        let (result, _) = StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: hrv,
            hrTelemetry: hrPoints,
            hourlySteps: stepBuckets,
            restingBpm: restingBpm,
            priorSleepScore: 65,
            calendar: cal
        )
        
        #expect(result.currentScore > 50)
        #expect(result.currentLevel == .moderate || result.currentLevel == .high)
        #expect(result.sympatheticPercent > result.parasympatheticPercent)
    }
    
    @Test("Peak recovery conditions yield Restful / Zen state")
    func testPeakRecoveryYieldsZenState() async throws {
        let cal = Calendar.current
        let today = Date()
        
        // Excellent HRV (75ms vs 45ms baseline), low resting HR (54 bpm), and great sleep (92)
        let hrPoints = [
            IntradayHeartRatePoint(timestamp: today, bpm: 56.0)
        ]
        let stepBuckets = [
            HourlyStepBucket(hour: cal.component(.hour, from: today), steps: 120)
        ]
        
        let (result, _) = StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: 75.0,
            hrTelemetry: hrPoints,
            hourlySteps: stepBuckets,
            restingBpm: 54.0,
            priorSleepScore: 92,
            calendar: cal
        )
        
        #expect(result.currentScore <= 25)
        #expect(result.currentLevel == .restful)
        #expect(result.monkeyMood == .zen)
        #expect(result.recommendedBreathing == .resonanceFlow)
        #expect(result.parasympatheticPercent >= 75)
    }
    
    @Test("Active workout hours are excluded from sedentary stress penalty")
    func testActiveWorkoutGating() async throws {
        let cal = Calendar.current
        let today = Date()
        let hour = cal.component(.hour, from: today)
        
        // High HR during a running hour (steps = 2,500)
        let hrPoints = [
            IntradayHeartRatePoint(timestamp: today, bpm: 155.0)
        ]
        let stepBuckets = [
            HourlyStepBucket(hour: hour, steps: 2500) // Active workout!
        ]
        
        let (_, intraday) = StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: 50.0, // Normal HRV
            hrTelemetry: hrPoints,
            hourlySteps: stepBuckets,
            restingBpm: 60.0,
            priorSleepScore: 85,
            calendar: cal
        )
        
        let point = try #require(intraday.first { $0.hour == hour })
        #expect(!point.isSedentary)
        // Since it's gated as active movement, stress score should NOT jump to 99
        #expect(point.score < 65)
    }
    
    @Test("StressWidgetSnapshot round-trip encoding and decoding")
    func testWidgetSnapshotSerialization() throws {
        let snapshot = StressWidgetSnapshot(
            hasData: true,
            stressScore: 42,
            levelRaw: "Calm",
            monkeyMoodRaw: "Curious Monkey",
            adviceSnippet: "Steady flow today!",
            hrvMs: 50.0,
            restingHeartRate: 61.0,
            parasympatheticPercent: 58,
            sympatheticPercent: 42,
            lastUpdated: Date()
        )
        
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(StressWidgetSnapshot.self, from: data)
        
        #expect(decoded.stressScore == 42)
        #expect(decoded.level == .calm)
        #expect(decoded.monkeyMood == .curious)
        #expect(decoded.parasympatheticPercent == 58)
    }
}
