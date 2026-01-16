using Daily.Models;
using System.Diagnostics;

namespace Daily.Services
{
    public class SyncService : ISyncService
    {
        private readonly Supabase.Client _supabase;
        private readonly IDatabaseService _databaseService;
        private readonly Daily.Services.Health.IHealthService _healthService; // Injected

        public SyncService(Supabase.Client supabase, IDatabaseService databaseService, Daily.Services.Health.IHealthService healthService)
        {
            _supabase = supabase;
            _databaseService = databaseService;
            _healthService = healthService;
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
                // 0. Sync Health (Native -> Cloud)
                // This ensures Supabase has the latest before we do anything else
                try { await _healthService.SyncNativeHealthDataAsync(); } 
                catch (Exception hex) { Console.WriteLine($"[SyncService] Health Sync Warning: {hex.Message}"); }

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
                        try { remoteLogs.Add(d.ToDomain()); }
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
                        try { remoteGoals.Add(d.ToDomain()); }
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

            // 5. Data Safety / Cost Management: Always check if we can prune old remote logs
            await PruneRemoteLogsAsync(userId);
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

            // 1. Pull Logs (Paginated to get all ~90 days of history ~2000 items)
            try {
                Console.Error.WriteLine($"[SyncService] Pulling Logs for User: {userId}...");
                
                int rangeStart = 0;
                int rangeEnd = 999;
                bool hasMore = true;

                while(hasMore)
                {
                    Console.Error.WriteLine($"[SyncService] Pulling Logs range {rangeStart}-{rangeEnd}...");
                    
                    var response = await _supabase.From<HabitLog>()
                        .Order("logged_at", global::Supabase.Postgrest.Constants.Ordering.Descending)
                        .Range(rangeStart, rangeEnd)
                        .Get();

                    int count = response.Models.Count;
                    if (count > 0)
                    {
                         Console.Error.WriteLine($"[SyncService] Pulled {count} logs (Batch).");
                         totalPulled += count;

                         // Prepare data in memory first
                         var localBatch = response.Models.Select(m => {
                             var l = m.ToLocal();
                             l.SyncedAt = DateTime.UtcNow;
                             return l;
                         }).ToList();

                         // Batch Insert (High Performance)
                         await _databaseService.Connection.RunInTransactionAsync(tran => 
                         {
                             foreach(var item in localBatch)
                             {
                                 tran.InsertOrReplace(item);
                             }
                         });

                         // Prepare next batch
                         rangeStart += 1000;
                         rangeEnd += 1000;
                    }

                    if (count < 1000)
                    {
                        hasMore = false;
                    }
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
                    var local = remote.ToLocal();
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

        // Mappers
        // Using Services.Mappers Extensions

        // --- Preferences Sync Logic ---

        // --- Helper for Debugging ---
        // --- Helper for Debugging ---
        public string DebugLog { get; private set; } = "";
        public event Action? OnDebugLogUpdated;

        public void Log(string message) => LogDebug(message);

        private void LogDebug(string message)
        {
            var logLine = $"{DateTime.Now:O}: {message}";
            Console.WriteLine(message);
            
            // In-Memory Log (Last 10 KB to avoid overflow)
            DebugLog += logLine + "\n";
            if (DebugLog.Length > 20000) 
            {
                DebugLog = DebugLog.Substring(DebugLog.Length - 20000);
            }
            
            OnDebugLogUpdated?.Invoke();

            try
            {
                var path = Path.Combine(FileSystem.CacheDirectory, "sync_debug.log");
                File.AppendAllText(path, logLine + "\n");
            }
            catch { /* Ignore logging errors */ }
        }

        private async Task PushPreferencesAsync(string userId)
        {
            LogDebug($"[SyncService] PushPreferencesAsync Started for {userId}");
            // DEBUG: Check all local prefs
            var allPrefs = await _databaseService.Connection.Table<LocalUserPreferences>().ToListAsync();
            LogDebug($"[SyncService] Total Local Prefs: {allPrefs.Count}. IDs: {string.Join(", ", allPrefs.Select(x => $"{x.Id} (Synced: {x.SyncedAt}, Updated: {x.UpdatedAt})"))}");

            var dirtyPrefs = await _databaseService.Connection.Table<LocalUserPreferences>()
                                .Where(p => p.SyncedAt == null && p.Id == userId)
                                .ToListAsync();

            LogDebug($"[SyncService] Dirty Prefs for {userId}: {dirtyPrefs.Count}");

            if (dirtyPrefs.Any())
            {
                LastSyncMessage += $"Found {dirtyPrefs.Count} dirty prefs. ";
                LogDebug($"[SyncService] Pushing {dirtyPrefs.Count} dirty preferences...");
                
                int pushedCount = 0;
                foreach (var local in dirtyPrefs)
                {
                    try
                    {
                        var remote = local.ToDomain();
                        
                        // --- CONFLICT RESOLUTION ---
                        // Check Remote State before Overwriting
                        bool skipPush = false;
                        try 
                        {
                            var existing = await _supabase.From<UserPreferences>()
                                .Select("updated_at")
                                .Where(x => x.Id == userId)
                                .Single();
                            
                            if (existing != null)
                            {
                                // Remote exists. Compare timestamps.
                                // If Remote UpdatedAt > Local UpdatedAt (w/ 1s Buffer for precision errors), Server Wins.
                                
                                // FIX: Local UpdatedAt is STORED as UTC but retrieved as Unspecified.
                                // Do NOT call ToUniversalTime() on it, or it will double-convert (Local->UTC).
                                var localTime = DateTime.SpecifyKind(local.UpdatedAt, DateTimeKind.Utc);
                                
                                // Remote is usually ISO8601 UTC, but ensure Kind is UTC.
                                var remoteTime = existing.UpdatedAt.ToUniversalTime();

                                LogDebug($"[SyncService] CONFLICT CHECK:");
                                LogDebug($"   Local ID: {local.Id} | UpdatedAt: {localTime:O} (Ticks: {localTime.Ticks})");
                                LogDebug($"   Remote ID: {existing.Id} | UpdatedAt: {remoteTime:O} (Ticks: {remoteTime.Ticks})");
                                var diff = remoteTime - localTime;
                                LogDebug($"   Diff (Remote - Local): {diff.TotalSeconds} seconds");

                                if (remoteTime > localTime.AddSeconds(1)) // 1s buffer for SQLite trunc
                                {
                                    LogDebug($"[SyncService] DECISION: REMOTE WIN. Remote is newer by {diff.TotalSeconds:F2}s. Skipping Push & Pulling.");
                                    skipPush = true;
                                    
                                    var fullRemote = await _supabase.From<UserPreferences>().Where(x => x.Id == userId).Single();
                                    if (fullRemote != null)
                                    {
                                        var updatedLocal = fullRemote.ToLocal();
                                        updatedLocal.SyncedAt = DateTime.UtcNow;
                                        await _databaseService.Connection.InsertOrReplaceAsync(updatedLocal);
                                        LogDebug($"[SyncService] Conflict Resolved: Pulled Remote Version.");
                                    }
                                }
                                else
                                {
                                    LogDebug($"[SyncService] DECISION: LOCAL WIN. Local is Newer or Equal. Proceeding with Push.");
                                }
                            }
                        }
                        catch (InvalidOperationException) 
                        { 
                            // .Single() throws if no elements. This means no remote record.
                            // Safe to Push.
                        }
                        catch (Exception checkEx)
                        {
                            LogDebug($"[SyncService] Conflict Check Warning: {checkEx.Message}. Proceeding with push.");
                        }

                        if (!skipPush)
                        {
                            // Create or Overwrite (We are newer or new)
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
                                 LogDebug(LastSyncError);
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        LastSyncError = $"Push Error for {local.Id}: {ex.Message}";
                        LogDebug($"[SyncService] {LastSyncError}");
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
                
                int successfulMergess = 0;
                foreach (var remote in response.Models)
                {
                    // Check Local State
                    var local = await _databaseService.Connection.Table<LocalUserPreferences>()
                                    .Where(x => x.Id == userId)
                                    .FirstOrDefaultAsync();

                    bool shouldOverwrite = true;
                    if (local != null)
                    {
                        // 1. If Local is Dirty, we generally trust local unless conflict resolution says otherwise.
                        // However, conflict resolution usually happens on Push. 
                        // If we are strictly Pulling, and find a conflict (Remote Newer vs Local Dirty), 
                        // usually Server Wins if we want eventual consistency, OR we keep local if we assume Push will happen later.
                        
                        // But here's the specific fix for "Settings not saving":
                        // If Local.UpdatedAt is NEWER than Remote.UpdatedAt, DO NOT OVERWRITE.
                        
                        if (local.UpdatedAt >= remote.UpdatedAt)
                        {
                            Console.WriteLine($"[SyncService] Pull Ignored: Local ({local.UpdatedAt}) is newer/equal to Remote ({remote.UpdatedAt}).");
                            shouldOverwrite = false;
                        }
                    }

                    if (shouldOverwrite)
                    {
                        var newLocal = remote.ToLocal();
                        newLocal.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.InsertOrReplaceAsync(newLocal);
                        successfulMergess++;
                    }
                }
                Console.WriteLine($"[SyncService] Pull Preferences Complete. Merged {successfulMergess} records.");
                return successfulMergess;
            }
            catch(Exception e) 
            { 
                Console.WriteLine("[SyncService] Pull Preferences Error: " + e); 
                return 0;
            }
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
                 var remoteList = dirty.Select(x => x.ToDomain()).ToList();
                 
                 try 
                 {
                     await _supabase.From<DailySummary>().Upsert(remoteList);
                     
                     foreach(var s in dirty)
                     {
                         s.SyncedAt = DateTime.UtcNow;
                         await _databaseService.Connection.UpdateAsync(s);
                     }
                     Console.WriteLine("[SyncService] Push Summaries Success.");
                  }
                  catch(Exception ex)
                  {
                      Console.WriteLine($"[SyncService] Push Summaries Failed: {ex.Message}");
                  }
              }
        }

        private async Task PruneRemoteLogsAsync(string userId)
        {
            try
            {
                // Safety Threshold: 90 Days
                var thresholdDate = DateTime.UtcNow.AddDays(-90);

                // 1. Get the latest date of a SAFELY SYNCED summary from local DB
                // We only trust our local state if it says it's synced.
                var latestSyncedSummary = await _databaseService.Connection.Table<LocalDailySummary>()
                                            .Where(s => s.UserId == userId && s.SyncedAt != null)
                                            .OrderByDescending(s => s.Date)
                                            .FirstOrDefaultAsync();

                if (latestSyncedSummary == null)
                {
                    Console.WriteLine("[SyncService] Pruning Aborted: No synced summaries found.");
                    return;
                }

                // 2. Determine Safe Prune Date based on Min(Threshold, LatestSummary)
                // We must NOT delete logs that are newer than our latest summary (even if they are > 90 days old, though unlikely)
                // We must NOT delete logs that are newer than 90 days (Business Rule)
                
                // Use the Date from the summary (Midnight). 
                // LoggedAt is exact time. If summary is for 2023-01-01, it covers 2023-01-01 00:00 to 23:59.
                // It is SAFE to delete logs < 2023-01-02 00:00? No, that's previous day.
                // If we summarized 2023-01-01, we extracted all logs for that day. 
                // So logs with LoggedAt < 2023-01-02 00:00 are theoretically safe.
                // However, let's differ to strict less than Date (Midnight) to be super safe 
                // (i.e. if summary date is Jan 1, we prune strictly < Jan 1, meaning up to Dec 31).
                
                var latestSummaryDate = latestSyncedSummary.Date;
                
                var safePruneDate = (latestSummaryDate < thresholdDate) ? latestSummaryDate : thresholdDate;
                
                Console.WriteLine($"[SyncService] Pruning Check: Threshold={thresholdDate:d}, LatestSummary={latestSummaryDate:d}. SafeDate={safePruneDate:d}");

                // 3. Execute Deletion on Supabase
                // "Delete from habits_logs where logged_at < safePruneDate"
                // Using PostgREST filtering
                await _supabase.From<HabitLog>()
                    .Where(x => x.LoggedAt < safePruneDate) // Strict Less Than
                    //.Where(x => x.UserId == Guid.Parse(userId)) // RLS handles this, but explicit doesn't hurt. 
                                                                  // Actually PostgREST client might fail if we filter by a field not in the model? 
                                                                  // HabitLog has UserId.
                    .Delete();
                    
                Console.WriteLine($"[SyncService] Pruning Command Sent. Remote logs older than {safePruneDate:d} should be deleted.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SyncService] Pruning Failed: {ex.Message}");
            }
        }

        private async Task<int> PullSummariesAsync(string userId)
        {
             try 
             {
                 // Pagination loop to fetch all summaries (likely > 1000)
                 int rangeStart = 0;
                 int rangeEnd = 999;
                 int totalPulled = 0;
                 bool hasMore = true;

                 while (hasMore)
                 {
                     Console.WriteLine($"[SyncService] Pulling Summaries range {rangeStart}-{rangeEnd}...");
                     
                     var userGuid = Guid.Parse(userId);
                     var response = await _supabase.From<DailySummary>()
                        .Where(x => x.UserId == userGuid)
                        .Range(rangeStart, rangeEnd)
                        .Get();

                     var count = response.Models.Count;
                     if (count > 0)
                     {
                         Console.WriteLine($"[SyncService] Pulled {count} summaries (Batch).");
                         
                         var localBatch = response.Models.Select(m => {
                             var l = m.ToLocal();
                             l.SyncedAt = DateTime.UtcNow;
                             return l;
                         }).ToList();

                         await _databaseService.Connection.RunInTransactionAsync(tran => 
                         {
                             foreach(var item in localBatch)
                             {
                                 tran.InsertOrReplace(item);
                             }
                         });
                         totalPulled += count;
                         
                         // Prepare next batch
                         rangeStart += 1000;
                         rangeEnd += 1000;
                     }
                     
                     if (count < 1000)
                     {
                         hasMore = false; // Less than full batch means we are done
                     }
                 }
                 
                 return totalPulled;
             }
             catch(Exception ex)
             {
                 Console.WriteLine($"[SyncService] Pull Summaries Error: {ex.Message}");
             }
             return 0;
        }
    }
}
