import Foundation

/// Autonomic nervous system (ANS) stress estimation engine v2.0 modeled after clinical HRV algorithms
/// and mobile biometric standards, unified 1:1 with Supabase `health-engine`.
public enum StressAnalysisEngine {
    
    /// Default population benchmarks for healthy adults when personal longitudinal history is sparse.
    public static let defaultBaselineHrv: Double = 45.0 // ms SDNN (Apple Watch / clinical short-term SDNN)
    public static let defaultBaselineHrvSdnn: Double = 45.0
    public static let defaultBaselineHrvRmssd: Double = 62.0 // ms RMSSD (Wear OS / Fitbit / Oura nocturnal RMSSD)
    public static let defaultBaselineRhr: Double = 60.0 // bpm
    
    /// Evaluates physiological telemetry and produces a unified `StressAnalysisResult`
    /// along with an intraday hourly curve, or `nil` if no biometric telemetry is available for the day.
    public static func calculateStress(
        targetDate: Date,
        hrvMs: Double?,
        isRmssd: Bool = false,
        hrTelemetry: [IntradayHeartRatePoint],
        hourlySteps: [HourlyStepBucket],
        restingBpm: Double?,
        priorSleepScore: Int?,
        personalBaselineHrv: Double? = nil,
        personalBaselineRhr: Double? = nil,
        calendar: Calendar = .current
    ) -> (result: StressAnalysisResult, intradayPoints: [IntradayStressPoint])? {
        
        let validHrv = (hrvMs != nil && hrvMs! > 0) ? hrvMs : nil
        
        // Guard against missing biometric telemetry:
        // Valid stress calculation requires at least one genuine physiological signal (HRV or heart rate samples).
        guard validHrv != nil || !hrTelemetry.isEmpty else {
            return nil
        }
        
        let metricDefaultHrv = isRmssd ? defaultBaselineHrvRmssd : defaultBaselineHrvSdnn
        let baselineHrv = (personalBaselineHrv != nil && personalBaselineHrv! > 0)
            ? (round(personalBaselineHrv! * 10.0) / 10.0)
            : metricDefaultHrv
        
        let derivedRhr = deriveNocturnalRhr(from: hrTelemetry, targetDate: targetDate, calendar: calendar)
        let baselineRhr: Double = {
            if let rhr = restingBpm, rhr > 0 { return rhr }
            if let derived = derivedRhr { return derived }
            if let personal = personalBaselineRhr, personal > 0 { return personal }
            return defaultBaselineRhr
        }()
        
        let sleepScore = (priorSleepScore != nil && priorSleepScore! > 0) ? priorSleepScore! : 80
        
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
        let dayHrvScore: Double? = validHrv.map { scoreFromHrv(hrv: $0, baseline: baselineHrv) }
        var lastSedentaryHrScore: Double? = nil
        var latestSedentaryHrBpm: Double? = nil
        
        for hour in 0...maxHourToEvaluate {
            let steps = stepsByHour[hour] ?? 0
            let isSedentary = steps < 300 // Exclude hours with brisk walking/running
            
            let hrSamples = hrByHour[hour] ?? []
            // Only generate an intraday point if this hour had actual biometric samples
            guard !hrSamples.isEmpty || (validHrv != nil && steps > 0) else {
                continue
            }
            let avgHr: Double? = !hrSamples.isEmpty ? (hrSamples.reduce(0, +) / Double(hrSamples.count)) : nil
            
            // B. Calibrated Sedentary HR Arousal Component (with inertia carry-forward during movement hours)
            let hrScore: Double
            if let hr = avgHr, isSedentary {
                let s = scoreFromSedentaryHr(avgHr: hr, baselineRhr: baselineRhr)
                hrScore = s
                lastSedentaryHrScore = s
                latestSedentaryHrBpm = hr
            } else if let lastSed = lastSedentaryHrScore {
                hrScore = 0.85 * lastSed + 0.15 * 32.0
            } else if let dHrv = dayHrvScore {
                hrScore = 0.70 * dHrv + 0.30 * 32.0
            } else {
                hrScore = 32.0
            }
            
            // C. Blended hourly stress (honest re-normalization when device has no HRV, e.g. Oura via HealthKit)
            let rawHourlyStress: Double
            if let dHrv = dayHrvScore {
                rawHourlyStress = (0.45 * dHrv) + (0.35 * hrScore) + (0.20 * sleepPenalty)
            } else {
                rawHourlyStress = (0.70 * hrScore) + (0.30 * sleepPenalty)
            }
            
            let finalHourlyScore = Int(round(min(max(rawHourlyStress, 5.0), 98.0)))
            let level = StressLevel.from(score: finalHourlyScore)
            
            let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: targetDate) ?? targetDate
            intraday.append(IntradayStressPoint(
                timestamp: hourDate,
                hour: hour,
                score: finalHourlyScore,
                level: level,
                hrvMs: validHrv,
                heartRateBpm: avgHr.map { round($0 * 10.0) / 10.0 },
                isSedentary: isSedentary
            ))
        }
        
