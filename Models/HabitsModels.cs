using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;
using System;

namespace Daily.Models
{
    [Table("habits_goals")]
    public class HabitGoal : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("habit_type")]
        public string HabitType { get; set; }

        [Column("target_value")]
        public double TargetValue { get; set; }

        [Column("unit")]
        public string Unit { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Newtonsoft.Json.JsonIgnore]
        public DateTime? SyncedAt { get; set; }

        [Column("is_deleted")]
        public bool IsDeleted { get; set; }
    }

    [Table("habits_logs")]
    public class HabitLog : BaseModel
    {
        [PrimaryKey("id")]
        public Guid Id { get; set; }

        [Column("user_id")]
        public Guid UserId { get; set; }

        [Column("habit_type")]
        public string HabitType { get; set; }

        [Column("value")]
        public double Value { get; set; }

        [Column("unit")]
        public string Unit { get; set; }

        [Column("logged_at")]
        public DateTime LoggedAt { get; set; }

        [Column("metadata")]
        public string? Metadata { get; set; }

        [Column("created_at")]
        public DateTime CreatedAt { get; set; }

        [Column("updated_at")]
        public DateTime? UpdatedAt { get; set; }

        // Local-only properties (not mapped to Supabase 'Column' unless consistent)
        // If we want to prevent these from sending to Supabase, we rely on Supabase client ignoring non-Column props?
        // Or we use [JsonIgnore] if using System.Text.Json, or explicit Ignore.
        // For now, let's assume simple POCO properties won't be sent if not decorating with Column? 
        // Actually Supabase client usually respects Column attribute. 
        // We will add them as properties.

        [Newtonsoft.Json.JsonIgnore]
        public DateTime? SyncedAt { get; set; }

        [Column("is_deleted")]
        public bool IsDeleted { get; set; }
    }
}
