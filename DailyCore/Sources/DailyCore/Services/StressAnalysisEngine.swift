import Foundation

/// Autonomic nervous system (ANS) stress estimation engine modeled after clinical HRV algorithms
/// and mobile biometric standards (such as StressWatch on Apple Watch).
public enum StressAnalysisEngine {
    
    /// Default population benchmarks for healthy adults when personal longitudinal history is sparse.
    public static let defaultBaselineHrv: Double = 45.0 // ms SDNN
    public static let defaultBaselineRhr: Double = 62.0 // bpm
    
    /// Evaluates physiological telemetry and produces a unified `StressAnalysisResult`
    /// along with an intraday hourly curve.
    public static func calculateStress(
        targetDate: Date,
        hrvMs: Double?,
        hrTelemetry: [IntradayHeartRatePoint],
        hourlySteps: [HourlyStepBucket],
        restingBpm: Double?,
        priorSleepScore: Int?,
        personalBaselineHrv: Double? = nil,
        personalBaselineRhr: Double? = nil,
        calendar: Calendar = .current
    ) -> (result: StressAnalysisResult, intradayPoints: [IntradayStressPoint]) {
        
        let baselineHrv = personalBaselineHrv ?? defaultBaselineHrv
        let baselineRhr = restingBpm ?? personalBaselineRhr ?? defaultBaselineRhr
        let sleepScore = priorSleepScore ?? 80
        
        // 1. Build Hourly Map of Steps (to isolate physical movement vs sedentary arousal)
        var stepsByHour: [Int: Int] = [:]
        for b in hourlySteps {
            stepsByHour[b.hour] = b.steps
        }
        
        // 2. Group Heart Rate telemetry by hour of the day
        var hrByHour: [Int: [Double]] = [:]
        for pt in hrTelemetry {
            if calendar.isDate(pt.timestamp, inSameDayAs: targetDate) {
                let hour = calendar.component(.hour, from: pt.timestamp)
                hrByHour[hour, default: []].append(pt.bpm)
            }
        }
        
        // 3. Compute Hourly Intraday Stress Points (0 to current hour or full 24h if past date)
        var intraday: [IntradayStressPoint] = []
        let currentHour = calendar.component(.hour, from: Date())
        let isToday = calendar.isDateInToday(targetDate)
        let maxHourToEvaluate = isToday ? currentHour : 23
        
        let sleepPenalty = max(0.0, min(100.0, 100.0 - Double(sleepScore)))
        
        for hour in 0...maxHourToEvaluate {
            let steps = stepsByHour[hour] ?? 0
            let isSedentary = steps < 300 // Exclude hours with brisk walking/running
            
            let hrSamples = hrByHour[hour] ?? []
            let avgHr: Double? = !hrSamples.isEmpty ? (hrSamples.reduce(0, +) / Double(hrSamples.count)) : nil
            
            // Hourly HRV estimation: if daytime samples exist or fallback to day baseline
            let hourHrv = hrvMs ?? baselineHrv
            
            // A. HRV Component (50% weight): High HRV -> Low Stress, Low HRV -> High Stress
            let hrvScore = scoreFromHrv(hrv: hourHrv, baseline: baselineHrv)
            
            // B. Heart Rate Elevation Component (30% weight)
            let hrScore: Double
            if let hr = avgHr, isSedentary {
                let delta = max(0.0, hr - baselineRhr)
                hrScore = min(100.0, (delta / 25.0) * 100.0)
            } else {
                hrScore = hrvScore * 0.8
            }
            
            // C. Recovery factor (20% weight)
            let rawHourlyStress = (0.50 * hrvScore) + (0.30 * hrScore) + (0.20 * sleepPenalty)
            let finalHourlyScore = Int(round(min(max(rawHourlyStress, 5.0), 98.0)))
            let level = StressLevel.from(score: finalHourlyScore)
            
            let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: targetDate) ?? targetDate
            intraday.append(IntradayStressPoint(
                timestamp: hourDate,
                hour: hour,
                score: finalHourlyScore,
                level: level,
                hrvMs: hourHrv,
                heartRateBpm: avgHr,
                isSedentary: isSedentary
            ))
        }
        
