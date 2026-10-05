// AUTO-GENERATED from HealthSpec/metric_registry.json - DO NOT EDIT MANUALLY
// Generated at: 2026-10-05T13:51:30.208Z

using System;
using System.Collections.Generic;

namespace Daily.Models.Health
{
    public enum CanonicalHealthMetric
    {
        Steps,
        ActiveEnergy,
        BasalEnergy,
        Distance,
        FloorsClimbed,
        WalkingSpeed,
        HeartRate,
        RestingHeartRate,
        HrvSdnn,
        HrvRmssd,
        OxygenSaturation,
        RespiratoryRate,
        SleepStageDeep,
        SleepStageRem,
        SleepStageLight,
        SleepStageAwake,
        SleepDuration,
        Stress,
        Pai,
        Weight,
        Hydration,
        Caffeine
    }

    public static class HealthMetricRegistry
    {
        private static readonly Dictionary<string, CanonicalHealthMetric> AliasMap = new(StringComparer.OrdinalIgnoreCase)
        {
            { "steps", CanonicalHealthMetric.Steps },
            { "step_count", CanonicalHealthMetric.Steps },
            { "HKQuantityTypeIdentifierStepCount", CanonicalHealthMetric.Steps },
            { "active_energy", CanonicalHealthMetric.ActiveEnergy },
            { "ActiveEnergy", CanonicalHealthMetric.ActiveEnergy },
            { "active_calories", CanonicalHealthMetric.ActiveEnergy },
            { "calorie", CanonicalHealthMetric.ActiveEnergy },
            { "calories", CanonicalHealthMetric.ActiveEnergy },
            { "HKQuantityTypeIdentifierActiveEnergyBurned", CanonicalHealthMetric.ActiveEnergy },
            { "basal_energy", CanonicalHealthMetric.BasalEnergy },
            { "BasalEnergyBurned", CanonicalHealthMetric.BasalEnergy },
            { "basal_calories", CanonicalHealthMetric.BasalEnergy },
            { "resting_energy", CanonicalHealthMetric.BasalEnergy },
            { "HKQuantityTypeIdentifierBasalEnergyBurned", CanonicalHealthMetric.BasalEnergy },
            { "distance", CanonicalHealthMetric.Distance },
            { "distance_walking_running", CanonicalHealthMetric.Distance },
            { "HKQuantityTypeIdentifierDistanceWalkingRunning", CanonicalHealthMetric.Distance },
            { "floors_climbed", CanonicalHealthMetric.FloorsClimbed },
            { "FloorsClimbed", CanonicalHealthMetric.FloorsClimbed },
            { "flights_climbed", CanonicalHealthMetric.FloorsClimbed },
            { "HKQuantityTypeIdentifierFlightsClimbed", CanonicalHealthMetric.FloorsClimbed },
            { "walking_speed", CanonicalHealthMetric.WalkingSpeed },
            { "WalkingSpeed", CanonicalHealthMetric.WalkingSpeed },
            { "HKQuantityTypeIdentifierWalkingSpeed", CanonicalHealthMetric.WalkingSpeed },
            { "heart_rate", CanonicalHealthMetric.HeartRate },
            { "HeartRate", CanonicalHealthMetric.HeartRate },
            { "hr", CanonicalHealthMetric.HeartRate },
            { "pulse", CanonicalHealthMetric.HeartRate },
            { "HKQuantityTypeIdentifierHeartRate", CanonicalHealthMetric.HeartRate },
            { "resting_heart_rate", CanonicalHealthMetric.RestingHeartRate },
            { "RestingHeartRate", CanonicalHealthMetric.RestingHeartRate },
            { "rhr", CanonicalHealthMetric.RestingHeartRate },
            { "HKQuantityTypeIdentifierRestingHeartRate", CanonicalHealthMetric.RestingHeartRate },
            { "hrv_sdnn", CanonicalHealthMetric.HrvSdnn },
            { "HeartRateVariabilitySDNN", CanonicalHealthMetric.HrvSdnn },
            { "hrv", CanonicalHealthMetric.HrvSdnn },
            { "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", CanonicalHealthMetric.HrvSdnn },
            { "hrv_rmssd", CanonicalHealthMetric.HrvRmssd },
            { "RMSSD", CanonicalHealthMetric.HrvRmssd },
            { "HeartRateVariabilityRmssdRecord", CanonicalHealthMetric.HrvRmssd },
            { "oxygen_saturation", CanonicalHealthMetric.OxygenSaturation },
            { "OxygenSaturation", CanonicalHealthMetric.OxygenSaturation },
            { "spo2", CanonicalHealthMetric.OxygenSaturation },
            { "blood_oxygen", CanonicalHealthMetric.OxygenSaturation },
            { "bo", CanonicalHealthMetric.OxygenSaturation },
            { "HKQuantityTypeIdentifierOxygenSaturation", CanonicalHealthMetric.OxygenSaturation },
            { "respiratory_rate", CanonicalHealthMetric.RespiratoryRate },
            { "RespiratoryRate", CanonicalHealthMetric.RespiratoryRate },
            { "breathing_rate", CanonicalHealthMetric.RespiratoryRate },
            { "HKQuantityTypeIdentifierRespiratoryRate", CanonicalHealthMetric.RespiratoryRate },
            { "sleep_stage_deep", CanonicalHealthMetric.SleepStageDeep },
            { "SleepDeep", CanonicalHealthMetric.SleepStageDeep },
            { "sleep_deep", CanonicalHealthMetric.SleepStageDeep },
            { "deep_sleep", CanonicalHealthMetric.SleepStageDeep },
            { "HKCategoryValueSleepAnalysisAsleepDeep", CanonicalHealthMetric.SleepStageDeep },
            { "sleep_stage_rem", CanonicalHealthMetric.SleepStageRem },
            { "SleepREM", CanonicalHealthMetric.SleepStageRem },
            { "sleep_rem", CanonicalHealthMetric.SleepStageRem },
            { "rem_sleep", CanonicalHealthMetric.SleepStageRem },
            { "HKCategoryValueSleepAnalysisAsleepREM", CanonicalHealthMetric.SleepStageRem },
            { "sleep_stage_light", CanonicalHealthMetric.SleepStageLight },
            { "SleepLight", CanonicalHealthMetric.SleepStageLight },
            { "sleep_light", CanonicalHealthMetric.SleepStageLight },
            { "light_sleep", CanonicalHealthMetric.SleepStageLight },
            { "core_sleep", CanonicalHealthMetric.SleepStageLight },
            { "HKCategoryValueSleepAnalysisAsleepCore", CanonicalHealthMetric.SleepStageLight },
            { "sleep_stage_awake", CanonicalHealthMetric.SleepStageAwake },
            { "SleepAwake", CanonicalHealthMetric.SleepStageAwake },
            { "sleep_awake", CanonicalHealthMetric.SleepStageAwake },
            { "awake", CanonicalHealthMetric.SleepStageAwake },
            { "HKCategoryValueSleepAnalysisAwake", CanonicalHealthMetric.SleepStageAwake },
            { "sleep_duration", CanonicalHealthMetric.SleepDuration },
            { "SleepDuration", CanonicalHealthMetric.SleepDuration },
            { "sleep", CanonicalHealthMetric.SleepDuration },
            { "total_sleep", CanonicalHealthMetric.SleepDuration },
            { "HKCategoryValueSleepAnalysisAsleepUnspecified", CanonicalHealthMetric.SleepDuration },
            { "stress", CanonicalHealthMetric.Stress },
            { "stress_score", CanonicalHealthMetric.Stress },
            { "autonomic_stress", CanonicalHealthMetric.Stress },
            { "pai", CanonicalHealthMetric.Pai },
            { "pai_score", CanonicalHealthMetric.Pai },
            { "weight", CanonicalHealthMetric.Weight },
            { "body_mass", CanonicalHealthMetric.Weight },
            { "HKQuantityTypeIdentifierBodyMass", CanonicalHealthMetric.Weight },
            { "hydration", CanonicalHealthMetric.Hydration },
            { "water", CanonicalHealthMetric.Hydration },
            { "water_intake", CanonicalHealthMetric.Hydration },
            { "dietary_water", CanonicalHealthMetric.Hydration },
            { "HKQuantityTypeIdentifierDietaryWater", CanonicalHealthMetric.Hydration },
            { "caffeine", CanonicalHealthMetric.Caffeine },
            { "caffeine_intake", CanonicalHealthMetric.Caffeine },
            { "dietary_caffeine", CanonicalHealthMetric.Caffeine },
            { "HKQuantityTypeIdentifierDietaryCaffeine", CanonicalHealthMetric.Caffeine }
        };

