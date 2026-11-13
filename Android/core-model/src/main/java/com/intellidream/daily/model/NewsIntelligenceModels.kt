package com.intellidream.daily.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// MARK: - 1. Political & Editorial Bias Spectrum (5-Step Universal + Independent Creator)

@Serializable
enum class MediaBias(val rawValue: String, val displayName: String, val compactCode: String) {
    @SerialName("left")
    Left("left", "Left", "L"),

    @SerialName("lean_left")
    LeanLeft("lean_left", "Lean Left", "LL"),

    @SerialName("center")
    Center("center", "Center", "C"),

    @SerialName("lean_right")
    LeanRight("lean_right", "Lean Right", "LR"),

    @SerialName("right")
    Right("right", "Right", "R"),

    @SerialName("independent_creator")
    IndependentCreator("independent_creator", "Independent", "IND"),

    @SerialName("unrated")
    Unrated("unrated", "Unrated", "—");

    val shortCode: String get() = compactCode

    val fiveStepIndex: Int?
        get() = when (this) {
            Left -> 0
            LeanLeft -> 1
            Center -> 2
            LeanRight -> 3
            Right -> 4
            IndependentCreator, Unrated -> null
        }

    enum class SpectrumBucket {
        Left, Center, Right, Independent, Unrated
    }

    val bucket: SpectrumBucket
        get() = when (this) {
            Left, LeanLeft -> SpectrumBucket.Left
            Center -> SpectrumBucket.Center
            LeanRight, Right -> SpectrumBucket.Right
            IndependentCreator -> SpectrumBucket.Independent
            Unrated -> SpectrumBucket.Unrated
        }

    companion object {
        fun fromRaw(raw: String): MediaBias =
            entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: Center
    }
}

// MARK: - 2. Factuality & Epistemic Reliability Tier

@Serializable
enum class FactualityTier(val rawValue: String, val displayName: String, val numericScore: Double) {
    @SerialName("very_high")
    VeryHigh("very_high", "Very High", 1.0),

    @SerialName("high")
    High("high", "High", 0.82),

    @SerialName("mixed")
    Mixed("mixed", "Mixed", 0.50),

    @SerialName("low")
    Low("low", "Low", 0.20);

    companion object {
        fun fromRaw(raw: String): FactualityTier =
            entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: High
    }
}

// MARK: - 3. Ownership & Funding Model

@Serializable
enum class OwnershipCategory(val rawValue: String, val displayName: String) {
    @SerialName("independent")
    Independent("independent", "Independent / Reader-Funded"),

    @SerialName("non_profit")
    NonProfit("non_profit", "Non-Profit / Trust"),

    @SerialName("public_broadcaster")
    PublicBroadcaster("public_broadcaster", "Public Service Media"),

    @SerialName("corporation")
    Corporation("corporation", "Media Corporation"),

    @SerialName("conglomerate")
    Conglomerate("conglomerate", "Corporate Conglomerate"),

    @SerialName("billionaire_individual")
    BillionaireIndividual("billionaire_individual", "Individual / Billionaire Owner"),

    @SerialName("private_equity")
    PrivateEquity("private_equity", "Private Equity / Fund"),

    @SerialName("state_affiliated")
    StateAffiliated("state_affiliated", "State-Affiliated Media");

    val isIndependentOrNonProfit: Boolean
        get() = this == Independent || this == NonProfit

    companion object {
        fun fromRaw(raw: String): OwnershipCategory =
            entries.firstOrNull { it.rawValue.equals(raw, ignoreCase = true) } ?: Corporation
    }
}

// MARK: - 4. Canonical Media Outlet Profile

