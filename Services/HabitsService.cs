using Daily.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class HabitsService : IHabitsService
    {
        private readonly Supabase.Client _supabase;
        private readonly ISettingsService _settingsService;
        private readonly IRefreshService _refreshService;
        
        public event Action OnHabitsUpdated;

        // In-memory fallback for Guest mode
        private readonly Dictionary<string, HabitGoal> _guestGoals = new();
        private readonly List<HabitLog> _guestLogs = new();

        public HabitsService(Supabase.Client supabase, ISettingsService settingsService, IRefreshService refreshService)
        {
            _supabase = supabase;
            _settingsService = settingsService;
            _refreshService = refreshService;

            // Default guest goal for Water
            _guestGoals["water"] = new HabitGoal 
            { 
                HabitType = "water", 
                TargetValue = 2000, 
                Unit = "ml" 
            };

            // Listen for global refresh (triggered by Auth/Settings changes)
            _refreshService.RefreshRequested += async () =>
            {
                if (IsAuthenticated)
                {
                    // Reset guest data on login/refresh to avoid confusion
                    _guestLogs.Clear();
                    _guestGoals.Clear();
                }
                // Notify UI to refresh
                OnHabitsUpdated?.Invoke();
                await Task.CompletedTask;
            };
        }

        // Robust check: Session exists AND User is populated
        private bool IsAuthenticated => _supabase.Auth.CurrentSession != null && _supabase.Auth.CurrentUser != null;

        public async Task<HabitGoal> GetGoalAsync(string habitType)
        {
            if (IsAuthenticated)
            {
                try
                {
                    var result = await _supabase.From<HabitGoal>()
                        .Where(g => g.HabitType == habitType)
                        .Single();
                    
                    if (result != null) return result;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] GetGoal Error: {ex.Message}");
                    // Fallback to default if fetch fails
                }

                // If no goal found or error, return default
                return new HabitGoal { HabitType = habitType, TargetValue = 2000, Unit = "ml" };
            }
            else
            {
                return _guestGoals.ContainsKey(habitType) ? _guestGoals[habitType] : new HabitGoal { HabitType = habitType, TargetValue = 2000, Unit = "ml" };
            }
        }

        public async Task UpdateGoalAsync(string habitType, double target, string unit)
        {
            if (IsAuthenticated)
            {
                try
                {
                    var userId = Guid.Parse(_supabase.Auth.CurrentUser.Id);
                    var goal = new HabitGoal
                    {
                        UserId = userId,
                        HabitType = habitType,
                        TargetValue = target,
                        Unit = unit,
                        UpdatedAt = DateTime.UtcNow
                    };
                    await _supabase.From<HabitGoal>().Upsert(goal);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] UpdateGoal Error: {ex.Message}");
                }
            }
            else
            {
                _guestGoals[habitType] = new HabitGoal { HabitType = habitType, TargetValue = target, Unit = unit };
            }
            OnHabitsUpdated?.Invoke();
        }

        public async Task<List<HabitLog>> GetLogsAsync(string habitType, DateTime date)
        {
            var start = date.Date;
            var end = start.AddDays(1);

            if (IsAuthenticated)
            {
                try
                {
                    var result = await _supabase.From<HabitLog>()
                        .Where(l => l.HabitType == habitType && l.LoggedAt >= start && l.LoggedAt < end)
                        .Order("logged_at", global::Supabase.Postgrest.Constants.Ordering.Descending)
                        .Get();

                    return result.Models;
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] GetLogs Error: {ex.Message}");
                    return new List<HabitLog>();
                }
            }
            else
            {
                return _guestLogs
                    .Where(l => l.HabitType == habitType && l.LoggedAt >= start && l.LoggedAt < end)
                    .OrderByDescending(l => l.LoggedAt)
                    .ToList();
            }
        }

        public async Task AddLogAsync(string habitType, double value, string unit, DateTime loggedAt, string? metadata = null)
        {
            if (IsAuthenticated)
            {
                try
                {
                    var userId = Guid.Parse(_supabase.Auth.CurrentUser.Id);
                    var log = new HabitLog
                    {
                        UserId = userId,
                        HabitType = habitType,
                        Value = value,
                        Unit = unit,
                        LoggedAt = loggedAt.ToUniversalTime(),
                        Metadata = metadata
                    };
                    await _supabase.From<HabitLog>().Insert(log);
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] AddLog Error: {ex.Message}");
                }
            }
            else
            {
                _guestLogs.Add(new HabitLog
                {
                    Id = Guid.NewGuid(),
                    HabitType = habitType,
                    Value = value,
                    Unit = unit,
                    LoggedAt = loggedAt,
                    Metadata = metadata
                });
            }
            OnHabitsUpdated?.Invoke();
        }

        public async Task DeleteLogAsync(Guid logId)
        {
            if (IsAuthenticated)
            {
                try
                {
                    await _supabase.From<HabitLog>()
                        .Where(l => l.Id == logId)
                        .Delete();
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] DeleteLog Error: {ex.Message}");
                }
            }
            else
            {
                var item = _guestLogs.FirstOrDefault(l => l.Id == logId);
                if (item != null) _guestLogs.Remove(item);
            }
            OnHabitsUpdated?.Invoke();
        }

        public async Task<double> GetDailyProgressAsync(string habitType, DateTime date)
        {
            var logs = await GetLogsAsync(habitType, date);
            return logs.Sum(l => l.Value);
        }

        public async Task<Dictionary<string, double>> GetDailyBreakdownAsync(string habitType, DateTime date)
        {
            var logs = await GetLogsAsync(habitType, date);
            // ... (rest of logic same as before, no Supabase call here)
            var breakdown = new Dictionary<string, double>();

            foreach (var log in logs)
            {
                string drinkName = "Water";
                if (!string.IsNullOrEmpty(log.Metadata))
                {
                    try
                    {
                        if (log.Metadata.Contains("\"drink\":"))
                        {
                            var parts = log.Metadata.Split(new[] { "\"drink\":" }, StringSplitOptions.RemoveEmptyEntries);
                            if (parts.Length > 1)
                            {
                                var val = parts[1].Trim().Trim(new[] { ' ', '}', '"' });
                                if (!string.IsNullOrEmpty(val)) drinkName = val;
                            }
                        }
                    }
                    catch { }
                }

                if (!breakdown.ContainsKey(drinkName)) breakdown[drinkName] = 0;
                breakdown[drinkName] += log.Value;
            }

            return breakdown;
        }
    }
}