        public static bool TryResolve(string alias, out CanonicalHealthMetric metric)
        {
            if (string.IsNullOrWhiteSpace(alias))
            {
                metric = default;
                return false;
            }
            return AliasMap.TryGetValue(alias.Trim(), out metric);
        }

        public static string ToKey(this CanonicalHealthMetric metric) => metric switch
        {
            CanonicalHealthMetric.Steps => "steps",
            CanonicalHealthMetric.ActiveEnergy => "active_energy",
            CanonicalHealthMetric.BasalEnergy => "basal_energy",
            CanonicalHealthMetric.Distance => "distance",
            CanonicalHealthMetric.FloorsClimbed => "floors_climbed",
            CanonicalHealthMetric.WalkingSpeed => "walking_speed",
            CanonicalHealthMetric.HeartRate => "heart_rate",
            CanonicalHealthMetric.RestingHeartRate => "resting_heart_rate",
            CanonicalHealthMetric.HrvSdnn => "hrv_sdnn",
            CanonicalHealthMetric.HrvRmssd => "hrv_rmssd",
            CanonicalHealthMetric.OxygenSaturation => "oxygen_saturation",
            CanonicalHealthMetric.RespiratoryRate => "respiratory_rate",
            CanonicalHealthMetric.SleepStageDeep => "sleep_stage_deep",
            CanonicalHealthMetric.SleepStageRem => "sleep_stage_rem",
            CanonicalHealthMetric.SleepStageLight => "sleep_stage_light",
            CanonicalHealthMetric.SleepStageAwake => "sleep_stage_awake",
            CanonicalHealthMetric.SleepDuration => "sleep_duration",
            CanonicalHealthMetric.Stress => "stress",
            CanonicalHealthMetric.Pai => "pai",
            CanonicalHealthMetric.Weight => "weight",
            CanonicalHealthMetric.Hydration => "hydration",
            CanonicalHealthMetric.Caffeine => "caffeine",
            _ => metric.ToString().ToLowerInvariant()
        };
    }
}