@Serializable
data class MediaOutletProfile(
    val domain: String,
    val name: String,
    val aliases: List<String> = emptyList(),
    val bias: MediaBias = MediaBias.Center,
    val biasContext: String = "",
    val factuality: FactualityTier = FactualityTier.High,
    val ownershipType: OwnershipCategory = OwnershipCategory.Corporation,
    val ownerLabel: String = "",
    val countryCode: String = "INT",
    val editorialNote: String = ""
) {
    val id: String get() = domain

    /** Sleek Variant A micro-pill text for `Live Feed` cards (`"Center · High"`, `"Independent · Very High"`). */
    val compactBadgeText: String
        get() = if (bias == MediaBias.Unrated) "Unrated" else "${bias.displayName} · ${factuality.displayName}"

    val countryFlag: String
        get() {
            val code = countryCode.uppercase(Locale.ROOT)
            if (code == "EU") return "🇪🇺"
            if (code == "INT" || code.length != 2) return "🌐"
            val first = Character.codePointAt(code, 0) - 0x41 + 0x1F1E6
            val second = Character.codePointAt(code, 1) - 0x41 + 0x1F1E6
            return try {
                String(Character.toChars(first)) + String(Character.toChars(second))
            } catch (_: Exception) {
                "🌐"
            }
        }
}

@Serializable
data class MediaIntelligenceSeedCatalog(
    val schemaVersion: Int = 1,
    val updatedAt: String = "",
    val outlets: List<MediaOutletProfile> = emptyList()
)

@Serializable
data class RemoteMediaOutletProfileRow(
    val domain: String,
    val name: String,
    val aliases: List<String>? = null,
    val bias: String,
    @SerialName("bias_context")
    val biasContext: String? = null,
    val factuality: String,
    @SerialName("ownership_type")
    val ownershipType: String,
    @SerialName("owner_label")
    val ownerLabel: String? = null,
    @SerialName("country_code")
    val countryCode: String? = null,
    @SerialName("editorial_note")
    val editorialNote: String? = null,
    @SerialName("updated_at")
    val updatedAt: String? = null
) {
    fun toDomainProfile(): MediaOutletProfile = MediaOutletProfile(
        domain = domain.lowercase(Locale.ROOT),
        name = name,
        aliases = aliases ?: emptyList(),
        bias = MediaBias.fromRaw(bias),
        biasContext = biasContext ?: "",
        factuality = FactualityTier.fromRaw(factuality),
        ownershipType = OwnershipCategory.fromRaw(ownershipType),
        ownerLabel = ownerLabel ?: "",
        countryCode = (countryCode ?: "INT").uppercase(Locale.ROOT),
        editorialNote = editorialNote ?: ""
    )
}

// MARK: - 5. Article-Level Epistemic Framing Tag

@Serializable
enum class ArticleFramingTag(val rawValue: String) {
    @SerialName("reporting")
    Reporting("reporting"),

    @SerialName("opinion")
    Opinion("opinion"),

    @SerialName("investigation")
    Investigation("investigation"),

    @SerialName("sensational")
    Sensational("sensational");

    /** Sleek Variant A: straight reporting adds zero visual noise (`null`). */
    val badgeLabel: String?
        get() = when (this) {
            Reporting -> null
            Opinion -> "Opinion"
            Investigation -> "Investigation"
            Sensational -> "Sensational"
        }
}

// MARK: - 6. Story Clustering, Bias Spectrum & Blindspots

@Serializable
data class ClusterSibling(
    val title: String,
    val link: String,
    val publicationName: String,
    val publishDateMillis: Long? = null
)

@Serializable
enum class BlindspotType(val rawValue: String, val shortBadge: String, val explanation: String) {
    @SerialName("none")
    None(
        "none",
        "",
        "Balanced multi-source coverage across the media spectrum."
    ),

    @SerialName("low_right_coverage")
    LowRightCoverage(
        "low_right_coverage",
        "Blindspot · Low Right",
        "Heavily covered by Left & Center-Left outlets, with minimal or zero coverage from Right-leaning outlets."
    ),

