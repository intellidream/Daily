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
        ActiveEnergy // Calories
    }

    [Table("vitals")]
    public class VitalMetric : BaseModel
    {
        [PrimaryKey("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [Column("user_id")]
        public string UserId { get; set; }

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
        public VitalType Type
        {
            get => Enum.TryParse<VitalType>(TypeString, out var t) ? t : VitalType.Steps;
            set => TypeString = value.ToString();
        }
    }
}
