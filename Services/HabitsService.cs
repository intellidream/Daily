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
        private readonly IHabitsRepository _repository;
        private readonly ISyncService _syncService;
        
        public event Action OnHabitsUpdated;
        public event Action OnViewTypeChanged;

        private string _currentViewType = "water"; // Default to "water"
        public string CurrentViewType
        {
            get => _currentViewType;
            set
            {
                if (_currentViewType != value)
                {
                    _currentViewType = value;
                    OnViewTypeChanged?.Invoke();
                }
            }
        }

        public HabitsService(Supabase.Client supabase, ISettingsService settingsService, IRefreshService refreshService, IHabitsRepository repository, ISyncService syncService)
        {
            _supabase = supabase;
            _settingsService = settingsService;
            _refreshService = refreshService;
            _repository = repository;
            _syncService = syncService;

            // Listen for Auth Changes to Trigger Migration
            _supabase.Auth.AddStateChangedListener((sender, state) =>
            {
               if (state == Supabase.Gotrue.Constants.AuthState.SignedIn)
               {
                   Task.Run(async () => 
                   {
                       try
                       {
                           Console.WriteLine($"[HabitsService] User Signed In: {CurrentUserId}. Check for migration...");
                           await _repository.MigrateGuestDataAsync(CurrentUserId.ToString());
                           await _syncService.SyncAsync();
                           OnHabitsUpdated?.Invoke();
                       }
                       catch(Exception ex)
                       {
                           Console.WriteLine($"[HabitsService] Migration Error: {ex}");
                       }
                   });
               }
            });

            // Listen for global refresh (triggered by Auth/Settings changes)
            _refreshService.RefreshRequested += async () =>
            {
                // Trigger Full Sync on refresh/login if online
                if (IsAuthenticated)
                {
                    _ = _syncService.SyncAsync();
                }
                OnHabitsUpdated?.Invoke();
            };
        }

        private bool IsAuthenticated => _supabase.Auth.CurrentSession != null && _supabase.Auth.CurrentUser != null;
        private Guid CurrentUserId => IsAuthenticated ? Guid.Parse(_supabase.Auth.CurrentUser.Id) : Guid.Empty; 
        
        // Fix: Use Guid.Empty string for guest to match Write logic
        private string CurrentUserIdString => IsAuthenticated ? _supabase.Auth.CurrentUser.Id : Guid.Empty.ToString();

        public async Task<HabitGoal> GetGoalAsync(string habitType)
        {
            var goal = await _repository.GetGoalAsync(habitType, CurrentUserIdString);
            if (goal == null)
            {
                return new HabitGoal 
                { 
                    HabitType = habitType, 
                    TargetValue = 2000, 
                    Unit = "ml",
                    UserId = CurrentUserId // Even if empty
                };
            }
            return goal;
        }

        public async Task UpdateGoalAsync(string habitType, double target, string unit)
        {
             var goal = await _repository.GetGoalAsync(habitType, CurrentUserIdString);
             if (goal == null)
             {
                 goal = new HabitGoal 
                 { 
                     HabitType = habitType,
                     Id = Guid.NewGuid(),
                     UserId = CurrentUserId, 
                     CreatedAt = DateTime.UtcNow 
                 };
             }
             
             // Update fields
             goal.UserId = CurrentUserId; 
             goal.TargetValue = target;
             goal.Unit = unit;
             goal.UpdatedAt = DateTime.UtcNow;
             goal.SyncedAt = null; // Mark dirty

             await _repository.SaveGoalAsync(goal);
             _ = _syncService.PushAsync(); // Background
             OnHabitsUpdated?.Invoke();
        }

        public async Task<List<HabitLog>> GetLogsAsync(string habitType, DateTime date)
        {
            return await _repository.GetLogsAsync(habitType, date, CurrentUserIdString);
        }

        public async Task AddLogAsync(string habitType, double value, string unit, DateTime loggedAt, string? metadata = null)
        {
             var log = new HabitLog
             {
                 Id = Guid.NewGuid(),
                 UserId = CurrentUserId,
                 HabitType = habitType,
                 Value = value,
                 Unit = unit,
                 LoggedAt = loggedAt.ToUniversalTime(),
                 Metadata = metadata,
                 CreatedAt = DateTime.UtcNow,
                 SyncedAt = null // Mark dirty
             };

             await _repository.SaveLogAsync(log);
             _ = _syncService.PushAsync(); // Background
             OnHabitsUpdated?.Invoke();
        }

        public async Task DeleteLogAsync(Guid logId)
        {
            await _repository.DeleteLogAsync(logId);
            _ = _syncService.PushAsync(); // Background
            OnHabitsUpdated?.Invoke();
        }

        // Helper methods (kept compatible with interface)
        public async Task<double> GetDailyProgressAsync(string habitType, DateTime date)
        {
            var logs = await GetLogsAsync(habitType, date);
            return logs.Sum(l => l.Value);
        }

        public async Task<Dictionary<string, double>> GetDailyBreakdownAsync(string habitType, DateTime date)
        {
            var logs = await GetLogsAsync(habitType, date);
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