    @SerialName("low_left_coverage")
    LowLeftCoverage(
        "low_left_coverage",
        "Blindspot · Low Left",
        "Heavily covered by Right & Center-Right outlets, with minimal or zero coverage from Left-leaning outlets."
    ),

    @SerialName("uncovered_locally")
    UncoveredLocally(
        "uncovered_locally",
        "Blindspot · Global Only",
        "Widely reported across international newsrooms, with little or no coverage in subscribed domestic feeds."
    ),

    @SerialName("domestic_only_focus")
    DomesticOnlyFocus(
        "domestic_only_focus",
        "Blindspot · RO Focus",
        "Intensively covered by Romanian newsrooms without international wire pickup yet."
    );

    val isBlindspot: Boolean get() = this != None
    val badgeTitle: String get() = shortBadge
}

@Serializable
data class BiasDistribution(
    val leftCount: Int = 0,
    val centerCount: Int = 0,
    val rightCount: Int = 0,
    val independentCount: Int = 0,
    val unratedCount: Int = 0
) {
    val ratedPoliticalCount: Int
        get() = leftCount + centerCount + rightCount

    val totalCount: Int
        get() = leftCount + centerCount + rightCount + independentCount + unratedCount

    val leftFraction: Float
        get() = if (ratedPoliticalCount > 0) leftCount.toFloat() / ratedPoliticalCount.toFloat() else 0f

    val centerFraction: Float
        get() = if (ratedPoliticalCount > 0) {
            centerCount.toFloat() / ratedPoliticalCount.toFloat()
        } else if (totalCount > 0) 1f else 0f

    val rightFraction: Float
        get() = if (ratedPoliticalCount > 0) rightCount.toFloat() / ratedPoliticalCount.toFloat() else 0f

    val leftPercentInt: Int
        get() = if (ratedPoliticalCount > 0) (leftFraction * 100f).roundToInt() else 0

    val rightPercentInt: Int
        get() = if (ratedPoliticalCount > 0) (rightFraction * 100f).roundToInt() else 0

    val centerPercentInt: Int
        get() = if (ratedPoliticalCount > 0) {
            max(0, 100 - leftPercentInt - rightPercentInt)
        } else if (totalCount > 0) 100 else 0
}

@Serializable
data class ClusterCoverageItem(
    val article: NewsArticle,
    val profile: MediaOutletProfile,
    val framing: ArticleFramingTag,
    val isExternalDiscovery: Boolean = false
) {
    val id: String get() = article.link
}

@Serializable
data class StoryCluster(
    val id: String,
    val leadArticle: NewsArticle,
    val items: List<ClusterCoverageItem>,
    val uniqueOutletCount: Int,
    val distribution: BiasDistribution,
    val blindspot: BlindspotType,
    val anchorEntities: List<String>,
    val latestPublishDateMillis: Long,
    val isExpandedExternally: Boolean = false
) {
    val hasMultipleSources: Boolean get() = uniqueOutletCount >= 2

    companion object {
        private val monthFormatter: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM", Locale.US).withZone(ZoneOffset.UTC)

        fun makeDeterministicHash(entities: List<String>, referenceEpochMillis: Long): String {
            val dayBucket = try {
                monthFormatter.format(Instant.ofEpochMilli(referenceEpochMillis))
            } catch (_: Exception) {
                "2026-11"
            }
            val normalized = entities
                .map { it.lowercase(Locale.ROOT).trim() }
                .filter { it.isNotEmpty() }
                .sorted()
                .take(5)
                .joinToString("|")
            val raw = "$dayBucket::$normalized"
            val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
            return digest.take(16).joinToString("") { "%02x".format(it) }
        }
    }
}

// MARK: - 7. AI Multi-Perspective Comparison & Cloud Cache Models

@Serializable
data class FramingDifferenceItem(
    val perspectiveLabel: String,
    val angle: String
) {
    val id: String get() = "$perspectiveLabel:${angle.take(32)}"
}

