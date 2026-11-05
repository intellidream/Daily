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

        [JsonPropertyName("all_devices_view")]
        [JsonProperty("all_devices_view")]
        public Dictionary<string, CanonicalAllDevicesMetricItem>? AllDevicesView { get; set; }

        [JsonPropertyName("sources_breakdown")]
        [JsonProperty("sources_breakdown")]
        public Dictionary<string, Dictionary<string, double>>? SourcesBreakdown { get; set; }
    }

    public class CanonicalAllDevicesMetricItem
    {
        [JsonPropertyName("value")]
        [JsonProperty("value")]
        public double? Value { get; set; }

        [JsonPropertyName("unit")]
        [JsonProperty("unit")]
        public string? Unit { get; set; }

        [JsonPropertyName("source_key")]
        [JsonProperty("source_key")]
        public string? SourceKey { get; set; }
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
        public string EffectiveSourceDevice
        {
            get
            {
                var raw = !string.IsNullOrEmpty(SourceDevice) ? SourceDevice : Tracker;
                var src = DeviceSource.From(raw);
                return src.IsVirtualEngine ? string.Empty : src.DisplayName;
            }
        }

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
        public double ActiveCaloriesKcalRaw { get; set; }

        [JsonPropertyName("active_calories")]
        [JsonProperty("active_calories")]
        public double ActiveCaloriesV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public double ActiveCaloriesKcal
        {
            get => ActiveCaloriesV2 > 0 ? ActiveCaloriesV2 : ActiveCaloriesKcalRaw;
            set { ActiveCaloriesV2 = value; ActiveCaloriesKcalRaw = value; }
        }

        [JsonPropertyName("hourly_steps")]
        [JsonProperty("hourly_steps")]
        public List<HourlyStepBucket> HourlySteps { get; set; } = new();

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }

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
        public List<IntradayHeartRatePoint>? IntradayHeartRateRaw { get; set; }

        [JsonPropertyName("intraday_points")]
        [JsonProperty("intraday_points")]
        public List<IntradayHeartRatePoint>? IntradayPointsV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public List<IntradayHeartRatePoint> IntradayHeartRate
        {
            get => (IntradayPointsV2 != null && IntradayPointsV2.Count > 0) ? IntradayPointsV2 : (IntradayHeartRateRaw ?? new());
            set { IntradayPointsV2 = value; IntradayHeartRateRaw = value; }
        }

        [JsonPropertyName("resting_heart_rate_bpm")]
        [JsonProperty("resting_heart_rate_bpm")]
        public double? RestingHeartRateBpmRaw { get; set; }

        [JsonPropertyName("resting_bpm")]
        [JsonProperty("resting_bpm")]
        public double? RestingBpmV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public double? RestingHeartRateBpm
        {
            get => RestingBpmV2 ?? RestingHeartRateBpmRaw;
            set { RestingBpmV2 = value; RestingHeartRateBpmRaw = value; }
        }

        [JsonPropertyName("average_heart_rate_bpm")]
        [JsonProperty("average_heart_rate_bpm")]
        public double? AverageHeartRateBpmRaw { get; set; }

        [JsonPropertyName("average_bpm")]
        [JsonProperty("average_bpm")]
        public double? AverageBpmV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public double? AverageHeartRateBpm
        {
            get => AverageBpmV2 ?? AverageHeartRateBpmRaw;
            set { AverageBpmV2 = value; AverageHeartRateBpmRaw = value; }
        }

        [JsonPropertyName("max_heart_rate_bpm")]
        [JsonProperty("max_heart_rate_bpm")]
        public double? MaxHeartRateBpmRaw { get; set; }

        [JsonPropertyName("max_bpm")]
        [JsonProperty("max_bpm")]
        public double? MaxBpmV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public double? MaxHeartRateBpm
        {
            get => MaxBpmV2 ?? MaxHeartRateBpmRaw;
            set { MaxBpmV2 = value; MaxHeartRateBpmRaw = value; }
        }

        [JsonPropertyName("min_heart_rate_bpm")]
        [JsonProperty("min_heart_rate_bpm")]
        public double? MinHeartRateBpmRaw { get; set; }

        [JsonPropertyName("min_bpm")]
        [JsonProperty("min_bpm")]
        public double? MinBpmV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public double? MinHeartRateBpm
        {
            get => MinBpmV2 ?? MinHeartRateBpmRaw;
            set { MinBpmV2 = value; MinHeartRateBpmRaw = value; }
        }

        [JsonPropertyName("heart_rate_zones")]
        [JsonProperty("heart_rate_zones")]
        public CanonicalHeartRateZones? HeartRateZonesRaw { get; set; }

        [JsonPropertyName("zones")]
        [JsonProperty("zones")]
        public CanonicalHeartRateZones? ZonesV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public CanonicalHeartRateZones? HeartRateZones
        {
            get => ZonesV2 ?? HeartRateZonesRaw;
            set { ZonesV2 = value; HeartRateZonesRaw = value; }
        }

        [JsonPropertyName("latest_bpm")]
        [JsonProperty("latest_bpm")]
        public double? LatestBpm { get; set; }

        [JsonPropertyName("latest_bpm_at")]
        [JsonProperty("latest_bpm_at")]
        public string? LatestBpmAt { get; set; }

        [JsonPropertyName("latest_source_device")]
        [JsonProperty("latest_source_device")]
        public string? LatestSourceDevice { get; set; }
    }

    public class IntradayHeartRatePoint
    {
        [JsonPropertyName("timestamp")]
        [JsonProperty("timestamp")]
        public string Timestamp { get; set; } = string.Empty;

        [JsonPropertyName("bpm")]
        [JsonProperty("bpm")]
        public double Bpm { get; set; }

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }
    }

    public class CanonicalHeartRateZones
    {
        [JsonPropertyName("resting")]
        [JsonProperty("resting")]
        public int Resting { get; set; }

        [JsonPropertyName("resting_minutes")]
        [JsonProperty("resting_minutes")]
        public int RestingMinutes { get; set; }

        [JsonPropertyName("fat_burn")]
        [JsonProperty("fat_burn")]
        public int FatBurn { get; set; }

        [JsonPropertyName("fat_burn_minutes")]
        [JsonProperty("fat_burn_minutes")]
        public int FatBurnMinutes { get; set; }

        [JsonPropertyName("cardio")]
        [JsonProperty("cardio")]
        public int Cardio { get; set; }

        [JsonPropertyName("cardio_minutes")]
        [JsonProperty("cardio_minutes")]
        public int CardioMinutes { get; set; }

        [JsonPropertyName("peak")]
        [JsonProperty("peak")]
        public int Peak { get; set; }

        [JsonPropertyName("peak_minutes")]
        [JsonProperty("peak_minutes")]
        public int PeakMinutes { get; set; }
    }

    public class CanonicalStressSummary
    {
        [JsonPropertyName("daily_average_score")]
        [JsonProperty("daily_average_score")]
        public int DailyAverageScoreRaw { get; set; }

        [JsonPropertyName("daily_average")]
        [JsonProperty("daily_average")]
        public int DailyAverageV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public int DailyAverageScore
        {
            get => DailyAverageV2 > 0 ? DailyAverageV2 : DailyAverageScoreRaw;
            set { DailyAverageV2 = value; DailyAverageScoreRaw = value; }
        }

        [JsonPropertyName("current_score")]
        [JsonProperty("current_score")]
        public int CurrentScore { get; set; }

        [JsonPropertyName("current_level")]
        [JsonProperty("current_level")]
        public string CurrentLevel { get; set; } = "Calm";

        [JsonPropertyName("parasympathetic_percent")]
        [JsonProperty("parasympathetic_percent")]
        public int? ParasympatheticPercentV2 { get; set; }

        [JsonPropertyName("sympathetic_percent")]
        [JsonProperty("sympathetic_percent")]
        public int? SympatheticPercentV2 { get; set; }

        [JsonPropertyName("baseline_hrv_ms")]
        [JsonProperty("baseline_hrv_ms")]
        public double? BaselineHrvMsV2 { get; set; }

        [JsonPropertyName("current_hrv_ms")]
        [JsonProperty("current_hrv_ms")]
        public double? CurrentHrvMsV2 { get; set; }

        [JsonPropertyName("resting_heart_rate_bpm")]
        [JsonProperty("resting_heart_rate_bpm")]
        public double? RestingHeartRateBpmV2 { get; set; }

        [JsonPropertyName("current_sedentary_bpm")]
        [JsonProperty("current_sedentary_bpm")]
        public double? CurrentSedentaryBpmV2 { get; set; }

        [JsonPropertyName("advice_quote")]
        [JsonProperty("advice_quote")]
        public string? AdviceQuote { get; set; }

        [JsonPropertyName("recommended_breathing")]
        [JsonProperty("recommended_breathing")]
        public string? RecommendedBreathing { get; set; }

        [JsonPropertyName("autonomic_balance")]
        [JsonProperty("autonomic_balance")]
        public CanonicalAutonomicBalance? AutonomicBalanceRaw { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public CanonicalAutonomicBalance AutonomicBalance
        {
            get => AutonomicBalanceRaw ?? new CanonicalAutonomicBalance
            {
                ParasympatheticPercent = ParasympatheticPercentV2 ?? Math.Clamp(100 - (CurrentScore > 0 ? CurrentScore : 50), 10, 90),
                SympatheticPercent = SympatheticPercentV2 ?? (100 - Math.Clamp(100 - (CurrentScore > 0 ? CurrentScore : 50), 10, 90))
            };
            set => AutonomicBalanceRaw = value;
        }

        [JsonPropertyName("biometric_drivers")]
        [JsonProperty("biometric_drivers")]
        public CanonicalStressDrivers? BiometricDriversRaw { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public CanonicalStressDrivers BiometricDrivers
        {
            get => BiometricDriversRaw ?? new CanonicalStressDrivers
            {
                BaselineHrvMs = BaselineHrvMsV2 ?? 45.0,
                CurrentHrvMs = CurrentHrvMsV2,
                RestingHeartRateBpm = RestingHeartRateBpmV2,
                CurrentSedentaryBpm = CurrentSedentaryBpmV2
            };
            set => BiometricDriversRaw = value;
        }

        [JsonPropertyName("monkey_mood")]
        [JsonProperty("monkey_mood")]
        public string? MonkeyMood { get; set; }

        [JsonPropertyName("source_device")]
        [JsonProperty("source_device")]
        public string? SourceDevice { get; set; }

        [JsonPropertyName("intraday_stress")]
        [JsonProperty("intraday_stress")]
        public List<IntradayStressPoint>? IntradayStressRaw { get; set; }

        [JsonPropertyName("intraday_points")]
        [JsonProperty("intraday_points")]
        public List<IntradayStressPoint>? IntradayPointsV2 { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public List<IntradayStressPoint> IntradayStress
        {
            get => (IntradayPointsV2 != null && IntradayPointsV2.Count > 0) ? IntradayPointsV2 : (IntradayStressRaw ?? new());
            set { IntradayPointsV2 = value; IntradayStressRaw = value; }
        }
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

        [JsonPropertyName("score")]
        [JsonProperty("score")]
        public int Score { get; set; }

        [JsonPropertyName("stress_score")]
        [JsonProperty("stress_score")]
        public int StressScore { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public int EffectiveScore => Score > 0 ? Score : StressScore;

        [JsonPropertyName("level")]
        [JsonProperty("level")]
        public string Level { get; set; } = "calm";
    }

    // ==========================================
    // LEAN HEALTH TABLES (SUPABASE v2.1)
    // ==========================================

    [Table("health_sources")]
    public class HealthSourceRecord : BaseModel
    {
        [PrimaryKey("id")]
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = string.Empty;

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        [JsonProperty("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("platform")]
        [JsonPropertyName("platform")]
        [JsonProperty("platform")]
        public string Platform { get; set; } = "unknown";

        [Column("device_kind")]
        [JsonPropertyName("device_kind")]
        [JsonProperty("device_kind")]
        public string DeviceKind { get; set; } = "wearable";

        [Column("vendor")]
        [JsonPropertyName("vendor")]
        [JsonProperty("vendor")]
        public string? Vendor { get; set; }

        [Column("model")]
        [JsonPropertyName("model")]
        [JsonProperty("model")]
        public string? Model { get; set; }

        [Column("display_name")]
        [JsonPropertyName("display_name")]
        [JsonProperty("display_name")]
        public string DisplayName { get; set; } = string.Empty;

        [Column("host_device_name")]
        [JsonPropertyName("host_device_name")]
        [JsonProperty("host_device_name")]
        public string? HostDeviceName { get; set; }

        [Column("priority_sleep")]
        [JsonPropertyName("priority_sleep")]
        [JsonProperty("priority_sleep")]
        public int PrioritySleep { get; set; } = 10;

        [Column("priority_activity")]
        [JsonPropertyName("priority_activity")]
        [JsonProperty("priority_activity")]
        public int PriorityActivity { get; set; } = 10;

        [Column("is_custom_priority")]
        [JsonPropertyName("is_custom_priority")]
        [JsonProperty("is_custom_priority")]
        public bool IsCustomPriority { get; set; }

        [Column("color")]
        [JsonPropertyName("color")]
        [JsonProperty("color")]
        public string? Color { get; set; } = "#3897F0";

        [Column("created_at")]
        [JsonPropertyName("created_at")]
        [JsonProperty("created_at")]
        public string? CreatedAt { get; set; }
    }

    [Table("health_sleep_sessions")]
    public class HealthSleepSessionRecord : BaseModel
    {
        [PrimaryKey("id")]
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = string.Empty;

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        [JsonProperty("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("local_date")]
        [JsonPropertyName("local_date")]
        [JsonProperty("local_date")]
        public string LocalDate { get; set; } = string.Empty;

        [Column("session_type")]
        [JsonPropertyName("session_type")]
        [JsonProperty("session_type")]
        public string SessionType { get; set; } = "primary_sleep";

        [Column("source_device_key")]
        [JsonPropertyName("source_device_key")]
        [JsonProperty("source_device_key")]
        public string SourceDeviceKey { get; set; } = string.Empty;

        [Column("host_device_name")]
        [JsonPropertyName("host_device_name")]
        [JsonProperty("host_device_name")]
        public string? HostDeviceName { get; set; }

        [Column("start_time")]
        [JsonPropertyName("start_time")]
        [JsonProperty("start_time")]
        public string StartTime { get; set; } = string.Empty;

        [Column("end_time")]
        [JsonPropertyName("end_time")]
        [JsonProperty("end_time")]
        public string EndTime { get; set; } = string.Empty;

        [Column("duration_seconds")]
        [JsonPropertyName("duration_seconds")]
        [JsonProperty("duration_seconds")]
        public int DurationSeconds { get; set; }

        [Column("time_in_bed_seconds")]
        [JsonPropertyName("time_in_bed_seconds")]
        [JsonProperty("time_in_bed_seconds")]
        public int? TimeInBedSeconds { get; set; }

        [Column("efficiency_percent")]
        [JsonPropertyName("efficiency_percent")]
        [JsonProperty("efficiency_percent")]
        public double? EfficiencyPercent { get; set; }

        [Column("sleep_score")]
        [JsonPropertyName("sleep_score")]
        [JsonProperty("sleep_score")]
        public int? SleepScore { get; set; }

        [Column("deep_seconds")]
        [JsonPropertyName("deep_seconds")]
        [JsonProperty("deep_seconds")]
        public int? DeepSeconds { get; set; }

        [Column("rem_seconds")]
        [JsonPropertyName("rem_seconds")]
        [JsonProperty("rem_seconds")]
        public int? RemSeconds { get; set; }

        [Column("light_seconds")]
        [JsonPropertyName("light_seconds")]
        [JsonProperty("light_seconds")]
        public int? LightSeconds { get; set; }

        [Column("awake_seconds")]
        [JsonPropertyName("awake_seconds")]
        [JsonProperty("awake_seconds")]
        public int? AwakeSeconds { get; set; }

        [Column("quality_rating")]
        [JsonPropertyName("quality_rating")]
        [JsonProperty("quality_rating")]
        public string? QualityRating { get; set; }

        [Column("stages")]
        [JsonPropertyName("stages")]
        [JsonProperty("stages")]
        public List<SleepStageRecord>? Stages { get; set; }

        [Column("source_priority")]
        [JsonPropertyName("source_priority")]
        [JsonProperty("source_priority")]
        public int SourcePriority { get; set; } = 10;

        [Column("is_user_selected")]
        [JsonPropertyName("is_user_selected")]
        [JsonProperty("is_user_selected")]
        public bool IsUserSelected { get; set; }

        public SleepSession ToDomainSleepSession(DateTime fallbackDate)
        {
            var canonDevice = DeviceSource.From(SourceDeviceKey).DisplayName;
            DateTimeOffset.TryParse(StartTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var sDto);
            DateTimeOffset.TryParse(EndTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var eDto);
            var start = sDto != default ? sDto.LocalDateTime : (DateTime.TryParse(StartTime, out var sp) ? sp : fallbackDate.Date.AddHours(-1));
            var end = eDto != default ? eDto.LocalDateTime : (DateTime.TryParse(EndTime, out var ep) ? ep : fallbackDate.Date.AddHours(7));

            int asleepS = DurationSeconds;
            int inBedS = Math.Max(asleepS, TimeInBedSeconds ?? (asleepS + (AwakeSeconds ?? 0)));
            bool hasGranular = Stages != null && Stages.Count > 0;

            var session = new SleepSession
            {
                StartTime = start,
                EndTime = end,
                IsNap = string.Equals(SessionType, "nap", StringComparison.OrdinalIgnoreCase),
                DurationSeconds = inBedS,
                AsleepSeconds = asleepS,
                DeepSeconds = DeepSeconds ?? 0,
                RemSeconds = RemSeconds ?? 0,
                LightSeconds = LightSeconds ?? 0,
                AwakeSeconds = AwakeSeconds ?? 0,
                SleepScore = SleepScore ?? 0,
                SourceDevice = canonDevice,
                HasGranularHypnogram = hasGranular
            };

            if (hasGranular)
            {
                session.Stages = Stages!.Select(st =>
                {
                    DateTimeOffset.TryParse(st.StartTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var stS);
                    DateTimeOffset.TryParse(st.EndTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var stE);
                    var sLocal = stS != default ? stS.LocalDateTime : (DateTime.TryParse(st.StartTime, out var sLocalP) ? sLocalP : start);
                    var eLocal = stE != default ? stE.LocalDateTime : (DateTime.TryParse(st.EndTime, out var eLocalP) ? eLocalP : sLocal.AddSeconds(st.DurationSeconds));
                    var stageKey = st.Stage.ToLowerInvariant() switch
                    {
                        "deep" => "sleep_stage_deep",
                        "rem" => "sleep_stage_rem",
                        "light" or "core" => "sleep_stage_light",
                        _ => "sleep_stage_awake"
                    };
                    return new HealthTelemetry
                    {
                        TypeString = stageKey,
                        Value = st.DurationSeconds,
                        Unit = "sec",
                        StartTime = sLocal,
                        EndTime = eLocal != default ? eLocal : sLocal.AddSeconds(st.DurationSeconds),
                        SourceDevice = canonDevice
                    };
                }).ToList();
            }

            return session;
        }
    }

    [Table("health_daily_vitals")]
    public class HealthDailyVitalsRecord : BaseModel
    {
        [PrimaryKey("id")]
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = string.Empty;

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        [JsonProperty("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("local_date")]
        [JsonPropertyName("local_date")]
        [JsonProperty("local_date")]
        public string LocalDate { get; set; } = string.Empty;

        [Column("source_device_key")]
        [JsonPropertyName("source_device_key")]
        [JsonProperty("source_device_key")]
        public string SourceDeviceKey { get; set; } = string.Empty;

        [Column("host_device_name")]
        [JsonPropertyName("host_device_name")]
        [JsonProperty("host_device_name")]
        public string? HostDeviceName { get; set; }

        [Column("steps")]
        [JsonPropertyName("steps")]
        [JsonProperty("steps")]
        public int Steps { get; set; }

        [Column("active_kcal")]
        [JsonPropertyName("active_kcal")]
        [JsonProperty("active_kcal")]
        public double ActiveKcal { get; set; }

        [Column("resting_heart_rate")]
        [JsonPropertyName("resting_heart_rate")]
        [JsonProperty("resting_heart_rate")]
        public int? RestingHeartRate { get; set; }

        [Column("spo2")]
        [JsonPropertyName("spo2")]
        [JsonProperty("spo2")]
        public double? Spo2 { get; set; }

        [Column("respiratory_rate")]
        [JsonPropertyName("respiratory_rate")]
        [JsonProperty("respiratory_rate")]
        public double? RespiratoryRate { get; set; }

        [Column("skin_temp_celsius")]
        [JsonPropertyName("skin_temp_celsius")]
        [JsonProperty("skin_temp_celsius")]
        public double? SkinTempCelsius { get; set; }

        [Column("weight_kg")]
        [JsonPropertyName("weight_kg")]
        [JsonProperty("weight_kg")]
        public double? WeightKg { get; set; }

        [Column("hrv_sdnn_nightly")]
        [JsonPropertyName("hrv_sdnn_nightly")]
        [JsonProperty("hrv_sdnn_nightly")]
        public double? HrvSdnnNightly { get; set; }

        [Column("hrv_rmssd_nightly")]
        [JsonPropertyName("hrv_rmssd_nightly")]
        [JsonProperty("hrv_rmssd_nightly")]
        public double? HrvRmssdNightly { get; set; }

        [Column("hourly_steps")]
        [JsonPropertyName("hourly_steps")]
        [JsonProperty("hourly_steps")]
        public List<HourlyStepBucket>? HourlySteps { get; set; }

        [Column("latest_heart_rate")]
        [JsonPropertyName("latest_heart_rate")]
        [JsonProperty("latest_heart_rate")]
        public int? LatestHeartRate { get; set; }

        [Column("latest_hr_at")]
        [JsonPropertyName("latest_hr_at")]
        [JsonProperty("latest_hr_at")]
        public string? LatestHrAt { get; set; }

        [Column("vitals_timestamps")]
        [JsonPropertyName("vitals_timestamps")]
        [JsonProperty("vitals_timestamps")]
        public Dictionary<string, string>? VitalsTimestamps { get; set; }

        [Column("updated_at")]
        [JsonPropertyName("updated_at")]
        [JsonProperty("updated_at")]
        public string? UpdatedAt { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        [System.Text.Json.Serialization.JsonIgnore]
        public bool HasSignal =>
            Steps > 0 ||
            ActiveKcal > 0 ||
            (LatestHeartRate ?? 0) > 0 ||
            (RestingHeartRate ?? 0) > 0 ||
            (Spo2 ?? 0) > 0 ||
            (RespiratoryRate ?? 0) > 0 ||
            SkinTempCelsius != null ||
            (WeightKg ?? 0) > 0 ||
            (HrvSdnnNightly ?? 0) > 0 ||
            (HrvRmssdNightly ?? 0) > 0;
    }

    [Table("health_intraday_heart_rate")]
    public class HealthIntradayHeartRateRecord : BaseModel
    {
        [PrimaryKey("id")]
        [JsonPropertyName("id")]
        [JsonProperty("id")]
        public string Id { get; set; } = string.Empty;

        [Column("user_id")]
        [JsonPropertyName("user_id")]
        [JsonProperty("user_id")]
        public string UserId { get; set; } = string.Empty;

        [Column("local_date")]
        [JsonPropertyName("local_date")]
        [JsonProperty("local_date")]
        public string LocalDate { get; set; } = string.Empty;

        [Column("source_device_key")]
        [JsonPropertyName("source_device_key")]
        [JsonProperty("source_device_key")]
        public string SourceDeviceKey { get; set; } = string.Empty;

        [Column("bucket_minute")]
        [JsonPropertyName("bucket_minute")]
        [JsonProperty("bucket_minute")]
        public int BucketMinute { get; set; }

        [Column("bpm_avg")]
        [JsonPropertyName("bpm_avg")]
        [JsonProperty("bpm_avg")]
        public int BpmAvg { get; set; }

        [Column("bpm_min")]
        [JsonPropertyName("bpm_min")]
        [JsonProperty("bpm_min")]
        public int BpmMin { get; set; }

        [Column("bpm_max")]
        [JsonPropertyName("bpm_max")]
        [JsonProperty("bpm_max")]
        public int BpmMax { get; set; }

        [Column("sample_count")]
        [JsonPropertyName("sample_count")]
        [JsonProperty("sample_count")]
        public int SampleCount { get; set; } = 1;

        public HealthTelemetry ToTelemetryPoint()
        {
            var localMidnight = DateTime.TryParse(LocalDate, out var parsed)
                ? DateTime.SpecifyKind(parsed.Date, DateTimeKind.Local)
                : DateTime.SpecifyKind(DateTime.Today, DateTimeKind.Local);
            var startUtc = localMidnight.AddMinutes(BucketMinute).ToUniversalTime();
            return new HealthTelemetry
            {
                TypeString = "heart_rate",
                Value = BpmAvg,
                Unit = "bpm",
                StartTime = startUtc,
                EndTime = startUtc.AddMinutes(5),
                SourceDevice = DeviceSource.From(SourceDeviceKey).DisplayName
            };
        }
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
        public string EngineVersion { get; set; } = "2.1";
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
