import Foundation

// MARK: - Sleep Recovery Status

public enum SleepRecoveryStatus: String, Codable, CaseIterable, Sendable {
    case optimal = "Optimal"
    case great = "Great"
    case fair = "Fair"
    case deficit = "Deficit"
    
    public var displayName: String {
        switch self {
        case .optimal: return "Optimal Recovery"
        case .great: return "Great Recharging"
        case .fair: return "Moderate Recovery"
        case .deficit: return "Recovery Deficit"
        }
    }
    
    public var systemIcon: String {
        switch self {
        case .optimal: return "bolt.shield.fill"
        case .great: return "sparkles"
        case .fair: return "battery.50percent"
        case .deficit: return "exclamationmark.triangle.fill"
        }
    }
    
    public var hexColor: String {
        switch self {
        case .optimal: return "#00E5FF" // Electric Cyan
        case .great: return "#00E676"   // Emerald Green
        case .fair: return "#FFD600"    // Amber Gold
        case .deficit: return "#FF5252" // Coral Crimson
        }
    }
}

// MARK: - Sleep Recovery Verdict

public struct SleepRecoveryVerdict: Identifiable, Sendable {
    public let id: String
    public let status: SleepRecoveryStatus
    public let headline: String
    public let narrative: String
    public let readinessScore: Int // 0 - 100
    public let physicalRepairRating: String // "High", "Adequate", "Low"
    public let cognitiveRestoreRating: String // "High", "Adequate", "Low"
    public let sleepContinuityRating: String // "Continuous", "Fragmented"
    
    public init(
        id: String = UUID().uuidString,
        status: SleepRecoveryStatus,
        headline: String,
        narrative: String,
        readinessScore: Int,
        physicalRepairRating: String,
        cognitiveRestoreRating: String,
        sleepContinuityRating: String
    ) {
        self.id = id
        self.status = status
        self.headline = headline
        self.narrative = narrative
        self.readinessScore = readinessScore
        self.physicalRepairRating = physicalRepairRating
        self.cognitiveRestoreRating = cognitiveRestoreRating
        self.sleepContinuityRating = sleepContinuityRating
    }
}

// MARK: - Actionable Sleep Tip Category & Model

public enum SleepTipCategory: String, Codable, CaseIterable, Sendable {
    case circadian = "Circadian Rhythm"
    case environment = "Bedroom Climate"
    case nutrition = "Evening Nutrition"
    case windDown = "Vagal Wind-Down"
    
    public var iconName: String {
        switch self {
        case .circadian: return "sun.horizon.fill"
        case .environment: return "thermometer.snowflake"
        case .nutrition: return "cup.and.saucer.fill"
        case .windDown: return "lungs.fill"
        }
    }
    
    public var hexColor: String {
        switch self {
        case .circadian: return "#FFB300" // Amber Sun
        case .environment: return "#40C4FF" // Ice Blue
        case .nutrition: return "#FF8A80" // Warm Coral
        case .windDown: return "#B388FF" // Soft Lavender
        }
    }
}

public struct SleepActionableTip: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: SleepTipCategory
    public let title: String
    public let advice: String
    public let scientificRationale: String
    
    public init(
        id: String = UUID().uuidString,
        category: SleepTipCategory,
        title: String,
        advice: String,
        scientificRationale: String
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.advice = advice
        self.scientificRationale = scientificRationale
    }
}

// MARK: - Sleep AI Context & Follow-Up Prompts

public struct SleepAIContext: Sendable {
    public let narrativeSynthesis: String
    public let suggestedPrompts: [String]
    
    public init(narrativeSynthesis: String, suggestedPrompts: [String]) {
        self.narrativeSynthesis = narrativeSynthesis
        self.suggestedPrompts = suggestedPrompts
    }
}

// MARK: - Sleep Analysis Engine

public final class SleepAnalysisEngine: Sendable {
    public static let shared = SleepAnalysisEngine()
    
    public init() {}
    
