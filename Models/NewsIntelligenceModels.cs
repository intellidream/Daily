using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models
{
    public enum MediaBias
    {
        Left,
        LeanLeft,
        Center,
        LeanRight,
        Right,
        Independent,
        Unrated
    }

    public static class MediaBiasExtensions
    {
        public static MediaBias Parse(string? raw)
        {
            return (raw ?? string.Empty).Trim().ToLowerInvariant() switch
            {
                "left" => MediaBias.Left,
                "lean_left" or "leanleft" => MediaBias.LeanLeft,
                "center" => MediaBias.Center,
                "lean_right" or "leanright" => MediaBias.LeanRight,
                "right" => MediaBias.Right,
                "independent" => MediaBias.Independent,
                _ => MediaBias.Unrated
            };
        }

        public static string ToWireValue(this MediaBias bias) => bias switch
        {
            MediaBias.Left => "left",
            MediaBias.LeanLeft => "lean_left",
            MediaBias.Center => "center",
            MediaBias.LeanRight => "lean_right",
            MediaBias.Right => "right",
            MediaBias.Independent => "independent",
            _ => "unrated"
        };

        public static string DisplayLabel(this MediaBias bias) => bias switch
        {
            MediaBias.Left => "Left",
            MediaBias.LeanLeft => "Lean Left",
            MediaBias.Center => "Center",
            MediaBias.LeanRight => "Lean Right",
            MediaBias.Right => "Right",
            MediaBias.Independent => "Independent",
            _ => "Unrated"
        };

        public static string ShortBadge(this MediaBias bias) => bias switch
        {
            MediaBias.Left => "L",
            MediaBias.LeanLeft => "LL",
            MediaBias.Center => "C",
            MediaBias.LeanRight => "LR",
            MediaBias.Right => "R",
            MediaBias.Independent => "IND",
            _ => "—"
        };

        public static string MacroSide(this MediaBias bias) => bias switch
        {
            MediaBias.Left or MediaBias.LeanLeft => "left",
            MediaBias.Center => "center",
            MediaBias.LeanRight or MediaBias.Right => "right",
            _ => "other"
        };

        public static int SortOrder(this MediaBias bias) => bias switch
        {
            MediaBias.Left => 0,
            MediaBias.LeanLeft => 1,
            MediaBias.Center => 2,
            MediaBias.LeanRight => 3,
            MediaBias.Right => 4,
            MediaBias.Independent => 5,
            _ => 6
        };
    }

    public enum FactualityTier
    {
        VeryHigh,
        High,
        MostlyFactual,
        Mixed,
        Low
    }

    public static class FactualityTierExtensions
    {
        public static FactualityTier Parse(string? raw)
        {
            return (raw ?? string.Empty).Trim().ToLowerInvariant() switch
            {
                "very_high" or "veryhigh" => FactualityTier.VeryHigh,
                "high" => FactualityTier.High,
                "mostly_factual" or "mostlyfactual" => FactualityTier.MostlyFactual,
                "low" => FactualityTier.Low,
                _ => FactualityTier.Mixed
            };
        }

        public static string ToWireValue(this FactualityTier tier) => tier switch
        {
            FactualityTier.VeryHigh => "very_high",
            FactualityTier.High => "high",
            FactualityTier.MostlyFactual => "mostly_factual",
            FactualityTier.Mixed => "mixed",
            FactualityTier.Low => "low",
            _ => "mixed"
        };

        public static string DisplayLabel(this FactualityTier tier) => tier switch
        {
            FactualityTier.VeryHigh => "Very High",
            FactualityTier.High => "High",
            FactualityTier.MostlyFactual => "Mostly Factual",
            FactualityTier.Mixed => "Mixed",
            FactualityTier.Low => "Low",
            _ => "Mixed"
        };

        public static string ShortLabel(this FactualityTier tier) => tier switch
        {
            FactualityTier.VeryHigh => "V.High",
            FactualityTier.High => "High",
            FactualityTier.MostlyFactual => "Mostly",
            FactualityTier.Mixed => "Mixed",
            FactualityTier.Low => "Low",
            _ => "Mixed"
        };
    }

    public enum OwnershipCategory
    {
        IndependentCreator,
        NonprofitTrust,
        PublicMedia,
        PrivateFamily,
        PubliclyTraded,
        BillionaireIndividual,
        PrivateEquity,
        CorporateConglomerate,
        StateAffiliated
    }

    public static class OwnershipCategoryExtensions
    {
        public static OwnershipCategory Parse(string? raw)
        {
            return (raw ?? string.Empty).Trim().ToLowerInvariant() switch
            {
                "independent_creator" => OwnershipCategory.IndependentCreator,
                "nonprofit_trust" => OwnershipCategory.NonprofitTrust,
                "public_media" => OwnershipCategory.PublicMedia,
                "private_family" => OwnershipCategory.PrivateFamily,
                "publicly_traded" => OwnershipCategory.PubliclyTraded,
                "billionaire_individual" => OwnershipCategory.BillionaireIndividual,
                "private_equity" => OwnershipCategory.PrivateEquity,
                "state_affiliated" => OwnershipCategory.StateAffiliated,
                _ => OwnershipCategory.CorporateConglomerate
            };
        }

        public static string DisplayLabel(this OwnershipCategory cat) => cat switch
        {
            OwnershipCategory.IndependentCreator => "Independent Creator",
            OwnershipCategory.NonprofitTrust => "Non-Profit / Trust",
            OwnershipCategory.PublicMedia => "Public Service Media",
            OwnershipCategory.PrivateFamily => "Private / Family Owned",
            OwnershipCategory.PubliclyTraded => "Publicly Traded Company",
            OwnershipCategory.BillionaireIndividual => "Individual / Principal Owner",
            OwnershipCategory.PrivateEquity => "Private Equity / Fund",
            OwnershipCategory.CorporateConglomerate => "Media Conglomerate",
            OwnershipCategory.StateAffiliated => "State-Affiliated Media",
            _ => "Media Organization"
        };
    }

    public enum ArticleFramingTag
    {
        StraightReporting,
        Opinion,
        Analysis,
        Investigative,
        Sensational
    }

    public static class ArticleFramingTagExtensions
    {
        public static string DisplayLabel(this ArticleFramingTag tag) => tag switch
        {
            ArticleFramingTag.StraightReporting => "Reporting",
            ArticleFramingTag.Opinion => "Opinion",
            ArticleFramingTag.Analysis => "Analysis",
            ArticleFramingTag.Investigative => "Investigation",
            ArticleFramingTag.Sensational => "Sensational",
            _ => "Reporting"
        };
    }

    public enum BlindspotType
    {
        LeftBlindspot,   // Minimal coverage on Left (<12%), heavy on Right (>55%)
        RightBlindspot   // Minimal coverage on Right (<12%), heavy on Left (>55%)
    }

    public static class BlindspotTypeExtensions
    {
        public static string BadgeTitle(this BlindspotType type) => type switch
        {
            BlindspotType.LeftBlindspot => "Left Blindspot",
            BlindspotType.RightBlindspot => "Right Blindspot",
            _ => "Blindspot"
        };

        public static string Explanation(this BlindspotType type) => type switch
        {
            BlindspotType.LeftBlindspot => "Low or no coverage from left-leaning publications compared to right-leaning outlets.",
            BlindspotType.RightBlindspot => "Low or no coverage from right-leaning publications compared to left-leaning outlets.",
            _ => string.Empty
        };
    }

    public sealed class SeedOutletEntryDto
    {
        [JsonPropertyName("domain")]
        public string Domain { get; set; } = string.Empty;

        [JsonPropertyName("displayName")]
        public string DisplayName { get; set; } = string.Empty;

        [JsonPropertyName("countryCode")]
        public string CountryCode { get; set; } = "INT";

        [JsonPropertyName("languageCode")]
        public string LanguageCode { get; set; } = "en";

        [JsonPropertyName("bias")]
        public string Bias { get; set; } = "unrated";

        [JsonPropertyName("biasScore")]
        public double BiasScore { get; set; }

        [JsonPropertyName("biasContext")]
        public string? BiasContext { get; set; }

        [JsonPropertyName("factuality")]
        public string Factuality { get; set; } = "mixed";

        [JsonPropertyName("factualityScore")]
        public int FactualityScore { get; set; } = 60;

        [JsonPropertyName("ownerName")]
        public string OwnerName { get; set; } = "Unverified Publisher";

        [JsonPropertyName("ownershipType")]
        public string OwnershipType { get; set; } = "corporate_conglomerate";

        [JsonPropertyName("fundingSummary")]
        public string FundingSummary { get; set; } = string.Empty;
    }

    public sealed class MediaOutletProfile
    {
        public string Domain { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
        public string CountryCode { get; init; } = "INT";
        public string LanguageCode { get; init; } = "en";
        public MediaBias Bias { get; init; } = MediaBias.Unrated;
        public double BiasScore { get; init; }
        public string? BiasContext { get; init; }
        public FactualityTier Factuality { get; init; } = FactualityTier.Mixed;
        public int FactualityScore { get; init; } = 60;
        public string OwnerName { get; init; } = "Unverified Publisher";
        public OwnershipCategory OwnershipType { get; init; } = OwnershipCategory.CorporateConglomerate;
        public string FundingSummary { get; init; } = string.Empty;
        public bool IsVerified { get; init; } = true;

        public string CompactCardBadge =>
            !IsVerified && Bias == MediaBias.Unrated
                ? string.Empty
                : $"{Bias.ShortBadge()} · {Factuality.ShortLabel()}";
    }

    public sealed class ClusterSibling
    {
        public string Title { get; init; } = string.Empty;
        public string Url { get; init; } = string.Empty;
        public string PublisherName { get; init; } = string.Empty;
        public string? PublisherDomain { get; init; }
        public DateTime? PublishedAt { get; init; }
    }

    public sealed class BiasDistribution
    {
        public int LeftCount { get; init; }
        public int LeanLeftCount { get; init; }
        public int CenterCount { get; init; }
        public int LeanRightCount { get; init; }
        public int RightCount { get; init; }
        public int IndependentCount { get; init; }
        public int UnratedCount { get; init; }

        public int LeftWingTotal => LeftCount + LeanLeftCount;
        public int RightWingTotal => LeanRightCount + RightCount;
        public int RatedSpectrumTotal => LeftWingTotal + CenterCount + RightWingTotal;
        public int TotalSources => RatedSpectrumTotal + IndependentCount + UnratedCount;

        public double LeftRatio => RatedSpectrumTotal > 0 ? (double)LeftWingTotal / RatedSpectrumTotal : 0.0;
        public double CenterRatio => RatedSpectrumTotal > 0 ? (double)CenterCount / RatedSpectrumTotal : 0.0;
        public double RightRatio => RatedSpectrumTotal > 0 ? (double)RightWingTotal / RatedSpectrumTotal : 0.0;

        public int LeftPercent => (int)Math.Round(LeftRatio * 100.0);
        public int CenterPercent => RatedSpectrumTotal > 0 ? Math.Max(0, 100 - LeftPercent - RightPercent) : 0;
        public int RightPercent => (int)Math.Round(RightRatio * 100.0);

        public string SummaryLabel =>
            RatedSpectrumTotal == 0
                ? $"{TotalSources} sources"
                : $"L {LeftPercent}% · C {CenterPercent}% · R {RightPercent}%";
    }

    public sealed class ClusterCoverageItem
    {
        public string Id { get; init; } = string.Empty;
        public RssItem Article { get; init; } = new();
        public MediaOutletProfile Outlet { get; init; } = new();
        public ArticleFramingTag Framing { get; init; } = ArticleFramingTag.StraightReporting;
        public bool IsFromSubscription { get; init; }
    }

    public sealed class StoryCluster
    {
        public string Id { get; init; } = string.Empty;
        public string CanonicalTitle { get; init; } = string.Empty;
        public DateTime LatestPublishedAt { get; init; }
        public string? HeroImageUrl { get; init; }
        public RssItem LeadArticle { get; init; } = new();
        public List<ClusterCoverageItem> Coverage { get; init; } = new();
        public BiasDistribution Distribution { get; init; } = new();
        public BlindspotType? Blindspot { get; init; }
        public List<string> SharedEntities { get; init; } = new();
        public bool IsExpandedExternal { get; init; }

        public int UniqueOutletCount { get; init; }
        public bool HasMultipleSources => UniqueOutletCount >= 2;
        public bool IsBlindspot => Blindspot.HasValue;
    }

    public sealed class FramingDifferenceItem
    {
        [JsonPropertyName("side")]
        public string Side { get; set; } = string.Empty;

        [JsonPropertyName("emphasis")]
        public string Emphasis { get; set; } = string.Empty;

        [JsonPropertyName("toneNote")]
        public string ToneNote { get; set; } = string.Empty;
    }

    public sealed class PerspectiveComparison
    {
        [JsonPropertyName("clusterHash")]
        public string ClusterHash { get; set; } = string.Empty;

        [JsonPropertyName("sharedFacts")]
        public List<string> SharedFacts { get; set; } = new();

        [JsonPropertyName("framingDifferences")]
        public List<FramingDifferenceItem> FramingDifferences { get; set; } = new();

        [JsonPropertyName("omissionsNote")]
        public string? OmissionsNote { get; set; }

        [JsonPropertyName("engineBadge")]
        public string EngineBadge { get; set; } = "Deterministic Lens";

        [JsonPropertyName("generatedAt")]
        public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    }

    public sealed class MediaDietSnapshot
    {
        public string PeriodMonth { get; set; } = string.Empty; // "YYYY-MM"
        public int LeftCount { get; set; }
        public int LeanLeftCount { get; set; }
        public int CenterCount { get; set; }
        public int LeanRightCount { get; set; }
        public int RightCount { get; set; }
        public int IndependentCount { get; set; }
        public int UnratedCount { get; set; }
        public int HighFactualityCount { get; set; }
        public int TotalArticlesCount { get; set; }

        public BiasDistribution Distribution => new()
        {
            LeftCount = LeftCount,
            LeanLeftCount = LeanLeftCount,
            CenterCount = CenterCount,
            LeanRightCount = LeanRightCount,
            RightCount = RightCount,
            IndependentCount = IndependentCount,
            UnratedCount = UnratedCount
        };

        public int HighFactualityPercent =>
            TotalArticlesCount > 0
                ? (int)Math.Round((double)HighFactualityCount / TotalArticlesCount * 100.0)
                : 0;

        public string? BlindspotRecommendation
        {
            get
            {
                var dist = Distribution;
                if (dist.RatedSpectrumTotal < 4) return null;
                if (dist.LeftRatio > 0.65 && dist.RightRatio < 0.12)
                    return "Your recent reading leans Left/Center. Explore Perspectives to compare Lean Right & Right coverage.";
                if (dist.RightRatio > 0.65 && dist.LeftRatio < 0.12)
                    return "Your recent reading leans Right/Center. Explore Perspectives to compare Lean Left & Left coverage.";
                return "Balanced media diet across multiple editorial perspectives.";
            }
        }
    }

    // ── Supabase Lightweight Remote Tables (Strict Storage & Egress Guardrails) ──

    [Table("media_outlet_profiles")]
    public class RemoteMediaOutletProfileRow : BaseModel
    {
        [PrimaryKey("domain", false)]
        [Column("domain")]
        public string Domain { get; set; } = string.Empty;

        [Column("display_name")]
        public string DisplayName { get; set; } = string.Empty;

        [Column("country_code")]
        public string CountryCode { get; set; } = "INT";

        [Column("language_code")]
        public string LanguageCode { get; set; } = "en";

        [Column("bias_rating")]
        public string BiasRating { get; set; } = "unrated";

        [Column("bias_score")]
        public double BiasScore { get; set; }

        [Column("bias_context")]
        public string? BiasContext { get; set; }

        [Column("factuality_rating")]
        public string FactualityRating { get; set; } = "mixed";

        [Column("factuality_score")]
        public int FactualityScore { get; set; } = 60;

        [Column("owner_name")]
        public string OwnerName { get; set; } = "Unverified Publisher";

        [Column("ownership_type")]
        public string OwnershipType { get; set; } = "corporate_conglomerate";

        [Column("funding_summary")]
        public string FundingSummary { get; set; } = string.Empty;

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }
    }

    [Table("news_perspective_cache")]
    public class RemotePerspectiveCacheRow : BaseModel
    {
        [PrimaryKey("cluster_hash", false)]
        [Column("cluster_hash")]
        public string ClusterHash { get; set; } = string.Empty;

        [Column("language_code")]
        public string LanguageCode { get; set; } = "en";

        [Column("source_count")]
        public int SourceCount { get; set; }

        [Column("comparison_json")]
        public string ComparisonJson { get; set; } = "{}";

        [Column("expires_at")]
        public DateTime ExpiresAt { get; set; }
    }

    [Table("news_reading_stats")]
    public class RemoteNewsReadingStatsRow : BaseModel
    {
        [PrimaryKey("user_id", false)]
        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("period_month")]
        public string PeriodMonth { get; set; } = string.Empty;

        [Column("left_count")]
        public int LeftCount { get; set; }

        [Column("lean_left_count")]
        public int LeanLeftCount { get; set; }

        [Column("center_count")]
        public int CenterCount { get; set; }

        [Column("lean_right_count")]
        public int LeanRightCount { get; set; }

        [Column("right_count")]
        public int RightCount { get; set; }

        [Column("independent_count")]
        public int IndependentCount { get; set; }

        [Column("unrated_count")]
        public int UnratedCount { get; set; }

        [Column("high_factuality_count")]
        public int HighFactualityCount { get; set; }

        [Column("total_articles_count")]
        public int TotalArticlesCount { get; set; }

        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
