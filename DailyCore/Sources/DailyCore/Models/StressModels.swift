import Foundation

// MARK: - Stress Level Categorization

/// Four-tier clinical stress classification mirroring autonomic nervous system (ANS) tone.
public enum StressLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case restful = "Restful"
    case calm = "Calm"
    case moderate = "Moderate"
    case high = "High"
    
    public var id: String { rawValue }
    
    /// Score range boundaries (0 - 100).
    public var scoreRange: ClosedRange<Int> {
        switch self {
        case .restful: return 0...25
        case .calm: return 26...50
        case .moderate: return 51...75
        case .high: return 76...100
        }
    }
    
    public var displayName: String { rawValue }
    
    /// Clinical state summary.
    public var clinicalDescription: String {
        switch self {
        case .restful:
            return "Parasympathetic dominance. Deep physiological recovery and high neural adaptability."
        case .calm:
            return "Balanced autonomic tone. Stable heart rhythm with healthy cognitive focus."
        case .moderate:
            return "Elevated sympathetic activation. Mild physiological strain or sustained task fatigue."
        case .high:
            return "Acute sympathetic dominance. High physiological arousal; recovery protocols recommended."
        }
    }
    
    /// Primary theme color hex for liquid glass cards and aura halos.
    public var hexColor: String {
        switch self {
        case .restful: return "#00E5FF" // Neon cyan / mint
        case .calm: return "#00FFB2"    // Teal / spring green
        case .moderate: return "#FFA726" // Warm amber
        case .high: return "#FF5252"     // Coral / bright red
        }
    }
    
    /// Secondary gradient pair hex.
    public var gradientHex: [String] {
        switch self {
        case .restful: return ["#00E5FF", "#7B2CBF"]
        case .calm: return ["#00FFB2", "#00B4D8"]
        case .moderate: return ["#FFA726", "#FF7043"]
        case .high: return ["#FF5252", "#D00000"]
        }
    }
    
    /// Classifies an integer score (0 - 100) into a clinical StressLevel.
    public static func from(score: Int) -> StressLevel {
        switch score {
        case 0...25: return .restful
        case 26...50: return .calm
        case 51...75: return .moderate
        default: return .high
        }
    }
}

// MARK: - Stylized Monkey Mascot Persona

/// Expressive monkey character moods corresponding to autonomic stress states.
public enum MonkeyMood: String, Codable, CaseIterable, Sendable {
    case zen = "Zen Monkey"
    case curious = "Curious Monkey"
    case busy = "Busy Monkey"
    case overheated = "Overheated Monkey"
    
    public var displayName: String { rawValue }
    
    /// Emoji / SF Symbol fallback representation.
    public var iconSymbol: String {
        switch self {
        case .zen: return "leaf.fill"
        case .curious: return "sparkles"
        case .busy: return "flame"
        case .overheated: return "thermometer.sun.fill"
        }
    }
    
    public var emoji: String {
        switch self {
        case .zen: return "🧘‍♂️"
        case .curious: return "🐵"
        case .busy: return "🐒"
        case .overheated: return "🙈"
        }
    }
    
    /// Contextual, charming and scientifically sound advice voiced by the monkey.
    public var adviceQuote: String {
        switch self {
        case .zen:
            return "You're in peak recovery mode! Perfect balance of mind and body — ideal for creative breakthroughs."
        case .curious:
            return "Autonomic tone is nice and steady. Keep up this calm rhythm with a fresh sip of water!"
        case .busy:
            return "Tension is gently creeping up. Step back for 3 minutes and try Box Breathing (4s In, 4s Hold, 4s Out, 4s Hold)."
        case .overheated:
            return "High sympathetic arousal detected! Do 3 Physiological Sighs right now: two quick nose inhales, one long slow exhale."
        }
    }
    
    /// Quick micro-habit action.
    public var quickActionTitle: String {
        switch self {
        case .zen: return "Deepen Focus"
        case .curious: return "Stay Hydrated"
        case .busy: return "Box Breathing"
        case .overheated: return "Physiological Sigh"
        }
    }
}

// MARK: - Breathing Protocols

