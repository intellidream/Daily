using Daily.Models;
using System.Diagnostics;

namespace Daily.Services
{
    public class SyncService : ISyncService
    {
        private readonly Supabase.Client _supabase;
        private readonly IDatabaseService _databaseService;

        public SyncService(Supabase.Client supabase, IDatabaseService databaseService)
        {
            _supabase = supabase;
            _databaseService = databaseService;
        }

        public string? LastSyncError { get; private set; }
        public string LastSyncMessage { get; private set; } = "";

        public async Task SyncAsync()
        {
            LastSyncError = null;
            LastSyncMessage = "";
            if (_supabase.Auth.CurrentSession == null) return;

            try
            {
                await PushAsync();
                await PullAsync();
            }
            catch (Exception ex)
            {
                LastSyncError = ex.Message;
                Debug.WriteLine($"[SyncService] Sync Error: {ex}");
            }
        }

        public async Task PushAsync()
        {
            Console.WriteLine("[SyncService] PushAsync Started");
            await _databaseService.InitializeAsync();
             var userId = _supabase.Auth.CurrentUser?.Id;
            if (userId == null) 
            {
                Console.WriteLine("[SyncService] Push Aborted: No User");
                return;
            }

            // 1. Push Logs
            var dirtyLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                                .Where(l => l.SyncedAt == null && l.UserId == userId)
                                .ToListAsync();

            if (dirtyLogs.Any())
            {
                Console.WriteLine($"[SyncService] Pushing {dirtyLogs.Count} dirty logs...");
                var remoteLogs = dirtyLogs.Select(ToDomain).ToList();
                
                try 
                {
                    // Supabase Bulk Insert/Upsert
                    await _supabase.From<HabitLog>().Upsert(remoteLogs);

                    // Mark local as synced
                    foreach (var l in dirtyLogs)
                    {
                        l.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.UpdateAsync(l);
                    }
                    Console.WriteLine("[SyncService] Push Logs Success");
                }
                catch(Exception ex)
                {
                     Console.WriteLine($"[SyncService] Push Logs Failed: {ex.Message}");
                }
            }

            // 2. Push Goals
             var dirtyGoals = await _databaseService.Connection.Table<LocalHabitGoal>()
                                .Where(g => g.SyncedAt == null && g.UserId == userId)
                                .ToListAsync();

            if (dirtyGoals.Any())
            {
                Console.WriteLine($"[SyncService] Pushing {dirtyGoals.Count} dirty goals...");
                var remoteGoals = dirtyGoals.Select(ToDomain).ToList();
                try 
                {
                    await _supabase.From<HabitGoal>().Upsert(remoteGoals);

                    foreach (var g in dirtyGoals)
                    {
                        g.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.UpdateAsync(g);
                    }
                     Console.WriteLine("[SyncService] Push Goals Success");
                }
                 catch(Exception ex)
                {
                     Console.WriteLine($"[SyncService] Push Goals Failed: {ex.Message}");
                }
            }

            // 3. Push Preferences
            await PushPreferencesAsync(userId);
        }

        public async Task<int> PullAsync()
        {
            Console.WriteLine("[SyncService] PullAsync Started");
            await _databaseService.InitializeAsync();
             var userId = _supabase.Auth.CurrentUser?.Id;
            if (userId == null) 
            {
                Console.WriteLine("[SyncService] Pull Aborted: No User");
                return 0;
            }

            int totalPulled = 0;

            // 1. Pull Logs
            try {
                Console.Error.WriteLine($"[SyncService] Pulling Logs for User: {userId}...");
                var response = await _supabase.From<HabitLog>()
                    //.Where(x => x.UserId == Guid.Parse(userId)) // REMOVED: Rely on RLS
                    .Order("logged_at", global::Supabase.Postgrest.Constants.Ordering.Descending)
                    .Limit(100)
                    .Get();

                Console.Error.WriteLine($"[SyncService] Pulled {response.Models.Count} logs from Cloud.");
                totalPulled += response.Models.Count;

                foreach (var remote in response.Models)
                {
                    var local = ToLocal(remote);
                    local.SyncedAt = DateTime.UtcNow; 
                    await _databaseService.Connection.InsertOrReplaceAsync(local);
                }
                Console.Error.WriteLine("[SyncService] Pull Logs Local Save Complete.");
            } 
            catch(Exception e) { Console.Error.WriteLine("[SyncService] Pull Logs Error: " + e); }

            // 2. Pull Goals
            try {
                Console.WriteLine($"[SyncService] Pulling Goals for User: {userId}...");
                var goalResponse = await _supabase.From<HabitGoal>()
                    //.Where(x => x.UserId == Guid.Parse(userId)) // REMOVED: Rely on RLS
                    .Get();

                Console.WriteLine($"[SyncService] Pulled {goalResponse.Models.Count} goals from Cloud.");
                totalPulled += goalResponse.Models.Count;

                foreach (var remote in goalResponse.Models)
                {
                    var local = ToLocal(remote);
                    local.SyncedAt = DateTime.UtcNow;
                    await _databaseService.Connection.InsertOrReplaceAsync(local);
                }
                 Console.WriteLine("[SyncService] Pull Goals Local Save Complete.");
            }
            catch(Exception e) { Console.WriteLine("[SyncService] Pull Goals Error: " + e); }

            // 3. Pull Preferences
            totalPulled += await PullPreferencesAsync(userId);

            return totalPulled;
        }