        // 4. Resolve Current / Master Stress Score
        let currentScore: Int
        let currentHrv = hrvMs ?? baselineHrv
        let currentHrvScore = scoreFromHrv(hrv: currentHrv, baseline: baselineHrv)
        
        // Derive recent sedentary HR
        let recentHr = hrTelemetry.last?.bpm
        let currentHrElevation: Double?
        let currentHrScore: Double
        if let hr = recentHr {
            let elevation = max(0.0, hr - baselineRhr)
            currentHrElevation = elevation
            currentHrScore = min(100.0, (elevation / 25.0) * 100.0)
        } else {
            currentHrElevation = nil
            currentHrScore = currentHrvScore * 0.8
        }
        
        if let lastPoint = intraday.last {
            currentScore = lastPoint.score
        } else {
            let blended = (0.50 * currentHrvScore) + (0.30 * currentHrScore) + (0.20 * sleepPenalty)
            currentScore = Int(round(min(max(blended, 10.0), 95.0)))
        }
        
        let currentLevel = StressLevel.from(score: currentScore)
        
        // 5. Daily Aggregates
        let dailyAverage: Int
        if !intraday.isEmpty {
            let sum = intraday.map(\.score).reduce(0, +)
            dailyAverage = Int(round(Double(sum) / Double(intraday.count)))
        } else {
            dailyAverage = currentScore
        }
        
        let peakPoint = intraday.max { $0.score < $1.score }
        let lowestPoint = intraday.min { $0.score < $1.score }
        
        // 6. Autonomic Balance
        let parasympathetic = min(max(100 - currentScore, 10), 90)
        let sympathetic = 100 - parasympathetic
        
        // 7. HRV Delta Percentage
        let hrvDeltaPercent = hrvMs != nil ? (((hrvMs! - baselineHrv) / baselineHrv) * 100.0) : nil
        
        // 8. Persona Mood & Guidance
        let mood: MonkeyMood
        let breathing: BreathingProtocol
        switch currentLevel {
        case .restful:
            mood = .zen
            breathing = .resonanceFlow
        case .calm:
            mood = .curious
            breathing = .relax478
        case .moderate:
            mood = .busy
            breathing = .boxBreathing
        case .high:
            mood = .overheated
            breathing = .physiologicalSigh
        }
        
        let result = StressAnalysisResult(
            currentScore: currentScore,
            currentLevel: currentLevel,
            dailyAverageScore: dailyAverage,
            peakHour: peakPoint?.hour,
            peakScore: peakPoint?.score,
            lowestHour: lowestPoint?.hour,
            lowestScore: lowestPoint?.score,
            parasympatheticPercent: parasympathetic,
            sympatheticPercent: sympathetic,
            baselineHrvMs: baselineHrv,
            currentHrvMs: hrvMs,
            hrvDeltaPercent: hrvDeltaPercent,
            restingHeartRateBpm: baselineRhr,
            currentSedentaryBpm: recentHr,
            heartRateElevationBpm: currentHrElevation,
            monkeyMood: mood,
            adviceQuote: mood.adviceQuote,
            recommendedBreathing: breathing,
            lastUpdated: Date()
        )
        
        return (result, intraday)
    }
    
    // MARK: - Mathematical Sub-routines
    
    /// Normalizes HRV using a sigmoid/tanh transfer function around baseline.
    /// High HRV yields lower stress (< 30), while depressed HRV yields high stress (> 70).
    public static func scoreFromHrv(hrv: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50.0 }
        let z = (hrv - baseline) / 16.0
        // tanh(z) ranges from -1 to +1.
        // When z is +2 (high HRV, +32ms above baseline), tanh is ~0.96 -> Score = 50 - 45 = 5 (Deep Rest)
        // When z is -2 (low HRV, -32ms below baseline), tanh is ~ -0.96 -> Score = 50 + 45 = 95 (High Stress)
        let normalized = 50.0 - (tanh(z) * 45.0)
        return min(max(normalized, 0.0), 100.0)
    }
}