public enum BreathingProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case physiologicalSigh = "Physiological Sigh"
    case boxBreathing = "Box Breathing (4-4-4-4)"
    case resonanceFlow = "Resonance Flow (5.5s)"
    case relax478 = "Relaxing 4-7-8"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .physiologicalSigh:
            return "Stanford Huberman protocol: Two rapid inhales through the nose, followed by a long, slow sigh through the mouth. Fastest way to downregulate autonomic arousal."
        case .boxBreathing:
            return "Navy SEAL reset: 4 seconds inhale, 4 seconds hold, 4 seconds exhale, 4 seconds hold. Restores executive composure."
        case .resonanceFlow:
            return "Heart-Rate Variability maximizer: 5.5 seconds in, 5.5 seconds out (approx. 5.5 breaths/min). Synchronizes vagal nerve tone."
        case .relax478:
            return "Parasympathetic primer: 4 seconds inhale, 7 seconds hold, 8 seconds exhale. Relaxes nervous system before sleep or rest."
        }
    }
    
    public var cyclesRecommended: Int {
        switch self {
        case .physiologicalSigh: return 3
        case .boxBreathing: return 4
        case .resonanceFlow: return 6
        case .relax478: return 4
        }
    }
}

// MARK: - Intraday & Analysis Models

/// Hourly point tracking stress fluctuation throughout the 24-hour cycle.
public struct IntradayStressPoint: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let timestamp: Date
    public let hour: Int
    public let score: Int
    public let level: StressLevel
    public let hrvMs: Double?
    public let heartRateBpm: Double?
    public let isSedentary: Bool
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        hour: Int,
        score: Int,
        level: StressLevel,
        hrvMs: Double? = nil,
        heartRateBpm: Double? = nil,
        isSedentary: Bool = true
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hour = hour
        self.score = min(max(score, 0), 100)
        self.level = level
        self.hrvMs = hrvMs
        self.heartRateBpm = heartRateBpm
        self.isSedentary = isSedentary
    }
    
    public var hourFormatted: String {
        String(format: "%02d:00", hour)
    }
}

/// Comprehensive daily stress analysis snapshot.
public struct StressAnalysisResult: Codable, Equatable, Sendable {
    public let currentScore: Int
    public let currentLevel: StressLevel
    public let dailyAverageScore: Int
    public let peakHour: Int?
    public let peakScore: Int?
    public let lowestHour: Int?
    public let lowestScore: Int?
    
    // Autonomic balance indices
    public let parasympatheticPercent: Int // Rest & Digest (0 - 100)
    public let sympatheticPercent: Int     // Fight or Flight (0 - 100)
    
    // Biometric drivers
    public let baselineHrvMs: Double
    public let currentHrvMs: Double?
    public let hrvDeltaPercent: Double? // +X% or -X% relative to baseline
    public let restingHeartRateBpm: Double?
    public let currentSedentaryBpm: Double?
    public let heartRateElevationBpm: Double?
    
    // Persona & Guidance
    public let monkeyMood: MonkeyMood
    public let adviceQuote: String
    public let recommendedBreathing: BreathingProtocol
    public let lastUpdated: Date
    
    public init(
        currentScore: Int,
        currentLevel: StressLevel,
        dailyAverageScore: Int,
        peakHour: Int? = nil,
        peakScore: Int? = nil,
        lowestHour: Int? = nil,
        lowestScore: Int? = nil,
        parasympatheticPercent: Int,
        sympatheticPercent: Int,
        baselineHrvMs: Double,
        currentHrvMs: Double? = nil,
        hrvDeltaPercent: Double? = nil,
        restingHeartRateBpm: Double? = nil,
        currentSedentaryBpm: Double? = nil,
        heartRateElevationBpm: Double? = nil,
        monkeyMood: MonkeyMood,
        adviceQuote: String,
        recommendedBreathing: BreathingProtocol,
        lastUpdated: Date = Date()
    ) {
        self.currentScore = min(max(currentScore, 0), 100)
        self.currentLevel = currentLevel
        self.dailyAverageScore = min(max(dailyAverageScore, 0), 100)
        self.peakHour = peakHour
        self.peakScore = peakScore
        self.lowestHour = lowestHour
        self.lowestScore = lowestScore
        self.parasympatheticPercent = min(max(parasympatheticPercent, 0), 100)
        self.sympatheticPercent = min(max(sympatheticPercent, 0), 100)
        self.baselineHrvMs = baselineHrvMs
        self.currentHrvMs = currentHrvMs
        self.hrvDeltaPercent = hrvDeltaPercent
        self.restingHeartRateBpm = restingHeartRateBpm
        self.currentSedentaryBpm = currentSedentaryBpm
        self.heartRateElevationBpm = heartRateElevationBpm
        self.monkeyMood = monkeyMood
        self.adviceQuote = adviceQuote
        self.recommendedBreathing = recommendedBreathing
        self.lastUpdated = lastUpdated
    }
}
