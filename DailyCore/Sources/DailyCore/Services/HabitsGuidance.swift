import Foundation

// MARK: - Diurnal Circadian Hydration Slot

public struct CircadianHydrationSlot: Identifiable, Sendable {
    public var id: String { timeRange }
    public var timeRange: String
    public var title: String
    public var recommendedVolumeMl: Int
    public var rationale: String
    public var iconName: String
    
    public var name: String { title }
    public var timeWindow: String { timeRange }
    public var targetMl: Double { Double(recommendedVolumeMl) }
    public var description: String { rationale }
    
    public init(
        timeRange: String,
        title: String,
        recommendedVolumeMl: Int,
        rationale: String,
        iconName: String
    ) {
        self.timeRange = timeRange
        self.title = title
        self.recommendedVolumeMl = recommendedVolumeMl
        self.rationale = rationale
        self.iconName = iconName
    }
}

// MARK: - Drink Hydration Index (DHI)

public struct DrinkHydrationInfo: Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var indexScore: Double
    public var description: String
    public var proTip: String
    public var iconName: String
    public var hexColor: String
    
    public var beverage: String { name }
    public var index: Double { indexScore }
    
    public init(
        name: String,
        indexScore: Double,
        description: String,
        proTip: String,
        iconName: String,
        hexColor: String
    ) {
        self.name = name
        self.indexScore = indexScore
        self.description = description
        self.proTip = proTip
        self.iconName = iconName
        self.hexColor = hexColor
    }
}

// MARK: - Urine Color Level (Armstrong Chart)

public struct UrineColorLevel: Identifiable, Sendable {
    public var id: Int { level }
    public var level: Int
    public var status: String
    public var hexColor: String
    public var recommendation: String
    
    public var name: String { status }
    public var colorHex: String { hexColor }
    
    public init(
        level: Int,
        status: String,
        hexColor: String,
        recommendation: String
    ) {
        self.level = level
        self.status = status
        self.hexColor = hexColor
        self.recommendation = recommendation
    }
}

// MARK: - Smoking Cessation Milestone

public struct RecoveryMilestone: Identifiable, Sendable {
    public var id: String { timeframe }
    public var timeframe: String
    public var benefit: String
    public var physiologicalChange: String
    public var iconName: String
    public var hexColor: String
    
    public var scientificDetail: String { physiologicalChange }
    public var colorHex: String { hexColor }

    
    public init(
        timeframe: String,
        benefit: String,
        physiologicalChange: String,
        iconName: String,
        hexColor: String
    ) {
        self.timeframe = timeframe
        self.benefit = benefit
        self.physiologicalChange = physiologicalChange
        self.iconName = iconName
        self.hexColor = hexColor
    }
}

// MARK: - 4D Craving Protocol Step

public struct CravingProtocolStep: Identifiable, Sendable {
    public var id: String { "\(letter)-\(action)" }
    public var letter: String
    public var action: String
    public var explanation: String
    public var durationText: String
    public var iconName: String
    public var stepNumber: Int
    
    public var step: Int { stepNumber }
    public var title: String { letter }
    
    public init(
        letter: String,
        action: String,
        explanation: String,
        durationText: String,
        iconName: String,
        stepNumber: Int = 1
    ) {
        self.letter = letter
        self.action = action
        self.explanation = explanation
        self.durationText = durationText
        self.iconName = iconName
        self.stepNumber = stepNumber
    }
}


// MARK: - Guidance Provider

public enum HabitsGuidance {
    
    // MARK: - Bubbles / Hydration Guidance
    
    public static let circadianSlots: [CircadianHydrationSlot] = [
        CircadianHydrationSlot(
            timeRange: "07:00 – 09:00",
            title: "Morning Kickstart",
            recommendedVolumeMl: 450,
            rationale: "Rehydrate brain and vital organs after 7-8h of nocturnal sleep post. Wakes up gastrointestinal motility.",
            iconName: "sunrise.fill"
        ),
        CircadianHydrationSlot(
            timeRange: "10:00 – 12:00",
            title: "Cognitive Focus Peak",
            recommendedVolumeMl: 300,
            rationale: "Maintains optimal cerebral blood flow. A 1% drop in body water degrades working memory and alertness.",
            iconName: "brain.head.profile"
        ),
        CircadianHydrationSlot(
            timeRange: "30m Pre-Meal",
            title: "Digestive Preparation",
            recommendedVolumeMl: 250,
            rationale: "Primes digestive enzymes and stimulates natural satiety. Avoid drinking large volumes during meals to maintain stomach acid concentration.",
            iconName: "fork.knife"
        ),
        CircadianHydrationSlot(
            timeRange: "14:00 – 16:00",
            title: "Afternoon Energy Boost",
            recommendedVolumeMl: 350,
            rationale: "Combats postprandial lethargy. Midday fatigue is commonly mild dehydration rather than actual lack of sleep.",
            iconName: "bolt.fill"
        ),
        CircadianHydrationSlot(
            timeRange: "Post 20:00",
            title: "Night Taper",
            recommendedVolumeMl: 100,
            rationale: "Limit water intake to small sips before bed to prevent nocturia, protecting uninterrupted Deep and REM sleep cycles.",
            iconName: "moon.stars.fill"
        )
    ]

    
    public static let drinkHydrationIndex: [DrinkHydrationInfo] = [
        DrinkHydrationInfo(
            name: "Pure Water",
            indexScore: 1.0,
            description: "The gold standard for cellular cellular osmosis.",
            proTip: "Room temperature or slightly cool water absorbs faster than iced water.",
            iconName: "drop.fill",
            hexColor: "#00E5FF"
        ),
        DrinkHydrationInfo(
            name: "Herbal & Green Tea",
            indexScore: 0.95,
            description: "High antioxidant polyphenol profile with excellent fluid retention.",
            proTip: "Chamomile in the evening relaxes nerves without diuretic impact.",
            iconName: "mug.fill",
            hexColor: "#84CC16"
        ),
        DrinkHydrationInfo(
            name: "Black Coffee",
            indexScore: 0.80,
            description: "Mild diuretic due to adenosine antagonism, but still net positive.",
            proTip: "Drink a 250ml glass of water alongside each espresso to offset fluid loss.",
            iconName: "cup.and.saucer.fill",
            hexColor: "#F59E0B"
        ),
        DrinkHydrationInfo(
            name: "Electrolyte Water",
            indexScore: 1.15,
            description: "Sodium + Potassium + Magnesium enables superior cellular fluid retention.",
            proTip: "Ideal post-workout or in hot weather when losing electrolytes through sweat.",
            iconName: "sparkles",
            hexColor: "#10B981"
        )
    ]
    