@Serializable
data class PerspectiveComparison(
    val clusterHash: String,
    val storyTitle: String,
    val summaryText: String,
    val commonFacts: List<String>,
    val framingDifferences: List<FramingDifferenceItem>,
    val omissions: List<String>,
    val languageCode: String = "en",
    val sourceCount: Int,
    val isAiGenerated: Boolean,
    val generatedAtMillis: Long = System.currentTimeMillis()
)

@Serializable
data class RemotePerspectiveCacheRow(
    @SerialName("cluster_hash")
    val clusterHash: String,
    @SerialName("story_title")
    val storyTitle: String,
    @SerialName("summary_text")
    val summaryText: String,
    @SerialName("common_facts")
    val commonFacts: List<String> = emptyList(),
    @SerialName("framing_differences")
    val framingDifferences: List<FramingDifferenceItem> = emptyList(),
    val omissions: List<String> = emptyList(),
    @SerialName("language_code")
    val languageCode: String = "en",
    @SerialName("source_count")
    val sourceCount: Int = 2,
    @SerialName("created_at")
    val createdAt: String? = null
) {
    fun toDomain(): PerspectiveComparison = PerspectiveComparison(
        clusterHash = clusterHash,
        storyTitle = storyTitle,
        summaryText = summaryText,
        commonFacts = commonFacts,
        framingDifferences = framingDifferences,
        omissions = omissions,
        languageCode = languageCode,
        sourceCount = sourceCount,
        isAiGenerated = true
    )
}

// MARK: - 8. Personal Media Diet (1 Row / Month / User)

@Serializable
data class MediaDietSnapshot(
    val yearMonth: String,
    val counts: Map<String, Int> = emptyMap()
) {
    val totalRead: Int get() = counts["total_read"] ?: 0
    val totalArticlesRead: Int get() = totalRead
    val leftRead: Int get() = (counts["left"] ?: 0) + (counts["lean_left"] ?: 0)
    val centerRead: Int get() = counts["center"] ?: 0
    val rightRead: Int get() = (counts["lean_right"] ?: 0) + (counts["right"] ?: 0)
    val independentCreatorRead: Int get() = counts["independent_creator"] ?: 0
    val highFactualityRead: Int get() = (counts["very_high"] ?: 0) + (counts["high"] ?: 0)
    val independentOwnershipRead: Int get() = counts["independent_own"] ?: 0
    val blindspotsExplored: Int get() = counts["blindspots_read"] ?: 0
    val blindspotsRead: Int get() = blindspotsExplored

    val distribution: BiasDistribution
        get() = BiasDistribution(
            leftCount = leftRead,
            centerCount = centerRead,
            rightCount = rightRead,
            independentCount = independentCreatorRead,
            unratedCount = counts["unrated"] ?: 0
        )

    val highFactualityPercent: Int
        get() = if (totalRead <= 0) 100 else min(100, (highFactualityRead.toDouble() / totalRead.toDouble() * 100.0).roundToInt())

    val independentOwnershipPercent: Int
        get() = if (totalRead <= 0) 0 else min(100, (independentOwnershipRead.toDouble() / totalRead.toDouble() * 100.0).roundToInt())

    val balanceSummaryLabel: String
        get() {
            if (totalRead < 3) return "Building Reading Profile"
            val dist = distribution
            if (dist.ratedPoliticalCount == 0) return "Independent & Technical Focus"
            if (dist.leftFraction > 0.62f) return "Leans Left-of-Center"
            if (dist.rightFraction > 0.62f) return "Leans Right-of-Center"
            return "Balanced Cross-Spectrum Diet"
        }
}

@Serializable
data class RemoteNewsReadingStatsRow(
    val id: String? = null,
    @SerialName("user_id")
    val userId: String,
    @SerialName("year_month")
    val yearMonth: String,
    val counts: Map<String, Int>,
    @SerialName("updated_at")
    val updatedAt: String? = null
)
