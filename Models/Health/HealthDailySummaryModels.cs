using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using Newtonsoft.Json;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models.Health
{
    /// <summary>
    /// Canonical Health & Vitals daily summary record mapping 1:1 with Supabase public.health_daily_summary table (version 1).
    /// </summary>
    [Table("health_daily_summary")]
    public class HealthDailySummaryRecord : BaseModel
    {

        [PrimaryKey("id")]
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        [JsonProperty("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("local_date")]
        [JsonPropertyName("local_date")]
        [JsonProperty("local_date")]
        public string LocalDate { get; set; } = string.Empty; // "yyyy-MM-dd"

        [Column("computed_at")]
        [JsonPropertyName("computed_at")]
        [JsonProperty("computed_at")]
        public string? ComputedAt { get; set; }

        [Column("engine_version")]
        [JsonPropertyName("engine_version")]
        [JsonProperty("engine_version")]
        public string EngineVersion { get; set; } = "1.0";

        [Column("raw_watermark")]
        [JsonPropertyName("raw_watermark")]
        [JsonProperty("raw_watermark")]
        public string? RawWatermark { get; set; }

        [Column("steps")]
        [JsonPropertyName("steps")]
        [JsonProperty("steps")]
        public int? Steps { get; set; }

        [Column("active_kcal")]
        [JsonPropertyName("active_kcal")]
        [JsonProperty("active_kcal")]
        public double? ActiveKcal { get; set; }

        [Column("sleep_asleep_s")]
        [JsonPropertyName("sleep_asleep_s")]
        [JsonProperty("sleep_asleep_s")]
        public int? SleepAsleepS { get; set; }

        [Column("sleep_score")]
        [JsonPropertyName("sleep_score")]
        [JsonProperty("sleep_score")]
        public int? SleepScore { get; set; }

        [Column("stress_avg")]
        [JsonPropertyName("stress_avg")]
        [JsonProperty("stress_avg")]
        public int? StressAvg { get; set; }

        [Column("rhr")]
        [JsonPropertyName("rhr")]
        [JsonProperty("rhr")]
        public double? Rhr { get; set; }

        [Column("hrv_sdnn")]
        [JsonPropertyName("hrv_sdnn")]
        [JsonProperty("hrv_sdnn")]
        public double? HrvSdnn { get; set; }

        [Column("hrv_rmssd")]
        [JsonPropertyName("hrv_rmssd")]
        [JsonProperty("hrv_rmssd")]
        public double? HrvRmssd { get; set; }

        [Column("weight")]
        [JsonPropertyName("weight")]
        [JsonProperty("weight")]
        public double? Weight { get; set; }

        [Column("spo2")]
        [JsonPropertyName("spo2")]
        [JsonProperty("spo2")]
        public double? Spo2 { get; set; }

        [Column("summary")]
        [JsonPropertyName("summary")]
        [JsonProperty("summary")]
        public DailyHealthSummaryPayload? Summary { get; set; }
    }

    public class DailyHealthSummaryPayload
    {
        [JsonPropertyName("date")]
        [JsonProperty("date")]
        public string Date { get; set; } = string.Empty;

        [JsonPropertyName("computed_at")]
        [JsonProperty("computed_at")]
        public string? ComputedAt { get; set; }

        [JsonPropertyName("sources")]
        [JsonProperty("sources")]
        public List<string> Sources { get; set; } = new();

        [JsonPropertyName("sleep")]
        [JsonProperty("sleep")]
        public CanonicalSleepSummary? Sleep { get; set; }

        [JsonPropertyName("activity")]
        [JsonProperty("activity")]
        public CanonicalActivitySummary? Activity { get; set; }

        [JsonPropertyName("cardiovascular")]
        [JsonProperty("cardiovascular")]
        public CanonicalCardiovascularSummary? Cardiovascular { get; set; }

        [JsonPropertyName("stress")]
        [JsonProperty("stress")]
        public CanonicalStressSummary? Stress { get; set; }

        [JsonPropertyName("vitals")]
        [JsonProperty("vitals")]
        public Dictionary<string, CanonicalVitalSummaryItem> Vitals { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    }

    public class CanonicalSleepSummary
    {
        [JsonPropertyName("primary_session")]
        [JsonProperty("primary_session")]
        public CanonicalSleepSession? PrimarySession { get; set; }

        [JsonPropertyName("all_sessions")]
        [JsonProperty("all_sessions")]
        public List<CanonicalSleepSession> AllSessions { get; set; } = new();

        [JsonPropertyName("naps")]
        [JsonProperty("naps")]
        public List<NapSession> Naps { get; set; } = new();

        [JsonPropertyName("guidance")]
        [JsonProperty("guidance")]
        public CanonicalSleepGuidance? Guidance { get; set; }

        [JsonPropertyName("tracker_priority_order")]
        [JsonProperty("tracker_priority_order")]
        public List<string> TrackerPriorityOrder { get; set; } = new();
    }

    public class CanonicalSleepSession
    {
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [JsonPropertyName("is_nap")]
        [JsonProperty("is_nap")]
        public bool IsNap { get; set; }

        [JsonPropertyName("start_time")]
        [JsonProperty("start_time")]
        public string StartTime { get; set; } = string.Empty;

        [JsonPropertyName("end_time")]
        [JsonProperty("end_time")]
        public string EndTime { get; set; } = string.Empty;

        [JsonPropertyName("duration_seconds")]
        [JsonProperty("duration_seconds")]
        public int DurationSeconds { get; set; }

        [JsonPropertyName("asleep_seconds")]
        [JsonProperty("asleep_seconds")]
        public int AsleepSeconds { get; set; }

        [JsonPropertyName("deep_seconds")]
        [JsonProperty("deep_seconds")]
        public int DeepSeconds { get; set; }

        [JsonPropertyName("deep_percent")]
        [JsonProperty("deep_percent")]
        public int DeepPercent { get; set; }

        [JsonPropertyName("rem_seconds")]
        [JsonProperty("rem_seconds")]
        public int RemSeconds { get; set; }

        [JsonPropertyName("rem_percent")]
        [JsonProperty("rem_percent")]
        public int RemPercent { get; set; }

        [JsonPropertyName("light_seconds")]
        [JsonProperty("light_seconds")]
        public int LightSeconds { get; set; }

        [JsonPropertyName("light_percent")]
        [JsonProperty("light_percent")]
        public int LightPercent { get; set; }

        [JsonPropertyName("awake_seconds")]
        [JsonProperty("awake_seconds")]
        public int AwakeSeconds { get; set; }

        [JsonPropertyName("awake_percent")]
        [JsonProperty("awake_percent")]
        public int AwakePercent { get; set; }

        [JsonPropertyName("awake_count")]
        [JsonProperty("awake_count")]
        public int AwakeCount { get; set; }

        [JsonPropertyName("efficiency_percent")]
        [JsonProperty("efficiency_percent")]
        public int EfficiencyPercent { get; set; }

        [JsonPropertyName("sleep_score")]
        [JsonProperty("sleep_score")]
        public int SleepScore { get; set; }

        [JsonPropertyName("quality_rating")]
        [JsonProperty("quality_rating")]
        public string? QualityRating { get; set; }

        [JsonPropertyName("restorative_percent")]
        [JsonProperty("restorative_percent")]
        public int RestorativePercent { get; set; }

        [JsonPropertyName("has_granular_hypnogram")]
        [JsonProperty("has_granular_hypnogram")]
        public bool HasGranularHypnogram { get; set; } = true;

        [JsonPropertyName("tracker")]
        [JsonProperty("tracker")]
        public string? Tracker { get; set; }

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public string EffectiveSourceDevice => !string.IsNullOrEmpty(SourceDevice) ? SourceDevice : (Tracker ?? "Canonical");

        [JsonPropertyName("stages")]
        [JsonProperty("stages")]
        public List<SleepStageRecord> Stages { get; set; } = new();
    }

    public class SleepStageRecord
    {
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [JsonPropertyName("stage")]
        [JsonProperty("stage")]
        public string? StageRaw { get; set; }

        [JsonPropertyName("stage_type")]
        [JsonProperty("stage_type")]
        public string? StageTypeRaw { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public string Stage
        {
            get => !string.IsNullOrEmpty(StageTypeRaw) ? StageTypeRaw : (StageRaw ?? string.Empty);
            set => StageTypeRaw = value;
        }

        [JsonPropertyName("start_time")]
        [JsonProperty("start_time")]
        public string StartTime { get; set; } = string.Empty;

        [JsonPropertyName("end_time")]
        [JsonProperty("end_time")]
        public string EndTime { get; set; } = string.Empty;

        [JsonPropertyName("duration_seconds")]
        [JsonProperty("duration_seconds")]
        public int DurationSeconds { get; set; }

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }
    }

    public class NapSession
    {
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [JsonPropertyName("start_time")]
        [JsonProperty("start_time")]
        public string StartTime { get; set; } = string.Empty;

        [JsonPropertyName("end_time")]
        [JsonProperty("end_time")]
        public string EndTime { get; set; } = string.Empty;

        [JsonPropertyName("duration_seconds")]
        [JsonProperty("duration_seconds")]
        public int DurationSeconds { get; set; }

        [JsonPropertyName("tracker")]
        [JsonProperty("tracker")]
        public string? Tracker { get; set; }

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }
    }

    public class CanonicalSleepGuidance
    {
        [JsonPropertyName("verdict")]
        [JsonProperty("verdict")]
        public CanonicalSleepVerdict? Verdict { get; set; }

        [JsonPropertyName("tips")]
        [JsonProperty("tips")]
        public List<CanonicalSleepTip> Tips { get; set; } = new();

        [JsonPropertyName("ai_context")]
        [JsonProperty("ai_context")]
        public CanonicalSleepAIContext? AiContext { get; set; }
    }

    public class CanonicalSleepVerdict
    {
        [JsonPropertyName("status")]
        [JsonProperty("status")]
        public string Status { get; set; } = "fair"; // "optimal", "great", "fair", "deficit"

        [JsonPropertyName("headline")]
        [JsonProperty("headline")]
        public string Headline { get; set; } = string.Empty;

        [JsonPropertyName("narrative")]
        [JsonProperty("narrative")]
        public string Narrative { get; set; } = string.Empty;

        [JsonPropertyName("readiness_score")]
        [JsonProperty("readiness_score")]
        public int ReadinessScore { get; set; }

        [JsonPropertyName("physical_repair_rating")]
        [JsonProperty("physical_repair_rating")]
        public string PhysicalRepairRating { get; set; } = "Normal";

        [JsonPropertyName("cognitive_restore_rating")]
        [JsonProperty("cognitive_restore_rating")]
        public string CognitiveRestoreRating { get; set; } = "Normal";

        [JsonPropertyName("sleep_continuity_rating")]
        [JsonProperty("sleep_continuity_rating")]
        public string SleepContinuityRating { get; set; } = "Good";
    }

    public class CanonicalSleepTip
    {
        [JsonPropertyName("category")]
        [JsonProperty("category")]
        public string Category { get; set; } = "wind_down";

        [JsonPropertyName("title")]
        [JsonProperty("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("advice")]
        [JsonProperty("advice")]
        public string Advice { get; set; } = string.Empty;

        [JsonPropertyName("scientific_rationale")]
        [JsonProperty("scientific_rationale")]
        public string ScientificRationale { get; set; } = string.Empty;
    }

    public class CanonicalSleepAIContext
    {
        [JsonPropertyName("narrative_synthesis")]
        [JsonProperty("narrative_synthesis")]
        public string NarrativeSynthesis { get; set; } = string.Empty;

        [JsonPropertyName("suggested_prompts")]
        [JsonProperty("suggested_prompts")]
        public List<string> SuggestedPrompts { get; set; } = new();
    }

    public class CanonicalActivitySummary
    {
        [JsonPropertyName("total_steps")]
        [JsonProperty("total_steps")]
        public int TotalSteps { get; set; }

        [JsonPropertyName("active_calories_kcal")]
        [JsonProperty("active_calories_kcal")]
        public double ActiveCaloriesKcal { get; set; }

        [JsonPropertyName("hourly_steps")]
        [JsonProperty("hourly_steps")]
        public List<HourlyStepBucket> HourlySteps { get; set; } = new();

        [JsonPropertyName("tracker_priority_order")]
        [JsonProperty("tracker_priority_order")]
        public List<string> TrackerPriorityOrder { get; set; } = new();
    }

    public class HourlyStepBucket
    {
        [JsonPropertyName("hour")]
        [JsonProperty("hour")]
        public int Hour { get; set; }

        [JsonPropertyName("steps")]
        [JsonProperty("steps")]
        public int Steps { get; set; }

        [JsonPropertyName("active_calories")]
        [JsonProperty("active_calories")]
        public double ActiveCalories { get; set; }
    }

    public class CanonicalCardiovascularSummary
    {
        [JsonPropertyName("intraday_heart_rate")]
        [JsonProperty("intraday_heart_rate")]
        public List<IntradayHeartRatePoint> IntradayHeartRate { get; set; } = new();

        [JsonPropertyName("resting_heart_rate_bpm")]
        [JsonProperty("resting_heart_rate_bpm")]
        public double? RestingHeartRateBpm { get; set; }

        [JsonPropertyName("average_heart_rate_bpm")]
        [JsonProperty("average_heart_rate_bpm")]
        public double? AverageHeartRateBpm { get; set; }

        [JsonPropertyName("max_heart_rate_bpm")]
        [JsonProperty("max_heart_rate_bpm")]
        public double? MaxHeartRateBpm { get; set; }

        [JsonPropertyName("min_heart_rate_bpm")]
        [JsonProperty("min_heart_rate_bpm")]
        public double? MinHeartRateBpm { get; set; }

        [JsonPropertyName("heart_rate_zones")]
        [JsonProperty("heart_rate_zones")]
        public CanonicalHeartRateZones? HeartRateZones { get; set; }
    }

    public class IntradayHeartRatePoint
    {
        [JsonPropertyName("timestamp")]
        [JsonProperty("timestamp")]
        public string Timestamp { get; set; } = string.Empty;

        [JsonPropertyName("bpm")]
        [JsonProperty("bpm")]
        public double Bpm { get; set; }
    }

    public class CanonicalHeartRateZones
    {
        [JsonPropertyName("resting_minutes")]
        [JsonProperty("resting_minutes")]
        public int RestingMinutes { get; set; }

        [JsonPropertyName("fat_burn_minutes")]
        [JsonProperty("fat_burn_minutes")]
        public int FatBurnMinutes { get; set; }

        [JsonPropertyName("cardio_minutes")]
        [JsonProperty("cardio_minutes")]
        public int CardioMinutes { get; set; }

        [JsonPropertyName("peak_minutes")]
        [JsonProperty("peak_minutes")]
        public int PeakMinutes { get; set; }
    }

    public class CanonicalStressSummary
    {
        [JsonPropertyName("daily_average_score")]
        [JsonProperty("daily_average_score")]
        public int DailyAverageScore { get; set; }

        [JsonPropertyName("current_score")]
        [JsonProperty("current_score")]
        public int CurrentScore { get; set; }

        [JsonPropertyName("current_level")]
        [JsonProperty("current_level")]
        public string CurrentLevel { get; set; } = "calm"; // "restful", "calm", "moderate", "high"

        [JsonPropertyName("autonomic_balance")]
        [JsonProperty("autonomic_balance")]
        public CanonicalAutonomicBalance? AutonomicBalance { get; set; }

        [JsonPropertyName("biometric_drivers")]
        [JsonProperty("biometric_drivers")]
        public CanonicalStressDrivers? BiometricDrivers { get; set; }

        [JsonPropertyName("monkey_mood")]
        [JsonProperty("monkey_mood")]
        public string? MonkeyMood { get; set; } // "zen", "curious", "busy", "overheated"

        [JsonPropertyName("intraday_stress")]
        [JsonProperty("intraday_stress")]
        public List<IntradayStressPoint> IntradayStress { get; set; } = new();
    }

    public class CanonicalAutonomicBalance
    {
        [JsonPropertyName("sympathetic_percent")]
        [JsonProperty("sympathetic_percent")]
        public int SympatheticPercent { get; set; } = 50;

        [JsonPropertyName("parasympathetic_percent")]
        [JsonProperty("parasympathetic_percent")]
        public int ParasympatheticPercent { get; set; } = 50;
    }

    public class CanonicalStressDrivers
    {
        [JsonPropertyName("baseline_hrv_ms")]
        [JsonProperty("baseline_hrv_ms")]
        public double BaselineHrvMs { get; set; } = 45.0;

        [JsonPropertyName("current_hrv_ms")]
        [JsonProperty("current_hrv_ms")]
        public double? CurrentHrvMs { get; set; }

        [JsonPropertyName("resting_heart_rate_bpm")]
        [JsonProperty("resting_heart_rate_bpm")]
        public double? RestingHeartRateBpm { get; set; }

        [JsonPropertyName("current_sedentary_bpm")]
        [JsonProperty("current_sedentary_bpm")]
        public double? CurrentSedentaryBpm { get; set; }
    }

    public class IntradayStressPoint
    {
        [JsonPropertyName("timestamp")]
        [JsonProperty("timestamp")]
        public string Timestamp { get; set; } = string.Empty;

        [JsonPropertyName("stress_score")]
        [JsonProperty("stress_score")]
        public int StressScore { get; set; }

        [JsonPropertyName("level")]
        [JsonProperty("level")]
        public string Level { get; set; } = "calm";
    }

    public class CanonicalVitalSummaryItem
    {
        [JsonPropertyName("value")]
        [JsonProperty("value")]
        public double Value { get; set; }

        [JsonPropertyName("unit")]
        [JsonProperty("unit")]
        public string? Unit { get; set; }

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }

        [JsonPropertyName("age_label")]
        [JsonProperty("age_label")]
        public string? AgeLabel { get; set; }

        [JsonPropertyName("timestamp")]
        [JsonProperty("timestamp")]
        public string? Timestamp { get; set; }
    }

    /// <summary>
    /// Local SQLite table entity for caching daily summaries offline (<300ms launch).
    /// </summary>
    [SQLite.Table("health_daily_summary_cache")]
    public class HealthDailySummaryEntity
    {
        [SQLite.PrimaryKey]
        public string LocalDate { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string? ComputedAt { get; set; }
        public string EngineVersion { get; set; } = "1.0";
        public int? Steps { get; set; }
        public double? ActiveKcal { get; set; }
        public int? SleepAsleepS { get; set; }
        public int? SleepScore { get; set; }
        public int? StressAvg { get; set; }
        public double? Rhr { get; set; }
        public double? HrvSdnn { get; set; }
        public double? HrvRmssd { get; set; }
        public double? Weight { get; set; }
        public double? Spo2 { get; set; }
        public string? SummaryJson { get; set; }
        public long UpdatedAtTimestamp { get; set; }
    }

    /// <summary>
    /// Optimized JSON serializer/deserializer handling both System.Text.Json and Postgrest BaseModel fields.
    /// </summary>
    public static class HealthJsonSerializer
    {
        public static readonly JsonSerializerOptions DefaultOptions = CreateOptions();

        private static JsonSerializerOptions CreateOptions()
        {
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
                TypeInfoResolver = new DefaultJsonTypeInfoResolver
                {
                    Modifiers =
                    {
                        ti =>
                        {
                            if (typeof(BaseModel).IsAssignableFrom(ti.Type))
                            {
                                foreach (var prop in ti.Properties)
                                {
                                    if (prop.Name == nameof(BaseModel.PrimaryKey) ||
                                        prop.Name == nameof(BaseModel.BaseUrl) ||
                                        prop.Name == nameof(BaseModel.RequestClientOptions) ||
                                        prop.Name == nameof(BaseModel.TableName))
                                    {
                                        prop.ShouldSerialize = (_, _) => false;
                                    }
                                }
                            }
                        }
                    }
                }
            };
            return options;
        }

        public static string Serialize<T>(T value, bool indented = false)
        {
            if (indented)
            {
                var opts = new JsonSerializerOptions(DefaultOptions) { WriteIndented = true };
                return System.Text.Json.JsonSerializer.Serialize(value, opts);
            }
            return System.Text.Json.JsonSerializer.Serialize(value, DefaultOptions);
        }

        public static T? Deserialize<T>(string json)
        {
            return System.Text.Json.JsonSerializer.Deserialize<T>(json, DefaultOptions);
        }
    }
}
