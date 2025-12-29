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
    }
}
