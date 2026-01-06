using SQLite;

namespace Daily.Models
{
    [Table("habits_logs")]
    public class LocalHabitLog
    {
        [PrimaryKey]
        public string Id { get; set; } // UUID as string

        [Indexed]
        public string UserId { get; set; } // UUID as string

        [Indexed]
        public string HabitType { get; set; }

        public double Value { get; set; }
        public string Unit { get; set; }
        public DateTime LoggedAt { get; set; }
        public string? Metadata { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Sync Status
        [Indexed]
        public DateTime? SyncedAt { get; set; } // Null = Dirty
        public bool IsDeleted { get; set; }
    }

    [Table("habits_goals")]
    public class LocalHabitGoal
    {
        [PrimaryKey]
        public string Id { get; set; } // UUID as string

        [Indexed]
        public string UserId { get; set; }

        [Indexed]
        public string HabitType { get; set; }

        public double TargetValue { get; set; }
        public string Unit { get; set; }
        
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public DateTime? SyncedAt { get; set; }
        public bool IsDeleted { get; set; }
    }

    [Table("user_preferences")]
    public class LocalUserPreferences
    {
        [PrimaryKey]
        public string Id { get; set; } // User ID

        public string Theme { get; set; }
        public string UnitSystem { get; set; }
        
        // Weather
        public string PressureUnit { get; set; }
        public string WindUnit { get; set; }
        public string VisibilityUnit { get; set; }
        public string PrecipitationUnit { get; set; }

        // Notifications
        public bool NotificationsEnabled { get; set; }
        public bool DailyForecastAlert { get; set; }
        public bool PrecipitationAlert { get; set; }

        // Smokes
        public int SmokesBaselineDaily { get; set; }
        public int SmokesPackSize { get; set; }
        public double SmokesPackCost { get; set; }
        public string SmokesCurrency { get; set; }
        public DateTime? SmokesQuitDate { get; set; }

        // Serialized JSON
        public string InterestsJson { get; set; }

        public DateTime? SyncedAt { get; set; }
    }
}
