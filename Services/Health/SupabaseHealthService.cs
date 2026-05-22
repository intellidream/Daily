using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Models.Health;
using Microsoft.Extensions.Logging;
using Supabase;
using System.Threading;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services;

namespace Daily.Services.Health
{
    public class SupabaseHealthService : IHealthService
    {
        private readonly Supabase.Client _supabase;
        private readonly INativeHealthStore _nativeHealthStore;
        private readonly ILogger<SupabaseHealthService> _logger;
        private readonly IServiceProvider _serviceProvider; // Lazy Resolution
        private readonly IRefreshService _refreshService;
        private readonly IDatabaseService _databaseService;
        private Supabase.Realtime.RealtimeChannel? _vitalsChannel;

        private bool IsAuthenticated => _supabase.Auth.CurrentSession != null && _supabase.Auth.CurrentUser != null;

        private readonly System.Threading.SemaphoreSlim _realtimeSemaphore = new(1, 1);
        private readonly System.Threading.SemaphoreSlim _syncSemaphore = new(1, 1);
        private CancellationTokenSource? _reconnectCts;
        private CancellationTokenSource? _syncDebounceCts;
        private readonly object _debounceLock = new();
        private DateTime _lastDeltaPullTime = DateTime.MinValue;
        private static bool _migrationRun = false;

        public SupabaseHealthService(
            Supabase.Client supabase, 
            INativeHealthStore nativeHealthStore, 
            ILogger<SupabaseHealthService> logger, 
            IServiceProvider serviceProvider, 
            IRefreshService refreshService,
            IDatabaseService databaseService)
        {
            try 
            {
                _supabase = supabase;
                _nativeHealthStore = nativeHealthStore;
                _logger = logger;
                _serviceProvider = serviceProvider;
                _refreshService = refreshService;
                _databaseService = databaseService;

                // Setup Auth Listener ONCE in Constructor
                _supabase.Auth.AddStateChangedListener((sender, state) => 
                {
                    Console.WriteLine($"[SupabaseHealthService] Auth State Changed: {state}");
                    if (state == Supabase.Gotrue.Constants.AuthState.SignedIn || state == Supabase.Gotrue.Constants.AuthState.SignedOut)
                    {
                         Task.Run(async () => 
                         {
                             try 
                             {
                                 await InitializeAsync();
                             }
                             catch(Exception ex)
                             {
                                 Console.WriteLine($"[SupabaseHealthService] Post-Auth Init Failed: {ex}");
                             }
                         });
                    }
                });

                _supabase.Realtime.AddStateChangedHandler((sender, state) =>
                {
                    Console.WriteLine($"[SupabaseHealthService] Realtime Socket State Changed: {state}");
                    if (state == Supabase.Realtime.Constants.SocketState.Open)
                    {
                        Console.WriteLine("[SupabaseHealthService] Realtime Socket opened/reconnected. Triggering debounced SetupRealtimeAsync...");
                        _reconnectCts?.Cancel();
                        _reconnectCts = new CancellationTokenSource();
                        var token = _reconnectCts.Token;
                        Task.Run(async () =>
                        {
                            try
                            {
                                await Task.Delay(1000, token);
                                if (!token.IsCancellationRequested)
                                    await SetupRealtimeAsync();
                            }
                            catch (TaskCanceledException) { }
                            catch (Exception ex) { Console.WriteLine($"[SupabaseHealthService] Debounced reconnect error: {ex.Message}"); }
                        });
                    }
                });
            }
            catch(Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Constructor FAULT: {ex}");
            }
        }

        public async Task InitializeAsync()
        {
            if (IsAuthenticated)
            {
                await _databaseService.InitializeAsync();
                if (!_migrationRun)
                {
                    await MigrateAndDeduplicateVitalsAsync();
                    _migrationRun = true;
                }

                await SetupRealtimeAsync();
                CheckCacheStalenessAndPullAsync();
            }
            else
            {
                // Clean up channel if logged out
                if (_vitalsChannel != null)
                {
                    try
                    {
                        _vitalsChannel.Unsubscribe();
                    }
                    catch { }
                    _vitalsChannel = null;
                }
            }
        }

