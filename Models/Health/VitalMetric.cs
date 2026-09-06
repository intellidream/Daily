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
        // Mindfulness & Wellness
        MindfulSession, // Minutes
        Stress, // 0-100 Stress Index
        PAI, // Personal Activity Intelligence Score
        NapDuration // Daytime Nap Minutes
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
        public string SourceDevice { get; set; } // "iOS", "Android", "Manual", "Zepp OS Watch", etc.

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        [Column("synced_at")]
        public DateTime? SyncedAt { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        public bool IsHistorical { get; set; } = false;

        public static VitalType ParseVitalType(string? typeStr)
        {
            if (string.IsNullOrWhiteSpace(typeStr)) return VitalType.Steps;
            var norm = typeStr.Trim().ToLowerInvariant().Replace("_", "").Replace(" ", "");
            return norm switch
            {
                "steps" or "stepcount" => VitalType.Steps,
                "heartrate" or "hr" => VitalType.HeartRate,
                "restingheartrate" or "rhr" => VitalType.RestingHeartRate,
                "sleepduration" or "sleep" => VitalType.SleepDuration,
                "weight" => VitalType.Weight,
                "activeenergy" or "activecalories" or "calories" or "energy" => VitalType.ActiveEnergy,
                "bloodpressuresystolic" or "systolic" => VitalType.BloodPressureSystolic,
                "bloodpressurediastolic" or "diastolic" => VitalType.BloodPressureDiastolic,
                "bloodglucose" or "glucose" => VitalType.BloodGlucose,
                "oxygensaturation" or "spo2" or "bloodoxygen" => VitalType.OxygenSaturation,
                "bodytemperature" or "temperature" or "temp" => VitalType.BodyTemperature,
                "hydration" or "water" => VitalType.Hydration,
                "distance" => VitalType.Distance,
                "floorsclimbed" or "floors" => VitalType.FloorsClimbed,
                "walkingspeed" => VitalType.WalkingSpeed,
                "runningspeed" => VitalType.RunningSpeed,
                "cyclingpower" => VitalType.CyclingPower,
                "cyclingcadence" => VitalType.CyclingCadence,
                "workoutduration" => VitalType.WorkoutDuration,
                "basalenergyburned" or "basalenergy" or "restingenergy" or "restingcalories" => VitalType.BasalEnergyBurned,
                "heartratevariabilitysdnn" or "hrv" or "hrvsdnn" => VitalType.HeartRateVariabilitySDNN,
                "heartratevariabilityrmssd" or "hrvrmssd" => VitalType.HeartRateVariabilityRMSSD,
                "respiratoryrate" or "resp" or "respiration" => VitalType.RespiratoryRate,
                "basalbodytemperature" => VitalType.BasalBodyTemperature,
                "bodyfatpercentage" or "bodyfat" => VitalType.BodyFatPercentage,
                "leanbodymass" or "leanmass" => VitalType.LeanBodyMass,
                "height" => VitalType.Height,
                "bodymassindex" or "bmi" => VitalType.BodyMassIndex,
                "bonemass" => VitalType.BoneMass,
                "carbs" or "carbohydrates" => VitalType.Carbs,
                "fat" or "fats" => VitalType.Fat,
                "protein" => VitalType.Protein,
                "caffeine" => VitalType.Caffeine,
                "sugar" => VitalType.Sugar,
                "vitaminc" => VitalType.VitaminC,
                "vitamina" => VitalType.VitaminA,
                "iron" => VitalType.Iron,
                "magnesium" => VitalType.Magnesium,
                "zinc" => VitalType.Zinc,
                "calcium" => VitalType.Calcium,
                "sleepawake" or "sleepstageawake" => VitalType.SleepAwake,
                "sleepdeep" or "sleepstagedeep" => VitalType.SleepDeep,
                "sleeplight" or "sleepcore" or "sleepstagelight" or "sleepstagecore" => VitalType.SleepLight,
                "sleeprem" or "sleepstagerem" => VitalType.SleepREM,
                "sleepnap" or "nap" or "napduration" => VitalType.NapDuration,
                "stress" => VitalType.Stress,
                "pai" => VitalType.PAI,
                "menstruationflow" => VitalType.MenstruationFlow,
                "ovulationtest" => VitalType.OvulationTest,
                "sexualactivity" => VitalType.SexualActivity,
                "mindfulsession" or "mindfulness" => VitalType.MindfulSession,
                _ => Enum.TryParse<VitalType>(typeStr, true, out var parsed) ? parsed : VitalType.Steps
            };
        }

        // Helper property for Enum handling
        [Newtonsoft.Json.JsonIgnore]
        public VitalType Type
        {
            get => ParseVitalType(TypeString);
            set => TypeString = value.ToString();
        }

        public bool MatchesType(VitalType target) => Type == target;
    }
}
