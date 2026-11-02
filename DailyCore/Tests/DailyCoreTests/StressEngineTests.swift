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
        
        let (result, _) = try #require(StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: hrv,
            hrTelemetry: hrPoints,
            hourlySteps: stepBuckets,
            restingBpm: restingBpm,
            priorSleepScore: 65,
            calendar: cal
        ))
        
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
        
        let (result, _) = try #require(StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: 75.0,
            hrTelemetry: hrPoints,
            hourlySteps: stepBuckets,
            restingBpm: 54.0,
            priorSleepScore: 92,
            calendar: cal
        ))
        
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
        
        let (_, intraday) = try #require(StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: 50.0, // Normal HRV
            hrTelemetry: hrPoints,
            hourlySteps: stepBuckets,
            restingBpm: 60.0,
            priorSleepScore: 85,
            calendar: cal
        ))
        
        let point = try #require(intraday.first { $0.hour == hour })
        #expect(!point.isSedentary)
        // Since it's gated as active movement, stress score should NOT jump to 99
        #expect(point.score < 65)
    }
    
    @Test("Missing biometric telemetry returns nil instead of synthesizing fake stress")
    func testMissingBiometricsReturnsNil() async throws {
        let today = Date()
        
        // No HRV and no intraday heart rate samples
        let calculation = StressAnalysisEngine.calculateStress(
            targetDate: today,
            hrvMs: nil,
            hrTelemetry: [],
            hourlySteps: [],
            restingBpm: nil,
            priorSleepScore: nil
        )
        
        #expect(calculation == nil)
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
    
    @Test("RMSSD vs SDNN calibration and active-hour walking stability prevent score collapse")
    func testRmssdAndActiveHourStability() async throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let pastDay = cal.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        
        // Simulate Pixel Watch 5 worn all day: RMSSD = 70ms, RHR = 61 bpm, Sleep = 92,
        // sedentary desk hours at 14:00 (82 bpm) & 15:00 (81 bpm), then brisk walk at 16:00 (550 steps, 105 bpm).
        let h14 = cal.date(bySettingHour: 14, minute: 15, second: 0, of: pastDay)!
        let h15 = cal.date(bySettingHour: 15, minute: 15, second: 0, of: pastDay)!
        let h16 = cal.date(bySettingHour: 16, minute: 15, second: 0, of: pastDay)!
        
        let hrPoints = [
            IntradayHeartRatePoint(timestamp: h14, bpm: 82.0),
            IntradayHeartRatePoint(timestamp: h15, bpm: 81.0),
            IntradayHeartRatePoint(timestamp: h16, bpm: 105.0)
        ]
        let steps = [
            HourlyStepBucket(hour: 14, steps: 90),
            HourlyStepBucket(hour: 15, steps: 110),
            HourlyStepBucket(hour: 16, steps: 550)
        ]
        
        let (pwResult, _) = try #require(StressAnalysisEngine.calculateStress(
            targetDate: pastDay,
            hrvMs: 70.0,
            isRmssd: true,
            hrTelemetry: hrPoints,
            hourlySteps: steps,
            restingBpm: 61.0,
            priorSleepScore: 92,
            calendar: cal
        ))
        
        // Must stay in healthy Calm range (~28-40), never collapsing to 8 or 12 during the walking hour
        #expect(pwResult.currentScore >= 25 && pwResult.currentScore <= 42)
        
        // Simulate Oura Ring on the same hand (no standalone HRV or RHR in HealthKit, nocturnal HR ~55 bpm)
        let h04 = cal.date(bySettingHour: 4, minute: 0, second: 0, of: pastDay)!
        let h05 = cal.date(bySettingHour: 5, minute: 0, second: 0, of: pastDay)!
        let h06 = cal.date(bySettingHour: 6, minute: 0, second: 0, of: pastDay)!
        let ouraHr = [
            IntradayHeartRatePoint(timestamp: h04, bpm: 55.0),
            IntradayHeartRatePoint(timestamp: h05, bpm: 56.0),
            IntradayHeartRatePoint(timestamp: h06, bpm: 55.0),
            IntradayHeartRatePoint(timestamp: h14, bpm: 82.0),
            IntradayHeartRatePoint(timestamp: h15, bpm: 81.0)
        ]
        let (ouraResult, _) = try #require(StressAnalysisEngine.calculateStress(
            targetDate: pastDay,
            hrvMs: nil,
            isRmssd: false,
            hrTelemetry: ouraHr,
            hourlySteps: steps,
            restingBpm: nil,
            priorSleepScore: 75,
            calendar: cal
        ))
        
        // Derived RHR should be ~61 bpm (55.5 + 5.5), and Oura stress should converge near Pixel Watch (~30-42), never 60!
        #expect(abs((ouraResult.restingHeartRateBpm ?? 0.0) - 61.0) <= 1.0)
        #expect(ouraResult.currentScore >= 25 && ouraResult.currentScore <= 44)
        #expect(abs(ouraResult.currentScore - pwResult.currentScore) <= 8)
    }
}
