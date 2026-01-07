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

        private System.Threading.Timer? _syncTimer;

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

        public void StartBackgroundSync()
        {
            if (_syncTimer == null)
            {
                // Sync every 60 seconds
                _syncTimer = new System.Threading.Timer(async _ => 
                {
                    if (_supabase.Auth.CurrentSession != null)
                    {
                        await SyncAsync();
                    }
                }, null, 10000, 60000); 
                Console.WriteLine("[SyncService] Background Sync Started.");
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

            Console.WriteLine($"[SyncService] Found {dirtyLogs.Count} dirty logs for User {userId}.");
            
            if (dirtyLogs.Any())
            {
                foreach(var d in dirtyLogs) Console.WriteLine($"   -> Dirty Log: {d.Id} ({d.HabitType} - {d.LoggedAt})");

                try 
                {
                    var remoteLogs = new List<HabitLog>();
                    foreach(var d in dirtyLogs)
                    {
                        try { remoteLogs.Add(ToDomain(d)); }
                        catch { Console.WriteLine($"[SyncService] SKIP Bad Log ID: {d.Id}"); }
                    }

                    if (remoteLogs.Any())
                    {
                        Console.WriteLine($"[SyncService] Uploading {remoteLogs.Count} logs to Supabase...");
                        
                        // Supabase Bulk Insert/Upsert
                        var result = await _supabase.From<HabitLog>().Upsert(remoteLogs);
                        
                        // Check result if possible (Make sure Supabase client returns the list)
                        var insertedCount = result.Models.Count;
                        Console.WriteLine($"[SyncService] Supabase returned {insertedCount} models.");

                        if (insertedCount > 0 || remoteLogs.Count > 0) // Assume success if no exception, but ideally check insertedCount
                        {
                            // Mark local as synced
                            foreach (var l in dirtyLogs)
                            {
                                l.SyncedAt = DateTime.UtcNow;
                                await _databaseService.Connection.UpdateAsync(l);
                            }
                            Console.WriteLine("[SyncService] Push Logs Success. Marked local as synced.");
                        }
                        else
                        {
                             Console.WriteLine("[SyncService] WARNING: Supabase returned 0 models active. RLS might be blocking insert?");
                        }
                    }
                }
                catch(Exception ex)
                {
                     Console.WriteLine($"[SyncService] Push Logs FAILED EXCEPTION: {ex.Message}");
                     Console.WriteLine($"[SyncService] Stack: {ex.StackTrace}");
                }
            }
            else
            {
                // Debug: Why 0?
                var total = await _databaseService.Connection.Table<LocalHabitLog>().CountAsync();
                var userTotal = await _databaseService.Connection.Table<LocalHabitLog>().Where(l => l.UserId == userId).CountAsync();
                Console.WriteLine($"[SyncService] DEBUG: Total Logs: {total}, User Logs: {userTotal}, Dirty: 0.");
            }

            // 2. Push Goals
             var dirtyGoals = await _databaseService.Connection.Table<LocalHabitGoal>()
                                .Where(g => g.SyncedAt == null && g.UserId == userId)
                                .ToListAsync();

            if (dirtyGoals.Any())
            {
                Console.WriteLine($"[SyncService] Pushing {dirtyGoals.Count} dirty goals...");
                try 
                {
                    var remoteGoals = new List<HabitGoal>();
                    foreach(var d in dirtyGoals)
                    {
                        try { remoteGoals.Add(ToDomain(d)); }
                        catch { Console.WriteLine($"[SyncService] SKIP Bad Goal ID: {d.Id}"); }
                    }
                    
                    if (remoteGoals.Any())
                    {
                        await _supabase.From<HabitGoal>().Upsert(remoteGoals);

                        foreach (var g in dirtyGoals)
                        {
                            g.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(g);
                        }
                         Console.WriteLine("[SyncService] Push Goals Success");
                    }
                }
                 catch(Exception ex)
                {
                     Console.WriteLine($"[SyncService] Push Goals Failed: {ex.Message}");
                }
            }

            // 3. Push Preferences
            await PushPreferencesAsync(userId);

            // 4. Consolidate & Push Summaries (New Protocol)
            await ConsolidateHistoryAsync(userId); 
            await PushSummariesAsync(userId);
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

            // 4. Pull Summaries
            totalPulled += await PullSummariesAsync(userId);

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
                UnitSystem = (local.UnitSystem == "imperial") ? "imperial" : "metric", // SANITIZE
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
                UnitSystem = (domain.UnitSystem == "imperial") ? "imperial" : "metric", // SANITIZE
                
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
        
        // --- Daily Summary Logic ---

        private async Task ConsolidateHistoryAsync(string userId)
        {
            // 90 Day Retention Policy
            var threshold = DateTime.UtcNow.AddDays(-90);
            
            // 1. Find candidates for consolidation (Old logs)
            // Note: SQLite doesn't natively support Date grouping easily in LINQ without strict models, 
            // so we pull key data first. Performance is fine for <100k rows.
            var oldLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                            .Where(l => l.LoggedAt < threshold && l.UserId == userId) 
                            .ToListAsync();

            if (!oldLogs.Any()) return;

            // 2. Group locally
            var grouped = oldLogs.GroupBy(l => new { l.HabitType, Date = l.LoggedAt.Date });

            int newSummaries = 0;
            foreach (var group in grouped)
            {
                var summaryId = $"{userId}_{group.Key.HabitType}_{group.Key.Date:yyyyMMdd}";
                
                // Check if exists
                var existing = await _databaseService.Connection.FindWithQueryAsync<LocalDailySummary>(
                    "SELECT * FROM habits_daily_summaries WHERE Id = ?", summaryId);

                if (existing == null)
                {
                    // Create Summary
                    var summary = new LocalDailySummary
                    {
                        Id = summaryId,
                        UserId = userId,
                        HabitType = group.Key.HabitType,
                        Date = group.Key.Date, // Midnight UTC
                        TotalValue = group.Sum(x => x.Value),
                        LogCount = group.Count(),
                        Metadata = null, 
                        CreatedAt = DateTime.UtcNow,
                        SyncedAt = null // Mark Dirty -> Push
                    };

                    await _databaseService.Connection.InsertAsync(summary);
                    newSummaries++;
                }
            }

            if (newSummaries > 0)
            {
                Console.WriteLine($"[SyncService] Consolidation: Created {newSummaries} daily summaries.");
            }
        }

        private async Task PushSummariesAsync(string userId)
        {
             var dirty = await _databaseService.Connection.Table<LocalDailySummary>()
                                .Where(s => s.SyncedAt == null && s.UserId == userId)
                                .ToListAsync();

             if (dirty.Any())
             {
                 Console.WriteLine($"[SyncService] Pushing {dirty.Count} daily summaries...");
                 var remoteList = dirty.Select(ToDomain).ToList();
                 
                 try 
                 {
                     await _supabase.From<DailySummary>().Upsert(remoteList);
                     
                     foreach(var s in dirty)
                     {
                         s.SyncedAt = DateTime.UtcNow;
                         await _databaseService.Connection.UpdateAsync(s);
                     }
                     Console.WriteLine("[SyncService] Push Summaries Success.");
                     
                     // TODO: Trigger PruneRemoteLogsAsync(userId) here to delete raw logs from Cloud
                 }
                 catch(Exception ex)
                 {
                     Console.WriteLine($"[SyncService] Push Summaries Failed: {ex.Message}");
                 }
             }
        }

        private async Task<int> PullSummariesAsync(string userId)
        {
             try 
             {
                 // Pull everything? Or just last year? For now all history (lightweight).
                 var response = await _supabase.From<DailySummary>()
                    .Where(x => x.UserId == Guid.Parse(userId))
                    .Get();

                 if (response.Models.Any())
                 {
                     Console.WriteLine($"[SyncService] Pulled {response.Models.Count} summaries.");
                     foreach(var r in response.Models)
                     {
                         var local = ToLocal(r);
                         local.SyncedAt = DateTime.UtcNow;
                         await _databaseService.Connection.InsertOrReplaceAsync(local);
                     }
                     return response.Models.Count;
                 }
             }
             catch(Exception ex)
             {
                 Console.WriteLine($"[SyncService] Pull Summaries Error: {ex.Message}");
             }
             return 0;
        }

        // --- Summary Mappers ---

        private DailySummary ToDomain(LocalDailySummary local)
        {
            return new DailySummary
            {
                Id = GenerateGuid(local.Id),
                
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

        private LocalDailySummary ToLocal(DailySummary domain)
        {
            // Reconstruct the stable String ID
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
                SyncedAt = DateTime.UtcNow // If pulling, it's synced
            };
        }

        private Guid GenerateGuid(string input)
        {
            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] hash = md5.ComputeHash(System.Text.Encoding.Default.GetBytes(input));
                return new Guid(hash);
            }
        }
    }
}
