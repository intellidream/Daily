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
        public string? DashboardWidgetsJson { get; set; }
        public string? WinUIDashboardWidgetsJson { get; set; }

        public DateTime UpdatedAt { get; set; }
        public DateTime? SyncedAt { get; set; }
    }

    [Table("habits_daily_summaries")]
    public class LocalDailySummary
    {
        [PrimaryKey]
        public string Id { get; set; } // UUID String

        [Indexed]
        public string UserId { get; set; }

        [Indexed]
        public string HabitType { get; set; }

        public DateTime Date { get; set; } // Stored as midnight UTC
        
        public double TotalValue { get; set; }
        public int LogCount { get; set; }
        public string? Metadata { get; set; } 

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        [Indexed]
        public DateTime? SyncedAt { get; set; } // Null = Dirty
    }

    [Table("behavior_events")]
    public class LocalBehaviorEvent
    {
        [PrimaryKey, AutoIncrement]
        public int Id { get; set; }

        [Indexed]
        public string UserId { get; set; }

        [Indexed]
        public string WidgetType { get; set; } // e.g. "HabitsWidget", "RssFeedWidget"

        public string Action { get; set; } // e.g. "view", "log", "click"

        public int DayOfWeek { get; set; } // 0=Sun..6=Sat

        public int HourOfDay { get; set; } // 0-23

        public DateTime Timestamp { get; set; }
    }

    [Table("navigation_transitions")]
    public class LocalNavigationTransition
    {
        [PrimaryKey, AutoIncrement]
        public int Id { get; set; }

        [Indexed]
        public string UserId { get; set; }

        [Indexed]
        public string FromWidget { get; set; }

        [Indexed]
        public string ToWidget { get; set; }

        public int DayOfWeek { get; set; }
        public int HourOfDay { get; set; }
        public DateTime Timestamp { get; set; }
    }

    [Table("rss_saved_articles")]
    public class LocalSavedArticle
    {
        [PrimaryKey]
        public string Id { get; set; } // UUID as string

        [Indexed]
        public string UserId { get; set; }

        [Indexed]
        public string ArticleUrl { get; set; } = string.Empty;

        public string Title { get; set; } = string.Empty;
        public string? ImageUrl { get; set; }
        public string? Description { get; set; }
        public string? Author { get; set; }

        [Indexed]
        public string PublicationName { get; set; } = string.Empty;
        public string? PublicationIconUrl { get; set; }

        [Indexed]
        public string ArticleType { get; set; } = "ReadLater"; // "ReadLater" or "Favorite"

        public DateTime ArticleDate { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        [Indexed]
        public DateTime? SyncedAt { get; set; } // Null = Dirty
        public bool IsDeleted { get; set; }
    }

    [Table("rss_subscriptions")]
    public class LocalRssSubscription
    {
        [PrimaryKey]
        public string Id { get; set; } // UUID as string

        [Indexed]
        public string UserId { get; set; } // UUID as string

        public string Name { get; set; }
        public string Url { get; set; }
        public string IconUrl { get; set; }
        public string Category { get; set; }

        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        // Sync Status
        [Indexed]
        public DateTime? SyncedAt { get; set; } // Null = Dirty
        public bool IsDeleted { get; set; }
    }

    [Table("vitals")]
    public class LocalVitalMetric
    {
        [PrimaryKey]
        public string Id { get; set; } // UUID as string

        [Indexed]
        public string UserId { get; set; } // UUID as string

        [Indexed]
        public string TypeString { get; set; }

        public double Value { get; set; }
        public string Unit { get; set; }

        [Indexed]
        public DateTime Date { get; set; }

        public string SourceDevice { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime UpdatedAt { get; set; }

        [Indexed]
        public DateTime? SyncedAt { get; set; }
    }

    [Table("smart_behavior_events")]
    public class SmartBehaviorEvent
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty;

        [Indexed]
        public string UserId { get; set; } = string.Empty;

        [Indexed]
        public string Feature { get; set; } = string.Empty; // e.g. "Weather", "Finances", "News", "Health", "Habits"

        public string ActionType { get; set; } = string.Empty; // e.g. "View", "Log", "Search", "Summarize"

        public string Metadata { get; set; } = string.Empty; // JSON payload details

        [Indexed]
        public DateTime Timestamp { get; set; }

        [Indexed]
        public bool IsSynced { get; set; } = false;
    }
}
