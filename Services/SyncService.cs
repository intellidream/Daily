using Daily.Models;
using Daily.Models.Finances;
using Daily.Services.Auth;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class SyncService : ISyncService
    {
        private readonly Supabase.Client _supabase;
        private readonly IDatabaseService _databaseService;
        private readonly Daily.Services.Health.IHealthService _healthService; // Injected
        private readonly ITagdosService? _tagdosService;
        private readonly ISupabaseSessionGuardian? _sessionGuardian;
        private bool _watermarkRecoveryChecked = false;

        public SyncService(
            Supabase.Client supabase,
            IDatabaseService databaseService,
            Daily.Services.Health.IHealthService healthService,
            ITagdosService? tagdosService = null,
            ISupabaseSessionGuardian? sessionGuardian = null)
        {
            _supabase = supabase;
            _databaseService = databaseService;
            _healthService = healthService;
            _tagdosService = tagdosService;
            _sessionGuardian = sessionGuardian;
        }

        private Task<T> ExecuteWithAuthAsync<T>(Func<Task<T>> operation, string operationName)
        {
            if (_sessionGuardian != null)
            {
                return _sessionGuardian.ExecuteWithAuthRetryAsync(operation, operationName);
            }
            return operation();
        }

        private void EnsureWatermarkRecoveryApplied()
        {
            if (_watermarkRecoveryChecked)
                return;

            _watermarkRecoveryChecked = true;
            const string migrationKey = "SyncService_WatermarkRecovery_2026_10_29";
            if (GetPreference(migrationKey, "") != "done")
            {
                var keysToReset = new[]
                {
                    "SyncService_LastPullTime_Habits",
                    "SyncService_LastPullTime_Preferences",
                    "SyncService_LastPullTime_SavedArticles",
                    "SyncService_LastPullTime_RssSubscriptions",
                    "SyncService_LastPullTime_CalendarAccounts",
                    "SyncService_LastPullTime_Finances",
                    "SyncService_LastPullTime_Tagdos"
                };

                foreach (var key in keysToReset)
                {
                    SetPreference(key, "");
                }

                SetPreference(migrationKey, "done");
                LogDebug("[SyncService] Applied one-time watermark recovery (2026-10-29): cleared LastPullTime watermarks for full cloud catch-up.");
            }
        }

        public string? LastSyncError { get; private set; }
        public string LastSyncMessage { get; private set; } = "";

        private System.Threading.Timer? _syncTimer;

        private class SyncRequest
        {
            public SyncAction Action { get; set; }
            public SyncScope Scope { get; set; }
        }

        private readonly object _lock = new();
        private bool _isProcessing = false;
        private SyncRequest? _pendingRequest = null;
        private readonly List<TaskCompletionSource<int>> _pendingTcs = new();

        private void LogSyncException(string context, Exception ex)
        {
            LastSyncError = ex.Message;
            var root = ex.GetBaseException();
            var sessionUser = _supabase.Auth.CurrentUser?.Id ?? "<no-user>";
            string msg = $"{context}: {ex.GetType().Name}: {ex.Message} | Root: {root.GetType().Name}: {root.Message} | User: {sessionUser}";
            LogDebug($"[SyncService] EXCEPTION: {msg}");
        }

        private Task<int> EnqueueRequestAsync(SyncAction action, SyncScope scope)
        {
            var tcs = new TaskCompletionSource<int>(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (_lock)
            {
                if (!_isProcessing)
                {
                    _isProcessing = true;
                    _ = Task.Run(() => ProcessLoopAsync(action, scope, tcs));
                }
                else
                {
                    if (_pendingRequest == null)
                    {
                        _pendingRequest = new SyncRequest { Action = action, Scope = scope };
                    }
                    else
                    {
                        _pendingRequest.Action |= action;
                        _pendingRequest.Scope |= scope;
                    }
                    _pendingTcs.Add(tcs);
                }
            }
            return tcs.Task;
        }

        private async Task ProcessLoopAsync(SyncAction initialAction, SyncScope initialScope, TaskCompletionSource<int> initialTcs)
        {
            SyncAction currentAction = initialAction;
            SyncScope currentScope = initialScope;
            var currentTcsList = new List<TaskCompletionSource<int>> { initialTcs };

            while (true)
            {
                int result = 0;
                Exception? error = null;
                try
                {
                    result = await ExecuteInternalAsync(currentAction, currentScope);
                }
                catch (Exception ex)
                {
                    error = ex;
                }

                // Complete the TCSs of this run
                foreach (var tcs in currentTcsList)
                {
                    if (error != null)
                    {
                        tcs.TrySetException(error);
                    }
                    else
                    {
                        tcs.TrySetResult(result);
                    }
                }

                // Check for pending requests
                lock (_lock)
                {
                    if (_pendingRequest == null)
                    {
                        _isProcessing = false;
                        break;
                    }

                    currentAction = _pendingRequest.Action;
                    currentScope = _pendingRequest.Scope;
                    currentTcsList = new List<TaskCompletionSource<int>>(_pendingTcs);

                    _pendingRequest = null;
                    _pendingTcs.Clear();
                }
            }
        }

        private async Task<int> ExecuteInternalAsync(SyncAction action, SyncScope scope)
        {
            LastSyncError = null;
            LastSyncMessage = "";

            if (_sessionGuardian != null)
            {
                try
                {
                    await _sessionGuardian.EnsureValidSessionAsync();
                }
                catch (Exception ex)
                {
                    LogSyncException("SessionGuardian.EnsureValidSessionAsync", ex);
                }
            }
            else
            {
                var authFallback = _supabase.Auth;
                if (authFallback?.CurrentSession != null)
                {
                    try
                    {
                        if (authFallback.CurrentSession.Expired())
                        {
                            LogDebug("[SyncService] Session token is expired. Proactively refreshing session...");
                            var refreshedSession = await authFallback.RefreshSession();
                            if (refreshedSession != null)
                            {
                                LogDebug("[SyncService] Proactive session refresh succeeded.");
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        LogSyncException("Proactive Refresh Session Exception", ex);
                    }
                }
            }

            var auth = _supabase.Auth;
            if (auth?.CurrentSession == null)
            {
                LogDebug("[SyncService] ExecuteInternalAsync skipped: no active Supabase session.");
                return 0;
            }

            EnsureWatermarkRecoveryApplied();

            int totalItems = 0;
            try
            {
                // 0. Sync Health (Native -> Cloud)
                if ((action & SyncAction.Push) != 0 && (scope & SyncScope.Habits) != 0)
                {
                    try { await _healthService.SyncNativeHealthDataAsync(); }
                    catch (Exception hex) { LogSyncException("Health Sync Warning", hex); }
                }

                if ((action & SyncAction.Push) != 0)
                {
                    await PushInternalAsync(scope);
                }

                if ((action & SyncAction.Pull) != 0)
                {
                    totalItems = await PullInternalAsync(scope);
                }
                else if ((action & SyncAction.Push) != 0 && (scope & SyncScope.Tagdos) != 0 && _tagdosService != null)
                {
                    await _tagdosService.SyncWithRemoteAsync();
                    OnTagdosPulled?.Invoke();
                }
            }
            catch (Exception ex)
            {
                LogSyncException("ExecuteInternalAsync", ex);
                throw;
            }
            return totalItems;
        }

        public Task SyncAsync(SyncScope scope = SyncScope.All)
        {
            return EnqueueRequestAsync(SyncAction.Sync, scope);
        }

        public Task PushAsync(SyncScope scope = SyncScope.All)
        {
            return EnqueueRequestAsync(SyncAction.Push, scope);
        }

        public async Task<int> PullAsync(SyncScope scope = SyncScope.All)
        {
            return await EnqueueRequestAsync(SyncAction.Pull, scope);
        }

        public void StartBackgroundSync()
        {
            if (_syncTimer == null)
            {
                // Sync every 15 minutes, starting after 1 second (1000 ms) to load fresh cloud data almost immediately
                _syncTimer = new System.Threading.Timer(_ =>
                {
                    _ = SafeBackgroundSyncAsync();
                }, null, 1000, 900000);
                Console.WriteLine("[SyncService] Background Sync Started.");
            }
        }

        private async Task SafeBackgroundSyncAsync()
        {
            try
            {
                await SyncAsync(SyncScope.All);
            }
            catch (Exception ex)
            {
                LogSyncException("SafeBackgroundSyncAsync", ex);
            }
        }

        private async Task PushInternalAsync(SyncScope scope)
        {
            Console.WriteLine($"[SyncService] PushAsync Started with scope: {scope}");
            await _databaseService.InitializeAsync();
            var userId = _supabase.Auth.CurrentUser?.Id;
            if (userId == null) 
            {
                Console.WriteLine("[SyncService] Push Aborted: No User");
                return;
            }

            if ((scope & SyncScope.Habits) != 0)
            {
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
                            
                            var result = await ExecuteWithAuthAsync(() => _supabase.From<HabitLog>().Upsert(remoteLogs), "PushHabitLogs");
                            var insertedCount = result.Models.Count;
                            Console.WriteLine($"[SyncService] Supabase returned {insertedCount} models.");

                            if (insertedCount > 0 || remoteLogs.Count > 0)
                            {
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
                         LogSyncException("PushHabitLogs", ex);
                         Console.WriteLine($"[SyncService] Push Logs FAILED EXCEPTION: {ex.Message}");
                         Console.WriteLine($"[SyncService] Stack: {ex.StackTrace}");
                    }
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
                            await ExecuteWithAuthAsync(() => _supabase.From<HabitGoal>().Upsert(remoteGoals), "PushHabitGoals");

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
                         LogSyncException("PushHabitGoals", ex);
                         Console.WriteLine($"[SyncService] Push Goals Failed: {ex.Message}");
                    }
                }

                // 4. Consolidate & Push Summaries (New Protocol)
                await ConsolidateHistoryAsync(userId); 
                await PushSummariesAsync(userId);

                // 6. Data Safety / Cost Management: Always check if we can prune old remote logs
                await PruneRemoteLogsAsync(userId);
            }

            if ((scope & SyncScope.Preferences) != 0)
            {
                // 3. Push Preferences
                await PushPreferencesAsync(userId);
            }
            
            if ((scope & SyncScope.Finances) != 0)
            {
                // 4. Push Finances (Accounts & Transactions & Holdings & Smart Ledger)
                await PushAccountsAsync(userId);
                await PushTransactionsAsync(userId);
                await PushHoldingsAsync(userId);
                await PushSmartLedgerAsync(userId);
                await PushLedgerTransactionsAsync(userId);
            }

            if ((scope & SyncScope.SavedArticles) != 0)
            {
                // 5. Push Saved Articles (Read Later / Favorites)
                await PushSavedArticlesAsync(userId);
            }
            
            if ((scope & SyncScope.RssSubscriptions) != 0)
            {
                // 6. Push RSS Subscriptions
                await PushRssSubscriptionsAsync(userId);
            }

            if ((scope & SyncScope.CalendarAccounts) != 0)
            {
                // 7. Push Calendar Accounts
                await PushCalendarAccountsAsync(userId);
            }
        }

        private async Task<int> PullInternalAsync(SyncScope scope)
        {
            Console.WriteLine($"[SyncService] PullAsync Started with scope: {scope}");
            await _databaseService.InitializeAsync();
            var userId = _supabase.Auth.CurrentUser?.Id;
            if (userId == null) 
            {
                Console.WriteLine("[SyncService] Pull Aborted: No User");
                return 0;
            }

            int totalPulled = 0;

            if ((scope & SyncScope.Habits) != 0)
            {
                var key = "SyncService_LastPullTime_Habits";
                var lastPullStr = GetPreference(key, "");
                DateTime lastPull = string.IsNullOrEmpty(lastPullStr) ? DateTime.MinValue : DateTime.Parse(lastPullStr).ToUniversalTime();
                var pullStartedUtc = DateTime.UtcNow;

                var logsRes = await PullLogsInternalAsync(userId, lastPull);
                var goalsRes = await PullGoalsInternalAsync(userId, lastPull);
                var sumRes = await PullSummariesInternalAsync(userId, lastPull);

                int pulled = logsRes.Count + goalsRes.Count + sumRes.Count;
                totalPulled += pulled;

                if (logsRes.Succeeded && goalsRes.Succeeded && sumRes.Succeeded)
                {
                    SetPreference(key, pullStartedUtc.ToString("O"));
                }
                else
                {
                    LogDebug("[SyncService] Retained previous LastPullTime_Habits watermark due to transient sub-pull failure.");
                }

                if (pulled > 0)
                {
                    OnHabitsPulled?.Invoke();
                }
            }

            if ((scope & SyncScope.Preferences) != 0)
            {
                var key = "SyncService_LastPullTime_Preferences";
                var lastPullStr = GetPreference(key, "");
                DateTime lastPull = string.IsNullOrEmpty(lastPullStr) ? DateTime.MinValue : DateTime.Parse(lastPullStr).ToUniversalTime();
                var pullStartedUtc = DateTime.UtcNow;

                var res = await PullPreferencesInternalAsync(userId, lastPull);
                totalPulled += res.Count;
                if (res.Succeeded)
                {
                    SetPreference(key, pullStartedUtc.ToString("O"));
                }
            }

            if ((scope & SyncScope.SavedArticles) != 0)
            {
                var key = "SyncService_LastPullTime_SavedArticles";
                var lastPullStr = GetPreference(key, "");
                DateTime lastPull = string.IsNullOrEmpty(lastPullStr) ? DateTime.MinValue : DateTime.Parse(lastPullStr).ToUniversalTime();
                var pullStartedUtc = DateTime.UtcNow;

                var res = await PullSavedArticlesInternalAsync(userId, lastPull);
                totalPulled += res.Count;
                if (res.Succeeded)
                {
                    SetPreference(key, pullStartedUtc.ToString("O"));
                }
            }

            if ((scope & SyncScope.RssSubscriptions) != 0)
            {
                var key = "SyncService_LastPullTime_RssSubscriptions";
                var lastPullStr = GetPreference(key, "");
                DateTime lastPull = string.IsNullOrEmpty(lastPullStr) ? DateTime.MinValue : DateTime.Parse(lastPullStr).ToUniversalTime();
                var pullStartedUtc = DateTime.UtcNow;

                var res = await PullRssSubscriptionsAsync(userId, lastPull);
                totalPulled += res.Count;
                if (res.Succeeded)
                {
                    SetPreference(key, pullStartedUtc.ToString("O"));
                    OnRssSubscriptionsPulled?.Invoke();
                }
            }

            if ((scope & SyncScope.CalendarAccounts) != 0)
            {
                var key = "SyncService_LastPullTime_CalendarAccounts";
                var lastPullStr = GetPreference(key, "");
                DateTime lastPull = string.IsNullOrEmpty(lastPullStr) ? DateTime.MinValue : DateTime.Parse(lastPullStr).ToUniversalTime();
                var pullStartedUtc = DateTime.UtcNow;

                var res = await PullCalendarAccountsAsync(userId, lastPull);
                totalPulled += res.Count;
                if (res.Succeeded)
                {
                    SetPreference(key, pullStartedUtc.ToString("O"));
                }
            }

            if ((scope & SyncScope.Finances) != 0)
            {
                var key = "SyncService_LastPullTime_Finances";
                var lastPullStr = GetPreference(key, "");
                DateTime lastPull = string.IsNullOrEmpty(lastPullStr) ? DateTime.MinValue : DateTime.Parse(lastPullStr).ToUniversalTime();
                var pullStartedUtc = DateTime.UtcNow;

                var accRes = await PullAccountsInternalAsync(userId, lastPull);
                var txRes = await PullTransactionsInternalAsync(userId, lastPull);
                var holdRes = await PullHoldingsInternalAsync(userId, lastPull);
                var ledgerRes = await PullSmartLedgerInternalAsync(userId, lastPull);
                var ledgerTxRes = await PullLedgerTransactionsInternalAsync(userId, lastPull);

                int pulled = accRes.Count + txRes.Count + holdRes.Count + ledgerRes.Count + ledgerTxRes.Count;
                totalPulled += pulled;

                if (accRes.Succeeded && txRes.Succeeded && holdRes.Succeeded && ledgerRes.Succeeded && ledgerTxRes.Succeeded)
                {
                    SetPreference(key, pullStartedUtc.ToString("O"));
                }
                else
                {
                    LogDebug("[SyncService] Retained previous LastPullTime_Finances watermark due to transient sub-pull failure.");
                }

                if (pulled > 0)
                {
                    OnFinancesPulled?.Invoke();
                }
            }

            if ((scope & SyncScope.Tagdos) != 0 && _tagdosService != null)
            {
                try
                {
                    await _tagdosService.SyncWithRemoteAsync();
                    SetPreference("SyncService_LastPullTime_Tagdos", DateTime.UtcNow.ToString("O"));
                    OnTagdosPulled?.Invoke();
                }
                catch (Exception tex)
                {
                    LogSyncException("PullTagdosAsync", tex);
                }
            }

            return totalPulled;
        }

        private async Task<(int Count, bool Succeeded)> PullLogsInternalAsync(string userId, DateTime lastPull)
        {
            try {
                Console.Error.WriteLine($"[SyncService] Pulling Logs for User: {userId}...");
                
                int rangeStart = 0;
                int rangeEnd = 999;
                bool hasMore = true;
                int totalPulled = 0;

                while(hasMore)
                {
                    Console.Error.WriteLine($"[SyncService] Pulling Logs range {rangeStart}-{rangeEnd}...");
                    
                    DateTime threshold;
                    if (lastPull == DateTime.MinValue)
                    {
                        threshold = DateTime.UtcNow.AddDays(-30);
                    }
                    else
                    {
                        // 15-minute safety overlap before last pull to ensure in-flight logs are never missed
                        threshold = lastPull.AddMinutes(-15);
                        if (threshold < DateTime.UtcNow.AddDays(-90))
                        {
                            threshold = DateTime.UtcNow.AddDays(-90);
                        }
                    }
                    
                    var rStart = rangeStart;
                    var rEnd = rangeEnd;
                    var response = await ExecuteWithAuthAsync(() =>
                    {
                        var query = _supabase.From<HabitLog>()
                            .Order("logged_at", global::Supabase.Postgrest.Constants.Ordering.Descending)
                            .Filter("created_at", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, threshold.ToString("O"));
                        return query.Range(rStart, rEnd).Get();
                    }, "PullHabitLogs");

                    int count = response.Models.Count;
                    if (count > 0)
                    {
                         Console.Error.WriteLine($"[SyncService] Pulled {count} logs (Batch).");
                         totalPulled += count;

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

                         rangeStart += 1000;
                         rangeEnd += 1000;
                    }

                    if (count < 1000)
                    {
                        hasMore = false;
                    }
                }
                Console.Error.WriteLine("[SyncService] Pull Logs Local Save Complete.");
                return (totalPulled, true);
            } 
            catch(Exception e) { 
                LogSyncException("PullLogsInternalAsync", e);
                Console.Error.WriteLine("[SyncService] Pull Logs Error: " + e); 
                return (0, false);
            }
        }

        private async Task<(int Count, bool Succeeded)> PullGoalsInternalAsync(string userId, DateTime lastPull)
        {
            try {
                Console.WriteLine($"[SyncService] Pulling Goals for User: {userId}...");
                var goalResponse = await ExecuteWithAuthAsync(() =>
                {
                    var query = (Supabase.Postgrest.Interfaces.IPostgrestTable<HabitGoal>)_supabase.From<HabitGoal>();
                    return query.Get();
                }, "PullHabitGoals");

                Console.WriteLine($"[SyncService] Pulled {goalResponse.Models.Count} goals from Cloud.");

                foreach (var remote in goalResponse.Models)
                {
                    var local = remote.ToLocal();
                    local.SyncedAt = DateTime.UtcNow;
                    await _databaseService.Connection.InsertOrReplaceAsync(local);
                }
                Console.WriteLine("[SyncService] Pull Goals Local Save Complete.");
                return (goalResponse.Models.Count, true);
            }
            catch(Exception e) { 
                LogSyncException("PullGoalsInternalAsync", e);
                Console.WriteLine("[SyncService] Pull Goals Error: " + e); 
                return (0, false);
            }
        }

        // Mappers
        // Using Services.Mappers Extensions

        // --- Preferences Sync Logic ---

        // --- Helper for Debugging ---
        public string DebugLog { get; private set; } = "";
        public event Action? OnDebugLogUpdated;
        public event Action? OnHabitsPulled;
        public event Action? OnPreferencesPulled;
        public event Action? OnRssSubscriptionsPulled;
        public event Action? OnSavedArticlesPulled;
        public event Action? OnFinancesPulled;
        public event Action? OnTagdosPulled;

        private async Task PushRssSubscriptionsAsync(string userId)
        {
            var dirty = await _databaseService.Connection.Table<LocalRssSubscription>()
                                .Where(x => x.SyncedAt == null && x.UserId == userId)
                                .ToListAsync();
            if (dirty.Any())
            {
                LogDebug($"[SyncService] Pushing {dirty.Count} dirty RSS subscriptions...");
                try 
                {
                    var remote = new List<RssSubscription>();
                    foreach(var d in dirty)
                    {
                        try { remote.Add(d.ToDomain()); } catch { }
                    }
                    if (remote.Any())
                    {
                        await ExecuteWithAuthAsync(() => _supabase.From<RssSubscription>().Upsert(remote), "PushRssSubscriptions");
                        foreach (var l in dirty)
                        {
                            l.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(l);
                        }
                        LogDebug($"[SyncService] Successfully pushed {remote.Count} RSS subscriptions.");
                    }
                }
                catch(Exception ex) 
                { 
                    LogDebug($"[SyncService] Push RssSubscriptions Failed: {ex.Message}");
                    LogSyncException("PushRssSubscriptionsAsync", ex);
                }
            }
        }

        private async Task<(int Count, bool Succeeded)> PullRssSubscriptionsAsync(string userId, DateTime lastPull)
        {
            try 
            {
                LogDebug("[SyncService] PullRssSubscriptionsAsync Started");
                var userGuid = Guid.Parse(userId);
                var response = await ExecuteWithAuthAsync(
                    () => _supabase.From<RssSubscription>().Where(x => x.UserId == userGuid).Get(),
                    "PullRssSubscriptions");
                int count = response.Models.Count;
                LogDebug($"[SyncService] Pulled {count} RSS subscriptions from Supabase.");
                if (count > 0)
                {
                    var localSubscriptions = await _databaseService.Connection.Table<LocalRssSubscription>()
                                                .Where(x => x.UserId == userId)
                                                .ToListAsync();

                    var localLookup = localSubscriptions.ToDictionary(x => x.Id);
                    var toSave = new List<LocalRssSubscription>();

                    foreach (var remote in response.Models)
                    {
                        var localSub = remote.ToLocal();
                        localSub.SyncedAt = DateTime.UtcNow;

                        if (localLookup.TryGetValue(localSub.Id, out var existingLocal))
                        {
                            // If local is dirty (SyncedAt == null) and local was updated after remote, keep local
                            if (existingLocal.SyncedAt == null && existingLocal.UpdatedAt >= remote.UpdatedAt)
                            {
                                LogDebug($"[SyncService] Pull Ignored for feed '{remote.Name}': Local is dirty and newer/equal (Local Updated: {existingLocal.UpdatedAt}, Remote Updated: {remote.UpdatedAt})");
                                continue;
                            }
                        }
                        toSave.Add(localSub);
                    }

                    if (toSave.Any())
                    {
                        await _databaseService.Connection.RunInTransactionAsync(tran => 
                        {
                            foreach(var item in toSave)
                            {
                                tran.InsertOrReplace(item);
                            }
                        });
                        LogDebug($"[SyncService] Saved {toSave.Count} RSS subscriptions to local SQLite DB.");
                    }
                }
                return (count, true);
            }
            catch(Exception ex) 
            { 
                LogDebug($"[SyncService] Pull RssSubscriptions Failed: {ex.Message}");
                LogSyncException("PullRssSubscriptionsAsync", ex);
                return (0, false); 
            }
        }

        private async Task PushCalendarAccountsAsync(string userId)
        {
            var dirty = await _databaseService.Connection.Table<LocalCalendarAccount>()
                                .Where(x => x.SyncedAt == null && x.UserId == userId)
                                .ToListAsync();
            if (dirty.Any())
            {
                Console.WriteLine($"[SyncService] Pushing {dirty.Count} dirty Calendar accounts...");
                try 
                {
                    var remote = new List<CalendarAccount>();
                    foreach(var d in dirty)
                    {
                        try { remote.Add(d.ToDomain()); } 
                        catch (Exception ex) { Console.WriteLine($"[SyncService] ToDomain error for calendar account {d.Id}: {ex.Message}"); }
                    }
                    if (remote.Any())
                    {
                        await ExecuteWithAuthAsync(() => _supabase.From<CalendarAccount>().Upsert(remote), "PushCalendarAccounts");
                        foreach (var l in dirty)
                        {
                            l.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(l);
                        }
                    }
                }
                catch(Exception ex)
                {
                    LogSyncException("PushCalendarAccountsAsync", ex);
                    Console.WriteLine($"[SyncService] Push CalendarAccounts Failed: {ex.Message}");
                }
            }
        }

        private async Task<(int Count, bool Succeeded)> PullCalendarAccountsAsync(string userId, DateTime lastPull)
        {
            try 
            {
                Console.WriteLine($"[SyncService] Pulling Calendar accounts for User: {userId}...");
                var userGuid = Guid.Parse(userId);
                
                // Self-healing: if local table is empty, force a full pull
                var localCount = await _databaseService.Connection.Table<LocalCalendarAccount>().CountAsync();
                if (localCount == 0)
                {
                    lastPull = DateTime.MinValue;
                }

                var effectiveLastPull = lastPull;
                var response = await ExecuteWithAuthAsync(() =>
                {
                    var query = _supabase.From<CalendarAccount>().Where(x => x.UserId == userGuid);
                    if (effectiveLastPull > DateTime.MinValue)
                    {
                        var queryDate = effectiveLastPull.AddMinutes(-5);
                        query = query.Filter("updated_at", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, queryDate.ToString("O"));
                    }
                    return query.Get();
                }, "PullCalendarAccounts");

                int count = response.Models.Count;
                if (count > 0)
                {
                    var localBatch = response.Models.Select(m => {
                        var l = m.ToLocal();
                        l.SyncedAt = DateTime.UtcNow;
                        return l;
                    }).ToList();

                    await _databaseService.Connection.RunInTransactionAsync(tran => 
                    {
                        foreach(var item in localBatch)
                        {
                            if (item.IsDeleted)
                            {
                                tran.Delete<LocalCalendarAccount>(item.Id);
                                tran.Table<LocalCalendarEvent>().Where(x => x.AccountId == item.Id).Delete();
                                tran.Table<LocalCalendarTodo>().Where(x => x.AccountId == item.Id).Delete();
                                continue;
                            }

                            var existing = tran.Find<LocalCalendarAccount>(item.Id);
                            if (existing != null)
                            {
                                item.CustomName = existing.CustomName;
                                item.IdentifiedName = existing.IdentifiedName;
                            }
                            tran.InsertOrReplace(item);
                        }
                    });
                }
                return (count, true);
            }
            catch(Exception ex)
            {
                LogSyncException("PullCalendarAccountsAsync", ex);
                Console.WriteLine($"[SyncService] Pull CalendarAccounts Failed: {ex.Message}");
                return (0, false);
            }
        }

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
                var path = Path.Combine(GetCacheDirectory(), "sync_debug.log");
                var fi = new FileInfo(path);
                if (fi.Exists && fi.Length > 2 * 1024 * 1024)
                {
                    File.Move(path, path + ".old", overwrite: true);
                }
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
                        bool skipPush = false;
                        try 
                        {
                            var existingResponse = await ExecuteWithAuthAsync(() => _supabase.From<UserPreferences>()
                                .Select("updated_at")
                                .Where(x => x.Id == userId)
                                .Get(), "CheckUserPreferencesConflict");
                            
                            var existing = existingResponse.Models.FirstOrDefault();
                            
                            if (existing != null)
                            {
                                // Remote exists. Compare timestamps.
                                var localTime = DateTime.SpecifyKind(local.UpdatedAt, DateTimeKind.Utc);
                                var remoteTime = existing.UpdatedAt.ToUniversalTime();

                                LogDebug($"[SyncService] CONFLICT CHECK:");
                                LogDebug($"   Local ID: {local.Id} | UpdatedAt: {localTime:O} (Ticks: {localTime.Ticks})");
                                LogDebug($"   Remote ID: {existing.Id} | UpdatedAt: {remoteTime:O} (Ticks: {remoteTime.Ticks})");
                                var diff = remoteTime - localTime;
                                LogDebug($"   Diff (Remote - Local): {diff.TotalSeconds} seconds");

                                if (remoteTime > localTime.AddSeconds(60)) 
                                {
                                    LogDebug($"[SyncService] DECISION: REMOTE WIN. Remote is newer by {diff.TotalSeconds:F2}s. Skipping Push & Pulling.");
                                    skipPush = true;
                                    
                                    var fullRemoteResponse = await ExecuteWithAuthAsync(() => _supabase.From<UserPreferences>().Where(x => x.Id == userId).Get(), "PullRemoteUserPreferencesOnConflict");
                                    var fullRemote = fullRemoteResponse.Models.FirstOrDefault();
                                    if (fullRemote != null)
                                    {
                                        var updatedLocal = fullRemote.ToLocal();
                                        updatedLocal.SyncedAt = DateTime.UtcNow;
                                        await _databaseService.Connection.InsertOrReplaceAsync(updatedLocal);
                                        LogDebug($"[SyncService] Conflict Resolved: Pulled Remote Version.");
                                        OnPreferencesPulled?.Invoke();
                                    }
                                }
                                else
                                {
                                    LogDebug($"[SyncService] DECISION: LOCAL WIN. Local is Newer or Equal. Proceeding with Push.");
                                }
                            }
                        }
                        catch (Exception checkEx)
                        {
                            LogDebug($"[SyncService] Conflict Check Warning: {checkEx.Message}. Proceeding with push.");
                        }

                        if (!skipPush)
                        {
                            // Create or Overwrite (We are newer or new)
                            var response = await ExecuteWithAuthAsync(() => _supabase.From<UserPreferences>().Upsert(remote), "PushUserPreferences");

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
                        LogSyncException($"PushPreferencesAsync({local.Id})", ex);
                    }
                }
                LastSyncMessage += $"Pushed {pushedCount}/{dirtyPrefs.Count}. ";
            }
            else 
            {
                LastSyncMessage += "No changes to push. ";
            }
        }
        private async Task<(int Count, bool Succeeded)> PullPreferencesInternalAsync(string userId, DateTime lastPull)
        {
             try {
                Console.WriteLine($"[SyncService] Pulling Preferences for User: {userId}...");

                var effectiveLastPull = lastPull;
                var response = await ExecuteWithAuthAsync(() =>
                {
                    var query = _supabase.From<UserPreferences>()
                        .Where(x => x.Id == userId); // Valid for string ID
                        
                    if (effectiveLastPull > DateTime.MinValue)
                    {
                        var queryDate = effectiveLastPull.AddMinutes(-5);
                        query = query.Filter("updated_at", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, queryDate.ToString("O"));
                    }

                    return query.Get();
                }, "PullUserPreferences");

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
                if (successfulMergess > 0)
                {
                    OnPreferencesPulled?.Invoke();
                }
                return (successfulMergess, true);
            }
            catch(Exception e) 
            { 
                LogSyncException("PullPreferencesInternalAsync", e);
                Console.WriteLine("[SyncService] Pull Preferences Error: " + e); 
                return (0, false);
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
                     await ExecuteWithAuthAsync(() => _supabase.From<DailySummary>().Upsert(remoteList), "PushDailySummaries");
                     
                     foreach(var s in dirty)
                     {
                         s.SyncedAt = DateTime.UtcNow;
                         await _databaseService.Connection.UpdateAsync(s);
                     }
                     Console.WriteLine("[SyncService] Push Summaries Success.");
                  }
                  catch(Exception ex)
                  {
                      LogSyncException("PushSummariesAsync", ex);
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

        private async Task<(int Count, bool Succeeded)> PullSummariesInternalAsync(string userId, DateTime lastPull)
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
                      var effectiveLastPull = lastPull;
                      var rStart = rangeStart;
                      var rEnd = rangeEnd;
                      var response = await ExecuteWithAuthAsync(() =>
                      {
                          var query = _supabase.From<DailySummary>()
                             .Where(x => x.UserId == userGuid);
                          
                          if (effectiveLastPull > DateTime.MinValue)
                          {
                              var queryDate = effectiveLastPull.AddMinutes(-5);
                              query = query.Filter("updated_at", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, queryDate.ToString("O"));
                          }

                          return query.Range(rStart, rEnd).Get();
                      }, "PullDailySummaries");

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
                  
                  return (totalPulled, true);
             }
             catch(Exception ex)
             {
                  LogSyncException("PullSummariesInternalAsync", ex);
                  Console.WriteLine($"[SyncService] Pull Summaries Error: {ex.Message}");
                  return (0, false);
             }
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
                    await ExecuteWithAuthAsync(() => _supabase.From<Account>().Upsert(remoteList), "PushAccounts");
                    foreach(var a in dirty)
                    {
                        a.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.UpdateAsync(a);
                    }
                    Console.WriteLine("[SyncService] Push Accounts Success.");
                }
                catch(Exception ex)
                {
                    LogSyncException("PushAccountsAsync", ex);
                    Console.WriteLine($"[SyncService] Push Accounts Failed: {ex.Message}");
                }
            }
        }

        private async Task<(int Count, bool Succeeded)> PullAccountsInternalAsync(string userId, DateTime lastPull)
        {
            try 
            {
                var userGuid = Guid.Parse(userId);
                // Note: Supabase 'accounts' table has no updated_at/created_at column; user account count is tiny.
                var response = await ExecuteWithAuthAsync(
                    () => _supabase.From<Account>().Where(a => a.UserId == userGuid).Get(),
                    "PullAccounts");

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
                return (count, true);
            }
            catch(Exception ex)
            {
                LogSyncException("PullAccountsInternalAsync", ex);
                Console.WriteLine($"[SyncService] Pull Accounts Failed: {ex.Message}");
                return (0, false);
            }
        }

        private async Task PushTransactionsAsync(string userId)
        {
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
                        await ExecuteWithAuthAsync(() => _supabase.From<Transaction>().Upsert(remoteList), "PushTransactions");
                        foreach(var t in validDirty)
                        {
                            t.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(t);
                        }
                    }
                    catch(Exception ex)
                    {
                        LogSyncException("PushTransactionsAsync", ex);
                        Console.WriteLine($"[SyncService] Push Transactions Failed: {ex.Message}");
                    }
                 }
             }
        }

        private async Task<(int Count, bool Succeeded)> PullTransactionsInternalAsync(string userId, DateTime lastPull)
        {
            try 
            {
                var effectiveLastPull = lastPull;
                var response = await ExecuteWithAuthAsync(() =>
                {
                    // Note: Supabase 'transactions' table uses 'date' (no updated_at/created_at column)
                    var query = _supabase.From<Transaction>().Order("date", Supabase.Postgrest.Constants.Ordering.Descending);
                    if (effectiveLastPull > DateTime.MinValue)
                    {
                        var queryDate = effectiveLastPull.AddDays(-7);
                        query = query.Filter("date", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, queryDate.ToString("yyyy-MM-dd"));
                    }
                    return query.Limit(1000).Get();
                }, "PullTransactions");

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
                return (count, true);
            }
             catch(Exception ex)
             {
                 LogSyncException("PullTransactionsInternalAsync", ex);
                 Console.WriteLine($"[SyncService] Pull Transactions Failed: {ex.Message}");
                 return (0, false);
             }
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
                        await ExecuteWithAuthAsync(() => _supabase.From<Holding>().Upsert(remoteList), "PushHoldings");
                        foreach(var h in validDirty)
                        {
                            h.SyncedAt = DateTime.UtcNow;
                            await _databaseService.Connection.UpdateAsync(h);
                        }
                    }
                    catch(Exception ex)
                    {
                        LogSyncException("PushHoldingsAsync", ex);
                        Console.WriteLine($"[SyncService] Push Holdings Failed: {ex.Message}");
                    }
                 }
             }
        }

        private async Task<(int Count, bool Succeeded)> PullHoldingsInternalAsync(string userId, DateTime lastPull)
        {
            try 
            {
                // Note: Supabase 'holdings' table has no updated_at/created_at column; RLS scopes to user via account join.
                var response = await ExecuteWithAuthAsync(() =>
                {
                    var query = (Supabase.Postgrest.Interfaces.IPostgrestTable<Holding>)_supabase.From<Holding>();
                    return query.Limit(1000).Get();
                }, "PullHoldings");

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
                return (count, true);
            }
             catch(Exception ex)
             {
                 LogSyncException("PullHoldingsInternalAsync", ex);
                 Console.WriteLine($"[SyncService] Pull Holdings Failed: {ex.Message}");
                 return (0, false);
             }
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

        // --- Saved Articles (Read Later / Favorites) Sync ---

        private async Task PushSavedArticlesAsync(string userId)
        {
            try
            {
                var dirty = await _databaseService.Connection.Table<LocalSavedArticle>()
                    .Where(a => a.SyncedAt == null && a.UserId == userId)
                    .ToListAsync();

                if (dirty.Any())
                {
                    Console.WriteLine($"[SyncService] Pushing {dirty.Count} saved articles...");
                    var remote = dirty.Select(d => d.ToDomain()).ToList();
                    await ExecuteWithAuthAsync(() => _supabase.From<SavedArticle>().Upsert(remote), "PushSavedArticles");

                    foreach (var d in dirty)
                    {
                        d.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.UpdateAsync(d);
                    }
                    Console.WriteLine("[SyncService] Push Saved Articles Success.");
                }
            }
            catch (Exception ex)
            {
                LogSyncException("PushSavedArticlesAsync", ex);
                Console.WriteLine($"[SyncService] Push Saved Articles Failed: {ex.Message}");
            }
        }

        private async Task<(int Count, bool Succeeded)> PullSavedArticlesInternalAsync(string userId, DateTime lastPull)
        {
            try
            {
                Console.WriteLine($"[SyncService] Pulling Saved Articles for User: {userId}...");

                var effectiveLastPull = lastPull;
                var response = await ExecuteWithAuthAsync(() =>
                {
                    var query = (Supabase.Postgrest.Interfaces.IPostgrestTable<SavedArticle>)_supabase.From<SavedArticle>();
                    if (effectiveLastPull > DateTime.MinValue)
                    {
                        var queryDate = effectiveLastPull.AddMinutes(-5);
                        query = query.Filter("updated_at", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, queryDate.ToString("O"));
                    }
                    return query.Get();
                }, "PullSavedArticles");

                Console.WriteLine($"[SyncService] Pulled {response.Models.Count} saved articles from Cloud.");

                foreach (var remote in response.Models)
                {
                    var local = remote.ToLocal();
                    local.SyncedAt = DateTime.UtcNow;
                    await _databaseService.Connection.InsertOrReplaceAsync(local);
                }

                if (response.Models.Count > 0)
                {
                    OnSavedArticlesPulled?.Invoke();
                }

                Console.WriteLine("[SyncService] Pull Saved Articles Complete.");
                return (response.Models.Count, true);
            }
            catch (Exception ex)
            {
                LogSyncException("PullSavedArticlesInternalAsync", ex);
                Console.WriteLine($"[SyncService] Pull Saved Articles Error: {ex.Message}");
                return (0, false);
            }
        }
        private string GetPreference(string key, string defaultValue)
        {
#if WINUI_NATIVE
            var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
            System.IO.Directory.CreateDirectory(appDataPath);
            var file = Path.Combine(appDataPath, key + ".txt");
            if (File.Exists(file)) return File.ReadAllText(file);
            return defaultValue;
#else
            return Microsoft.Maui.Storage.Preferences.Default.Get(key, defaultValue);
#endif
        }

        private void SetPreference(string key, string value)
        {
#if WINUI_NATIVE
            var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp");
            System.IO.Directory.CreateDirectory(appDataPath);
            var file = Path.Combine(appDataPath, key + ".txt");
            File.WriteAllText(file, value);
#else
            Microsoft.Maui.Storage.Preferences.Default.Set(key, value);
#endif
        }

        private string GetCacheDirectory()
        {
#if WINUI_NATIVE
            var appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp", "Cache");
            System.IO.Directory.CreateDirectory(appDataPath);
            return appDataPath;
#else
            return Microsoft.Maui.Storage.FileSystem.CacheDirectory;
#endif
        }

        // ==========================================
        // SMART LEDGER SYNC
        // ==========================================

        private async Task PushSmartLedgerAsync(string userId)
        {
            var allUserRows = await _databaseService.Connection.Table<LocalSmartLedger>()
                                .Where(a => a.UserId == userId)
                                .OrderByDescending(a => a.UpdatedAt)
                                .ToListAsync();

            if (!allUserRows.Any())
                return;

            var canonical = allUserRows.First();
            // Deduplicate any stale local rows with older timestamps
            foreach (var extra in allUserRows.Skip(1))
            {
                await _databaseService.Connection.DeleteAsync(extra);
            }

            if (canonical.SyncedAt != null)
                return;

            LogDebug($"[SyncService] Pushing canonical Smart Ledger ({canonical.Id})...");
            try
            {
                var userGuid = Guid.Parse(userId);
                var existingResp = await ExecuteWithAuthAsync(
                    () => _supabase.From<SmartLedger>()
                        .Where(x => x.UserId == userGuid)
                        .Order("updated_at", Supabase.Postgrest.Constants.Ordering.Descending)
                        .Limit(1)
                        .Get(),
                    "CheckRemoteSmartLedger");

                var remoteLatest = existingResp.Models.FirstOrDefault();
                if (remoteLatest != null)
                {
                    var remoteTime = remoteLatest.UpdatedAt.ToUniversalTime();
                    var localTime = Mappers.SafeUtc(canonical.UpdatedAt);

                    if (remoteTime > localTime)
                    {
                        // Remote is newer than our unsynced local copy -> adopt remote
                        await _databaseService.Connection.DeleteAsync(canonical);
                        var adopted = Mappers.ToLocal(remoteLatest);
                        adopted.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.InsertOrReplaceAsync(adopted);
                        LogDebug("[SyncService] Smart Ledger push skipped: adopted newer cloud version.");
                        OnFinancesPulled?.Invoke();
                        return;
                    }

                    // Adopt canonical remote UUID so we never create duplicate smart_ledgers rows per user!
                    if (!string.Equals(canonical.Id, remoteLatest.Id.ToString(), StringComparison.OrdinalIgnoreCase))
                    {
                        var oldId = canonical.Id;
                        canonical.Id = remoteLatest.Id.ToString();
                        await _databaseService.Connection.DeleteAsync<LocalSmartLedger>(oldId);
                        await _databaseService.Connection.InsertOrReplaceAsync(canonical);
                    }
                }

                var remoteModel = Mappers.ToDomain(canonical);
                await ExecuteWithAuthAsync(() => _supabase.From<SmartLedger>().Upsert(remoteModel), "PushSmartLedger");

                canonical.SyncedAt = DateTime.UtcNow;
                await _databaseService.Connection.InsertOrReplaceAsync(canonical);
                LogDebug("[SyncService] Push Smart Ledger Success.");
            }
            catch (Exception ex)
            {
                LogSyncException("PushSmartLedgerAsync", ex);
                LogDebug($"[SyncService] Push Smart Ledger Failed: {ex.Message}");
            }
        }

        private async Task<(int Count, bool Succeeded)> PullSmartLedgerInternalAsync(string userId, DateTime lastPull)
        {
            try 
            {
                var userGuid = Guid.Parse(userId);

                // Always inspect the single latest canonical SmartLedger row for this user (tiny 1-row payload, matches macOS/iOS SmartLedgerStore)
                var remote = await ExecuteWithAuthAsync(
                    () => _supabase.From<SmartLedger>()
                        .Where(x => x.UserId == userGuid)
                        .Order("updated_at", Supabase.Postgrest.Constants.Ordering.Descending)
                        .Limit(1)
                        .Get(),
                    "PullSmartLedger");

                var rm = remote.Models.FirstOrDefault();
                if (rm != null)
                {
                    var localRows = await _databaseService.Connection.Table<LocalSmartLedger>()
                        .Where(x => x.UserId == userId)
                        .OrderByDescending(x => x.UpdatedAt)
                        .ToListAsync();

                    var existing = localRows.FirstOrDefault();
                    foreach (var extra in localRows.Skip(1))
                    {
                        await _databaseService.Connection.DeleteAsync(extra);
                    }

                    var remoteTime = rm.UpdatedAt.ToUniversalTime();
                    var localTime = existing != null ? Mappers.SafeUtc(existing.UpdatedAt) : DateTime.MinValue;
                    bool localDirty = existing != null && existing.SyncedAt == null;

                    bool shouldAdoptRemote = existing == null
                        || (!localDirty && (remoteTime > localTime || existing.LedgerText != rm.LedgerText || !string.Equals(existing.Id, rm.Id.ToString(), StringComparison.OrdinalIgnoreCase)))
                        || (localDirty && remoteTime > localTime);

                    if (shouldAdoptRemote)
                    {
                        if (existing != null && !string.Equals(existing.Id, rm.Id.ToString(), StringComparison.OrdinalIgnoreCase))
                        {
                            await _databaseService.Connection.DeleteAsync(existing);
                        }

                        var local = Mappers.ToLocal(rm);
                        local.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.InsertOrReplaceAsync(local);
                        LogDebug($"[SyncService] Pulled & merged latest Smart Ledger (updated_at={remoteTime:O}).");
                        return (1, true);
                    }
                }
                return (0, true);
            }
            catch (Exception ex)
            {
                LogSyncException("PullSmartLedgerInternalAsync", ex);
                return (0, false);
            }
        }

        // ==========================================
        // SMART LEDGER TRANSACTIONS SYNC
        // ==========================================

        private async Task PushLedgerTransactionsAsync(string userId)
        {
            var dirty = await _databaseService.Connection.Table<LocalLedgerTransaction>()
                                .Where(a => a.SyncedAt == null && a.UserId == userId)
                                .ToListAsync();
            if (dirty.Any())
            {
                LogDebug($"[SyncService] Pushing {dirty.Count} Ledger Transactions...");
                var remoteList = dirty.Select(Mappers.ToDomain).ToList();
                try 
                {
                    await ExecuteWithAuthAsync(() => _supabase.From<LedgerTransaction>().Upsert(remoteList), "PushLedgerTransactions");
                    foreach (var a in dirty)
                    {
                        a.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.UpdateAsync(a);
                    }
                    LogDebug("[SyncService] Push Ledger Transactions Success.");
                }
                catch(Exception ex)
                {
                    LogSyncException("PushLedgerTransactionsAsync", ex);
                    LogDebug($"[SyncService] Push Ledger Transactions Failed: {ex.Message}");
                }
            }
        }

        private async Task<(int Count, bool Succeeded)> PullLedgerTransactionsInternalAsync(string userId, DateTime lastPull)
        {
            try 
            {
                var userGuid = Guid.Parse(userId);
                
                // Self-healing: if local table is empty, force a full pull
                var localCount = await _databaseService.Connection.Table<LocalLedgerTransaction>().CountAsync();
                if (localCount == 0)
                {
                    lastPull = DateTime.MinValue;
                }

                var effectiveLastPull = lastPull;
                var remote = await ExecuteWithAuthAsync(() =>
                {
                    var query = _supabase.From<LedgerTransaction>().Where(x => x.UserId == userGuid);
                    if (effectiveLastPull > DateTime.MinValue)
                    {
                        var queryDate = effectiveLastPull.AddMinutes(-5);
                        query = query.Filter("created_at", global::Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, queryDate.ToString("O"));
                    }
                    return query.Get();
                }, "PullLedgerTransactions");

                if (remote.Models.Any())
                {
                    LogDebug($"[SyncService] Pulled {remote.Models.Count} Ledger Transactions.");
                    foreach (var rm in remote.Models)
                    {
                        var local = Mappers.ToLocal(rm);
                        local.SyncedAt = DateTime.UtcNow;
                        await _databaseService.Connection.InsertOrReplaceAsync(local);
                    }
                    return (remote.Models.Count, true);
                }
                return (0, true);
            }
            catch (Exception ex)
            {
                LogSyncException("PullLedgerTransactionsInternalAsync", ex);
                return (0, false);
            }
        }
    }
}
