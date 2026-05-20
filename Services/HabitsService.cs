using Daily.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Supabase.Realtime;

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

        private Supabase.Realtime.RealtimeChannel? _habitsLogsChannel;
        private Supabase.Realtime.RealtimeChannel? _habitsGoalsChannel;

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

        private readonly ISeederService _seederService;
        private readonly IRssFeedService _rssFeedService;

        public HabitsService(Supabase.Client supabase, ISettingsService settingsService, IRefreshService refreshService, IHabitsRepository repository, ISyncService syncService, ISeederService seederService, IRssFeedService rssFeedService)
        {
            _supabase = supabase;
            _settingsService = settingsService;
            _refreshService = refreshService;
            _repository = repository;
            _syncService = syncService;
            _seederService = seederService;
            _rssFeedService = rssFeedService;

            // Listen for Auth Changes to Trigger Migration
            _supabase.Auth.AddStateChangedListener((sender, state) =>
            {
               if (state == Supabase.Gotrue.Constants.AuthState.SignedIn)
               {
                   RunStartupMigration();
               }
            });

            if (_supabase.Auth.CurrentSession != null)
            {
                RunStartupMigration();
            }

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

        private void RunStartupMigration()
        {
            Task.Run(async () => 
            {
                try
                {
                    Console.WriteLine($"[HabitsService] User Signed In: {CurrentUserId}. Check for migration...");
                    await _repository.MigrateGuestDataAsync(CurrentUserId.ToString());
                    await _seederService.SeedRssFeedsAsync(CurrentUserId.ToString());
                    await _rssFeedService.InitializeCustomFeedsAsync();
                    await _syncService.SyncAsync();
                    OnHabitsUpdated?.Invoke();
                }
                catch(Exception ex)
                {
                    Console.WriteLine($"[HabitsService] Migration Error: {ex}");
                }
            });
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
             InvalidateRpcCache();
             _ = _syncService.PushAsync(); // Background
             OnHabitsUpdated?.Invoke();
        }

        public async Task DeleteLogAsync(Guid logId)
        {
            await _repository.DeleteLogAsync(logId);
            InvalidateRpcCache();
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

        public async Task<List<DailySummary>> GetHistoryAsync(string habitType, DateTime startDate, DateTime endDate)
        {
            return await _repository.GetDailyTotalsAsync(habitType, startDate, endDate, CurrentUserIdString);
        }

        public async Task InitializeAsync()
        {
             // Force check auth state and sync if needed
             if (IsAuthenticated)
             {
                 Console.WriteLine($"[HabitsService] Initialize: User {CurrentUserId} detected. Triggering Sync & Realtime...");
                 
                 // Ensure data migrations and seeds are run on startup if auto-hydrated
                 try 
                 {
                     await _repository.MigrateGuestDataAsync(CurrentUserId.ToString());
                     await _seederService.SeedRssFeedsAsync(CurrentUserId.ToString());
                 } 
                 catch(Exception ex) { Console.WriteLine($"[HabitsService] Init Migration Error: {ex}"); }

                 await _rssFeedService.InitializeCustomFeedsAsync();
                 
                 await _syncService.SyncAsync();
                 await SetupRealtimeAsync();
             }
             else
             {
                 Console.WriteLine("[HabitsService] Initialize: Guest mode.");
             }
        }

        private async Task SetupRealtimeAsync()
        {
            if (!IsAuthenticated) return;
            
            try 
            {
                if (_habitsLogsChannel == null)
                {
                    _habitsLogsChannel = _supabase.Realtime.Channel("realtime", "public", "habits_logs");
                    _habitsLogsChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnHabitLogReceived);
                    await _habitsLogsChannel.Subscribe();
                    Console.WriteLine("[HabitsService] Realtime subscribed to habits_logs");
                }

                if (_habitsGoalsChannel == null)
                {
                    _habitsGoalsChannel = _supabase.Realtime.Channel("realtime", "public", "habits_goals");
                    _habitsGoalsChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnHabitGoalReceived);
                    await _habitsGoalsChannel.Subscribe();
                    Console.WriteLine("[HabitsService] Realtime subscribed to habits_goals");
                }
            } 
            catch (Exception ex) 
            {
                Console.WriteLine($"[HabitsService] Realtime setup failed: {ex.Message}");
            }
        }

        private void OnHabitLogReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try 
            {
                var remoteLog = e.Model<HabitLog>();
                
                if (remoteLog != null && remoteLog.UserId == CurrentUserId)
                {
                    var localLog = remoteLog.ToLocal();
                    localLog.SyncedAt = DateTime.UtcNow; // Prevent sync push loop
                    InvalidateRpcCache();
                    _repository.SaveLocalLogAsync(localLog).ContinueWith(_ => OnHabitsUpdated?.Invoke());
                    Console.WriteLine($"[HabitsService] Realtime: Synced incoming habit log {localLog.Id}");
                }
            } 
            catch(Exception ex) { Console.WriteLine($"[HabitsService] Realtime Log Error: {ex}"); }
        }

        private void OnHabitGoalReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try 
            {
                var remoteGoal = e.Model<HabitGoal>();
                
                if (remoteGoal != null && remoteGoal.UserId == CurrentUserId)
                {
                    var localGoal = remoteGoal.ToLocal();
                    localGoal.SyncedAt = DateTime.UtcNow; // Prevent sync push loop
                    _repository.SaveLocalGoalAsync(localGoal).ContinueWith(_ => OnHabitsUpdated?.Invoke());
                    Console.WriteLine($"[HabitsService] Realtime: Synced incoming habit goal {localGoal.Id}");
                }
            } 
            catch(Exception ex) { Console.WriteLine($"[HabitsService] Realtime Goal Error: {ex}"); }
        }
        public async Task<Dictionary<string, int>> GetSmokesBreakdownAsync(DateTime sinceDate)
        {
            return await _repository.GetGlobalTypeBreakdownAsync("smokes", sinceDate, CurrentUserIdString);
        }

        // =====================================================
        // Server-Side Aggregation via Supabase RPC
        // =====================================================

        // Simple in-memory cache for RPC results
        private static readonly Dictionary<string, (DateTime CachedAt, object Data)> _rpcCache = new();
        private static readonly TimeSpan _cacheTtl = TimeSpan.FromMinutes(5);

        public async Task<List<DailySummary>> GetConsistencyAsync(string habitType, DateTime startDate, DateTime endDate)
        {
            var cacheKey = $"consistency_{habitType}_{startDate:yyyyMMdd}_{endDate:yyyyMMdd}_{CurrentUserIdString}";

            // Check cache
            if (_rpcCache.TryGetValue(cacheKey, out var cached) && (DateTime.UtcNow - cached.CachedAt) < _cacheTtl)
            {
                return (List<DailySummary>)cached.Data;
            }

            // Try RPC
            if (IsAuthenticated)
            {
                try
                {
                    var response = await _supabase.Rpc("get_habits_consistency", new Dictionary<string, object>
                    {
                        { "p_habit_type", habitType },
                        { "p_start_date", startDate.ToString("yyyy-MM-dd") },
                        { "p_end_date", endDate.ToString("yyyy-MM-dd") }
                    });

                    var json = response.Content;
                    if (!string.IsNullOrEmpty(json) && json != "null")
                    {
                        var items = JsonSerializer.Deserialize<List<ConsistencyRow>>(json, new JsonSerializerOptions 
                        { 
                            PropertyNameCaseInsensitive = true 
                        });

                        if (items != null)
                        {
                            var result = items.Select(r => new DailySummary
                            {
                                Id = Guid.Empty,
                                UserId = CurrentUserId,
                                HabitType = habitType,
                                Date = r.Day,
                                TotalValue = r.TotalValue,
                                LogCount = r.LogCount
                            }).ToList();

                            // Cache the result
                            _rpcCache[cacheKey] = (DateTime.UtcNow, result);
                            Console.WriteLine($"[HabitsService] RPC consistency: Got {result.Count} days for {habitType}");
                            return result;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] RPC consistency fallback to local: {ex.Message}");
                }
            }

            // Fallback to local
            return await GetHistoryAsync(habitType, startDate, endDate);
        }

        public async Task<(double TotalSmoked, int DaysTracked)> GetSmokesFinancialsAsync(DateTime sinceDate)
        {
            var cacheKey = $"financials_smokes_{sinceDate:yyyyMMdd}_{CurrentUserIdString}";

            // Check cache
            if (_rpcCache.TryGetValue(cacheKey, out var cached) && (DateTime.UtcNow - cached.CachedAt) < _cacheTtl)
            {
                return ((double, int))cached.Data;
            }

            // Try RPC
            if (IsAuthenticated)
            {
                try
                {
                    var response = await _supabase.Rpc("get_smokes_financials", new Dictionary<string, object>
                    {
                        { "p_since_date", sinceDate.ToUniversalTime().ToString("o") }
                    });

                    var json = response.Content;
                    if (!string.IsNullOrEmpty(json) && json != "null")
                    {
                        var data = JsonSerializer.Deserialize<SmokesFinancialsRow>(json, new JsonSerializerOptions 
                        { 
                            PropertyNameCaseInsensitive = true 
                        });

                        if (data != null)
                        {
                            var result = (data.TotalSmoked, data.DaysTracked);
                            _rpcCache[cacheKey] = (DateTime.UtcNow, result);
                            Console.WriteLine($"[HabitsService] RPC financials: {data.TotalSmoked} smokes over {data.DaysTracked} days");
                            return result;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[HabitsService] RPC financials fallback to local: {ex.Message}");
                }
            }

            // Fallback to local breakdown
            var breakdown = await GetSmokesBreakdownAsync(sinceDate);
            var totalSmoked = breakdown.Values.Sum();
            var daysTracked = (int)(DateTime.Today - sinceDate.Date).TotalDays + 1;
            return (totalSmoked, daysTracked);
        }

        /// <summary>Invalidate RPC cache (e.g., after logging a new entry)</summary>
        private void InvalidateRpcCache()
        {
            _rpcCache.Clear();
        }

        // JSON deserialization models for RPC responses
        private class ConsistencyRow
        {
            public DateTime Day { get; set; }
            public double TotalValue { get; set; }
            public int LogCount { get; set; }

            [System.Text.Json.Serialization.JsonPropertyName("total_value")]
            public double TotalValueJson { set => TotalValue = value; }
            [System.Text.Json.Serialization.JsonPropertyName("log_count")]
            public int LogCountJson { set => LogCount = value; }
        }

        private class SmokesFinancialsRow
        {
            public double TotalSmoked { get; set; }
            public int DaysTracked { get; set; }

            [System.Text.Json.Serialization.JsonPropertyName("total_smoked")]
            public double TotalSmokedJson { set => TotalSmoked = value; }
            [System.Text.Json.Serialization.JsonPropertyName("days_tracked")]
            public int DaysTrackedJson { set => DaysTracked = value; }
        }
    }
}
