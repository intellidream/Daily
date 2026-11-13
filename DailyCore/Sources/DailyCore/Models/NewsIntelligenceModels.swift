import Foundation
import CryptoKit

// MARK: - 1. Political & Editorial Bias Spectrum (5-Step Universal + Independent Creator)

public enum MediaBias: String, Codable, CaseIterable, Hashable, Sendable {
    case left = "left"
    case leanLeft = "lean_left"
    case center = "center"
    case leanRight = "lean_right"
    case right = "right"
    case independentCreator = "independent_creator"
    case unrated = "unrated"

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .leanLeft: return "Lean Left"
        case .center: return "Center"
        case .leanRight: return "Lean Right"
        case .right: return "Right"
        case .independentCreator: return "Independent"
        case .unrated: return "Unrated"
        }
    }

    public var compactCode: String {
        switch self {
        case .left: return "L"
        case .leanLeft: return "LL"
        case .center: return "C"
        case .leanRight: return "LR"
        case .right: return "R"
        case .independentCreator: return "IND"
        case .unrated: return "—"
        }
    }

    public var shortCode: String { compactCode }

    /// 0...4 index on the classic 5-step political bar (`nil` for independent creator / unrated).
    public var fiveStepIndex: Int? {
        switch self {
        case .left: return 0
        case .leanLeft: return 1
        case .center: return 2
        case .leanRight: return 3
        case .right: return 4
        case .independentCreator, .unrated: return nil
        }
    }

    public enum SpectrumBucket: String, Codable, Hashable, Sendable {
        case left
        case center
        case right
        case independent
        case unrated
    }

    public var bucket: SpectrumBucket {
        switch self {
        case .left, .leanLeft:
            return .left
        case .center:
            return .center
        case .leanRight, .right:
            return .right
        case .independentCreator:
            return .independent
        case .unrated:
            return .unrated
        }
    }
}

// MARK: - 2. Factuality & Epistemic Reliability Tier

public enum FactualityTier: String, Codable, CaseIterable, Hashable, Sendable {
    case veryHigh = "very_high"
    case high = "high"
    case mixed = "mixed"
    case low = "low"

    public var displayName: String {
        switch self {
        case .veryHigh: return "Very High"
        case .high: return "High"
        case .mixed: return "Mixed"
        case .low: return "Low"
        }
    }

    public var numericScore: Double {
        switch self {
        case .veryHigh: return 1.0
        case .high: return 0.82
        case .mixed: return 0.50
        case .low: return 0.20
        }
    }
}

// MARK: - 3. Ownership & Funding Model

public enum OwnershipCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case independent = "independent"
    case nonProfit = "non_profit"
    case publicBroadcaster = "public_broadcaster"
    case corporation = "corporation"
    case conglomerate = "conglomerate"
    case billionaireIndividual = "billionaire_individual"
    case privateEquity = "private_equity"
    case stateAffiliated = "state_affiliated"

    public var displayName: String {
        switch self {
        case .independent: return "Independent / Reader-Funded"
        case .nonProfit: return "Non-Profit / Trust"
        case .publicBroadcaster: return "Public Service Media"
        case .corporation: return "Media Corporation"
        case .conglomerate: return "Corporate Conglomerate"
        case .billionaireIndividual: return "Individual / Billionaire Owner"
        case .privateEquity: return "Private Equity / Fund"
        case .stateAffiliated: return "State-Affiliated Media"
        }
    }

    public var systemIcon: String {
        switch self {
        case .independent: return "person.2.badge.key.fill"
        case .nonProfit: return "heart.text.square.fill"
        case .publicBroadcaster: return "building.columns.fill"
        case .corporation: return "building.2.fill"
        case .conglomerate: return "globe.desk.fill"
        case .billionaireIndividual: return "person.crop.circle.badge.exclamationmark"
        case .privateEquity: return "chart.pie.fill"
        case .stateAffiliated: return "flag.2.crossed.fill"
        }
    }

    public var isIndependentOrNonProfit: Bool {
        switch self {
        case .independent, .nonProfit:
            return true
        default:
            return false
        }
    }
}

