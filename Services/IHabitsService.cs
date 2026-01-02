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
    }
}
