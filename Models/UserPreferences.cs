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
        public string WindUnit { get; set; } = "km/h"; // m/s, km/h, mph
        public string VisibilityUnit { get; set; } = "km"; // km, mi
        public string PrecipitationUnit { get; set; } = "mm"; // mm, in
        
        public bool NotificationsEnabled { get; set; } = true;
        public bool DailyForecastAlert { get; set; } = true;
        public bool PrecipitationAlert { get; set; } = true;
    }
}