        private async Task MigrateAndDeduplicateVitalsAsync()
        {
            try
            {
                Console.WriteLine("[SupabaseHealthService] Running vitals migration and deduplication...");
                var allVitals = await _databaseService.Connection.Table<LocalVitalMetric>().ToListAsync();
                if (allVitals == null || !allVitals.Any())
                {
                    Console.WriteLine("[SupabaseHealthService] No local vitals to migrate.");
                    return;
                }

                var migratedList = new List<LocalVitalMetric>();
                var grouped = allVitals.GroupBy(v => new { v.UserId, v.TypeString, Date = v.Date.NormalizeToUtcMidnight() });

                foreach (var group in grouped)
                {
                    // Pick the latest record by UpdatedAt
                    var latest = group.OrderByDescending(v => v.UpdatedAt).First();
                    
                    // Generate the deterministic ID
                    var normalizedDate = group.Key.Date;
                    var dateStr = normalizedDate.ToString("yyyy-MM-dd");
                    var expectedId = Mappers.GenerateGuid($"{latest.UserId.ToLowerInvariant()}_{latest.TypeString}_{dateStr}").ToString().ToLowerInvariant();
                    
                    latest.Id = expectedId;
                    
                    // Standardize other fields to UTC
                    latest.Date = normalizedDate;
                    latest.CreatedAt = latest.CreatedAt.SafeUtc();
                    latest.UpdatedAt = latest.UpdatedAt.SafeUtc();
                    if (latest.SyncedAt.HasValue)
                    {
                        latest.SyncedAt = latest.SyncedAt.Value.SafeUtc();
                    }

                    migratedList.Add(latest);
                }

                // Delete everything and insert the clean, migrated list inside a transaction
                await _databaseService.Connection.RunInTransactionAsync(tran =>
                {
                    tran.DeleteAll<LocalVitalMetric>();
                    foreach (var local in migratedList)
                    {
                        tran.Insert(local);
                    }
                }).ConfigureAwait(false);

                Console.WriteLine($"[SupabaseHealthService] Vitals migration completed. Deduplicated from {allVitals.Count} to {migratedList.Count} records.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Error during vitals migration: {ex.Message}");
                _logger.LogError(ex, "Failed to run vitals migration and deduplication");
            }
        }

        private async Task SetupRealtimeAsync()
        {
            if (!IsAuthenticated) return;

            await _realtimeSemaphore.WaitAsync();
            try
            {
                var token = _supabase.Auth.CurrentSession?.AccessToken;
                if (!string.IsNullOrEmpty(token))
                {
                    Console.WriteLine("[SupabaseHealthService] Propagating current session token to Realtime.");
                    _supabase.Realtime.SetAuth(token);
                }
                if (_vitalsChannel != null && !_vitalsChannel.IsJoined)
                {
                    Console.WriteLine("[SupabaseHealthService] Realtime vitals channel exists but is not joined. Removing to recreate...");
                    try
                    {
                        _supabase.Realtime.Remove(_vitalsChannel);
                    }
                    catch (Exception removeEx)
                    {
                        Console.WriteLine($"[SupabaseHealthService] Error removing channel: {removeEx.Message}");
                    }
                    _vitalsChannel = null;
                }

                if (_vitalsChannel == null)
                {
                    var userId = _supabase.Auth.CurrentUser?.Id ?? _supabase.Auth.CurrentSession?.User?.Id;
                    if (!string.IsNullOrEmpty(userId))
                    {
                        _vitalsChannel = _supabase.Realtime.Channel("realtime", "public", "vitals", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                    }
                    else
                    {
                        _vitalsChannel = _supabase.Realtime.Channel("realtime", "public", "vitals", null, null, new Dictionary<string, string>());
                    }
                    _vitalsChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnVitalReceived);
                    await _vitalsChannel.Subscribe();
                    Console.WriteLine($"[SupabaseHealthService] Realtime subscribed to vitals. Filtered user: {userId}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime setup failed: {ex.Message}");
            }
            finally
            {
                _realtimeSemaphore.Release();
            }
        }

        private async Task SaveRemoteVitalToLocalAsync(VitalMetric remoteVital)
        {
            try
            {
                var localRepresentation = remoteVital.ToLocal();
                localRepresentation.SyncedAt = DateTime.UtcNow; // Prevent sync push loop

                await _databaseService.InitializeAsync();
                await _databaseService.Connection.RunInTransactionAsync(tran =>
                {
                    // Delete any legacy duplicates matching user, type, and date with a different ID
                    tran.Execute("DELETE FROM vitals WHERE UserId = ? AND TypeString = ? AND Date = ? AND Id != ?", 
                                 localRepresentation.UserId, localRepresentation.TypeString, localRepresentation.Date, localRepresentation.Id);
                    tran.InsertOrReplace(localRepresentation);
                }).ConfigureAwait(false);

                Console.WriteLine($"[SupabaseHealthService] Realtime: Directly wrote/updated local SQLite vital {localRepresentation.Id}");

                // Trigger UI refresh
                await _refreshService.TriggerHealthRefreshAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime direct save error: {ex.Message}");
                _logger.LogError(ex, "Failed to direct-write realtime vital update");
            }
        }

        private void OnVitalReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime Vital Postgres Change received! Event: {e.Event}, Topic: {e.Topic}");
                
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return;
                }

