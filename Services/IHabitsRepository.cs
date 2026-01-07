using Daily.Models;

namespace Daily.Services
{
    public interface IHabitsRepository
    {
        Task<List<HabitLog>> GetLogsAsync(string habitType, DateTime date, string userId);
        Task SaveLogAsync(HabitLog log);
        Task DeleteLogAsync(Guid logId);

        Task<HabitGoal?> GetGoalAsync(string habitType, string userId);
        Task SaveGoalAsync(HabitGoal goal);

        Task MigrateGuestDataAsync(string newUserId);

        // Aggregation Methods
        Task<List<DailySummary>> GetDailyTotalsAsync(string habitType, DateTime startDate, DateTime endDate, string userId);
        Task<DailySummary> GetGlobalTotalsAsync(string habitType, string userId);
    }
}