// MARK: - 4. Canonical Media Outlet Profile

public struct MediaOutletProfile: Identifiable, Hashable, Codable, Sendable {
    public var id: String { domain }
    public var domain: String
    public var name: String
    public var aliases: [String]
    public var bias: MediaBias
    public var biasContext: String
    public var factuality: FactualityTier
    public var ownershipType: OwnershipCategory
    public var ownerLabel: String
    public var countryCode: String
    public var editorialNote: String

    public init(
        domain: String,
        name: String,
        aliases: [String] = [],
        bias: MediaBias,
        biasContext: String,
        factuality: FactualityTier,
        ownershipType: OwnershipCategory,
        ownerLabel: String,
        countryCode: String = "INT",
        editorialNote: String = ""
    ) {
        self.domain = domain.lowercased()
        self.name = name
        self.aliases = aliases
        self.bias = bias
        self.biasContext = biasContext
        self.factuality = factuality
        self.ownershipType = ownershipType
        self.ownerLabel = ownerLabel
        self.countryCode = countryCode.uppercased()
        self.editorialNote = editorialNote
    }

    /// Sleek Variant A micro-pill text for `Live Feed` cards (`"Center · High"`, `"Independent · Very High"`).
    public var compactBadgeText: String {
        if bias == .unrated {
            return "Unrated"
        }
        return "\(bias.displayName) · \(factuality.displayName)"
    }

    public var countryFlag: String {
        let code = countryCode.uppercased()
        if code == "EU" { return "🇪🇺" }
        if code == "INT" || code.count != 2 { return "🌐" }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for u in code.utf16 {
            if let scalar = UnicodeScalar(base + UInt32(u)) {
                scalars.append(scalar)
            }
        }
        return scalars.isEmpty ? "🌐" : String(scalars)
    }
}

/// Seed JSON root container (`media_intelligence_seed.json`).
public struct MediaIntelligenceSeedCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let updatedAt: String
    public let outlets: [MediaOutletProfile]
}

/// Supabase row mapping for `public.media_outlet_profiles`.
public struct RemoteMediaOutletProfileRow: Codable, Sendable {
    public let domain: String
    public let name: String
    public let aliases: [String]?
    public let bias: String
    public let biasContext: String?
    public let factuality: String
    public let ownershipType: String
    public let ownerLabel: String?
    public let countryCode: String?
    public let editorialNote: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case name
        case aliases
        case bias
        case biasContext = "bias_context"
        case factuality
        case ownershipType = "ownership_type"
        case ownerLabel = "owner_label"
        case countryCode = "country_code"
        case editorialNote = "editorial_note"
        case updatedAt = "updated_at"
    }

    public func toDomainProfile() -> MediaOutletProfile {
        MediaOutletProfile(
            domain: domain,
            name: name,
            aliases: aliases ?? [],
            bias: MediaBias(rawValue: bias) ?? .center,
            biasContext: biasContext ?? "",
            factuality: FactualityTier(rawValue: factuality) ?? .high,
            ownershipType: OwnershipCategory(rawValue: ownershipType) ?? .corporation,
            ownerLabel: ownerLabel ?? "",
            countryCode: countryCode ?? "INT",
            editorialNote: editorialNote ?? ""
        )
    }
}

// MARK: - 5. Article-Level Epistemic Framing Tag

public enum ArticleFramingTag: String, Codable, CaseIterable, Hashable, Sendable {
    case reporting = "reporting"
    case opinion = "opinion"
    case investigation = "investigation"
    case sensational = "sensational"

    public var badgeLabel: String? {
        switch self {
        case .reporting: return nil // Sleek Variant A: straight reporting adds zero visual noise
        case .opinion: return "Opinion"
        case .investigation: return "Investigation"
        case .sensational: return "Sensational"
        }
    }