    public static let armstrongUrineScale: [UrineColorLevel] = [
        UrineColorLevel(
            level: 1,
            status: "Optimal Hydration",
            hexColor: "#F8FAF0",
            recommendation: "Pale straw to crystal clear. Your body is fully hydrated."
        ),
        UrineColorLevel(
            level: 2,
            status: "Good Hydration",
            hexColor: "#FDE047",
            recommendation: "Light yellow. Maintain current cadence of fluid intake."
        ),
        UrineColorLevel(
            level: 3,
            status: "Mild Dehydration",
            hexColor: "#EAB308",
            recommendation: "Bright or medium yellow. Drink a 300ml glass of water within the next hour."
        ),
        UrineColorLevel(
            level: 4,
            status: "Moderate Dehydration",
            hexColor: "#CA8A04",
            recommendation: "Amber or honey tone. Drink 500ml of water immediately."
        )
    ]
    
    // MARK: - Smokes / Cessation Guidance
    
    public static let fourDsCravingProtocol: [CravingProtocolStep] = [
        CravingProtocolStep(
            letter: "D",
            action: "Delay",
            explanation: "Cravings are neurochemical waves peaking in 3–5 minutes before fading. Wait 10 minutes before reacting.",
            durationText: "5–10 mins",
            iconName: "timer",
            stepNumber: 1
        ),
        CravingProtocolStep(
            letter: "D",
            action: "Deep Breathe",
            explanation: "Breathe in for 4 seconds, hold 4 seconds, exhale 4 seconds. Triggers parasympathetic nerve calming and lowers cortisol.",
            durationText: "1–2 mins",
            iconName: "wind",
            stepNumber: 2
        ),
        CravingProtocolStep(
            letter: "D",
            action: "Drink Water",
            explanation: "Sip cold water slowly. Occupies the oral fixation trigger while accelerating metabolic toxin clearance.",
            durationText: "2 mins",
            iconName: "drop.fill",
            stepNumber: 3
        ),
        CravingProtocolStep(
            letter: "D",
            action: "Distract",
            explanation: "Shift physical location or engage your hands in a concrete task (walk, message a friend, stretch).",
            durationText: "5–10 mins",
            iconName: "figure.walk",
            stepNumber: 4
        )
    ]


    
    public static let recoveryMilestones: [RecoveryMilestone] = [
        RecoveryMilestone(
            timeframe: "20 Minutes",
            benefit: "Heart Rate & BP Drop",
            physiologicalChange: "Pulse and peripheral blood pressure return toward baseline resting levels.",
            iconName: "heart.fill",
            hexColor: "#EF4444"
        ),
        RecoveryMilestone(
            timeframe: "12 Hours",
            benefit: "Carbon Monoxide Cleared",
            physiologicalChange: "Blood carbon monoxide (CO) drops by 50%+, restoring red blood cell oxygen carrying capacity.",
            iconName: "lungs.fill",
            hexColor: "#3B82F6"
        ),
        RecoveryMilestone(
            timeframe: "48 Hours",
            benefit: "Nerve Endings Regenerate",
            physiologicalChange: "All nicotine eliminated from the body. Taste buds and olfactory receptors begin sharp recovery.",
            iconName: "sparkles",
            hexColor: "#10B981"
        ),
        RecoveryMilestone(
            timeframe: "72 Hours",
            benefit: "Bronchial Tubes Relax",
            physiologicalChange: "Breathing eases noticeably as bronchial airway spasm diminishes; total lung capacity expands.",
            iconName: "wind",
            hexColor: "#00E5FF"
        ),
        RecoveryMilestone(
            timeframe: "2–4 Weeks",
            benefit: "Physical Addiction Ended",
            physiologicalChange: "Nicotine withdrawal symptoms fully subside. Peripheral vascular circulation significantly improves.",
            iconName: "checkmark.shield.fill",
            hexColor: "#8B5CF6"
        ),
        RecoveryMilestone(
            timeframe: "1 Year",
            benefit: "Cardiovascular Risk Halved",
            physiologicalChange: "Excess risk of coronary heart disease drops by 50% compared to a continuing smoker.",
            iconName: "medal.fill",
            hexColor: "#F59E0B"
        )
    ]
}