                if (e.Event == Supabase.Realtime.Constants.EventType.Delete)
                {
                    var deletedVital = e.Model<VitalMetric>();
                    if (deletedVital != null && deletedVital.Id != Guid.Empty)
                    {
                        var deleteId = deletedVital.Id.ToString().ToLowerInvariant();
                        Console.WriteLine($"[SupabaseHealthService] Realtime: Deleting vital {deleteId} locally.");
                        Task.Run(async () =>
                        {
                            try
                            {
                                await _databaseService.InitializeAsync();
                                await _databaseService.Connection.ExecuteAsync("DELETE FROM vitals WHERE Id = ?", deleteId);
                                await _refreshService.TriggerHealthRefreshAsync();
                            }
                            catch (Exception ex)
                            {
                                Console.WriteLine($"[SupabaseHealthService] Realtime delete error: {ex.Message}");
                            }
                        });
                    }
                    return;
                }

                var remoteVital = e.Model<VitalMetric>();
                if (remoteVital == null)
                {
                    Console.WriteLine("[SupabaseHealthService] Realtime: remoteVital is NULL! Cannot parse database change.");
                    return;
                }

                string currentUserIdStr = user?.Id ?? "NULL";
                Console.WriteLine($"[SupabaseHealthService] Realtime parsed remoteVital: Id={remoteVital.Id}, UserId={remoteVital.UserId}, Type={remoteVital.TypeString}, Value={remoteVital.Value}, CurrentUserId={currentUserIdStr}");

                bool isMatch = remoteVital.UserId == uid || remoteVital.UserId == Guid.Empty;

                if (isMatch)
                {
                    Console.WriteLine($"[SupabaseHealthService] Realtime: Match found. Saving remote vital directly to local cache.");
                    Task.Run(async () =>
                    {
                        await SaveRemoteVitalToLocalAsync(remoteVital);
                    });
                }
                else
                {
                    Console.WriteLine($"[SupabaseHealthService] Realtime: User ID mismatch. remoteVital.UserId={remoteVital.UserId}, uid={user?.Id}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime Vital Error in OnVitalReceived: {ex}");
            }
        }