    /// Evaluates a nocturnal sleep session and generates recovery verdict, science tips, and AI context.
    public func analyze(
        session: SleepSession,
        nocturnalRestingBpm: Double? = nil,
        nocturnalHrvMs: Double? = nil
    ) -> (verdict: SleepRecoveryVerdict, tips: [SleepActionableTip], aiContext: SleepAIContext) {
        let score = session.sleepScore
        let deepPct = session.deepPercent
        let remPct = session.remPercent
        let effPct = session.efficiencyPercent
        let awakeCount = session.awakeCount
        let durationHours = session.asleepSeconds / 3600.0
        
        // 1. Determine Status & Readiness Score
        let status: SleepRecoveryStatus
        let readiness: Int
        
        if score >= 85 && effPct >= 85 && deepPct >= 14 {
            status = .optimal
            readiness = min(100, 85 + Int((Double(score - 85) / 15.0) * 15.0))
        } else if score >= 72 {
            status = .great
            readiness = min(84, 70 + Int((Double(score - 72) / 13.0) * 14.0))
        } else if score >= 55 {
            status = .fair
            readiness = min(69, 50 + Int((Double(score - 55) / 17.0) * 19.0))
        } else {
            status = .deficit
            readiness = max(20, min(49, Int(score)))
        }
        
        // 2. Physical & Cognitive Ratings
        let physicalRating: String
        if deepPct >= 18 || session.deepSeconds >= 4500 {
            physicalRating = "High"
        } else if deepPct >= 12 || session.deepSeconds >= 2700 {
            physicalRating = "Adequate"
        } else {
            physicalRating = "Low"
        }
        
        let cognitiveRating: String
        if remPct >= 20 || session.remSeconds >= 5400 {
            cognitiveRating = "High"
        } else if remPct >= 14 || session.remSeconds >= 3600 {
            cognitiveRating = "Adequate"
        } else {
            cognitiveRating = "Low"
        }
        
        let continuityRating: String = (awakeCount <= 2 && effPct >= 88) ? "Continuous" : "Fragmented"
        
        // 3. Headline & Narrative Synthesis
        let headline: String
        let narrative: String
        
        switch status {
        case .optimal:
            headline = "Completely Recharged & Peak Readiness"
            narrative = "Your sleep architecture was deeply restorative (\(session.totalAsleepFormatted) asleep, \(session.restorativePercent)% Deep+REM). Growth hormone release and muscular repair peaked during your \(session.deepFormatted) of deep sleep. Your central nervous system is primed for peak physical and cognitive output today."
        case .great:
            headline = "Well-Rested with Solid Recovery"
            narrative = "You achieved a balanced sleep window with \(session.totalAsleepFormatted) of sleep and \(effPct)% efficiency. Both physical cellular restoration (\(session.deepFormatted) Deep) and memory consolidation (\(session.remFormatted) REM) were sufficient to handle full daily demands."
        case .fair:
            if durationHours < 6.5 {
                headline = "Moderate Rest • Short Sleep Duration"
                narrative = "Sleep efficiency remained stable at \(effPct)%, but total sleep duration was limited to \(session.totalAsleepFormatted). Your body accumulated mild recovery load. Consider a brief 20-minute afternoon power nap to stay sharp."
            } else {
                headline = "Moderate Rest • Light Architecture"
                narrative = "You spent \(session.timeInBedFormatted) in bed, but lighter sleep stages dominated. Deep slow-wave sleep (\(session.deepFormatted)) was slightly restricted, meaning physical repair was partial."
            }
        case .deficit:
            headline = "Recovery Deficit • Prioritize Rest Today"
            narrative = "Significant sleep disruption detected (\(awakeCount) awakenings, \(effPct)% efficiency). High recovery load will elevate physiological strain today. Defer heavy physical strain and focus on hydration and an early bedtime tonight."
        }
        
        let verdict = SleepRecoveryVerdict(
            status: status,
            headline: headline,
            narrative: narrative,
            readinessScore: readiness,
            physicalRepairRating: physicalRating,
            cognitiveRestoreRating: cognitiveRating,
            sleepContinuityRating: continuityRating
        )
        
        // 4. Generate Contextual Clinical Tips
        var tips: [SleepActionableTip] = []
        
        // A. Deep sleep optimization
        if deepPct < 15 {
            tips.append(SleepActionableTip(
                category: .environment,
                title: "Cool Bedroom to 18–20°C",
                advice: "Lower your thermostat or ventilate your room 30 minutes before sleep.",
                scientificRationale: "Thermoregulation drop triggers slow-wave NREM sleep, directly expanding deep sleep duration."
            ))
        }
        
        // B. REM sleep optimization
        if remPct < 18 {
            tips.append(SleepActionableTip(
                category: .nutrition,
                title: "Cut Evening Alcohol & Heavy Carbs",
                advice: "Finish dinner at least 3 hours before bed and avoid alcohol.",
                scientificRationale: "Ethanol metabolism suppresses REM sleep cycles in the first half of the night, reducing dream and memory processing."
            ))
        }
        
        // C. Continuity & Awakenings
        if awakeCount >= 3 || effPct < 85 {
            tips.append(SleepActionableTip(
                category: .windDown,
                title: "5-Minute Vagal Box Breathing",
                advice: "Inhale 4s, hold 4s, exhale 4s, hold 4s right before turning off the lights.",
                scientificRationale: "Stimulates the parasympathetic vagal nerve, lowering heart rate and minimizing midnight micro-arousals."
            ))
        }
        
        // D. Circadian anchor tip (always relevant)
        tips.append(SleepActionableTip(
            category: .circadian,
            title: "Morning Sunlight Exposure",
            advice: "Spend 15–20 minutes outside in natural daylight within 1 hour of waking.",
            scientificRationale: "Suppresses melatonin release, synchronizes your central circadian clock, and programs natural sleep onset 16 hours later."
        ))
        
        // Keep top 3 distinct tips
        let topTips = Array(tips.prefix(3))
        
        // 5. Build AI Context & Prompts
        let suggestedPrompts = [
            "De ce am avut Deep Sleep scăzut azi noapte?",
            "Este recomandat un antrenament cardio intens azi?",
            "Cum îmi pot îmbunătăți somnul REM și HRV-ul nocturn?",
            "Ce rutină de seară mă ajută să reduc trezirile nocturne?"
        ]
        
        let aiContext = SleepAIContext(
            narrativeSynthesis: narrative,
            suggestedPrompts: suggestedPrompts
        )
        
        return (verdict, topTips, aiContext)
    }
}