        // Mappers (Duplicate from Repo? Maybe move Mappers to shared static? Or just copy for decoupled isolation)
        // Copying for now to avoid tight coupling or circular dependencies.
        private HabitLog ToDomain(LocalHabitLog local)
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
        
        private LocalHabitLog ToLocal(HabitLog domain)
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

        // ... (Previous Mappers) ...

        private HabitGoal ToDomain(LocalHabitGoal local)
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

        private LocalHabitGoal ToLocal(HabitGoal domain)
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

        // --- Preferences Sync Logic ---

        private async Task PushPreferencesAsync(string userId)
        {
            // DEBUG: Check all local prefs
            var allPrefs = await _databaseService.Connection.Table<LocalUserPreferences>().ToListAsync();
            Console.WriteLine($"[SyncService] Total Local Prefs: {allPrefs.Count}. IDs: {string.Join(", ", allPrefs.Select(x => $"{x.Id} (Synced: {x.SyncedAt})"))}");

            var dirtyPrefs = await _databaseService.Connection.Table<LocalUserPreferences>()
                                .Where(p => p.SyncedAt == null && p.Id == userId)
                                .ToListAsync();

            Console.WriteLine($"[SyncService] Dirty Prefs for {userId}: {dirtyPrefs.Count}");

            if (dirtyPrefs.Any())
            {
                LastSyncMessage += $"Found {dirtyPrefs.Count} dirty prefs. ";
                Console.WriteLine($"[SyncService] Pushing {dirtyPrefs.Count} dirty preferences...");
                
                int pushedCount = 0;
                foreach (var local in dirtyPrefs)
                {
                    try
                    {
                        var remote = ToDomain(local);
                        // Upsert individually to match reliable test behavior
                        var response = await _supabase.From<UserPreferences>().Upsert(remote);

                        if (response.Models.Count > 0)
                        {
                            local.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(local);
                            pushedCount++;
                        }
                        else
                        {
                             LastSyncError = $"Push Warning: 0 rows written for ID {local.Id}";
                        }
                    }
                    catch (Exception ex)
                    {
                        LastSyncError = $"Push Error for {local.Id}: {ex.Message}";
                        Console.WriteLine($"[SyncService] {LastSyncError}");
                    }
                }
                LastSyncMessage += $"Pushed {pushedCount}/{dirtyPrefs.Count}. ";
            }
            else 
            {
                LastSyncMessage += "No changes to push. ";
            }
        }

        private async Task<int> PullPreferencesAsync(string userId)
        {
             try {
                Console.WriteLine($"[SyncService] Pulling Preferences for User: {userId}...");
                var response = await _supabase.From<UserPreferences>()
                    .Where(x => x.Id == userId) // Valid for string ID
                    .Get();

                Console.WriteLine($"[SyncService] Pulled {response.Models.Count} preferences from Cloud.");
                
                foreach (var remote in response.Models)
                {
                    var local = ToLocal(remote);
                    local.SyncedAt = DateTime.UtcNow;
                    await _databaseService.Connection.InsertOrReplaceAsync(local);
                }
                Console.WriteLine("[SyncService] Pull Preferences Local Save Complete.");
                return response.Models.Count;
            }
            catch(Exception e) 
            { 
                Console.WriteLine("[SyncService] Pull Preferences Error: " + e); 
                return 0;
            }
        }

        private UserPreferences ToDomain(LocalUserPreferences local)
        {
            return new UserPreferences
            {
                Id = local.Id, // String ID
                Theme = local.Theme,
                UnitSystem = local.UnitSystem,
                PressureUnit = local.PressureUnit,
                Interests = string.IsNullOrEmpty(local.InterestsJson) 
                            ? new List<string>() 
                            : System.Text.Json.JsonSerializer.Deserialize<List<string>>(local.InterestsJson) ?? new List<string>(),
                
                // Mapped properties
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
                
                // Base properties not stored in Local but needed for domain? 
                // LocalUserPreferences doesn't have CreatedAt/UpdatedAt in definition currently, should check.
                // Assuming defaults or nulls.
            };
        }

        private LocalUserPreferences ToLocal(UserPreferences domain)
        {
            return new LocalUserPreferences
            {
                Id = domain.Id,
                Theme = domain.Theme,
                UnitSystem = domain.UnitSystem,
                
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
                
                InterestsJson = System.Text.Json.JsonSerializer.Serialize(domain.Interests)
            };
        }
    }
}