        public async Task PullDeltasAsync()
        {
            if (!IsAuthenticated) return;

            await _syncSemaphore.WaitAsync();
            try
            {
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return;
                }
                var userIdStr = uid.ToString().ToLowerInvariant();

                await _databaseService.InitializeAsync();

                // Find latest Local Vital Metric update time
                var latestLocal = await _databaseService.Connection.Table<LocalVitalMetric>()
                                      .Where(v => v.UserId == userIdStr)
                                      .OrderByDescending(v => v.UpdatedAt)
                                      .FirstOrDefaultAsync();

                List<VitalMetric> remoteRecords;
                if (latestLocal != null)
                {
                    var lastLocalUpdate = DateTime.SpecifyKind(latestLocal.UpdatedAt, DateTimeKind.Utc).AddMinutes(-5);
                    Console.WriteLine($"[SupabaseHealthService] Pulling vitals deltas for user {userIdStr} since {lastLocalUpdate:O} (with 5m skew buffer)");
                    var result = await _supabase.From<VitalMetric>()
                                              .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                                              .Filter("updated_at", Supabase.Postgrest.Constants.Operator.GreaterThan, lastLocalUpdate.ToString("O"))
                                              .Get();
                    remoteRecords = result.Models;
                }
                else
                {
                    // Fallback to fetch the last 30 days of data
                    var dateThreshold = DateTime.UtcNow.AddDays(-30);
                    Console.WriteLine($"[SupabaseHealthService] Cache empty. Pulling last 30 days of vitals for user {userIdStr} since {dateThreshold:O}");
                    var result = await _supabase.From<VitalMetric>()
                                              .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                                              .Filter("date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, dateThreshold.ToString("O"))
                                              .Get();
                    remoteRecords = result.Models;
                }

                if (remoteRecords != null && remoteRecords.Any())
                {
                    Console.WriteLine($"[SupabaseHealthService] Syncing {remoteRecords.Count} retrieved vitals to local SQLite (overwriting directly).");
                    
                    // Group remote records by Type and Date to find the best remote record for each day/type
                    var groupedRemotes = remoteRecords
                        .GroupBy(r => new { r.TypeString, Date = r.Date.NormalizeToUtcMidnight() })
                        .ToList();

                    var localsToSave = new List<LocalVitalMetric>();

                    foreach (var group in groupedRemotes)
                    {
                        // Determine the best remote record in this group
                        VitalMetric bestRemote;
                        if (IsCumulative(group.Key.TypeString))
                        {
                            bestRemote = group.OrderByDescending(r => r.Value).First();
                        }
                        else
                        {
                            bestRemote = group.OrderByDescending(r => r.UpdatedAt).First();
                        }

                        var localRepresentation = bestRemote.ToLocal();
                        localsToSave.Add(localRepresentation);
                    }

                    await _databaseService.Connection.RunInTransactionAsync(tran =>
                    {
                        foreach (var local in localsToSave)
                        {
                            // Delete any duplicate vitals matching user, type, and date but having a different ID
                            tran.Execute("DELETE FROM vitals WHERE UserId = ? AND TypeString = ? AND Date = ? AND Id != ?", 
                                         local.UserId, local.TypeString, local.Date, local.Id);
                            tran.InsertOrReplace(local);
                        }
                    }).ConfigureAwait(false);
                }

                _lastDeltaPullTime = DateTime.UtcNow;
                
                // Trigger UI refresh
                await _refreshService.TriggerHealthRefreshAsync();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to pull vitals deltas");
                Console.WriteLine($"[SupabaseHealthService] PullDeltasAsync Error: {ex.Message}");
            }
            finally
            {
                _syncSemaphore.Release();
            }
        }

