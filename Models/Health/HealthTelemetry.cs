using System;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models.Health
{
    [Table("health_telemetry")]
    public class HealthTelemetry : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("type")]
        public string TypeString { get; set; } = string.Empty;

        [Column("value")]
        public double? Value { get; set; }

        [Column("unit")]
        public string? Unit { get; set; }

        [Column("start_time")]
        public DateTime StartTime { get; set; }

        [Column("end_time")]
        public DateTime? EndTime { get; set; }

        [Column("source_device")]
        public string? SourceDevice { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [Newtonsoft.Json.JsonIgnore]
        public string NormalizedType => TypeString?.Trim().ToLowerInvariant().Replace("_", "").Replace(" ", "") ?? string.Empty;

        [Newtonsoft.Json.JsonIgnore]
        public bool IsHeartRate => NormalizedType == "heartrate" || NormalizedType == "hr";

        [Newtonsoft.Json.JsonIgnore]
        public bool IsSteps => NormalizedType == "steps" || NormalizedType == "stepcount";

        [Newtonsoft.Json.JsonIgnore]
        public bool IsSleep => NormalizedType.StartsWith("sleep");

        [Newtonsoft.Json.JsonIgnore]
        public bool IsSleepStage => NormalizedType.StartsWith("sleepstage");

        [Newtonsoft.Json.JsonIgnore]
        public bool IsActiveEnergy => NormalizedType == "activeenergy" || NormalizedType == "calories" || NormalizedType == "energy";

        [Newtonsoft.Json.JsonIgnore]
        public double NumericValue => Value ?? 0;

        [Newtonsoft.Json.JsonIgnore]
        public double DurationSeconds
        {
            get
            {
                if (Value.HasValue && Value.Value > 0)
                {
                    var u = Unit?.Trim().ToLowerInvariant();
                    if (u == "hours" || u == "hour" || u == "h" || u == "hr") return Value.Value * 3600.0;
                    if (u == "minutes" || u == "minute" || u == "min" || u == "m") return Value.Value * 60.0;
                    if (u == "seconds" || u == "sec" || u == "s") return Value.Value;
                }
                if (EndTime.HasValue && EndTime.Value > StartTime)
                {
                    return (EndTime.Value - StartTime).TotalSeconds;
                }
                return 0;
            }
        }

        [Newtonsoft.Json.JsonIgnore]
        public DateTime EffectiveEndTime => DurationSeconds > 0 
            ? StartTime.AddSeconds(DurationSeconds) 
            : (EndTime.HasValue && EndTime.Value > StartTime ? EndTime.Value : StartTime);

        [Newtonsoft.Json.JsonIgnore]
        public DateTime LocalStartTime => StartTime.Kind == DateTimeKind.Utc 
            ? StartTime.ToLocalTime() 
            : DateTime.SpecifyKind(StartTime, DateTimeKind.Utc).ToLocalTime();

        [Newtonsoft.Json.JsonIgnore]
        public DateTime LocalEndTime => EffectiveEndTime.Kind == DateTimeKind.Utc 
            ? EffectiveEndTime.ToLocalTime() 
            : DateTime.SpecifyKind(EffectiveEndTime, DateTimeKind.Utc).ToLocalTime();

        [Newtonsoft.Json.JsonIgnore]
        public string SleepCategory
        {
            get
            {
                var norm = NormalizedType;
                if (norm.Contains("deep")) return "Deep";
                if (norm.Contains("rem")) return "REM";
                if (norm.Contains("awake") || norm.Contains("wake")) return "Awake";
                return "Core";
            }
        }
    }
}
