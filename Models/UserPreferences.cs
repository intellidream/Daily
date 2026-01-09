using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace Daily.Models
{
    [Table("user_preferences")]
    public class UserPreferences : BaseModel
    {
        [PrimaryKey("id")]
        public string Id { get; set; }

        [Column("theme")]
        public string Theme { get; set; }

        [Column("unit_system")] // 'metric' or 'imperial'
        public string UnitSystem { get; set; } = "metric";

        [Column("pressure_unit")] // 'hpa', 'mmhg', 'inhg'
        public string PressureUnit { get; set; } = "hpa";
        
        [Column("news_interests")]
        public List<string> Interests { get; set; } = new();

        // New Preferences (Local Only until DB Schema Updated)
        [Column("wind_unit")]
        public string WindUnit { get; set; } = "km/h"; // m/s, km/h, mph
        [Column("visibility_unit")]
        public string VisibilityUnit { get; set; } = "km"; // km, mi
        [Column("precipitation_unit")]
        public string PrecipitationUnit { get; set; } = "mm"; // mm, in
        
        [Column("notifications_enabled")]
        public bool NotificationsEnabled { get; set; } = true;
        [Column("daily_forecast_alert")]
        public bool DailyForecastAlert { get; set; } = true;
        [Column("precipitation_alert")]
        public bool PrecipitationAlert { get; set; } = true;

        // Smokes Configuration (Synced)
        [Column("smokes_baseline")]
        public int SmokesBaselineDaily { get; set; } = 0;

        [Column("smokes_pack_size")]
        public int SmokesPackSize { get; set; } = 20;

        [Column("smokes_pack_cost")]
        public double SmokesPackCost { get; set; } = 0;

        [Column("smokes_currency")]
        public string SmokesCurrency { get; set; } = "USD";

        [Column("smokes_quit_date")]
        public DateTime? SmokesQuitDate { get; set; }

        [Column("updated_at")]
        public DateTime UpdatedAt { get; set; }
    }
}
