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
        private Supabase.Realtime.RealtimeChannel? _healthVitalsChannel;
        private Supabase.Realtime.RealtimeChannel? _telemetryChannel;
        private Supabase.Gotrue.Interfaces.IGotrueClient<Supabase.Gotrue.User, Supabase.Gotrue.Session>.AuthEventHandler? _authStateChangedHandler;
        private Supabase.Realtime.Interfaces.IRealtimeClient<Supabase.Realtime.RealtimeSocket, Supabase.Realtime.RealtimeChannel>.SocketStateEventHandler? _realtimeStateChangedHandler;

        private bool IsAuthenticated => _supabase.Auth.CurrentSession != null && _supabase.Auth.CurrentUser != null;

        private string _currentViewType = "Overview";
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
        public event Action? OnViewTypeChanged;

        private DateTime _selectedDate = DateTime.Today;
        public DateTime SelectedDate
        {
            get => _selectedDate;
            set
            {
                if (_selectedDate.Date != value.Date)
                {
                    _selectedDate = value.Date;
                    OnSelectedDateChanged?.Invoke();
                }
            }
        }
        public event Action? OnSelectedDateChanged;

        private async Task EnsureFreshSessionAsync()
        {
            var auth = _supabase.Auth;
            if (auth?.CurrentSession != null && auth.CurrentSession.Expired())
            {
                try
                {
                    var sync = _serviceProvider.GetService<ISyncService>();
                    sync?.Log("[SupabaseHealthService] Session token is expired. Proactively refreshing session...");
                    await auth.RefreshSession();
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[SupabaseHealthService] Proactive session refresh failed: {ex.Message}");
                }
            }
        }

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
                _authStateChangedHandler = (sender, state) => 
                {
                    Console.WriteLine($"[SupabaseHealthService] Auth State Changed: {state}");
                    if (state == Supabase.Gotrue.Constants.AuthState.SignedIn || 
                        state == Supabase.Gotrue.Constants.AuthState.SignedOut)
                    {
                          Task.Run(async () => 
                          {
                              try 
                              {
                                  await InitializeAsync(forceRecreateRealtime: false);
                              }
                              catch(Exception ex)
                              {
                                  Console.WriteLine($"[SupabaseHealthService] Post-Auth Init Failed: {ex}");
                              }
                          });
                    }
                };
                _supabase.Auth.AddStateChangedListener(_authStateChangedHandler);

                _realtimeStateChangedHandler = (sender, state) =>
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
                                {
                                    await SetupRealtimeAsync();
                                    Console.WriteLine("[SupabaseHealthService] Reconnected. Triggering background health catch-up pull...");
                                    _ = PullDeltasAsync();
                                }
                            }
                            catch (TaskCanceledException) { }
                            catch (Exception ex) { Console.WriteLine($"[SupabaseHealthService] Debounced reconnect error: {ex.Message}"); }
                        });
                    }
                };
                _supabase.Realtime.AddStateChangedHandler(_realtimeStateChangedHandler);
            }
            catch(Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Constructor FAULT: {ex}");
            }
        }

        public async Task InitializeAsync(bool forceRecreateRealtime = false)
        {
            if (IsAuthenticated)
            {
                await _databaseService.InitializeAsync();
                if (!_migrationRun)
                {
                    await MigrateAndDeduplicateVitalsAsync();
                    _migrationRun = true;
                }

                await SetupRealtimeAsync(forceRecreateRealtime);
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
                if (_healthVitalsChannel != null)
                {
                    try
                    {
                        _healthVitalsChannel.Unsubscribe();
                    }
                    catch { }
                    _healthVitalsChannel = null;
                }
                if (_telemetryChannel != null)
                {
                    try
                    {
                        _telemetryChannel.Unsubscribe();
                    }
                    catch { }
                    _telemetryChannel = null;
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

        private async Task SetupRealtimeAsync(bool forceRecreate = false)
        {
            if (!IsAuthenticated) return;

            await _realtimeSemaphore.WaitAsync();
            try
            {
                await EnsureFreshSessionAsync();
                var token = _supabase.Auth.CurrentSession?.AccessToken;
                if (!string.IsNullOrEmpty(token))
                {
                    Console.WriteLine("[SupabaseHealthService] Propagating current session token to Realtime.");
                    _supabase.Realtime.SetAuth(token);
                }
                
                if (forceRecreate && _vitalsChannel != null)
                {
                    Console.WriteLine("[SupabaseHealthService] Force recreating realtime vitals channel due to token refresh.");
                    try { _vitalsChannel.Unsubscribe(); } catch { }
                    try { _supabase.Realtime.Remove(_vitalsChannel); } catch { }
                    _vitalsChannel = null;
                }
                
                if (forceRecreate && _healthVitalsChannel != null)
                {
                    try { _healthVitalsChannel.Unsubscribe(); } catch { }
                    try { _supabase.Realtime.Remove(_healthVitalsChannel); } catch { }
                    _healthVitalsChannel = null;
                }

                if (forceRecreate && _telemetryChannel != null)
                {
                    try { _telemetryChannel.Unsubscribe(); } catch { }
                    try { _supabase.Realtime.Remove(_telemetryChannel); } catch { }
                    _telemetryChannel = null;
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
                
                if (_healthVitalsChannel != null && !_healthVitalsChannel.IsJoined)
                {
                    try
                    {
                        _supabase.Realtime.Remove(_healthVitalsChannel);
                    }
                    catch { }
                    _healthVitalsChannel = null;
                }

                if (_telemetryChannel != null && !_telemetryChannel.IsJoined)
                {
                    try
                    {
                        _supabase.Realtime.Remove(_telemetryChannel);
                    }
                    catch { }
                    _telemetryChannel = null;
                }

                if (_vitalsChannel == null)
                {
                    var userId = _supabase.Auth.CurrentUser?.Id ?? _supabase.Auth.CurrentSession?.User?.Id;
                    if (!string.IsNullOrEmpty(userId))
                    {
                        _vitalsChannel = _supabase.Realtime.Channel("realtime", "public", "vitals", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                        _healthVitalsChannel = _supabase.Realtime.Channel("realtime_health", "public", "health_vitals", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                        _telemetryChannel = _supabase.Realtime.Channel("realtime_telemetry", "public", "health_telemetry", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                    }
                    else
                    {
                        _vitalsChannel = _supabase.Realtime.Channel("realtime", "public", "vitals", null, null, new Dictionary<string, string>());
                        _healthVitalsChannel = _supabase.Realtime.Channel("realtime_health", "public", "health_vitals", null, null, new Dictionary<string, string>());
                        _telemetryChannel = _supabase.Realtime.Channel("realtime_telemetry", "public", "health_telemetry", null, null, new Dictionary<string, string>());
                    }
                    _vitalsChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnVitalReceived);
                    await _vitalsChannel.Subscribe();
                    
                    if (_healthVitalsChannel != null)
                    {
                        _healthVitalsChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnHealthVitalReceived);
                        await _healthVitalsChannel.Subscribe();
                    }

                    if (_telemetryChannel != null)
                    {
                        _telemetryChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnTelemetryReceived);
                        await _telemetryChannel.Subscribe();
                    }
                    
                    Console.WriteLine($"[SupabaseHealthService] Realtime subscribed to vitals, health_vitals, and health_telemetry. Filtered user: {userId}");
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

        private void OnHealthVitalReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime HealthVital Postgres Change received! Event: {e.Event}, Topic: {e.Topic}");
                
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    return;
                }

                if (e.Event == Supabase.Realtime.Constants.EventType.Delete)
                {
                    var deletedVital = e.Model<HealthVitalMetric>();
                    if (deletedVital != null && deletedVital.Id != Guid.Empty)
                    {
                        var deleteId = deletedVital.Id.ToString().ToLowerInvariant();
                        Console.WriteLine($"[SupabaseHealthService] Realtime: Deleting health_vitals {deleteId} locally.");
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

                var remoteVital = e.Model<HealthVitalMetric>();
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
                    Console.WriteLine($"[SupabaseHealthService] Realtime: Match found. Saving remote health_vital directly to local cache.");
                    Task.Run(async () =>
                    {
                        await SaveRemoteVitalToLocalAsync(remoteVital.ToVitalMetric());
                    });
                }
                else
                {
                    Console.WriteLine($"[SupabaseHealthService] Realtime: User ID mismatch. remoteVital.UserId={remoteVital.UserId}, uid={user?.Id}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime HealthVital Error in OnHealthVitalReceived: {ex}");
            }
        }

        private void OnTelemetryReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime HealthTelemetry change received! Event: {e.Event}, Topic: {e.Topic}");
                Task.Run(async () =>
                {
                    await _refreshService.TriggerHealthRefreshAsync();
                });
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime Telemetry Error in OnTelemetryReceived: {ex}");
            }
        }

        public async Task PullDeltasAsync()
        {
            if (!IsAuthenticated) return;

            await _syncSemaphore.WaitAsync();
            try
            {
                _lastDeltaPullTime = DateTime.UtcNow;
                await EnsureFreshSessionAsync();
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

                List<VitalMetric> remoteRecords = new();
                if (latestLocal != null)
                {
                    var lastLocalUpdate = DateTime.SpecifyKind(latestLocal.UpdatedAt, DateTimeKind.Utc).AddMinutes(-5);
                    Console.WriteLine($"[SupabaseHealthService] Pulling vitals deltas for user {userIdStr} since {lastLocalUpdate:O} (with 5m skew buffer)");
                    var result = await _supabase.From<VitalMetric>()
                                              .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                                              .Filter("updated_at", Supabase.Postgrest.Constants.Operator.GreaterThan, lastLocalUpdate.ToString("O"))
                                              .Get();
                    if (result.Models != null) remoteRecords.AddRange(result.Models);

                    try
                    {
                        var hvResult = await _supabase.From<HealthVitalMetric>()
                                                  .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                                                  .Filter("updated_at", Supabase.Postgrest.Constants.Operator.GreaterThan, lastLocalUpdate.ToString("O"))
                                                  .Get();
                        if (hvResult.Models != null && hvResult.Models.Any())
                        {
                            remoteRecords.AddRange(hvResult.Models.Select(hv => hv.ToVitalMetric()));
                        }
                    }
                    catch (Exception hvex)
                    {
                        Console.WriteLine($"[SupabaseHealthService] Non-fatal error pulling health_vitals deltas: {hvex.Message}");
                    }
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
                    if (result.Models != null) remoteRecords.AddRange(result.Models);

                    try
                    {
                        var hvResult = await _supabase.From<HealthVitalMetric>()
                                                  .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                                                  .Filter("date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, dateThreshold.ToString("O"))
                                                  .Get();
                        if (hvResult.Models != null && hvResult.Models.Any())
                        {
                            remoteRecords.AddRange(hvResult.Models.Select(hv => hv.ToVitalMetric()));
                        }
                    }
                    catch (Exception hvex)
                    {
                        Console.WriteLine($"[SupabaseHealthService] Non-fatal error pulling health_vitals initial: {hvex.Message}");
                    }
                }

                if (remoteRecords != null && remoteRecords.Any())
                {
                    Console.WriteLine($"[SupabaseHealthService] Syncing {remoteRecords.Count} retrieved vitals to local SQLite (overwriting directly).");
                    
                    // Group remote records by Type and Date to find the best remote record for each day/type
                    var groupedRemotes = remoteRecords
                        .GroupBy(r => new { r.Type, Date = r.Date.NormalizeToUtcMidnight() })
                        .ToList();

                    var localsToSave = new List<LocalVitalMetric>();

                    foreach (var group in groupedRemotes)
                    {
                        // Determine the best remote record in this group
                        VitalMetric bestRemote;
                        var typeString = group.Key.Type.ToString();
                        if (IsCumulative(typeString))
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
            return await FetchMetricsForDateAsync(date);
        }

        public async Task<List<VitalMetric>> FetchMetricsForDateAsync(DateTime date)
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

                var targetDate = date.Date;
                var nextDate = targetDate.AddDays(1);

                // 1. Fetch exact date records from local SQLite
                var localRecords = await _databaseService.Connection.Table<LocalVitalMetric>()
                                      .Where(v => v.UserId == userIdStr && v.Date >= targetDate && v.Date < nextDate)
                                      .ToListAsync();

                var resultMetrics = new Dictionary<VitalType, VitalMetric>();

                foreach (var rec in localRecords)
                {
                    var domain = rec.ToDomain();
                    var vType = domain.Type;
                    if (!resultMetrics.ContainsKey(vType) || domain.UpdatedAt > resultMetrics[vType].UpdatedAt)
                    {
                        resultMetrics[vType] = domain;
                    }
                }

                // 2. Aggregate from health_telemetry for this exact day if telemetry has data
                try
                {
                    var startOfDay = targetDate;
                    var endOfDay = nextDate.AddTicks(-1);
                    var telemetryToday = await GetHealthTelemetryAsync(startOfDay, endOfDay);

                    if (telemetryToday != null && telemetryToday.Any())
                    {
                        // Steps
                        var tSteps = telemetryToday.Where(x => x.IsSteps && x.LocalStartTime.Date == targetDate).Sum(x => x.Value ?? 0);
                        if (tSteps > 0)
                        {
                            if (!resultMetrics.ContainsKey(VitalType.Steps) || tSteps > resultMetrics[VitalType.Steps].Value)
                            {
                                resultMetrics[VitalType.Steps] = new VitalMetric
                                {
                                    Type = VitalType.Steps,
                                    Value = tSteps,
                                    Unit = "count",
                                    Date = targetDate,
                                    SourceDevice = telemetryToday.FirstOrDefault(x => x.IsSteps)?.SourceDevice ?? "Wearable"
                                };
                            }
                        }

                        // Active Energy
                        var tCal = telemetryToday.Where(x => x.IsActiveEnergy && x.LocalStartTime.Date == targetDate).Sum(x => x.Value ?? 0);
                        if (tCal > 0)
                        {
                            if (!resultMetrics.ContainsKey(VitalType.ActiveEnergy) || tCal > resultMetrics[VitalType.ActiveEnergy].Value)
                            {
                                resultMetrics[VitalType.ActiveEnergy] = new VitalMetric
                                {
                                    Type = VitalType.ActiveEnergy,
                                    Value = tCal,
                                    Unit = "kcal",
                                    Date = targetDate,
                                    SourceDevice = telemetryToday.FirstOrDefault(x => x.IsActiveEnergy)?.SourceDevice ?? "Wearable"
                                };
                            }
                        }

                        // Heart Rate (most recent reading of the day)
                        var hrEntries = telemetryToday.Where(x => x.IsHeartRate && x.LocalStartTime.Date == targetDate && x.Value.HasValue)
                                                      .OrderByDescending(x => x.StartTime)
                                                      .ToList();
                        if (hrEntries.Any() && !resultMetrics.ContainsKey(VitalType.HeartRate))
                        {
                            var latestHr = hrEntries.First();
                            resultMetrics[VitalType.HeartRate] = new VitalMetric
                            {
                                Type = VitalType.HeartRate,
                                Value = latestHr.Value!.Value,
                                Unit = "bpm",
                                Date = targetDate,
                                SourceDevice = latestHr.SourceDevice ?? "Wearable"
                            };
                        }

                        // Stress from telemetry
                        var stressEntries = telemetryToday.Where(x => x.NormalizedType == "stress" && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (stressEntries.Any() && !resultMetrics.ContainsKey(VitalType.Stress))
                        {
                            resultMetrics[VitalType.Stress] = new VitalMetric
                            {
                                Type = VitalType.Stress,
                                Value = Math.Round(stressEntries.Average(x => x.Value!.Value), 0),
                                Unit = "score",
                                Date = targetDate,
                                SourceDevice = stressEntries.First().SourceDevice ?? "Wearable"
                            };
                        }

                        // PAI from telemetry
                        var paiEntries = telemetryToday.Where(x => x.NormalizedType == "pai" && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (paiEntries.Any() && !resultMetrics.ContainsKey(VitalType.PAI))
                        {
                            resultMetrics[VitalType.PAI] = new VitalMetric
                            {
                                Type = VitalType.PAI,
                                Value = paiEntries.OrderByDescending(x => x.StartTime).First().Value!.Value,
                                Unit = "score",
                                Date = targetDate,
                                SourceDevice = paiEntries.First().SourceDevice ?? "Wearable"
                            };
                        }

                        // Distance from telemetry
                        var distEntries = telemetryToday.Where(x => x.NormalizedType == "distance" && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (distEntries.Any() && (!resultMetrics.ContainsKey(VitalType.Distance) || distEntries.Sum(x => x.Value!.Value) > resultMetrics[VitalType.Distance].Value))
                        {
                            var totalDist = distEntries.Sum(x => x.Value!.Value);
                            resultMetrics[VitalType.Distance] = new VitalMetric
                            {
                                Type = VitalType.Distance,
                                Value = Math.Round(totalDist, 2),
                                Unit = distEntries.First().Unit ?? "m",
                                Date = targetDate,
                                SourceDevice = distEntries.First().SourceDevice ?? "Wearable"
                            };
                        }

                        // SpO2 / Blood Oxygen from telemetry
                        var spo2Entries = telemetryToday.Where(x => (x.NormalizedType == "bloodoxygen" || x.NormalizedType == "oxygensaturation" || x.NormalizedType == "spo2") && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (spo2Entries.Any() && !resultMetrics.ContainsKey(VitalType.OxygenSaturation))
                        {
                            var latestSpo2 = spo2Entries.OrderByDescending(x => x.StartTime).First();
                            var val = latestSpo2.Value!.Value;
                            if (val <= 1.0 && val > 0) val *= 100.0;
                            resultMetrics[VitalType.OxygenSaturation] = new VitalMetric
                            {
                                Type = VitalType.OxygenSaturation,
                                Value = Math.Round(val, 1),
                                Unit = "%",
                                Date = targetDate,
                                SourceDevice = latestSpo2.SourceDevice ?? "Wearable"
                            };
                        }

                        // HRV from telemetry
                        var hrvEntries = telemetryToday.Where(x => (x.NormalizedType == "hrv" || x.NormalizedType == "hrvsdnn" || x.NormalizedType == "heartratevariabilitysdnn" || x.NormalizedType == "heartratevariabilityrmssd" || x.NormalizedType == "hrvrmssd") && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (hrvEntries.Any() && !resultMetrics.ContainsKey(VitalType.HeartRateVariabilitySDNN))
                        {
                            var latestHrv = hrvEntries.OrderByDescending(x => x.StartTime).First();
                            resultMetrics[VitalType.HeartRateVariabilitySDNN] = new VitalMetric
                            {
                                Type = VitalType.HeartRateVariabilitySDNN,
                                Value = Math.Round(latestHrv.Value!.Value, 1),
                                Unit = "ms",
                                Date = targetDate,
                                SourceDevice = latestHrv.SourceDevice ?? "Wearable"
                            };
                        }

                        // Respiratory rate from telemetry
                        var respEntries = telemetryToday.Where(x => (x.NormalizedType == "respiratoryrate" || x.NormalizedType == "resp") && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (respEntries.Any() && !resultMetrics.ContainsKey(VitalType.RespiratoryRate))
                        {
                            var latestResp = respEntries.OrderByDescending(x => x.StartTime).First();
                            resultMetrics[VitalType.RespiratoryRate] = new VitalMetric
                            {
                                Type = VitalType.RespiratoryRate,
                                Value = Math.Round(latestResp.Value!.Value, 1),
                                Unit = "brpm",
                                Date = targetDate,
                                SourceDevice = latestResp.SourceDevice ?? "Wearable"
                            };
                        }

                        // Daytime Nap duration from telemetry
                        var napEntries = telemetryToday.Where(x => (x.NormalizedType == "sleepnap" || x.NormalizedType == "nap") && x.LocalStartTime.Date == targetDate && x.Value.HasValue).ToList();
                        if (napEntries.Any() && !resultMetrics.ContainsKey(VitalType.NapDuration))
                        {
                            double totalNapMins = 0;
                            foreach (var nap in napEntries)
                            {
                                var u = nap.Unit?.ToLowerInvariant();
                                if (u == "hours" || u == "h") totalNapMins += (nap.Value!.Value * 60.0);
                                else if (u == "seconds" || u == "s") totalNapMins += (nap.Value!.Value / 60.0);
                                else totalNapMins += nap.Value!.Value;
                            }
                            resultMetrics[VitalType.NapDuration] = new VitalMetric
                            {
                                Type = VitalType.NapDuration,
                                Value = Math.Round(totalNapMins, 0),
                                Unit = "min",
                                Date = targetDate,
                                SourceDevice = napEntries.First().SourceDevice ?? "Wearable"
                            };
                        }
                    }
                }
                catch (Exception tex)
                {
                    Console.WriteLine($"[SupabaseHealthService] Non-fatal error aggregating telemetry for date: {tex.Message}");
                }

                // Check if Hydration can be retrieved from habits if not in vitals
                if (!resultMetrics.ContainsKey(VitalType.Hydration))
                {
                    try
                    {
                        var waterSummary = await _databaseService.Connection.Table<LocalDailySummary>()
                            .Where(s => s.UserId == userIdStr && s.HabitType == "water" && s.Date >= targetDate && s.Date < nextDate)
                            .FirstOrDefaultAsync();
                        if (waterSummary != null && waterSummary.TotalValue > 0)
                        {
                            resultMetrics[VitalType.Hydration] = new VitalMetric
                            {
                                Type = VitalType.Hydration,
                                Value = waterSummary.TotalValue,
                                Unit = "ml",
                                Date = targetDate,
                                SourceDevice = "Habits"
                            };
                        }
                        else
                        {
                            var waterLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                                .Where(l => l.UserId == userIdStr && l.HabitType == "water" && !l.IsDeleted && l.LoggedAt >= targetDate && l.LoggedAt < nextDate)
                                .ToListAsync();
                            if (waterLogs.Any())
                            {
                                var totalWater = waterLogs.Sum(x => x.Value);
                                if (totalWater > 0)
                                {
                                    resultMetrics[VitalType.Hydration] = new VitalMetric
                                    {
                                        Type = VitalType.Hydration,
                                        Value = totalWater,
                                        Unit = waterLogs.First().Unit ?? "ml",
                                        Date = targetDate,
                                        SourceDevice = "Habits"
                                    };
                                }
                            }
                        }
                    }
                    catch { }
                }

                // Check Caffeine from habits if not in vitals
                if (!resultMetrics.ContainsKey(VitalType.Caffeine))
                {
                    try
                    {
                        var cafLogs = await _databaseService.Connection.Table<LocalHabitLog>()
                            .Where(l => l.UserId == userIdStr && (l.HabitType == "caffeine" || l.HabitType == "coffee") && !l.IsDeleted && l.LoggedAt >= targetDate && l.LoggedAt < nextDate)
                            .ToListAsync();
                        if (cafLogs.Any())
                        {
                            var totalCaf = cafLogs.Sum(x => x.Value);
                            if (totalCaf > 0)
                            {
                                resultMetrics[VitalType.Caffeine] = new VitalMetric
                                {
                                    Type = VitalType.Caffeine,
                                    Value = totalCaf,
                                    Unit = "mg",
                                    Date = targetDate,
                                    SourceDevice = "Habits"
                                };
                            }
                        }
                    }
                    catch { }
                }

                // 3. For Persistent Snapshot Metrics ONLY (Weight, Height, Body Fat, Blood Pressure, Glucose):
                // If not recorded on targetDate, look for the most recent historical reading, marked as IsHistorical = true
                var persistentTypes = new[] 
                { 
                    VitalType.Weight, 
                    VitalType.Height, 
                    VitalType.BodyFatPercentage, 
                    VitalType.LeanBodyMass, 
                    VitalType.BoneMass, 
                    VitalType.BloodPressureSystolic, 
                    VitalType.BloodPressureDiastolic, 
                    VitalType.BloodGlucose 
                };

                foreach (var pType in persistentTypes)
                {
                    if (!resultMetrics.ContainsKey(pType))
                    {
                        var pTypeStr = pType.ToString();
                        var pastRecord = await _databaseService.Connection.Table<LocalVitalMetric>()
                                              .Where(v => v.UserId == userIdStr && v.Date < targetDate && (v.TypeString == pTypeStr || v.TypeString == pTypeStr.ToLowerInvariant()))
                                              .OrderByDescending(v => v.Date)
                                              .FirstOrDefaultAsync();
                        if (pastRecord != null)
                        {
                            var dom = pastRecord.ToDomain();
                            dom.IsHistorical = true;
                            resultMetrics[pType] = dom;
                        }
                    }
                }

                CheckCacheStalenessAndPullAsync();

                return resultMetrics.Values.ToList();
            }
            catch (Exception ex)
            {
                var msg = $"Failed to read metrics from local SQLite cache for date: {ex.Message}";
                Console.WriteLine(msg);
                _logger.LogError(ex, msg);
                return new List<VitalMetric>();
            }
        }

        public async Task<(SleepSession? PrimarySession, List<SleepSession> AllSessions)> GetSleepSessionsAsync(DateTime date)
        {
            var allSessions = new List<SleepSession>();
            try
            {
                var targetDate = date.Date;
                var windowStart = targetDate.AddDays(-1).AddHours(18); // yesterday 18:00
                var windowEnd = targetDate.AddHours(16); // today 16:00

                var telemetry = await GetHealthTelemetryAsync(windowStart, windowEnd);
                var sleepTelemetry = telemetry
                    .Where(x => x.IsSleep && x.LocalStartTime >= windowStart && x.LocalStartTime <= windowEnd)
                    .OrderBy(x => x.LocalStartTime)
                    .ToList();

                if (sleepTelemetry.Any())
                {
                    // Cluster stages into distinct sessions if gap between stages >= 90 minutes
                    var currentCluster = new List<HealthTelemetry> { sleepTelemetry[0] };

                    for (int i = 1; i < sleepTelemetry.Count; i++)
                    {
                        var prev = currentCluster.Last();
                        var curr = sleepTelemetry[i];
                        var gap = (curr.LocalStartTime - prev.LocalEndTime).TotalMinutes;

                        if (gap < 90)
                        {
                            currentCluster.Add(curr);
                        }
                        else
                        {
                            var s = CreateSessionFromStages(currentCluster, targetDate);
                            if (s.DurationSeconds >= 600) // at least 10 minutes
                            {
                                allSessions.Add(s);
                            }
                            currentCluster = new List<HealthTelemetry> { curr };
                        }
                    }

                    if (currentCluster.Any())
                    {
                        var s = CreateSessionFromStages(currentCluster, targetDate);
                        if (s.DurationSeconds >= 600)
                        {
                            allSessions.Add(s);
                        }
                    }
                }

                // If no telemetry sessions formed, fallback to check aggregated vitals for targetDate
                if (!allSessions.Any())
                {
                    var vitals = await FetchMetricsForDateAsync(targetDate);
                    var sleepM = vitals.FirstOrDefault(v => v.MatchesType(VitalType.SleepDuration));
                    if (sleepM != null && sleepM.Value > 0)
                    {
                        var deepM = vitals.FirstOrDefault(v => v.MatchesType(VitalType.SleepDeep))?.Value ?? 0;
                        var remM = vitals.FirstOrDefault(v => v.MatchesType(VitalType.SleepREM))?.Value ?? 0;
                        var lightM = vitals.FirstOrDefault(v => v.MatchesType(VitalType.SleepLight))?.Value ?? 0;
                        var awakeM = vitals.FirstOrDefault(v => v.MatchesType(VitalType.SleepAwake))?.Value ?? 0;

                        var syntheticSession = new SleepSession
                        {
                            StartTime = targetDate.AddHours(-1).AddMinutes(-30),
                            EndTime = targetDate.AddHours(7),
                            IsNap = false
                        };

                        var t = syntheticSession.StartTime;
                        if (awakeM > 0)
                        {
                            syntheticSession.Stages.Add(new HealthTelemetry { TypeString = "SleepAwake", Value = awakeM, Unit = "minutes", StartTime = t.ToUniversalTime(), EndTime = t.AddMinutes(awakeM).ToUniversalTime() });
                            t = t.AddMinutes(awakeM);
                        }
                        if (lightM > 0)
                        {
                            syntheticSession.Stages.Add(new HealthTelemetry { TypeString = "SleepLight", Value = lightM, Unit = "minutes", StartTime = t.ToUniversalTime(), EndTime = t.AddMinutes(lightM).ToUniversalTime() });
                            t = t.AddMinutes(lightM);
                        }
                        if (deepM > 0)
                        {
                            syntheticSession.Stages.Add(new HealthTelemetry { TypeString = "SleepDeep", Value = deepM, Unit = "minutes", StartTime = t.ToUniversalTime(), EndTime = t.AddMinutes(deepM).ToUniversalTime() });
                            t = t.AddMinutes(deepM);
                        }
                        if (remM > 0)
                        {
                            syntheticSession.Stages.Add(new HealthTelemetry { TypeString = "SleepREM", Value = remM, Unit = "minutes", StartTime = t.ToUniversalTime(), EndTime = t.AddMinutes(remM).ToUniversalTime() });
                        }

                        allSessions.Add(syntheticSession);
                    }
                }

                // Pick primary nocturnal session:
                // Prioritize sessions waking up in morning of targetDate (04:00 to 14:00) with largest duration
                var primary = allSessions
                    .OrderByDescending(s => !s.IsNap)
                    .ThenByDescending(s => s.AsleepSeconds)
                    .FirstOrDefault();

                return (primary, allSessions);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error clustering sleep sessions");
                return (null, allSessions);
            }
        }

        private SleepSession CreateSessionFromStages(List<HealthTelemetry> stages, DateTime targetDate)
        {
            var start = stages.Min(x => x.LocalStartTime);
            var end = stages.Max(x => x.LocalEndTime);
            var isNap = (end - start).TotalHours < 3.5 && (start.Date == targetDate && start.Hour >= 11);

            return new SleepSession
            {
                StartTime = start,
                EndTime = end,
                IsNap = isNap,
                Stages = stages
            };
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
                
                if (metricsToday != null && metricsToday.Any())
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
                    await EnsureFreshSessionAsync();
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

        public async Task<List<HealthTelemetry>> GetHealthTelemetryAsync(DateTime start, DateTime end)
        {
            try
            {
                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                if (user == null || !Guid.TryParse(user.Id, out var uid))
                {
                    Console.WriteLine("[SupabaseHealthService] GetHealthTelemetryAsync: User is not authenticated or Id is invalid.");
                    return new List<HealthTelemetry>();
                }
                var userIdStr = uid.ToString().ToLowerInvariant();

                // Convert to UTC strings for PostgREST
                var startStr = start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");
                var endStr = end.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ");

                Console.WriteLine($"[SupabaseHealthService] Fetching telemetry for user {userIdStr} between {startStr} and {endStr}...");

                var result = await _supabase.From<HealthTelemetry>()
                                          .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, userIdStr)
                                          .Filter("start_time", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                                          .Filter("start_time", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                                          .Order("start_time", Supabase.Postgrest.Constants.Ordering.Ascending)
                                          .Limit(5000)
                                          .Get();

                var list = result.Models ?? new List<HealthTelemetry>();
                Console.WriteLine($"[SupabaseHealthService] Fetched {list.Count} telemetry records from Supabase.");
                return list;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to fetch granular telemetry from Supabase");
                Console.WriteLine($"[HealthTelemetry] ERROR: {ex.Message}");
                return new List<HealthTelemetry>();
            }
        }
    }
}