        // 4. Resolve Current / Master Stress Score from genuine sedentary tone (immune to active-hour step collapse)
        let recentHr = hrTelemetry.last?.bpm
        let effectiveSedentaryBpm = latestSedentaryHrBpm ?? recentHr
        let currentHrElevation: Double? = effectiveSedentaryBpm.map { max(0.0, $0 - baselineRhr) }
        
        let currentScore: Int
        let sedentaryPoints = intraday.filter { $0.isSedentary && $0.heartRateBpm != nil }
        if sedentaryPoints.count >= 2 {
            let lastSed = Double(sedentaryPoints[sedentaryPoints.count - 1].score)
            let prevSed = Double(sedentaryPoints[sedentaryPoints.count - 2].score)
            currentScore = Int(round(0.70 * lastSed + 0.30 * prevSed))
        } else if let onlySed = sedentaryPoints.first {
            currentScore = onlySed.score
        } else if let lastPoint = intraday.last {
            currentScore = lastPoint.score
        } else {
            let fallbackHrScore: Double
            if let sedBpm = effectiveSedentaryBpm {
                fallbackHrScore = scoreFromSedentaryHr(avgHr: sedBpm, baselineRhr: baselineRhr)
            } else if let dHrv = dayHrvScore {
                fallbackHrScore = 0.70 * dHrv + 0.30 * 32.0
            } else {
                fallbackHrScore = 32.0
            }
            let blended: Double
            if let dHrv = dayHrvScore {
                blended = (0.45 * dHrv) + (0.35 * fallbackHrScore) + (0.20 * sleepPenalty)
            } else {
                blended = (0.70 * fallbackHrScore) + (0.30 * sleepPenalty)
            }
            currentScore = Int(round(min(max(blended, 8.0), 95.0)))
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
        let hrvDeltaPercent = validHrv.map { (($0 - baselineHrv) / baselineHrv) * 100.0 }
        
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
            currentHrvMs: validHrv,
            hrvDeltaPercent: hrvDeltaPercent,
            restingHeartRateBpm: round(baselineRhr),
            currentSedentaryBpm: effectiveSedentaryBpm.map { round($0) },
            heartRateElevationBpm: currentHrElevation.map { round($0 * 10.0) / 10.0 },
            monkeyMood: mood,
            adviceQuote: mood.adviceQuote,
            recommendedBreathing: breathing,
            lastUpdated: Date()
        )
        
        return (result, intraday)
    }
    
    // MARK: - Mathematical Sub-routines
    
    /// Normalizes HRV using a metric-calibrated sigmoid/tanh transfer function around baseline.
    /// High HRV yields lower stress (< 25), baseline yields 50, depressed HRV yields high stress (> 75).
    public static func scoreFromHrv(hrv: Double, baseline: Double) -> Double {
        guard baseline > 0 else { return 50.0 }
        let scale = max(14.0, baseline * 0.35)
        let z = (hrv - baseline) / scale
        let normalized = 50.0 - (tanh(z) * 45.0)
        return min(max(normalized, 0.0), 100.0)
    }
    
    /// Calibrated sedentary waking HR arousal curve relative to clinical resting heart rate.
    /// Accounts for natural upright waking orthostatic + metabolic offset (+10..20 bpm above RHR)
    /// without saturating at 100/100 during normal desk work or conversation.
    public static func scoreFromSedentaryHr(avgHr: Double, baselineRhr: Double) -> Double {
        let delta = avgHr - baselineRhr
        let z = (delta - 22.0) / 16.0
        let score = 46.0 + (tanh(z) * 44.0)
        return min(max(score, 6.0), 95.0)
    }
    
    /// Derives a clinical resting HR baseline from nocturnal 5-min HR buckets when a wearable
    /// (e.g. Oura Ring via Apple HealthKit) does not export a standalone RHR metric.
    public static func deriveNocturnalRhr(
        from hrTelemetry: [IntradayHeartRatePoint],
        targetDate: Date,
        calendar: Calendar = .current
    ) -> Double? {
        var nocturnalBpms: [Double] = []
        var daytimeBpms: [Double] = []
        
        for pt in hrTelemetry {
            guard pt.bpm > 35.0 && pt.bpm < 220.0 else { continue }
            guard calendar.isDate(pt.timestamp, inSameDayAs: targetDate) else { continue }
            let h = calendar.component(.hour, from: pt.timestamp)
            if h < 8 && pt.bpm <= 95.0 {
                nocturnalBpms.append(pt.bpm)
            } else if h >= 8 {
                daytimeBpms.append(pt.bpm)
            }
        }
        
        if nocturnalBpms.count >= 3 {
            nocturnalBpms.sort()
            let mid = nocturnalBpms.count / 2
            let nocturnalMedian = (nocturnalBpms.count % 2 == 1)
                ? nocturnalBpms[mid]
                : (nocturnalBpms[mid - 1] + nocturnalBpms[mid]) / 2.0
            let clinicalRhr = nocturnalMedian + 5.5
            return round(min(max(clinicalRhr, 45.0), 85.0))
        }
        
        if daytimeBpms.count >= 3, let minDay = daytimeBpms.min() {
            return round(min(max(minDay - 2.0, 48.0), 72.0))
        }
        
        return nil
    }
}
