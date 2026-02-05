using Daily.Models;
using Daily.Models.Finances;
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
            
            // 4. Push Finances (Accounts & Transactions & Holdings)
            await PushAccountsAsync(userId);
            await PushTransactionsAsync(userId);
            await PushHoldingsAsync(userId);

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
            
            // 4. Pull Finances
            totalPulled += await PullAccountsAsync(userId);
            totalPulled += await PullTransactionsAsync(userId);
            totalPulled += await PullHoldingsAsync(userId);

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
              return 0;
         }

        // ==========================================
        // Finance Sync Logic
        // ==========================================

        private async Task PushAccountsAsync(string userId)
        {
            var dirty = await _databaseService.Connection.Table<LocalAccount>()
                                .Where(a => a.SyncedAt == null && a.UserId == userId)
                                .ToListAsync();
            
            if (dirty.Any())
            {
                Console.WriteLine($"[SyncService] Pushing {dirty.Count} Accounts...");
                var remoteList = dirty.Select(MapToRemote).ToList();
                try 
                {
                    await _supabase.From<Account>().Upsert(remoteList);
                    foreach(var a in dirty)
                    {
                        a.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.UpdateAsync(a);
                    }
                    Console.WriteLine("[SyncService] Push Accounts Success.");
                }
                catch(Exception ex) { Console.WriteLine($"[SyncService] Push Accounts Failed: {ex.Message}"); }
            }
        }

        private async Task<int> PullAccountsAsync(string userId)
        {
            try 
            {
                var response = await _supabase.From<Account>().Where(a => a.UserId == Guid.Parse(userId)).Get();
                int count = response.Models.Count;
                if (count > 0)
                {
                    Console.WriteLine($"[SyncService] Pulled {count} Accounts.");
                    await _databaseService.Connection.RunInTransactionAsync(tran => 
                    {
                        foreach(var remote in response.Models)
                        {
                            var local = MapToLocal(remote);
                            local.SyncedAt = DateTime.UtcNow;
                            tran.InsertOrReplace(local);
                        }
                    });
                }
                return count;
            }
            catch(Exception ex) { Console.WriteLine($"[SyncService] Pull Accounts Failed: {ex.Message}"); return 0; }
        }

        private async Task PushTransactionsAsync(string userId)
        {
             // Join not easy, so fetch all dirty transactions and check account ownership or trust UserId if added to Transaction?
             // Transaction doesn't have UserId on it. It has AccountId.
             // We need to fetch transactions where Account.UserId == userId.
             // But locally we can't easily join in SQLite-net-pcl without query.
             // Easier: Just fetch all dirty transactions. 
             // Ideally we should filter by User, but LocalTransaction doesn't have UserId.
             // We can fetch Account first.
             
             // Optimization: Fetch all dirty transactions. Filter in memory if needed, but usually local DB only has current user data?
             // Wait, multi-user support on same device? If so, we must be careful.
             // Assuming single user per DB or we need to look up Account.
             
             var dirty = await _databaseService.Connection.Table<LocalTransaction>()
                                .Where(t => t.SyncedAt == null)
                                .ToListAsync();
             
             if (dirty.Any())
             {
                 // Filter by User ownership (via Account)
                 var accountIds = dirty.Select(t => t.AccountId).Distinct().ToList();
                 var userAccounts = await _databaseService.Connection.Table<LocalAccount>()
                                        .Where(a => accountIds.Contains(a.Id) && a.UserId == userId)
                                        .ToListAsync();
                 var validAccountIds = userAccounts.Select(a => a.Id).ToHashSet();
                 
                 var validDirty = dirty.Where(d => validAccountIds.Contains(d.AccountId)).ToList();
                 
                 if (validDirty.Any())
                 {
                    Console.WriteLine($"[SyncService] Pushing {validDirty.Count} Transactions...");
                    var remoteList = validDirty.Select(MapToRemote).ToList();
                    try
                    {
                        await _supabase.From<Transaction>().Upsert(remoteList);
                        foreach(var t in validDirty)
                        {
                            t.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(t);
                        }
                    }
                    catch(Exception ex) { Console.WriteLine($"[SyncService] Push Transactions Failed: {ex.Message}"); }
                 }
             }
        }

        private async Task<int> PullTransactionsAsync(string userId)
        {
            // Pull transactions for all accounts belonging to user.
            // Supabase: Join? Or fetching all transactions for user?
            // Transaction has AccountId. User has Accounts.
            // RLS usually handles: "Select * from transactions" returns only mine (via account ownership).
            // If RLS is set up correctly (auth.uid() = account.user_id), we can just Select *.
            // But we can't select * from transactions without filter? 
            // Usually we filter by account_id.
            
            // Let's rely on embedded resource or fetch accounts then transactions.
            // Simplest: Fetch Accounts (we have them), then fetch transactions for those accounts.
            // Or use RLS. Let's try fetching all Transactions (assuming RLS restricts).
            // NOTE: If RLS requires a join that PostgREST doesn't automaticlly allow without embedding...
            // User provided schema: 
            // create policy "Users can view their own transactions" on transactions for select using (
            //   exists ( select 1 from accounts where accounts.id = transactions.account_id and accounts.user_id = auth.uid() )
            // );
            // So YES, RLS works. calling .Get() on Transactions should return all user transactions.
            
            try 
            {
                // Range logic for transactions if many?
                var response = await _supabase.From<Transaction>().Order("date", Supabase.Postgrest.Constants.Ordering.Descending).Limit(1000).Get();
                int count = response.Models.Count;
                if (count > 0)
                {
                    Console.WriteLine($"[SyncService] Pulled {count} Transactions.");
                     await _databaseService.Connection.RunInTransactionAsync(tran => 
                    {
                        foreach(var remote in response.Models)
                        {
                            var local = MapToLocal(remote);
                            local.SyncedAt = DateTime.UtcNow;
                            tran.InsertOrReplace(local);
                        }
                    });
                }
                return count;
            }
             catch(Exception ex) { Console.WriteLine($"[SyncService] Pull Transactions Failed: {ex.Message}"); return 0; }
        }

        private async Task PushHoldingsAsync(string userId)
        {
             var dirty = await _databaseService.Connection.Table<LocalHolding>()
                                .Where(h => h.SyncedAt == null)
                                .ToListAsync();
             
             if (dirty.Any())
             {
                 // Filter by User ownership (via Account)
                 var accountIds = dirty.Select(h => h.AccountId).Distinct().ToList();
                 var userAccounts = await _databaseService.Connection.Table<LocalAccount>()
                                        .Where(a => accountIds.Contains(a.Id) && a.UserId == userId)
                                        .ToListAsync();
                 var validAccountIds = userAccounts.Select(a => a.Id).ToHashSet();
                 
                 var validDirty = dirty.Where(d => validAccountIds.Contains(d.AccountId)).ToList();
                 
                 if (validDirty.Any())
                 {
                    Console.WriteLine($"[SyncService] Pushing {validDirty.Count} Holdings...");
                    var remoteList = validDirty.Select(MapToRemote).ToList();
                    try
                    {
                        await _supabase.From<Holding>().Upsert(remoteList);
                        foreach(var h in validDirty)
                        {
                            h.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(h);
                        }
                    }
                    catch(Exception ex) { Console.WriteLine($"[SyncService] Push Holdings Failed: {ex.Message}"); }
                 }
             }
        }

        private async Task<int> PullHoldingsAsync(string userId)
        {
            try 
            {
                var response = await _supabase.From<Holding>().Limit(1000).Get(); // RLS handles userid via account join
                int count = response.Models.Count;
                if (count > 0)
                {
                    Console.WriteLine($"[SyncService] Pulled {count} Holdings.");
                     await _databaseService.Connection.RunInTransactionAsync(tran => 
                    {
                        foreach(var remote in response.Models)
                        {
                            var local = MapToLocal(remote);
                            local.SyncedAt = DateTime.UtcNow;
                            tran.InsertOrReplace(local);
                        }
                    });
                }
                return count;
            }
             catch(Exception ex) { Console.WriteLine($"[SyncService] Pull Holdings Failed: {ex.Message}"); return 0; }
        }

        // Mappers
        private Account MapToRemote(LocalAccount l) => new Account
        {
            Id = Guid.Parse(l.Id),
            UserId = Guid.Parse(l.UserId),
            Name = l.Name,
            Type = l.Type,
            Currency = l.Currency,
            CurrentBalance = l.CurrentBalance,
            CreatedAt = l.CreatedAt,
            UpdatedAt = l.UpdatedAt
        };

        private LocalAccount MapToLocal(Account r) => new LocalAccount
        {
            Id = r.Id.ToString(),
            UserId = r.UserId.ToString(),
            Name = r.Name,
            Type = r.Type,
            Currency = r.Currency,
            CurrentBalance = r.CurrentBalance,
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt
        };

        private Transaction MapToRemote(LocalTransaction l) => new Transaction
        {
            Id = Guid.Parse(l.Id),
            AccountId = Guid.Parse(l.AccountId),
            Date = l.Date,
            Amount = l.Amount,
            Category = l.Category,
            Description = l.Description,
            CreatedAt = l.CreatedAt,
            UpdatedAt = l.UpdatedAt
        };

        private LocalTransaction MapToLocal(Transaction r) => new LocalTransaction
        {
            Id = r.Id.ToString(),
            AccountId = r.AccountId.ToString(),
            Date = r.Date,
            Amount = r.Amount,
            Category = r.Category,
            Description = r.Description,
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt
        };

        private Holding MapToRemote(LocalHolding l) => new Holding
        {
            Id = Guid.Parse(l.Id),
            AccountId = Guid.Parse(l.AccountId),
            SecuritySymbol = l.SecuritySymbol,
            Quantity = l.Quantity,
            CostBasis = l.CostBasis,
            CreatedAt = l.CreatedAt,
            UpdatedAt = l.UpdatedAt
        };

        private LocalHolding MapToLocal(Holding r) => new LocalHolding
        {
            Id = r.Id.ToString(),
            AccountId = r.AccountId.ToString(),
            SecuritySymbol = r.SecuritySymbol,
            Quantity = r.Quantity,
            CostBasis = r.CostBasis,
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt
        };
    }
}