    public var systemIcon: String {
        switch self {
        case .reporting: return "newspaper"
        case .opinion: return "quote.bubble.fill"
        case .investigation: return "magnifyingglass.circle.fill"
        case .sensational: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - 6. Story Clustering, Bias Spectrum & Blindspots

/// Unpacked sibling article from Google News RSS `<ol><li>` cluster blocks.
public struct ClusterSibling: Hashable, Codable, Sendable {
    public var title: String
    public var link: String
    public var publicationName: String
    public var publishDate: Date?

    public init(title: String, link: String, publicationName: String, publishDate: Date? = nil) {
        self.title = title
        self.link = link
        self.publicationName = publicationName
        self.publishDate = publishDate
    }
}

public enum BlindspotType: String, Codable, Hashable, Sendable {
    case none = "none"
    case lowRightCoverage = "low_right_coverage"       // Covered heavily by Left/Lean-Left, <=10% Right
    case lowLeftCoverage = "low_left_coverage"         // Covered heavily by Right/Lean-Right, <=10% Left
    case uncoveredLocally = "uncovered_locally"        // Major global story (>=4 int'l sources, 0 RO sources)
    case domesticOnlyFocus = "domestic_only_focus"     // Major local story (>=4 RO sources, 0 int'l sources)

    public var isBlindspot: Bool {
        self != .none
    }

    public var shortBadge: String {
        switch self {
        case .none: return ""
        case .lowRightCoverage: return "Blindspot · Low Right"
        case .lowLeftCoverage: return "Blindspot · Low Left"
        case .uncoveredLocally: return "Blindspot · Global Only"
        case .domesticOnlyFocus: return "Blindspot · RO Focus"
        }
    }

    public var badgeTitle: String { shortBadge }

    public var explanation: String {
        switch self {
        case .none:
            return "Balanced multi-source coverage across the media spectrum."
        case .lowRightCoverage:
            return "Heavily covered by Left & Center-Left outlets, with minimal or zero coverage from Right-leaning outlets."
        case .lowLeftCoverage:
            return "Heavily covered by Right & Center-Right outlets, with minimal or zero coverage from Left-leaning outlets."
        case .uncoveredLocally:
            return "Widely reported across international newsrooms, with little or no coverage in subscribed domestic feeds."
        case .domesticOnlyFocus:
            return "Intensively covered by Romanian newsrooms without international wire pickup yet."
        }
    }
}

public struct BiasDistribution: Hashable, Codable, Sendable {
    public let leftCount: Int
    public let centerCount: Int
    public let rightCount: Int
    public let independentCount: Int
    public let unratedCount: Int

    public var ratedPoliticalCount: Int {
        leftCount + centerCount + rightCount
    }

    public var totalCount: Int {
        leftCount + centerCount + rightCount + independentCount + unratedCount
    }

    public var leftFraction: Double {
        let denom = ratedPoliticalCount
        guard denom > 0 else { return 0.0 }
        return Double(leftCount) / Double(denom)
    }

    public var centerFraction: Double {
        let denom = ratedPoliticalCount
        guard denom > 0 else {
            return totalCount > 0 ? 1.0 : 0.0
        }
        return Double(centerCount) / Double(denom)
    }

    public var rightFraction: Double {
        let denom = ratedPoliticalCount
        guard denom > 0 else { return 0.0 }
        return Double(rightCount) / Double(denom)
    }

    public var leftPercentInt: Int {
        guard ratedPoliticalCount > 0 else { return 0 }
        return Int((leftFraction * 100.0).rounded())
    }

    public var rightPercentInt: Int {
        guard ratedPoliticalCount > 0 else { return 0 }
        return Int((rightFraction * 100.0).rounded())
    }

    public var centerPercentInt: Int {
        guard ratedPoliticalCount > 0 else { return totalCount > 0 ? 100 : 0 }
        return max(0, 100 - leftPercentInt - rightPercentInt)
    }

    public init(
        leftCount: Int = 0,
        centerCount: Int = 0,
        rightCount: Int = 0,
        independentCount: Int = 0,
        unratedCount: Int = 0
    ) {
        self.leftCount = leftCount
        self.centerCount = centerCount
        self.rightCount = rightCount
        self.independentCount = independentCount
        self.unratedCount = unratedCount
    }
}

public struct ClusterCoverageItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { article.link }
    public let article: NewsArticle
    public let profile: MediaOutletProfile
    public let framing: ArticleFramingTag
    public let isExternalDiscovery: Bool

    public init(
        article: NewsArticle,
        profile: MediaOutletProfile,
        framing: ArticleFramingTag,
        isExternalDiscovery: Bool = false
    ) {
        self.article = article
        self.profile = profile
        self.framing = framing
        self.isExternalDiscovery = isExternalDiscovery
    }
}

public struct StoryCluster: Identifiable, Hashable, Codable, Sendable {
    public let id: String // Deterministic `clusterHash`
    public let leadArticle: NewsArticle
    public let items: [ClusterCoverageItem]
    public let uniqueOutletCount: Int
    public let distribution: BiasDistribution
    public let blindspot: BlindspotType
    public let anchorEntities: [String]
    public let latestPublishDate: Date
    public let isExpandedExternally: Bool

    public var hasMultipleSources: Bool {
        uniqueOutletCount >= 2
    }

    public init(
        id: String,
        leadArticle: NewsArticle,
        items: [ClusterCoverageItem],
        uniqueOutletCount: Int,
        distribution: BiasDistribution,
        blindspot: BlindspotType,
        anchorEntities: [String],
        latestPublishDate: Date,
        isExpandedExternally: Bool = false
    ) {
        self.id = id
        self.leadArticle = leadArticle
        self.items = items
        self.uniqueOutletCount = uniqueOutletCount
        self.distribution = distribution
        self.blindspot = blindspot
        self.anchorEntities = anchorEntities
        self.latestPublishDate = latestPublishDate
        self.isExpandedExternally = isExpandedExternally
    }

    public static func makeDeterministicHash(entities: [String], referenceDate: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: referenceDate)
        let dayBucket = String(format: "%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
        let normalized = entities
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .prefix(5)
            .joined(separator: "|")
        let raw = "\(dayBucket)::\(normalized)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 7. AI Multi-Perspective Comparison & Cloud Cache Models

public struct FramingDifferenceItem: Hashable, Codable, Sendable, Identifiable {
    public var id: String { "\(perspectiveLabel):\(angle.prefix(32))" }
    public let perspectiveLabel: String
    public let angle: String

    public init(perspectiveLabel: String, angle: String) {
        self.perspectiveLabel = perspectiveLabel
        self.angle = angle
    }
}

public struct PerspectiveComparison: Hashable, Codable, Sendable {
    public let clusterHash: String
    public let storyTitle: String
    public let summaryText: String
    public let commonFacts: [String]
    public let framingDifferences: [FramingDifferenceItem]
    public let omissions: [String]
    public let languageCode: String
    public let sourceCount: Int
    public let isAiGenerated: Bool
    public let generatedAt: Date

    public init(
        clusterHash: String,
        storyTitle: String,
        summaryText: String,
        commonFacts: [String],
        framingDifferences: [FramingDifferenceItem],
        omissions: [String],
        languageCode: String = "en",
        sourceCount: Int,
        isAiGenerated: Bool,
        generatedAt: Date = Date()
    ) {
        self.clusterHash = clusterHash
        self.storyTitle = storyTitle
        self.summaryText = summaryText
        self.commonFacts = commonFacts
        self.framingDifferences = framingDifferences
        self.omissions = omissions
        self.languageCode = languageCode
        self.sourceCount = sourceCount
        self.isAiGenerated = isAiGenerated
        self.generatedAt = generatedAt
    }
}

public struct RemotePerspectiveCacheRow: Codable, Sendable {
    public let clusterHash: String
    public let storyTitle: String
    public let summaryText: String
    public let commonFacts: [String]
    public let framingDifferences: [FramingDifferenceItem]
    public let omissions: [String]
    public let languageCode: String
    public let sourceCount: Int
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case clusterHash = "cluster_hash"
        case storyTitle = "story_title"
        case summaryText = "summary_text"
        case commonFacts = "common_facts"
        case framingDifferences = "framing_differences"
        case omissions
        case languageCode = "language_code"
        case sourceCount = "source_count"
        case createdAt = "created_at"
    }

    public func toDomain() -> PerspectiveComparison {
        PerspectiveComparison(
            clusterHash: clusterHash,
            storyTitle: storyTitle,
            summaryText: summaryText,
            commonFacts: commonFacts,
            framingDifferences: framingDifferences,
            omissions: omissions,
            languageCode: languageCode,
            sourceCount: sourceCount,
            isAiGenerated: true
        )
    }
}

// MARK: - 8. Personal Media Diet (1 Row / Month / User)

public struct MediaDietSnapshot: Hashable, Codable, Sendable {
    public var yearMonth: String
    public var counts: [String: Int]

    public init(yearMonth: String, counts: [String: Int] = [:]) {
        self.yearMonth = yearMonth
        self.counts = counts
    }

    public var totalRead: Int { counts["total_read"] ?? 0 }
    public var totalArticlesRead: Int { totalRead }
    public var leftRead: Int { (counts["left"] ?? 0) + (counts["lean_left"] ?? 0) }
    public var centerRead: Int { counts["center"] ?? 0 }
    public var rightRead: Int { (counts["lean_right"] ?? 0) + (counts["right"] ?? 0) }
    public var independentCreatorRead: Int { counts["independent_creator"] ?? 0 }
    public var highFactualityRead: Int { (counts["very_high"] ?? 0) + (counts["high"] ?? 0) }
    public var independentOwnershipRead: Int { counts["independent_own"] ?? 0 }
    public var blindspotsExplored: Int { counts["blindspots_read"] ?? 0 }
    public var blindspotsRead: Int { blindspotsExplored }

    public var distribution: BiasDistribution {
        BiasDistribution(
            leftCount: leftRead,
            centerCount: centerRead,
            rightCount: rightRead,
            independentCount: independentCreatorRead,
            unratedCount: counts["unrated"] ?? 0
        )
    }

    public var highFactualityPercent: Int {
        guard totalRead > 0 else { return 100 }
        return min(100, Int((Double(highFactualityRead) / Double(totalRead) * 100.0).rounded()))
    }

    public var independentOwnershipPercent: Int {
        guard totalRead > 0 else { return 0 }
        return min(100, Int((Double(independentOwnershipRead) / Double(totalRead) * 100.0).rounded()))
    }

    public var balanceSummaryLabel: String {
        guard totalRead >= 3 else { return "Building Reading Profile" }
        let dist = distribution
        if dist.ratedPoliticalCount == 0 {
            return "Independent & Technical Focus"
        }
        if dist.leftFraction > 0.62 {
            return "Leans Left-of-Center"
        }
        if dist.rightFraction > 0.62 {
            return "Leans Right-of-Center"
        }
        return "Balanced Cross-Spectrum Diet"
    }
}

public struct RemoteNewsReadingStatsRow: Codable, Sendable {
    public let id: String?
    public let userId: String
    public let yearMonth: String
    public let counts: [String: Int]
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case yearMonth = "year_month"
        case counts
        case updatedAt = "updated_at"
    }

    public init(id: String? = nil, userId: String, yearMonth: String, counts: [String: Int], updatedAt: String? = nil) {
        self.id = id
        self.userId = userId
        self.yearMonth = yearMonth
        self.counts = counts
        self.updatedAt = updatedAt
    }
}
