using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models.Health
{
    public enum VitalType
    {
        Steps,
        HeartRate,
        RestingHeartRate,
        SleepDuration, // Minutes
        Weight,
        ActiveEnergy, // Calories
        // V50 Additions
        BloodPressureSystolic,
        BloodPressureDiastolic,
        BloodGlucose,
        OxygenSaturation,
        BodyTemperature,
        Hydration,
        Distance,
        // Expanded Activity
        FloorsClimbed,
        WalkingSpeed,
        RunningSpeed, // New
        CyclingPower,
        CyclingCadence, // New
        WorkoutDuration, // New
        BasalEnergyBurned, // Resting Calories
        // Expanded Vitals
        HeartRateVariabilitySDNN,
        HeartRateVariabilityRMSSD, // New
        RespiratoryRate,
        BasalBodyTemperature, // New
        // Body Measurements
        BodyFatPercentage,
        LeanBodyMass,
        Height, // New
        BodyMassIndex, // New
        BoneMass, // New
        // Nutrition
        Carbs,
        Fat,
        Protein,
        Caffeine,
        Sugar, // New
        VitaminC, // New
        VitaminA, // New
        Iron, // New
        Magnesium, // New
        Zinc, // New
        Calcium, // New
        // Sleep Stages
        SleepAwake, // New
        SleepDeep, // New
        SleepLight, // New
        SleepREM, // New
        // Cycle Tracking
        MenstruationFlow, // 0=None, 1=Light, 2=Medium, 3=Heavy
        OvulationTest, // 0=Neg, 1=Pos
        SexualActivity, // New (0=No, 1=Protection, 2=Unprotected) - Simplified to just "Event"
        // Mindfulness
        MindfulSession, // Minutes
    }

    [Table("vitals")]
    public class VitalMetric : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("type")]
        public string TypeString { get; set; } // Stored as string for Postgrest compatibility

        [Column("value")]
        public double Value { get; set; }

        [Column("unit")]
        public string Unit { get; set; }

        [Column("date")]
        public DateTime Date { get; set; }

        [Column("source_device")]
        public string SourceDevice { get; set; } // "iOS", "Android", "Manual"

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        // Helper property for Enum handling
        [Newtonsoft.Json.JsonIgnore]
        public VitalType Type
        {
            get => Enum.TryParse<VitalType>(TypeString, out var t) ? t : VitalType.Steps;
            set => TypeString = value.ToString();
        }
    }
}
