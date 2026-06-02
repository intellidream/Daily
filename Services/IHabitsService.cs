using Daily.Models;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IHabitsService
    {
        event Action OnHabitsUpdated;
        
        // Navigation State
        string CurrentViewType { get; set; } // "water" or "smokes"
        event Action OnViewTypeChanged;

        Task<HabitGoal> GetGoalAsync(string habitType);
        Task UpdateGoalAsync(string habitType, double target, string unit);
        
        Task<List<HabitLog>> GetLogsAsync(string habitType, DateTime date);
        Task AddLogAsync(string habitType, double value, string unit, DateTime loggedAt, string? metadata = null);
        Task DeleteLogAsync(Guid logId);
        
        Task<double> GetDailyProgressAsync(string habitType, DateTime date);

        Task<Dictionary<string, double>> GetDailyBreakdownAsync(string habitType, DateTime date);
        
        Task<List<DailySummary>> GetHistoryAsync(string habitType, DateTime startDate, DateTime endDate);
        
        /// <summary>
        /// Server-side aggregation via Supabase RPC. Returns daily totals for a habit type
        /// over a date range. Falls back to local GetHistoryAsync if offline.
        /// </summary>
        Task<List<DailySummary>> GetConsistencyAsync(string habitType, DateTime startDate, DateTime endDate);
        
        /// <summary>
        /// Server-side aggregation via Supabase RPC. Returns total smokes and days tracked
        /// since the given date. Falls back to local GetSmokesBreakdownAsync if offline.
        /// </summary>
        Task<(double TotalSmoked, int DaysTracked)> GetSmokesFinancialsAsync(DateTime sinceDate);
        
        Task InitializeAsync(bool forceRecreateRealtime = false);
        
        Task<Dictionary<string, int>> GetSmokesBreakdownAsync(DateTime sinceDate);
    }
}
