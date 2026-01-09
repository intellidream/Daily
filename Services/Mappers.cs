using Daily.Models;

namespace Daily.Services
{
    public static class Mappers
    {
        // --- HabitLog ---

        public static HabitLog ToDomain(this LocalHabitLog local)
        {
            return new HabitLog
            {
                Id = Guid.Parse(local.Id),
                UserId = Guid.Parse(local.UserId),
                HabitType = local.HabitType,
                Value = local.Value,
                Unit = local.Unit,
                LoggedAt = local.LoggedAt,
                Metadata = local.Metadata,
                CreatedAt = local.CreatedAt,
                UpdatedAt = local.UpdatedAt,
                SyncedAt = local.SyncedAt,
                IsDeleted = local.IsDeleted
            };
        }
        
        public static LocalHabitLog ToLocal(this HabitLog domain)
        {
            return new LocalHabitLog
            {
                Id = domain.Id.ToString(),
                UserId = domain.UserId.ToString(),
                HabitType = domain.HabitType,
                Value = domain.Value,
                Unit = domain.Unit,
                LoggedAt = domain.LoggedAt,
                Metadata = domain.Metadata,
                CreatedAt = domain.CreatedAt,
                UpdatedAt = domain.UpdatedAt,
                SyncedAt = domain.SyncedAt,
                IsDeleted = domain.IsDeleted
            };
        }

        // --- HabitGoal ---

        public static HabitGoal ToDomain(this LocalHabitGoal local)
        {
            return new HabitGoal
            {
                Id = Guid.Parse(local.Id),
                UserId = Guid.Parse(local.UserId),
                HabitType = local.HabitType,
                TargetValue = local.TargetValue,
                Unit = local.Unit,
                CreatedAt = local.CreatedAt,
                UpdatedAt = local.UpdatedAt,
                SyncedAt = local.SyncedAt,
                IsDeleted = local.IsDeleted
            };
        }

        public static LocalHabitGoal ToLocal(this HabitGoal domain)
        {
            return new LocalHabitGoal
            {
                Id = domain.Id.ToString(),
                UserId = domain.UserId.ToString(),
                HabitType = domain.HabitType,
                TargetValue = domain.TargetValue,
                Unit = domain.Unit,
                CreatedAt = domain.CreatedAt,
                UpdatedAt = domain.UpdatedAt,
                SyncedAt = domain.SyncedAt,
                IsDeleted = domain.IsDeleted
            };
        }

        // --- DailySummary ---

        public static DailySummary ToDomain(this LocalDailySummary local)
        {
            return new DailySummary
            {
                Id = GenerateGuid(local.Id), // Use consistent hash ID
                UserId = Guid.Parse(local.UserId),
                HabitType = local.HabitType,
                Date = local.Date,
                TotalValue = local.TotalValue,
                LogCount = local.LogCount,
                Metadata = local.Metadata,
                CreatedAt = local.CreatedAt,
                UpdatedAt = local.UpdatedAt
            };
        }

        public static LocalDailySummary ToLocal(this DailySummary domain)
        {
            // Reconstruct the stable String ID if needed or use domain ID if mapped back.
            // For now, consistent logic with SyncService:
            var strId = $"{domain.UserId}_{domain.HabitType}_{domain.Date:yyyyMMdd}";
            
            return new LocalDailySummary
            {
                Id = strId,
                UserId = domain.UserId.ToString(),
                HabitType = domain.HabitType,
                Date = domain.Date,
                TotalValue = domain.TotalValue,
                LogCount = domain.LogCount,
                Metadata = domain.Metadata,
                CreatedAt = domain.CreatedAt,
                UpdatedAt = domain.UpdatedAt,
                SyncedAt = DateTime.UtcNow // If coming from Domain (Remote), it is synced. 
            };
        }
        
        // --- UserPreferences ---

        public static UserPreferences ToDomain(this LocalUserPreferences local)
        {
            return new UserPreferences
            {
                Id = local.Id, 
                Theme = local.Theme,
                UnitSystem = (local.UnitSystem == "imperial") ? "imperial" : "metric", // Sanitize
                PressureUnit = local.PressureUnit,
                WindUnit = local.WindUnit,
                VisibilityUnit = local.VisibilityUnit,
                PrecipitationUnit = local.PrecipitationUnit,
                NotificationsEnabled = local.NotificationsEnabled,
                DailyForecastAlert = local.DailyForecastAlert,
                PrecipitationAlert = local.PrecipitationAlert,
                
                SmokesBaselineDaily = local.SmokesBaselineDaily,
                SmokesPackSize = local.SmokesPackSize,
                SmokesPackCost = local.SmokesPackCost,
                SmokesCurrency = local.SmokesCurrency,
                SmokesQuitDate = local.SmokesQuitDate,
                
                Interests = string.IsNullOrEmpty(local.InterestsJson) 
                            ? new List<string>() 
                            : System.Text.Json.JsonSerializer.Deserialize<List<string>>(local.InterestsJson) ?? new List<string>(),
                // Ensure UTC Kind for correct serialization
                UpdatedAt = DateTime.SpecifyKind(local.UpdatedAt, DateTimeKind.Utc) 
            };
        }

        public static LocalUserPreferences ToLocal(this UserPreferences domain)
        {
            return new LocalUserPreferences
            {
                Id = domain.Id,
                Theme = domain.Theme,
                UnitSystem = (domain.UnitSystem == "imperial") ? "imperial" : "metric",
                
                PressureUnit = domain.PressureUnit,
                WindUnit = domain.WindUnit,
                VisibilityUnit = domain.VisibilityUnit,
                PrecipitationUnit = domain.PrecipitationUnit,
                
                NotificationsEnabled = domain.NotificationsEnabled,
                DailyForecastAlert = domain.DailyForecastAlert,
                PrecipitationAlert = domain.PrecipitationAlert,
                
                SmokesBaselineDaily = domain.SmokesBaselineDaily,
                SmokesPackSize = domain.SmokesPackSize,
                SmokesPackCost = domain.SmokesPackCost,
                SmokesCurrency = domain.SmokesCurrency,
                SmokesQuitDate = domain.SmokesQuitDate,
                
                InterestsJson = System.Text.Json.JsonSerializer.Serialize(domain.Interests),
                UpdatedAt = domain.UpdatedAt
            };
        }

        // --- Helpers ---
        
        private static Guid GenerateGuid(string input)
        {
            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] hash = md5.ComputeHash(System.Text.Encoding.Default.GetBytes(input));
                return new Guid(hash);
            }
        }
    }
}