        private void CheckCacheStalenessAndPullAsync()
        {
            if ((DateTime.UtcNow - _lastDeltaPullTime).TotalMinutes >= 15)
            {
                Task.Run(async () =>
                {
                    try
                    {
                        await PullDeltasAsync();
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SupabaseHealthService] Background delta pull failed: {ex.Message}");
                    }
                });
            }
        }

        public async Task<List<VitalMetric>> GetVitalsAsync(DateTime start, DateTime end)
        {
            try
            {
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return new List<VitalMetric>();
                }
                var userIdStr = uid.ToString().ToLowerInvariant();

                await _databaseService.InitializeAsync();

                var localVitals = await _databaseService.Connection.Table<LocalVitalMetric>()
                                      .Where(v => v.UserId == userIdStr && v.Date >= start && v.Date <= end)
                                      .OrderByDescending(v => v.Date)
                                      .ToListAsync();

                CheckCacheStalenessAndPullAsync();

                return localVitals.Select(v => v.ToDomain()).ToList();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to fetch vitals from local SQLite cache");
                return new List<VitalMetric>();
            }
        }

        public async Task<VitalMetric?> GetLatestMetricAsync(VitalType type)
        {
            try
            {
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return null;
                }
                var userIdStr = uid.ToString().ToLowerInvariant();
                var typeString = type.ToString();

                await _databaseService.InitializeAsync();

                var localRecords = await _databaseService.Connection.Table<LocalVitalMetric>()
                                      .Where(v => v.UserId == userIdStr && v.TypeString == typeString)
                                      .OrderByDescending(v => v.Date)
                                      .ToListAsync();
                var latestLocal = localRecords.OrderByDescending(v => v.Date).ThenByDescending(v => v.UpdatedAt).FirstOrDefault();

                CheckCacheStalenessAndPullAsync();

                return latestLocal?.ToDomain();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Failed to fetch latest {type} from local SQLite cache");
                return null;
            }
        }

        public async Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            try
            {
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return new List<VitalMetric>();
                }
                var userIdStr = uid.ToString().ToLowerInvariant();

                await _databaseService.InitializeAsync();

                var start = date.Date.AddDays(-30);
                var end = date.Date.AddDays(2);

                var localRecords = await _databaseService.Connection.Table<LocalVitalMetric>()
                                      .Where(v => v.UserId == userIdStr && v.Date >= start && v.Date < end)
                                      .OrderByDescending(v => v.Date)
                                      .ToListAsync();

                CheckCacheStalenessAndPullAsync();

                if (localRecords.Any())
                {
                    var latestMetrics = localRecords
                        .GroupBy(m => m.TypeString)
                        .Select(g => g.OrderByDescending(x => x.Date).ThenByDescending(x => x.UpdatedAt).First().ToDomain())
                        .ToList();

                    var sync = _serviceProvider.GetService<ISyncService>();
                    sync?.Log($"[Read] Found {latestMetrics.Count} recent metrics from local DB (Window: -30 days).");
                    return latestMetrics;
                }

                return new List<VitalMetric>();
            }
            catch (Exception ex)
            {
                var msg = $"Failed to read metrics from local SQLite cache: {ex.Message}";
                Console.WriteLine(msg);
                _logger.LogError(ex, msg);
                return new List<VitalMetric>();
            }
        }

        public async Task SyncNativeHealthDataAsync()
        {
            try 
            {
                var sync = _serviceProvider.GetService<ISyncService>();
                Action<string> log = (msg) => 
                {
                    Console.WriteLine($"[SupabaseHealthService] {msg}");
                    sync?.Log($"[Health] {msg}");
                };

                log("SyncNativeHealthDataAsync STARTED");

                if (!_nativeHealthStore.IsSupported)
                {
                    log("Native Health Store not supported (Skipping Upload). Reading handled by Widget.");
                    return;
                }

                log("Requesting Permissions...");
                var hasPermission = await _nativeHealthStore.RequestPermissionsAsync();
                if (!hasPermission)
                {
                    log("Permissions Denied.");
                    return;
                }

                log($"Fetching metrics for Today ({DateTime.Today:d}) AND Yesterday...");
                
                var metricsToday = await _nativeHealthStore.FetchMetricsAsync(DateTime.Today);
                var metricsYesterday = await _nativeHealthStore.FetchMetricsAsync(DateTime.Today.AddDays(-1));
                
                int countToday = metricsToday?.Count ?? 0;
                int countYesterday = metricsYesterday?.Count ?? 0;
                
                log($"[Fetch] Today: {countToday} items, Yesterday: {countYesterday} items.");
                
                if (countToday > 0)
                {
                    var types = string.Join(", ", metricsToday.Select(x => x.TypeString).Distinct());
                    log($"[Fetch] Today's Types: {types}");
                }

                var metrics = new List<VitalMetric>();
                if (metricsToday != null) metrics.AddRange(metricsToday);
                if (metricsYesterday != null) metrics.AddRange(metricsYesterday);
                
                if (!metrics.Any())
                {
                    log("No health metrics found locally (Today or Yesterday). Aborting Upload.");
                    return;
                }

                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                
                if (user == null) 
                {
                     log("ABORT: User is NULL.");
                     return;
                }

                if (!Guid.TryParse(user.Id, out var uid))
                {
                    log("ABORT: Invalid User ID.");
                    return;
                }

                try 
                {
                    var minDate = metrics.Min(m => m.Date);
                    var maxDate = metrics.Max(m => m.Date);

                    var minDateStr = minDate.ToString("O");
                    var maxDateStr = maxDate.ToString("O");

                    var existingResult = await _supabase.From<VitalMetric>()
                                              .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, uid.ToString())
                                              .Filter("date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, minDateStr)
                                              .Filter("date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, maxDateStr)
                                              .Get();
                    
                    var existingMetrics = existingResult.Models;
                    
                    foreach (var local in metrics)
                    {
                        local.UserId = uid;
                        local.UpdatedAt = DateTime.UtcNow;
                        local.SyncedAt = DateTime.Now; // Local device time

                        var remoteGroup = existingMetrics.Where(e => e.Date.SafeUtc().Date == local.Date.SafeUtc().Date && e.TypeString == local.TypeString).ToList();
                        if (remoteGroup.Any())
                        {
                            // Find the best remote record for comparison
                            VitalMetric remote = IsCumulative(local.TypeString) 
                                ? remoteGroup.OrderByDescending(r => r.Value).First()
                                : remoteGroup.OrderByDescending(r => r.UpdatedAt).First();

                            local.Id = remote.Id;
                            if (IsCumulative(local.TypeString))
                            {
                                if (remote.Value > local.Value)
                                {
                                    log($"[Sync] Keeping Remote (Cumulative) {local.TypeString}: {remote.Value} (Local: {local.Value})");
                                    local.Value = remote.Value;
                                    local.SourceDevice = remote.SourceDevice;
                                    local.Unit = remote.Unit;
                                }
                            }
                        }
                    }

                    var upsertOptions = new Supabase.Postgrest.QueryOptions
                    {
                        Upsert = true,
                        OnConflict = "user_id, date, type" 
                    };

                    var response = await _supabase.From<VitalMetric>().Upsert(metrics, upsertOptions);
                    log($"[Sync] Upserted {response.Models.Count} merged records successfully.");

                    // Save upserted/synced records to local SQLite
                    var localVitals = metrics.Select(m => m.ToLocal()).ToList();
                    await _databaseService.Connection.RunInTransactionAsync(tran =>
                    {
                        foreach (var local in localVitals)
                        {
                            tran.Execute("DELETE FROM vitals WHERE UserId = ? AND TypeString = ? AND Date = ? AND Id != ?", 
                                         local.UserId, local.TypeString, local.Date, local.Id);
                            tran.InsertOrReplace(local);
                        }
                    }).ConfigureAwait(false);
                    log($"[Sync] Saved {localVitals.Count} metrics locally in SQLite.");
                    await _refreshService.TriggerHealthRefreshAsync();
                }
                catch (Supabase.Postgrest.Exceptions.PostgrestException pex)
                {
                     log($"Postgrest Error: {pex.Message}");
                     throw;
                }
                catch (Exception ex)
                {
                    log($"Sync Preparation/Execution Failed: {ex.Message}");
                    throw;
                }
            }
            catch (Exception ex)
            {
                var msg = $"Fatal Health Sync Error: {ex.Message}";
                Console.WriteLine(msg);
                _logger.LogError(ex, msg);
                
                 var sync = _serviceProvider.GetService<ISyncService>();
                 sync?.Log($"[Health] {msg}");
            }
        }

        public async Task<List<VitalMetric>> GetHistoryAsync(VitalType type, int days = 7)
        {
            try
            {
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return new List<VitalMetric>();
                }
                var userIdStr = uid.ToString().ToLowerInvariant();
                var typeString = type.ToString();

                var start = DateTime.UtcNow.Date.AddDays(-days);
                var end = DateTime.UtcNow.Date.AddDays(1);

                await _databaseService.InitializeAsync();

                Console.WriteLine($"[Health History] Querying {typeString} from {start:O} to {end:O} locally");

                var localHistory = await _databaseService.Connection.Table<LocalVitalMetric>()
                                      .Where(v => v.UserId == userIdStr && v.TypeString == typeString && v.Date >= start && v.Date < end)
                                      .OrderBy(v => v.Date)
                                      .ToListAsync();

                CheckCacheStalenessAndPullAsync();

                Console.WriteLine($"[Health History] Got {localHistory.Count} records for {typeString} from local DB");
                return localHistory.Select(v => v.ToDomain()).ToList();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Failed to fetch history for {type} from local SQLite cache");
                Console.WriteLine($"[Health History] ERROR for {type}: {ex.Message}");
                return new List<VitalMetric>();
            }
        }

        private bool IsCumulative(string typeString)
        {
            if (Enum.TryParse<VitalType>(typeString, out var type))
            {
                return type switch
                {
                    VitalType.Steps => true,
                    VitalType.ActiveEnergy => true,
                    VitalType.BasalEnergyBurned => true, // Resting Cal
                    VitalType.Distance => true,
                    VitalType.FloorsClimbed => true,
                    VitalType.Hydration => true, 
                    VitalType.Carbs => true,
                    VitalType.Fat => true,
                    VitalType.Protein => true,
                    VitalType.Caffeine => true,
                    VitalType.SleepDuration => true, 
                    _ => false 
                };
            }
            return false;
        }
    }
}
