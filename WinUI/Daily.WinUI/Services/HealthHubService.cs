using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services;
using Daily.Services.Health;
using Microsoft.Extensions.Logging;
#if WINUI_NATIVE
using Microsoft.UI.Dispatching;
#endif
using Supabase.Realtime;

namespace Daily_WinUI.Services
{
    /// <summary>
    /// Pure canonical & per-device lean renderer data service for WinUI 3 Health Hub.
    /// Provides instant local SQLite loading (<300ms), live Supabase Realtime synchronization,
    /// per-device lean queries (health_sleep_sessions, health_daily_vitals, health_intraday_heart_rate),
    /// and strict adherence to zero-synthetic honest health metrics.
    /// </summary>
    public class HealthHubService : IHealthHubService
    {
        private readonly Supabase.Client _supabaseClient;
        private readonly IDatabaseService _dbService;
        private readonly ILogger<HealthHubService>? _logger;
        private readonly Daily.Services.Auth.ISupabaseSessionGuardian? _sessionGuardian;
        private readonly ConcurrentDictionary<string, HealthDailySummaryRecord> _memoryCache = new();
        private readonly ConcurrentDictionary<string, byte> _fullSummaryAttemptedDates = new();
        private readonly ConcurrentDictionary<string, List<HealthSleepSessionRecord>> _sleepCache = new();
        private readonly ConcurrentDictionary<string, List<HealthDailyVitalsRecord>> _vitalsCache = new();
        private readonly ConcurrentDictionary<string, List<HealthIntradayHeartRateRecord>> _hrCache = new();
        private readonly ConcurrentDictionary<string, Task<HealthDailySummaryRecord?>> _inFlightFetches = new();
        private readonly ConcurrentDictionary<string, Task<List<HealthSleepSessionRecord>>> _inFlightSleepFetches = new();
        private readonly ConcurrentDictionary<string, Task<List<HealthDailyVitalsRecord>>> _inFlightVitalsFetches = new();
        private readonly ConcurrentDictionary<string, Task<List<HealthIntradayHeartRateRecord>>> _inFlightHrFetches = new();
        private readonly ConcurrentDictionary<string, (DateTime CachedUtc, List<HealthDailySummaryRecord> Rows)> _rangeSummariesCache = new();
        private readonly ConcurrentDictionary<string, (DateTime CachedUtc, List<HealthSleepSessionRecord> Rows)> _rangeSleepCache = new();
        private readonly ConcurrentDictionary<string, (DateTime CachedUtc, List<HealthDailyVitalsRecord> Rows)> _rangeVitalsCache = new();
        private readonly object _sourcesFetchLock = new();
        private Task<List<HealthSourceRecord>>? _inFlightSourcesFetch;
        private DateTime _lastSourcesFetchedUtc = DateTime.MinValue;
        private readonly System.Threading.SemaphoreSlim _realtimeSemaphore = new(1, 1);
        private volatile List<HealthSourceRecord> _sourcesCache = new();
        private bool _hasLoadedSources = false;

        private const string ScalarSummaryColumns = "id,user_id,local_date,computed_at,engine_version,raw_watermark,steps,active_kcal,sleep_asleep_s,sleep_score,stress_avg,rhr,hrv_sdnn,hrv_rmssd,weight,spo2";
        private const string ScalarSleepRangeColumns = "id,user_id,local_date,session_type,source_device_key,start_time,end_time,duration_seconds,time_in_bed_seconds,sleep_score,deep_seconds,rem_seconds,light_seconds,awake_seconds,source_priority,is_user_selected";

        private DateTime _selectedDate = DateTime.Today;
        private string _currentViewType = "Overview";
        private HealthDailySummaryRecord? _currentSummary;
        private RealtimeChannel? _realtimeChannel;
        private RealtimeChannel? _vitalsRealtimeChannel;
        private RealtimeChannel? _sleepRealtimeChannel;
        private RealtimeChannel? _sourcesRealtimeChannel;
        private System.Threading.Timer? _periodicRefreshTimer;
        private System.Threading.CancellationTokenSource? _realtimeLeanDebounceCts;
        private readonly object _realtimeDebounceLock = new();
        private long _lastRealtimeFetchTicks = 0;
        private bool _isInitialized = false;

        public HealthHubService(
            Supabase.Client supabaseClient,
            IDatabaseService dbService,
            ILogger<HealthHubService>? logger = null,
            Daily.Services.Auth.ISupabaseSessionGuardian? sessionGuardian = null)
        {
            _supabaseClient = supabaseClient;
            _dbService = dbService;
            _logger = logger;
            _sessionGuardian = sessionGuardian;

            try
            {
                _supabaseClient.Realtime.AddStateChangedHandler((sender, state) =>
                {
                    if (state == Supabase.Realtime.Constants.SocketState.Open)
                    {
                        _logger?.LogInformation("[HealthHubService] Realtime socket opened. Ensuring subscription...");
                        _ = Task.Run(async () =>
                        {
                            try
                            {
                                await SetupRealtimeSubscriptionAsync(forceRecreate: true).ConfigureAwait(false);
                            }
                            catch (Exception ex)
                            {
                                _logger?.LogWarning(ex, "[HealthHubService] Socket state reconnect error: {Message}", ex.Message);
                            }
                        });
                    }
                });

                _supabaseClient.Auth.AddStateChangedListener((sender, state) =>
                {
                    if (state == Supabase.Gotrue.Constants.AuthState.SignedIn ||
                        state == Supabase.Gotrue.Constants.AuthState.TokenRefreshed)
                    {
                        var recreate = state == Supabase.Gotrue.Constants.AuthState.SignedIn;
                        _ = Task.Run(async () =>
                        {
                            try
                            {
                                await SetupRealtimeSubscriptionAsync(forceRecreate: recreate).ConfigureAwait(false);
                            }
                            catch { }
                        });
                    }
                });
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] Failed to attach listeners in constructor: {Message}", ex.Message);
            }
        }

        public HealthHubService(
            Supabase.Client supabaseClient,
            IDatabaseService dbService,
            ISettingsService? settingsService,
            ILogger<HealthHubService>? logger = null)
            : this(supabaseClient, dbService, logger)
        {
        }

        public DateTime SelectedDate
        {
            get => _selectedDate;
            set
            {
                if (_selectedDate.Date != value.Date)
                {
                    _selectedDate = value.Date;
                    _ = LoadSummaryForSelectedDateAsync();
                    OnSelectedDateChanged?.Invoke();
                }
            }
        }

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

        public HealthDailySummaryRecord? CurrentSummary => _currentSummary;

        public event Action? OnSelectedDateChanged;
        public event Action? OnViewTypeChanged;
        public event Action<HealthDailySummaryRecord?>? OnDailySummaryChanged;
        public event Action? OnHealthSourcesChanged;

        private static bool IsSupportedEngineVersion(string? version) =>
            version == "2.0" || version == "2.1";

        public async Task InitializeAsync(bool forceRecreateRealtime = false)
        {
            if (_isInitialized && !forceRecreateRealtime) return;

            try
            {
                await _dbService.InitializeAsync().ConfigureAwait(false);

                // Purge pre-v2 cached summaries so canonical v2/v2.1 unified data loads cleanly
                try
                {
                    await _dbService.Connection.ExecuteAsync(
                        "DELETE FROM health_daily_summary_cache WHERE EngineVersion IS NULL OR EngineVersion NOT IN ('2.0', '2.1')"
                    ).ConfigureAwait(false);
                }
                catch { }

                await LoadSummaryFromLocalCacheAsync(_selectedDate).ConfigureAwait(false);

                _ = Task.Run(async () =>
                {
                    try
                    {
                        await GetHealthSourcesAsync(forceRefresh: true).ConfigureAwait(false);
                        await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
                        await Task.WhenAll(
                            GetLeanSleepSessionsAsync(_selectedDate, forceRefresh: true),
                            GetLeanDailyVitalsAsync(_selectedDate, forceRefresh: true),
                            GetLeanIntradayHeartRateAsync(_selectedDate, forceRefresh: true)
                        ).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        _logger?.LogWarning(ex, "[HealthHubService] Background initial summary fetch error: {Message}", ex.Message);
                    }
                });

                _ = Task.Run(async () =>
                {
                    try
                    {
                        await SetupRealtimeSubscriptionAsync(forceRecreateRealtime).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        _logger?.LogWarning(ex, "[HealthHubService] Background realtime setup error: {Message}", ex.Message);
                    }
                });

                _periodicRefreshTimer?.Dispose();
                _periodicRefreshTimer = new System.Threading.Timer(async _ =>
                {
                    try
                    {
                        if (!string.IsNullOrEmpty(_supabaseClient.Auth.CurrentSession?.User?.Id))
                        {
                            await PullDeltasAsync().ConfigureAwait(false);
                        }
                    }
                    catch { }
                }, null, TimeSpan.FromMinutes(15), TimeSpan.FromMinutes(15));

                _isInitialized = true;
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "[HealthHubService] Initialization error: {Message}", ex.Message);
            }
        }

        private async Task<HealthDailySummaryRecord?> LoadSummaryFromLocalCacheAsync(DateTime date)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var hasActiveSession = !string.IsNullOrEmpty(_supabaseClient.Auth.CurrentSession?.User?.Id);
            if (_memoryCache.TryGetValue(dateStr, out var cached) && (cached.Summary != null || !hasActiveSession))
            {
                _currentSummary = cached;
                DispatchToUI(() => OnDailySummaryChanged?.Invoke(cached));
                return cached;
            }

            try
            {
                var entity = await _dbService.Connection.FindAsync<HealthDailySummaryEntity>(dateStr).ConfigureAwait(false);
                if (entity != null && IsSupportedEngineVersion(entity.EngineVersion))
                {
                    var record = MapEntityToRecord(entity);
                    if (record.Summary != null || !_memoryCache.TryGetValue(dateStr, out var existingMem) || existingMem.Summary == null)
                    {
                        _memoryCache[dateStr] = record;
                    }
                    _currentSummary = record;
                    DispatchToUI(() => OnDailySummaryChanged?.Invoke(record));
                    return record;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] SQLite cache read error: {Message}", ex.Message);
            }

            return null;
        }

        private async Task LoadSummaryForSelectedDateAsync()
        {
            try
            {
                await LoadSummaryFromLocalCacheAsync(_selectedDate).ConfigureAwait(false);

                _ = Task.Run(async () =>
                {
                    try
                    {
                        await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        _logger?.LogWarning(ex, "[HealthHubService] Remote refresh failed for {Date}: {Message}", _selectedDate, ex.Message);
                    }
                });
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "[HealthHubService] Failed to load summary for {Date}: {Message}", _selectedDate, ex.Message);
            }
        }

        private async Task<string?> EnsureUserIdAsync()
        {
            if (_sessionGuardian != null)
            {
                try { await _sessionGuardian.EnsureValidSessionAsync().ConfigureAwait(false); } catch { }
            }
            return _supabaseClient.Auth.CurrentSession?.User?.Id;
        }

        private async Task<HealthDailySummaryRecord?> RefreshSummaryFromRemoteAsync(DateTime date)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId))
            {
                return _memoryCache.TryGetValue(dateStr, out var fallback) ? fallback : null;
            }

            try
            {
                var fetchTask = _sessionGuardian != null
                    ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                        () => _supabaseClient.From<HealthDailySummaryRecord>()
                            .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                            .Get(),
                        "HealthHubService.RefreshSummaryFromRemote")
                    : _supabaseClient.From<HealthDailySummaryRecord>()
                        .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                        .Get();

                var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                if (completed != fetchTask)
                {
                    _logger?.LogWarning("[HealthHubService] Remote fetch timed out for {Date}", dateStr);
                    return _memoryCache.TryGetValue(dateStr, out var timeoutFallback) ? timeoutFallback : null;
                }

                var resp = await fetchTask.ConfigureAwait(false);
                _fullSummaryAttemptedDates[dateStr] = 1;
                var record = resp.Models.FirstOrDefault();
                if (record != null)
                {
                    _memoryCache[dateStr] = record;
                    await SaveRecordToSqliteAsync(record).ConfigureAwait(false);

                    if (date.Date == _selectedDate.Date)
                    {
                        _currentSummary = record;
                        DispatchToUI(() =>
                        {
                            OnDailySummaryChanged?.Invoke(record);
                        });
                    }
                    return record;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] Remote fetch failed for {Date}: {Message}", dateStr, ex.Message);
            }

            return _memoryCache.TryGetValue(dateStr, out var mem) ? mem : null;
        }

        public async Task<HealthDailySummaryRecord?> GetDailySummaryAsync(DateTime date, bool forceRefresh = false)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var hasActiveSession = !string.IsNullOrEmpty(_supabaseClient.Auth.CurrentSession?.User?.Id);

            if (!forceRefresh && _memoryCache.TryGetValue(dateStr, out var cached) &&
                (cached.Summary != null || !hasActiveSession || _fullSummaryAttemptedDates.ContainsKey(dateStr)))
            {
                return cached;
            }

            if (!forceRefresh)
            {
                try
                {
                    var entity = await _dbService.Connection.FindAsync<HealthDailySummaryEntity>(dateStr).ConfigureAwait(false);
                    if (entity != null && IsSupportedEngineVersion(entity.EngineVersion))
                    {
                        var record = MapEntityToRecord(entity);
                        if (record.Summary != null || !_memoryCache.TryGetValue(dateStr, out var existingMem) || existingMem.Summary == null)
                        {
                            _memoryCache[dateStr] = record;
                        }
                        if (record.Summary != null || !hasActiveSession || _fullSummaryAttemptedDates.ContainsKey(dateStr))
                        {
                            return record;
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger?.LogWarning(ex, "[HealthHubService] SQLite cache read error: {Message}", ex.Message);
                }
            }

            var key = dateStr + (forceRefresh ? "_force" : "");
            return await _inFlightFetches.GetOrAdd(key, _ => Task.Run(async () =>
            {
                try
                {
                    return await RefreshSummaryFromRemoteAsync(date).ConfigureAwait(false);
                }
                finally
                {
                    _inFlightFetches.TryRemove(key, out Task<HealthDailySummaryRecord?>? _);
                }
            })).ConfigureAwait(false);
        }

        // ==========================================
        // LEAN PER-DEVICE QUERIES (SUPABASE v2)
        // ==========================================

        public async Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsAsync(DateTime date, bool forceRefresh = false)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var hasCached = _sleepCache.TryGetValue(dateStr, out var cached);
            if (!forceRefresh && hasCached && cached != null)
            {
                return cached;
            }

            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId))
            {
                return cached ?? new List<HealthSleepSessionRecord>();
            }

            var key = dateStr + (forceRefresh ? "_force" : "");
            return await _inFlightSleepFetches.GetOrAdd(key, _ => Task.Run(async () =>
            {
                try
                {
                    var fetchTask = _sessionGuardian != null
                        ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                            () => _supabaseClient.From<HealthSleepSessionRecord>()
                                .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                                .Get(),
                            "HealthHubService.GetLeanSleepSessions")
                        : _supabaseClient.From<HealthSleepSessionRecord>()
                            .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                            .Get();

                    var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                    if (completed == fetchTask)
                    {
                        var resp = await fetchTask.ConfigureAwait(false);
                        var list = resp.Models
                            .Where(r => !DeviceSource.IsVirtual(r.SourceDeviceKey) && r.DurationSeconds > 0)
                            .ToList();
                        _sleepCache[dateStr] = list;
                        return list;
                    }
                }
                catch (Exception ex)
                {
                    _logger?.LogWarning(ex, "[HealthHubService] GetLeanSleepSessions failed for {Date}: {Message}", dateStr, ex.Message);
                }
                finally
                {
                    _inFlightSleepFetches.TryRemove(key, out Task<List<HealthSleepSessionRecord>>? _);
                }

                return cached ?? new List<HealthSleepSessionRecord>();
            })).ConfigureAwait(false);
        }

        public async Task<List<HealthDailyVitalsRecord>> GetLeanDailyVitalsAsync(DateTime date, bool forceRefresh = false)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var hasCached = _vitalsCache.TryGetValue(dateStr, out var cached);
            if (!forceRefresh && hasCached && cached != null)
            {
                return cached;
            }

            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId))
            {
                return cached ?? new List<HealthDailyVitalsRecord>();
            }

            var key = dateStr + (forceRefresh ? "_force" : "");
            return await _inFlightVitalsFetches.GetOrAdd(key, _ => Task.Run(async () =>
            {
                try
                {
                    var fetchTask = _sessionGuardian != null
                        ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                            () => _supabaseClient.From<HealthDailyVitalsRecord>()
                                .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                                .Get(),
                            "HealthHubService.GetLeanDailyVitals")
                        : _supabaseClient.From<HealthDailyVitalsRecord>()
                            .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                            .Get();

                    var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                    if (completed == fetchTask)
                    {
                        var resp = await fetchTask.ConfigureAwait(false);
                        var list = resp.Models
                            .Where(r => !DeviceSource.IsVirtual(r.SourceDeviceKey) && r.HasSignal)
                            .ToList();
                        _vitalsCache[dateStr] = list;
                        return list;
                    }
                }
                catch (Exception ex)
                {
                    _logger?.LogWarning(ex, "[HealthHubService] GetLeanDailyVitals failed for {Date}: {Message}", dateStr, ex.Message);
                }
                finally
                {
                    _inFlightVitalsFetches.TryRemove(key, out Task<List<HealthDailyVitalsRecord>>? _);
                }

                return cached ?? new List<HealthDailyVitalsRecord>();
            })).ConfigureAwait(false);
        }

        public async Task<List<HealthIntradayHeartRateRecord>> GetLeanIntradayHeartRateAsync(DateTime date, bool forceRefresh = false)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var hasCached = _hrCache.TryGetValue(dateStr, out var cached);
            if (!forceRefresh && hasCached && cached != null)
            {
                return cached;
            }

            // Pillar 2: health_intraday_heart_rate has a 7-day rolling retention; older dates use archived Summary.Cardiovascular.IntradayHeartRate.
            if ((DateTime.Today - date.Date).TotalDays > 8)
            {
                var empty = new List<HealthIntradayHeartRateRecord>();
                _hrCache[dateStr] = empty;
                return empty;
            }

            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId))
            {
                return cached ?? new List<HealthIntradayHeartRateRecord>();
            }

            var key = dateStr + (forceRefresh ? "_force" : "");
            return await _inFlightHrFetches.GetOrAdd(key, _ => Task.Run(async () =>
            {
                try
                {
                    var fetchTask = _sessionGuardian != null
                        ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                            () => _supabaseClient.From<HealthIntradayHeartRateRecord>()
                                .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                                .Order("bucket_minute", Supabase.Postgrest.Constants.Ordering.Ascending)
                                .Get(),
                            "HealthHubService.GetLeanIntradayHeartRate")
                        : _supabaseClient.From<HealthIntradayHeartRateRecord>()
                            .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                            .Order("bucket_minute", Supabase.Postgrest.Constants.Ordering.Ascending)
                            .Get();

                    var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                    if (completed == fetchTask)
                    {
                        var resp = await fetchTask.ConfigureAwait(false);
                        var list = resp.Models
                            .Where(r => !DeviceSource.IsVirtual(r.SourceDeviceKey) && r.BpmAvg > 0)
                            .OrderBy(r => r.BucketMinute)
                            .ToList();
                        _hrCache[dateStr] = list;
                        return list;
                    }
                }
                catch (Exception ex)
                {
                    _logger?.LogWarning(ex, "[HealthHubService] GetLeanIntradayHeartRate failed for {Date}: {Message}", dateStr, ex.Message);
                }
                finally
                {
                    _inFlightHrFetches.TryRemove(key, out Task<List<HealthIntradayHeartRateRecord>>? _);
                }

                return cached ?? new List<HealthIntradayHeartRateRecord>();
            })).ConfigureAwait(false);
        }

        public async Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsRangeAsync(DateTime startDate, DateTime endDate)
        {
            var startStr = startDate.ToString("yyyy-MM-dd");
            var endStr = endDate.ToString("yyyy-MM-dd");
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId)) return new List<HealthSleepSessionRecord>();

            var rangeKey = $"{currentUserId}|{startStr}|{endStr}";
            if (_rangeSleepCache.TryGetValue(rangeKey, out var cachedRange) &&
                (DateTime.UtcNow - cachedRange.CachedUtc).TotalMinutes < 30)
            {
                return cachedRange.Rows;
            }

            try
            {
                var fetchTask = _sessionGuardian != null
                    ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                        () => _supabaseClient.From<HealthSleepSessionRecord>()
                            .Select(ScalarSleepRangeColumns)
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                            .Where(x => x.UserId == currentUserId)
                            .Get(),
                        "HealthHubService.GetLeanSleepSessionsRange")
                    : _supabaseClient.From<HealthSleepSessionRecord>()
                        .Select(ScalarSleepRangeColumns)
                        .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                        .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                        .Where(x => x.UserId == currentUserId)
                        .Get();

                var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                if (completed == fetchTask)
                {
                    var resp = await fetchTask.ConfigureAwait(false);
                    var list = resp.Models
                        .Where(r => !DeviceSource.IsVirtual(r.SourceDeviceKey) && r.DurationSeconds > 0)
                        .ToList();
                    // Note: do NOT overwrite single-day _sleepCache here because range rows omit Stages JSONB.
                    _rangeSleepCache[rangeKey] = (DateTime.UtcNow, list);
                    return list;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] GetLeanSleepSessionsRange failed: {Message}", ex.Message);
            }

            return new List<HealthSleepSessionRecord>();
        }

        public async Task<List<HealthDailyVitalsRecord>> GetLeanDailyVitalsRangeAsync(DateTime startDate, DateTime endDate)
        {
            var startStr = startDate.ToString("yyyy-MM-dd");
            var endStr = endDate.ToString("yyyy-MM-dd");
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId)) return new List<HealthDailyVitalsRecord>();

            var rangeKey = $"{currentUserId}|{startStr}|{endStr}";
            if (_rangeVitalsCache.TryGetValue(rangeKey, out var cachedRange) &&
                (DateTime.UtcNow - cachedRange.CachedUtc).TotalMinutes < 30)
            {
                return cachedRange.Rows;
            }

            try
            {
                var fetchTask = _sessionGuardian != null
                    ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                        () => _supabaseClient.From<HealthDailyVitalsRecord>()
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                            .Where(x => x.UserId == currentUserId)
                            .Get(),
                        "HealthHubService.GetLeanDailyVitalsRange")
                    : _supabaseClient.From<HealthDailyVitalsRecord>()
                        .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                        .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                        .Where(x => x.UserId == currentUserId)
                        .Get();

                var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                if (completed == fetchTask)
                {
                    var resp = await fetchTask.ConfigureAwait(false);
                    var list = resp.Models
                        .Where(r => !DeviceSource.IsVirtual(r.SourceDeviceKey) && r.HasSignal)
                        .ToList();
                    foreach (var g in list.GroupBy(r => r.LocalDate))
                    {
                        _vitalsCache[g.Key] = g.ToList();
                    }
                    _rangeVitalsCache[rangeKey] = (DateTime.UtcNow, list);
                    return list;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] GetLeanDailyVitalsRange failed: {Message}", ex.Message);
            }

            return new List<HealthDailyVitalsRecord>();
        }

        public async Task<List<HealthSourceRecord>> GetHealthSourcesAsync(bool forceRefresh = false)
        {
            if (!forceRefresh && _hasLoadedSources && _sourcesCache.Count > 0 &&
                (DateTime.UtcNow - _lastSourcesFetchedUtc).TotalMinutes < 15)
            {
                return _sourcesCache;
            }

            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId))
            {
                return _sourcesCache;
            }

            Task<List<HealthSourceRecord>> activeTask;
            lock (_sourcesFetchLock)
            {
                if (_inFlightSourcesFetch != null && !_inFlightSourcesFetch.IsCompleted)
                {
                    activeTask = _inFlightSourcesFetch;
                }
                else
                {
                    activeTask = Task.Run(async () =>
                    {
                        try
                        {
                            var fetchTask = _sessionGuardian != null
                                ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                                    () => _supabaseClient.From<HealthSourceRecord>()
                                        .Where(x => x.UserId == currentUserId)
                                        .Get(),
                                    "HealthHubService.GetHealthSources")
                                : _supabaseClient.From<HealthSourceRecord>()
                                    .Where(x => x.UserId == currentUserId)
                                    .Get();

                            var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                            if (completed == fetchTask)
                            {
                                var resp = await fetchTask.ConfigureAwait(false);
                                var deduped = new Dictionary<string, HealthSourceRecord>(StringComparer.OrdinalIgnoreCase);
                                foreach (var s in resp.Models)
                                {
                                    var canon = DeviceSource.From(string.IsNullOrWhiteSpace(s.DisplayName) ? s.Id : s.DisplayName);
                                    if (canon.IsVirtualEngine) continue;
                                    s.DisplayName = canon.DisplayName;
                                    if (!deduped.TryGetValue(canon.DisplayName, out var existing))
                                    {
                                        deduped[canon.DisplayName] = s;
                                    }
                                    else if (s.IsCustomPriority && !existing.IsCustomPriority)
                                    {
                                        deduped[canon.DisplayName] = s;
                                    }
                                    else if (s.IsCustomPriority == existing.IsCustomPriority && Math.Min(s.PrioritySleep, s.PriorityActivity) < Math.Min(existing.PrioritySleep, existing.PriorityActivity))
                                    {
                                        deduped[canon.DisplayName] = s;
                                    }
                                }

                                var ordered = deduped.Values
                                    .OrderBy(s => s.IsCustomPriority ? Math.Min(s.PrioritySleep, s.PriorityActivity) : DefaultAscendingPriorityRank(s.DisplayName))
                                    .ThenBy(s => DefaultAscendingPriorityRank(s.DisplayName))
                                    .ThenBy(s => s.DisplayName)
                                    .ToList();

                                _sourcesCache = ordered;
                                _hasLoadedSources = true;
                                _lastSourcesFetchedUtc = DateTime.UtcNow;
                                return ordered;
                            }
                        }
                        catch (Exception ex)
                        {
                            _logger?.LogWarning(ex, "[HealthHubService] GetHealthSourcesAsync failed: {Message}", ex.Message);
                        }
                        finally
                        {
                            lock (_sourcesFetchLock)
                            {
                                _inFlightSourcesFetch = null;
                            }
                        }

                        return _sourcesCache;
                    });
                    _inFlightSourcesFetch = activeTask;
                }
            }

            return await activeTask.ConfigureAwait(false);
        }

        public async Task<bool> SaveDevicePriorityOrderAsync(IReadOnlyList<string> orderedSourceIds)
        {
            if (orderedSourceIds == null || orderedSourceIds.Count == 0) return false;
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId)) return false;

            try
            {
                var rpcParams = new Dictionary<string, object>
                {
                    ["ordered_source_ids"] = orderedSourceIds.ToArray()
                };
                if (_sessionGuardian != null)
                {
                    await _sessionGuardian.ExecuteWithAuthRetryAsync(
                        () => _supabaseClient.Rpc("save_health_source_priorities", rpcParams),
                        "HealthHubService.SaveDevicePriorityOrder").ConfigureAwait(false);
                }
                else
                {
                    await _supabaseClient.Rpc("save_health_source_priorities", rpcParams).ConfigureAwait(false);
                }

                InvalidateRangeCaches();
                await GetHealthSourcesAsync(forceRefresh: true).ConfigureAwait(false);
                await RecomputeServerSummaryForDateAsync(_selectedDate).ConfigureAwait(false);
                await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
                DispatchToUI(() =>
                {
                    OnHealthSourcesChanged?.Invoke();
                    OnDailySummaryChanged?.Invoke(_currentSummary);
                });
                return true;
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] SaveDevicePriorityOrderAsync failed: {Message}", ex.Message);
                return false;
            }
        }

        public async Task<bool> ResetDevicePriorityOrderAsync()
        {
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId)) return false;

            try
            {
                var emptyParams = new Dictionary<string, object>();
                if (_sessionGuardian != null)
                {
                    await _sessionGuardian.ExecuteWithAuthRetryAsync(
                        () => _supabaseClient.Rpc("reset_health_source_priorities", emptyParams),
                        "HealthHubService.ResetDevicePriorityOrder").ConfigureAwait(false);
                }
                else
                {
                    await _supabaseClient.Rpc("reset_health_source_priorities", emptyParams).ConfigureAwait(false);
                }

                InvalidateRangeCaches();
                await GetHealthSourcesAsync(forceRefresh: true).ConfigureAwait(false);
                await RecomputeServerSummaryForDateAsync(_selectedDate).ConfigureAwait(false);
                await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
                DispatchToUI(() =>
                {
                    OnHealthSourcesChanged?.Invoke();
                    OnDailySummaryChanged?.Invoke(_currentSummary);
                });
                return true;
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] ResetDevicePriorityOrderAsync failed: {Message}", ex.Message);
                return false;
            }
        }

        private void InvalidateRangeCaches()
        {
            _rangeSummariesCache.Clear();
            _rangeSleepCache.Clear();
            _rangeVitalsCache.Clear();
        }

        private async Task RecomputeServerSummaryForDateAsync(DateTime date)
        {
            try
            {
                var body = new Dictionary<string, object>
                {
                    ["local_date"] = date.ToString("yyyy-MM-dd"),
                    ["tz_offset_min"] = (int)TimeZoneInfo.Local.GetUtcOffset(date).TotalMinutes,
                    ["compact"] = true
                };
                var uid = _supabaseClient.Auth.CurrentSession?.User?.Id;
                if (!string.IsNullOrEmpty(uid))
                {
                    body["user_id"] = uid;
                }
                await _supabaseClient.Functions.Invoke("health-engine", options: new Supabase.Functions.Client.InvokeFunctionOptions
                {
                    Body = body
                }).ConfigureAwait(false);
            }
            catch { }
        }

        public int GetEffectivePriorityRank(string? deviceName) =>
            ResolveEffectivePriorityRank(deviceName, _sourcesCache);

        public static int DefaultAscendingPriorityRank(string? deviceName)
        {
            var lower = DeviceSource.From(deviceName).DisplayName.ToLowerInvariant();
            if (lower.Contains("oura")) return 1;
            if (lower.Contains("apple watch") || lower.Contains("ultra 2")) return 2;
            if (lower.Contains("pixel watch") || lower.Contains("fitbit")) return 3;
            if (lower.Contains("garmin") || lower.Contains("whoop") || lower.Contains("polar") || lower.Contains("withings")) return 3;
            if (lower.Contains("oneplus")) return 4;
            if (lower.Contains("amazfit") || lower.Contains("zepp") || lower.Contains("balance")) return 5;
            if (lower.Contains("huawei") || lower.Contains("gt 5")) return 6;
            if (lower.Contains("samsung") || lower.Contains("radar") || lower.Contains("fold")) return 9;
            if (lower.Contains("health connect") || lower.Contains("trapper") || lower.Contains("healthkit") || lower.Contains("apple health") || lower.Contains("schmitz") || lower.Contains("iphone")) return 10;
            if (lower.Contains("manual")) return 11;
            return 12;
        }

        public static int ResolveEffectivePriorityRank(string? deviceName, IReadOnlyList<HealthSourceRecord>? sources)
        {
            var canon = DeviceSource.From(deviceName).DisplayName;
            if (sources != null && sources.Count > 0)
            {
                var matched = sources.FirstOrDefault(s =>
                    string.Equals(DeviceSource.From(string.IsNullOrWhiteSpace(s.DisplayName) ? s.Id : s.DisplayName).DisplayName, canon, StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(s.Id, deviceName, StringComparison.OrdinalIgnoreCase));

                if (matched != null)
                {
                    if (matched.IsCustomPriority)
                    {
                        int rank = Math.Min(matched.PrioritySleep, matched.PriorityActivity);
                        if (rank > 0) return rank;
                    }
                    int dbRank = Math.Min(matched.PrioritySleep, matched.PriorityActivity);
                    if (dbRank > 0 && dbRank <= 20) return dbRank;
                }
            }
            return DefaultAscendingPriorityRank(canon);
        }

        // ==========================================
        // LEAN HEALTH v2.1 3-CLASS ARBITRATION
        // ==========================================

        public record ArbitratedLatestHeartRateResult(double Bpm, DateTimeOffset Timestamp, string SourceDevice);
        public record ArbitratedActivityResult(int TotalSteps, double ActiveCalories, List<HourlyStepBucket> HourlySteps, string? SourceDevice);
        public record ArbitratedSpotVitalResult(double Value, DateTimeOffset Timestamp, string SourceDevice);

        public static ArbitratedLatestHeartRateResult? ArbitrateLatestHeartRate(
            IReadOnlyList<HealthDailyVitalsRecord>? vitals,
            IReadOnlyList<HealthIntradayHeartRateRecord>? intradayBuckets,
            DateTime targetDate,
            IReadOnlyList<HealthSourceRecord>? sources = null,
            string? deviceFilter = null)
        {
            string? targetCanon = !string.IsNullOrWhiteSpace(deviceFilter)
                ? DeviceSource.From(deviceFilter).DisplayName
                : null;

            bool MatchesFilter(string? raw)
            {
                if (string.IsNullOrWhiteSpace(raw)) return false;
                var c = DeviceSource.From(raw);
                if (c.IsVirtualEngine) return false;
                return targetCanon == null || string.Equals(c.DisplayName, targetCanon, StringComparison.OrdinalIgnoreCase);
            }

            var perDevice = new Dictionary<string, (double Bpm, DateTimeOffset Ts)>(StringComparer.OrdinalIgnoreCase);

            if (vitals != null)
            {
                foreach (var v in vitals)
                {
                    if (!MatchesFilter(v.SourceDeviceKey)) continue;
                    int bpm = v.LatestHeartRate ?? 0;
                    if (bpm < 30 || bpm >= 240) continue;

                    DateTimeOffset ts = default;
                    if (!string.IsNullOrWhiteSpace(v.LatestHrAt) && DateTimeOffset.TryParse(v.LatestHrAt, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var hrDto))
                    {
                        ts = hrDto;
                    }
                    else if (!string.IsNullOrWhiteSpace(v.UpdatedAt) && DateTimeOffset.TryParse(v.UpdatedAt, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var upDto))
                    {
                        ts = upDto;
                    }
                    else
                    {
                        ts = new DateTimeOffset(DateTime.SpecifyKind(targetDate.Date, DateTimeKind.Local));
                    }

                    var canon = DeviceSource.From(v.SourceDeviceKey).DisplayName;
                    if (!perDevice.TryGetValue(canon, out var prev) || ts > prev.Ts)
                    {
                        perDevice[canon] = (bpm, ts);
                    }
                }
            }

            if (intradayBuckets != null)
            {
                var localMidnight = DateTime.SpecifyKind(targetDate.Date, DateTimeKind.Local);
                foreach (var b in intradayBuckets)
                {
                    if (!MatchesFilter(b.SourceDeviceKey) || b.BpmAvg < 30 || b.BpmAvg >= 240) continue;
                    int clampedMin = Math.Clamp(b.BucketMinute, 0, 1439);
                    // End of 5-minute bucket
                    var bucketTs = new DateTimeOffset(localMidnight.AddMinutes(Math.Min(1439, clampedMin + 4)));
                    var canon = DeviceSource.From(b.SourceDeviceKey).DisplayName;
                    if (!perDevice.TryGetValue(canon, out var prev) || bucketTs > prev.Ts.AddMinutes(5))
                    {
                        perDevice[canon] = (b.BpmAvg, bucketTs);
                    }
                }
            }

            if (perDevice.Count == 0) return null;

            var newestTs = perDevice.Values.Max(x => x.Ts);
            var simultaneousCutoff = newestTs.AddMinutes(-15);

            var winner = perDevice
                .Where(kv => kv.Value.Ts >= simultaneousCutoff)
                .OrderBy(kv => ResolveEffectivePriorityRank(kv.Key, sources))
                .ThenByDescending(kv => kv.Value.Ts)
                .First();

            return new ArbitratedLatestHeartRateResult(winner.Value.Bpm, winner.Value.Ts, winner.Key);
        }

        public static ArbitratedActivityResult ArbitrateHourlyActivity(
            IReadOnlyList<HealthDailyVitalsRecord>? vitals,
            IReadOnlyList<HealthSourceRecord>? sources = null,
            string? deviceFilter = null)
        {
            string? targetCanon = !string.IsNullOrWhiteSpace(deviceFilter)
                ? DeviceSource.From(deviceFilter).DisplayName
                : null;

            var eligible = (vitals ?? Array.Empty<HealthDailyVitalsRecord>())
                .Where(v =>
                {
                    var c = DeviceSource.From(v.SourceDeviceKey);
                    if (c.IsVirtualEngine) return false;
                    return targetCanon == null || string.Equals(c.DisplayName, targetCanon, StringComparison.OrdinalIgnoreCase);
                })
                .ToList();

            if (eligible.Count == 0)
            {
                return new ArbitratedActivityResult(0, 0, new List<HourlyStepBucket>(), null);
            }

            var mergedBuckets = new List<HourlyStepBucket>(24);
            var contributorSteps = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            for (int h = 0; h < 24; h++)
            {
                int hour = h;
                var hourCandidates = eligible
                    .Select(v =>
                    {
                        var hb = v.HourlySteps?.FirstOrDefault(b => b.Hour == hour);
                        var canon = DeviceSource.From(v.SourceDeviceKey).DisplayName;
                        return (Canon: canon, Steps: hb?.Steps ?? 0, Kcal: hb?.ActiveCalories ?? 0.0, Rank: ResolveEffectivePriorityRank(canon, sources));
                    })
                    .Where(c => c.Steps > 0 || c.Kcal > 0)
                    .OrderBy(c => c.Rank)
                    .ThenByDescending(c => c.Steps)
                    .ToList();

                if (hourCandidates.Count > 0)
                {
                    var best = hourCandidates[0];
                    mergedBuckets.Add(new HourlyStepBucket
                    {
                        Hour = hour,
                        Steps = best.Steps,
                        ActiveCalories = best.Kcal
                    });
                    contributorSteps[best.Canon] = (contributorSteps.TryGetValue(best.Canon, out var prevS) ? prevS : 0) + best.Steps;
                }
                else
                {
                    mergedBuckets.Add(new HourlyStepBucket { Hour = hour, Steps = 0, ActiveCalories = 0 });
                }
            }

            int envelopeSteps = mergedBuckets.Sum(b => b.Steps);
            int maxSingleSteps = eligible.Max(v => v.Steps);
            int finalSteps = Math.Max(envelopeSteps, maxSingleSteps);

            double envelopeKcal = mergedBuckets.Sum(b => b.ActiveCalories);
            double maxSingleKcal = eligible.Max(v => v.ActiveKcal);
            double finalKcal = Math.Max(envelopeKcal, maxSingleKcal);

            string? dominantDevice = null;
            if (contributorSteps.Count > 1)
            {
                dominantDevice = contributorSteps
                    .OrderByDescending(kv => kv.Value)
                    .ThenBy(kv => ResolveEffectivePriorityRank(kv.Key, sources))
                    .First().Key;
            }
            else if (contributorSteps.Count == 1)
            {
                dominantDevice = contributorSteps.Keys.First();
            }
            else
            {
                var topSingle = eligible
                    .Where(v => v.Steps > 0 || v.ActiveKcal > 0)
                    .OrderBy(v => ResolveEffectivePriorityRank(v.SourceDeviceKey, sources))
                    .ThenByDescending(v => v.Steps)
                    .FirstOrDefault();
                if (topSingle != null)
                {
                    dominantDevice = DeviceSource.From(topSingle.SourceDeviceKey).DisplayName;
                }
            }

            return new ArbitratedActivityResult(finalSteps, finalKcal, mergedBuckets, dominantDevice);
        }

        public static ArbitratedSpotVitalResult? ArbitrateSpotVital(
            IReadOnlyList<HealthDailyVitalsRecord>? vitals,
            string metricKey,
            Func<HealthDailyVitalsRecord, double?> selector,
            IReadOnlyList<HealthSourceRecord>? sources = null,
            int simultaneousWindowMinutes = 30)
        {
            if (vitals == null || vitals.Count == 0) return null;

            var candidates = new List<(string Canon, double Val, DateTimeOffset Ts)>();
            foreach (var v in vitals)
            {
                var c = DeviceSource.From(v.SourceDeviceKey);
                if (c.IsVirtualEngine) continue;
                var val = selector(v);
                if (!val.HasValue || val.Value <= 0) continue;

                DateTimeOffset ts = default;
                if (v.VitalsTimestamps != null && v.VitalsTimestamps.TryGetValue(metricKey, out var mIso) &&
                    DateTimeOffset.TryParse(mIso, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var mDto))
                {
                    ts = mDto;
                }
                else if (!string.IsNullOrWhiteSpace(v.UpdatedAt) &&
                         DateTimeOffset.TryParse(v.UpdatedAt, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var uDto))
                {
                    ts = uDto;
                }

                candidates.Add((c.DisplayName, val.Value, ts));
            }

            if (candidates.Count == 0) return null;

            var newestTs = candidates.Max(x => x.Ts);
            if (newestTs == default)
            {
                var byPrio = candidates.OrderBy(x => ResolveEffectivePriorityRank(x.Canon, sources)).First();
                return new ArbitratedSpotVitalResult(byPrio.Val, byPrio.Ts, byPrio.Canon);
            }

            var cutoff = newestTs.AddMinutes(-simultaneousWindowMinutes);
            var winner = candidates
                .Where(x => x.Ts >= cutoff)
                .OrderBy(x => ResolveEffectivePriorityRank(x.Canon, sources))
                .ThenByDescending(x => x.Ts)
                .First();

            return new ArbitratedSpotVitalResult(winner.Val, winner.Ts, winner.Canon);
        }

        public async Task<List<HealthDailySummaryRecord>> GetDailySummariesRangeAsync(DateTime startDate, DateTime endDate)
        {
            var startOnly = startDate.Date;
            var endOnly = endDate.Date;
            var startStr = startOnly.ToString("yyyy-MM-dd");
            var endStr = endOnly.ToString("yyyy-MM-dd");
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            var rangeKey = $"{currentUserId ?? "offline"}|{startStr}|{endStr}";

            if (!string.IsNullOrEmpty(currentUserId) &&
                _rangeSummariesCache.TryGetValue(rangeKey, out var cachedRange) &&
                (DateTime.UtcNow - cachedRange.CachedUtc).TotalMinutes < 30)
            {
                return cachedRange.Rows
                    .Select(r => _memoryCache.TryGetValue(r.LocalDate, out var live) ? live : r)
                    .OrderBy(x => x.LocalDate)
                    .ToList();
            }

            var results = new Dictionary<string, HealthDailySummaryRecord>(StringComparer.OrdinalIgnoreCase);

            try
            {
                var cached = await _dbService.Connection.QueryAsync<HealthDailySummaryEntity>(
                    "SELECT * FROM health_daily_summary_cache WHERE LocalDate >= ? AND LocalDate <= ? AND EngineVersion IN ('2.0', '2.1') ORDER BY LocalDate",
                    startStr, endStr).ConfigureAwait(false);

                foreach (var entity in cached)
                {
                    var rec = MapEntityToRecord(entity);
                    results[rec.LocalDate] = rec;
                    if (rec.Summary != null || !_memoryCache.TryGetValue(rec.LocalDate, out var existingMem) || existingMem.Summary == null)
                    {
                        _memoryCache[rec.LocalDate] = rec;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] Range cache read error: {Message}", ex.Message);
            }

            if (!string.IsNullOrEmpty(currentUserId))
            {
                var mutableCutoff = DateTime.Today.AddDays(-1);
                DateTime? earliestNeeded = null;
                for (var d = startOnly; d <= endOnly; d = d.AddDays(1))
                {
                    var dStr = d.ToString("yyyy-MM-dd");
                    if (!results.ContainsKey(dStr) || d >= mutableCutoff)
                    {
                        earliestNeeded = d;
                        break;
                    }
                }

                if (earliestNeeded.HasValue)
                {
                    var fetchStartStr = earliestNeeded.Value.ToString("yyyy-MM-dd");
                    try
                    {
                        var fetchTask = _sessionGuardian != null
                            ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                                () => _supabaseClient.From<HealthDailySummaryRecord>()
                                    .Select(ScalarSummaryColumns)
                                    .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, fetchStartStr)
                                    .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                                    .Where(x => x.UserId == currentUserId)
                                    .Get(),
                                "HealthHubService.GetDailySummariesRange")
                            : _supabaseClient.From<HealthDailySummaryRecord>()
                                .Select(ScalarSummaryColumns)
                                .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, fetchStartStr)
                                .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                                .Where(x => x.UserId == currentUserId)
                                .Get();

                        var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                        if (completed == fetchTask)
                        {
                            var resp = await fetchTask.ConfigureAwait(false);
                            foreach (var record in resp.Models)
                            {
                                if (record.Summary == null && results.TryGetValue(record.LocalDate, out var prev) && prev.Summary != null)
                                {
                                    record.Summary = prev.Summary;
                                }
                                else if (record.Summary == null && _memoryCache.TryGetValue(record.LocalDate, out var memPrev) && memPrev.Summary != null)
                                {
                                    record.Summary = memPrev.Summary;
                                }

                                results[record.LocalDate] = record;
                                if (record.Summary != null || !_memoryCache.TryGetValue(record.LocalDate, out var existingMem) || existingMem.Summary == null)
                                {
                                    _memoryCache[record.LocalDate] = record;
                                }
                                await SaveRecordToSqliteAsync(record).ConfigureAwait(false);
                            }
                        }
                        else
                        {
                            _logger?.LogWarning("[HealthHubService] Range remote read timed out for {Start} to {End}", fetchStartStr, endStr);
                        }
                    }
                    catch (Exception ex)
                    {
                        _logger?.LogWarning(ex, "[HealthHubService] Range remote read error: {Message}", ex.Message);
                    }
                }
            }

            var orderedList = results.Values.OrderBy(x => x.LocalDate).ToList();
            if (!string.IsNullOrEmpty(currentUserId))
            {
                _rangeSummariesCache[rangeKey] = (DateTime.UtcNow, orderedList);
            }
            return orderedList;
        }

        public async Task<DailyHealthSummaryPayload?> GetPayloadForDateAsync(DateTime date)
        {
            var summary = await GetDailySummaryAsync(date);
            return summary?.Summary;
        }

        private async Task SetupRealtimeSubscriptionAsync(bool forceRecreate)
        {
            var userId = _supabaseClient.Auth.CurrentSession?.User?.Id;
            if (string.IsNullOrEmpty(userId)) return;

            await _realtimeSemaphore.WaitAsync().ConfigureAwait(false);
            try
            {
                if (_realtimeChannel != null && !forceRecreate && _realtimeChannel.IsJoined) return;

                void Cleanup(ref RealtimeChannel? ch)
                {
                    if (ch != null)
                    {
                        try { ch.Unsubscribe(); } catch { }
                        try { _supabaseClient.Realtime.Remove(ch); } catch { }
                        ch = null;
                    }
                }

                Cleanup(ref _realtimeChannel);
                Cleanup(ref _vitalsRealtimeChannel);
                Cleanup(ref _sleepRealtimeChannel);
                Cleanup(ref _sourcesRealtimeChannel);

                _realtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_daily_summary", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _realtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeSummaryReceived);

                _vitalsRealtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_daily_vitals", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _vitalsRealtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeLeanTableReceived);

                _sleepRealtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_sleep_sessions", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _sleepRealtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeLeanTableReceived);

                _sourcesRealtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_sources", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _sourcesRealtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeHealthSourcesReceived);

                var subscribeTask = Task.WhenAll(
                    _realtimeChannel.Subscribe(),
                    _vitalsRealtimeChannel.Subscribe(),
                    _sleepRealtimeChannel.Subscribe(),
                    _sourcesRealtimeChannel.Subscribe()
                );
                _ = subscribeTask.ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted);
                var completed = await Task.WhenAny(subscribeTask, Task.Delay(3000)).ConfigureAwait(false);
                if (completed != subscribeTask)
                {
                    _logger?.LogWarning("[HealthHubService] Realtime channel subscribe timed out after 3000ms. Will retry on socket open.");
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] Realtime subscription error: {Message}", ex.Message);
            }
            finally
            {
                _realtimeSemaphore.Release();
            }
        }

        private void OnRealtimeSummaryReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try
            {
                var record = e.Model<HealthDailySummaryRecord>();
                if (record != null && !string.IsNullOrEmpty(record.LocalDate))
                {
                    _fullSummaryAttemptedDates[record.LocalDate] = 1;
                    _memoryCache[record.LocalDate] = record;
                    _sleepCache.TryRemove(record.LocalDate, out _);
                    _vitalsCache.TryRemove(record.LocalDate, out _);
                    _hrCache.TryRemove(record.LocalDate, out _);
                    InvalidateRangeCaches();
                    _ = SaveRecordToSqliteAsync(record);

                    var todayStr = DateTime.Today.ToString("yyyy-MM-dd");
                    if (record.LocalDate == _selectedDate.ToString("yyyy-MM-dd") || record.LocalDate == todayStr)
                    {
                        if (record.LocalDate == _selectedDate.ToString("yyyy-MM-dd"))
                        {
                            _currentSummary = record;
                        }
                        DispatchToUI(() =>
                        {
                            if (record.LocalDate == _selectedDate.ToString("yyyy-MM-dd"))
                            {
                                OnDailySummaryChanged?.Invoke(record);
                                OnSelectedDateChanged?.Invoke();
                            }
                            else if (record.LocalDate == todayStr && _selectedDate.Date == DateTime.Today.AddDays(-1) && _currentSummary?.LocalDate != _selectedDate.ToString("yyyy-MM-dd"))
                            {
                                _selectedDate = DateTime.Today;
                                _currentSummary = record;
                                OnDailySummaryChanged?.Invoke(record);
                                OnSelectedDateChanged?.Invoke();
                            }
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "[HealthHubService] Realtime change processing error: {Message}", ex.Message);
            }
        }

        private void OnRealtimeHealthSourcesReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    await GetHealthSourcesAsync(forceRefresh: true).ConfigureAwait(false);
                    await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
                    DispatchToUI(() =>
                    {
                        OnHealthSourcesChanged?.Invoke();
                        OnDailySummaryChanged?.Invoke(_currentSummary);
                    });
                }
                catch { }
            });
        }

        private void OnRealtimeLeanTableReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            System.Threading.CancellationToken token;
            lock (_realtimeDebounceLock)
            {
                _realtimeLeanDebounceCts?.Cancel();
                _realtimeLeanDebounceCts?.Dispose();
                _realtimeLeanDebounceCts = new System.Threading.CancellationTokenSource();
                token = _realtimeLeanDebounceCts.Token;
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    await Task.Delay(5000, token).ConfigureAwait(false);
                    if (token.IsCancellationRequested) return;

                    var nowTicks = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                    System.Threading.Interlocked.Exchange(ref _lastRealtimeFetchTicks, nowTicks);

                    var dateStr = _selectedDate.ToString("yyyy-MM-dd");
                    _sleepCache.TryRemove(dateStr, out _);
                    _vitalsCache.TryRemove(dateStr, out _);
                    _hrCache.TryRemove(dateStr, out _);
                    InvalidateRangeCaches();
                    await Task.WhenAll(
                        RefreshSummaryFromRemoteAsync(_selectedDate),
                        GetLeanSleepSessionsAsync(_selectedDate, forceRefresh: true),
                        GetLeanDailyVitalsAsync(_selectedDate, forceRefresh: true),
                        GetLeanIntradayHeartRateAsync(_selectedDate, forceRefresh: true)
                    ).ConfigureAwait(false);
                    DispatchToUI(() => OnDailySummaryChanged?.Invoke(_currentSummary));
                }
                catch { }
            });
        }

        private void DispatchToUI(Action action)
        {
            try
            {
#if WINUI_NATIVE
                var dispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread()
                    ?? Daily_WinUI.App.Current?.MainWindow?.DispatcherQueue;
                if (dispatcher != null)
                {
                    if (dispatcher.HasThreadAccess)
                    {
                        action();
                    }
                    else
                    {
                        dispatcher.TryEnqueue(() => action());
                    }
                    return;
                }
#endif
                action();
            }
            catch
            {
                action();
            }
        }

        private async Task SaveRecordToSqliteAsync(HealthDailySummaryRecord record)
        {
            try
            {
                string? summaryJson = null;
                if (record.Summary != null)
                {
                    summaryJson = HealthJsonSerializer.Serialize(record.Summary);
                }
                else
                {
                    var existing = await _dbService.Connection.FindAsync<HealthDailySummaryEntity>(record.LocalDate).ConfigureAwait(false);
                    summaryJson = existing?.SummaryJson;
                }

                var entity = new HealthDailySummaryEntity
                {
                    LocalDate = record.LocalDate,
                    UserId = record.UserId,
                    ComputedAt = record.ComputedAt,
                    EngineVersion = string.IsNullOrEmpty(record.EngineVersion) ? "2.0" : record.EngineVersion,
                    Steps = record.Steps,
                    ActiveKcal = record.ActiveKcal,
                    SleepAsleepS = record.SleepAsleepS,
                    SleepScore = record.SleepScore,
                    StressAvg = record.StressAvg,
                    Rhr = record.Rhr,
                    HrvSdnn = record.HrvSdnn,
                    HrvRmssd = record.HrvRmssd,
                    Weight = record.Weight,
                    Spo2 = record.Spo2,
                    SummaryJson = summaryJson,
                    UpdatedAtTimestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
                };

                await _dbService.Connection.InsertOrReplaceAsync(entity).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "[HealthHubService] SQLite upsert error for {Date}: {Message}", record.LocalDate, ex.Message);
            }
        }

        private HealthDailySummaryRecord MapEntityToRecord(HealthDailySummaryEntity entity)
        {
            DailyHealthSummaryPayload? payload = null;
            if (!string.IsNullOrWhiteSpace(entity.SummaryJson))
            {
                try
                {
                    payload = HealthJsonSerializer.Deserialize<DailyHealthSummaryPayload>(entity.SummaryJson);
                }
                catch { }
            }

            return new HealthDailySummaryRecord
            {
                LocalDate = entity.LocalDate,
                UserId = entity.UserId,
                ComputedAt = entity.ComputedAt,
                EngineVersion = entity.EngineVersion,
                Steps = entity.Steps,
                ActiveKcal = entity.ActiveKcal,
                SleepAsleepS = entity.SleepAsleepS,
                SleepScore = entity.SleepScore,
                StressAvg = entity.StressAvg,
                Rhr = entity.Rhr,
                HrvSdnn = entity.HrvSdnn,
                HrvRmssd = entity.HrvRmssd,
                Weight = entity.Weight,
                Spo2 = entity.Spo2,
                Summary = payload
            };
        }

        // ==========================================
        // IHealthService Backwards Compatibility
        // ==========================================

        public async Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            return await FetchMetricsForDateAsync(date);
        }

        public async Task<List<VitalMetric>> FetchMetricsForDateAsync(DateTime date)
        {
            var summaryTask = GetDailySummaryAsync(date);
            var leanVitalsTask = GetLeanDailyVitalsAsync(date);
            var leanSleepTask = GetLeanSleepSessionsAsync(date);
            var sourcesTask = GetHealthSourcesAsync();
            await Task.WhenAll(summaryTask, leanVitalsTask, leanSleepTask, sourcesTask).ConfigureAwait(false);

            var summary = summaryTask.Result;
            var leanVitals = leanVitalsTask.Result;
            var leanSleep = leanSleepTask.Result;
            var sources = sourcesTask.Result;
            var list = new List<VitalMetric>();
            var dateOnly = date.Date;

            // Emit per-device metrics from lean vitals first (ordered by user/canonical ascending priority rank)
            foreach (var v in leanVitals.OrderBy(r => ResolveEffectivePriorityRank(r.SourceDeviceKey, sources)))
            {
                var canon = DeviceSource.From(v.SourceDeviceKey).DisplayName;
                if (DeviceSource.IsVirtual(canon)) continue;

                if (v.Steps > 0)
                    list.Add(new VitalMetric { Type = VitalType.Steps, Value = v.Steps, Unit = "steps", Date = dateOnly, SourceDevice = canon });
                if (v.ActiveKcal > 0)
                    list.Add(new VitalMetric { Type = VitalType.ActiveEnergy, Value = v.ActiveKcal, Unit = "kcal", Date = dateOnly, SourceDevice = canon });
                if ((v.LatestHeartRate ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.HeartRate, Value = v.LatestHeartRate!.Value, Unit = "bpm", Date = dateOnly, SourceDevice = canon });
                if ((v.RestingHeartRate ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.RestingHeartRate, Value = v.RestingHeartRate!.Value, Unit = "bpm", Date = dateOnly, SourceDevice = canon });
                if ((v.HrvSdnnNightly ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.HeartRateVariabilitySDNN, Value = v.HrvSdnnNightly!.Value, Unit = "ms", Date = dateOnly, SourceDevice = canon });
                if ((v.HrvRmssdNightly ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.HeartRateVariabilityRMSSD, Value = v.HrvRmssdNightly!.Value, Unit = "ms", Date = dateOnly, SourceDevice = canon });
                if ((v.Spo2 ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.OxygenSaturation, Value = v.Spo2!.Value, Unit = "%", Date = dateOnly, SourceDevice = canon });
                if ((v.RespiratoryRate ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.RespiratoryRate, Value = v.RespiratoryRate!.Value, Unit = "br/min", Date = dateOnly, SourceDevice = canon });
                if ((v.WeightKg ?? 0) > 0)
                    list.Add(new VitalMetric { Type = VitalType.Weight, Value = v.WeightKg!.Value, Unit = "kg", Date = dateOnly, SourceDevice = canon });
                if (v.SkinTempCelsius.HasValue)
                    list.Add(new VitalMetric { Type = VitalType.BodyTemperature, Value = v.SkinTempCelsius.Value, Unit = "°C", Date = dateOnly, SourceDevice = canon });
            }

            foreach (var s in leanSleep.Where(s => s.SessionType == "primary_sleep" && s.DurationSeconds > 0)
                                       .OrderBy(s => ResolveEffectivePriorityRank(s.SourceDeviceKey, sources)))
            {
                var canon = DeviceSource.From(s.SourceDeviceKey).DisplayName;
                if (!DeviceSource.IsVirtual(canon))
                {
                    list.Add(new VitalMetric { Type = VitalType.SleepDuration, Value = s.DurationSeconds / 60.0, Unit = "min", Date = dateOnly, SourceDevice = canon });
                }
            }

            // Fallback to canonical summary vitals with honest source attribution (never "Canonical")
            if (summary?.Summary?.Vitals != null)
            {
                foreach (var (k, v) in summary.Summary.Vitals)
                {
                    if (HealthMetricRegistry.TryResolve(k, out var canMetric))
                    {
                        var vt = VitalMetric.ParseVitalType(canMetric.ToKey());
                        var src = DeviceSource.From(v.SourceDevice);
                        var canonSrc = src.IsVirtualEngine ? "" : src.DisplayName;
                        if (!list.Any(x => x.Type == vt && string.Equals(x.SourceDevice, canonSrc, StringComparison.OrdinalIgnoreCase)))
                        {
                            list.Add(new VitalMetric
                            {
                                Type = vt,
                                Value = v.Value,
                                Unit = v.Unit ?? "",
                                Date = dateOnly,
                                SourceDevice = canonSrc
                            });
                        }
                    }
                }
            }

            // Top-level summary column fallbacks when offline SQLite summary has no Vitals dictionary entries
            if (summary != null)
            {
                var fallbackSrc = summary.Summary?.Sources?.Select(DeviceSource.From).FirstOrDefault(x => !x.IsVirtualEngine)?.DisplayName ?? "";
                void EnsureTopLevel(VitalType vt, double? val, string unit)
                {
                    if (val.HasValue && val.Value > 0 && !list.Any(x => x.Type == vt))
                    {
                        list.Add(new VitalMetric { Type = vt, Value = val.Value, Unit = unit, Date = dateOnly, SourceDevice = fallbackSrc });
                    }
                }
                EnsureTopLevel(VitalType.Steps, summary.Steps, "steps");
                EnsureTopLevel(VitalType.ActiveEnergy, summary.ActiveKcal, "kcal");
                EnsureTopLevel(VitalType.RestingHeartRate, summary.Rhr, "bpm");
                EnsureTopLevel(VitalType.HeartRateVariabilitySDNN, summary.HrvSdnn, "ms");
                EnsureTopLevel(VitalType.HeartRateVariabilityRMSSD, summary.HrvRmssd, "ms");
                EnsureTopLevel(VitalType.OxygenSaturation, summary.Spo2, "%");
                EnsureTopLevel(VitalType.Weight, summary.Weight, "kg");
                EnsureTopLevel(VitalType.Stress, summary.StressAvg, "pts");
                if (summary.Summary?.Cardiovascular?.LatestBpm is double lbpm && lbpm >= 30)
                {
                    var hrSrc = !string.IsNullOrEmpty(summary.Summary.Cardiovascular.LatestSourceDevice)
                        ? DeviceSource.From(summary.Summary.Cardiovascular.LatestSourceDevice).DisplayName
                        : fallbackSrc;
                    if (!list.Any(x => x.Type == VitalType.HeartRate))
                    {
                        list.Add(new VitalMetric { Type = VitalType.HeartRate, Value = lbpm, Unit = "bpm", Date = dateOnly, SourceDevice = hrSrc });
                    }
                }
            }

            return list;
        }

        public async Task<List<VitalMetric>> GetHistoryAsync(VitalType type, int days = 7)
        {
            var end = DateTime.Today;
            var start = end.AddDays(-days + 1);
            var summaries = await GetDailySummariesRangeAsync(start, end);
            var result = new List<VitalMetric>();

            foreach (var s in summaries)
            {
                if (!DateTime.TryParse(s.LocalDate, out var dt)) continue;

                double? val = type switch
                {
                    VitalType.Steps => s.Steps,
                    VitalType.ActiveEnergy => s.ActiveKcal,
                    VitalType.SleepDuration => s.SleepAsleepS.HasValue ? s.SleepAsleepS.Value / 60.0 : null,
                    VitalType.RestingHeartRate => s.Rhr,
                    VitalType.HeartRateVariabilitySDNN => s.HrvSdnn,
                    VitalType.HeartRateVariabilityRMSSD => s.HrvRmssd,
                    VitalType.Weight => s.Weight,
                    VitalType.OxygenSaturation => s.Spo2,
                    VitalType.Stress => s.StressAvg,
                    _ => null
                };

                if (val.HasValue)
                {
                    var dom = s.Summary?.Sources?.Select(DeviceSource.From).FirstOrDefault(x => !x.IsVirtualEngine)?.DisplayName ?? "";
                    result.Add(new VitalMetric
                    {
                        Type = type,
                        Value = val.Value,
                        Date = dt.Date,
                        SourceDevice = dom
                    });
                }
            }

            return result;
        }

        public async Task<(SleepSession? PrimarySession, List<SleepSession> AllSessions)> GetSleepSessionsAsync(DateTime date)
        {
            var leanRowsTask = GetLeanSleepSessionsAsync(date);
            var sourcesTask = GetHealthSourcesAsync();
            await Task.WhenAll(leanRowsTask, sourcesTask).ConfigureAwait(false);
            var leanRows = leanRowsTask.Result;
            var sources = sourcesTask.Result;

            if (leanRows.Any())
            {
                var ordered = leanRows
                    .OrderByDescending(r => r.IsUserSelected)
                    .ThenByDescending(r => r.HasGranularSleepStages)
                    .ThenBy(r => ResolveEffectivePriorityRank(r.SourceDeviceKey, sources))
                    .ThenByDescending(r => r.DurationSeconds)
                    .ToList();

                var allDomain = ordered.Select(r => r.ToDomainSleepSession(date)).ToList();
                var primaryDomain = allDomain.FirstOrDefault(s => !s.IsNap) ?? allDomain.FirstOrDefault();
                return (primaryDomain, allDomain);
            }

            var summary = await GetDailySummaryAsync(date).ConfigureAwait(false);
            var primary = summary?.Summary?.Sleep?.PrimarySession;

            if (primary == null || primary.DurationSeconds <= 0)
            {
                return (null, new List<SleepSession>());
            }

            DateTimeOffset.TryParse(primary.StartTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var startDto);
            DateTimeOffset.TryParse(primary.EndTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var endDto);
            var start = startDto != default ? startDto.LocalDateTime : (DateTime.TryParse(primary.StartTime, out var sParsed) ? sParsed : date.Date.AddHours(23));
            var end = endDto != default ? endDto.LocalDateTime : (DateTime.TryParse(primary.EndTime, out var eParsed) ? eParsed : date.Date.AddDays(1).AddHours(7));

            var session = new SleepSession
            {
                StartTime = start,
                EndTime = end,
                IsNap = false,
                DurationSeconds = primary.DurationSeconds,
                AsleepSeconds = primary.AsleepSeconds,
                DeepSeconds = primary.DeepSeconds,
                RemSeconds = primary.RemSeconds,
                LightSeconds = primary.LightSeconds,
                AwakeSeconds = primary.AwakeSeconds,
                SleepScore = primary.SleepScore > 0 ? primary.SleepScore : (summary?.SleepScore ?? 0),
                SourceDevice = primary.EffectiveSourceDevice,
                HasGranularHypnogram = primary.HasGranularHypnogram
            };

            if (primary.Stages != null && primary.Stages.Any())
            {
                session.Stages = primary.Stages.Select(st =>
                {
                    DateTimeOffset.TryParse(st.StartTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var sTimeDto);
                    DateTimeOffset.TryParse(st.EndTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var eTimeDto);
                    var sTime = sTimeDto != default ? sTimeDto.LocalDateTime : (DateTime.TryParse(st.StartTime, out var stp) ? stp : start);
                    var eTime = eTimeDto != default ? eTimeDto.LocalDateTime : (DateTime.TryParse(st.EndTime, out var etp) ? etp : sTime.AddSeconds(st.DurationSeconds));
                    var stageKey = st.Stage.ToLowerInvariant() switch
                    {
                        "deep" => "sleep_stage_deep",
                        "rem" => "sleep_stage_rem",
                        "light" or "core" => "sleep_stage_light",
                        _ => "sleep_stage_awake"
                    };

                    var stSrc = !string.IsNullOrEmpty(st.SourceDevice) ? DeviceSource.From(st.SourceDevice).DisplayName : primary.EffectiveSourceDevice;
                    return new HealthTelemetry
                    {
                        TypeString = stageKey,
                        Value = st.DurationSeconds,
                        Unit = "sec",
                        StartTime = sTime,
                        EndTime = eTime != default ? eTime : sTime.AddSeconds(st.DurationSeconds),
                        SourceDevice = stSrc
                    };
                }).ToList();
            }

            var all = new List<SleepSession> { session };
            if (summary?.Summary?.Sleep?.AllSessions != null && summary.Summary.Sleep.AllSessions.Count > 1)
            {
                foreach (var other in summary.Summary.Sleep.AllSessions.Where(s => s != primary))
                {
                    DateTimeOffset.TryParse(other.StartTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var oStartDto);
                    DateTimeOffset.TryParse(other.EndTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var oEndDto);
                    all.Add(new SleepSession
                    {
                        StartTime = oStartDto != default ? oStartDto.LocalDateTime : date.Date,
                        EndTime = oEndDto != default ? oEndDto.LocalDateTime : date.Date,
                        IsNap = other.IsNap,
                        DurationSeconds = other.DurationSeconds,
                        AsleepSeconds = other.AsleepSeconds,
                        DeepSeconds = other.DeepSeconds,
                        RemSeconds = other.RemSeconds,
                        LightSeconds = other.LightSeconds,
                        AwakeSeconds = other.AwakeSeconds,
                        SleepScore = other.SleepScore,
                        SourceDevice = other.EffectiveSourceDevice,
                        HasGranularHypnogram = other.HasGranularHypnogram
                    });
                }
            }
            return (session, all);
        }

        public async Task<List<HealthTelemetry>> GetHealthTelemetryAsync(DateTime start, DateTime end)
        {
            var list = new List<HealthTelemetry>();

            // Single-day view: pull directly from lean per-device tables so device switching has exact HR & hourly steps
            if (start.Date == end.Date)
            {
                var hrBucketsTask = GetLeanIntradayHeartRateAsync(start.Date);
                var vitalsTask = GetLeanDailyVitalsAsync(start.Date);
                await Task.WhenAll(hrBucketsTask, vitalsTask).ConfigureAwait(false);

                foreach (var b in hrBucketsTask.Result)
                {
                    var canon = DeviceSource.From(b.SourceDeviceKey).DisplayName;
                    if (DeviceSource.IsVirtual(canon)) continue;
                    var ts = start.Date.AddMinutes(b.BucketMinute);
                    list.Add(new HealthTelemetry
                    {
                        TypeString = "heart_rate",
                        Value = b.BpmAvg,
                        Unit = "bpm",
                        StartTime = ts,
                        EndTime = ts.AddMinutes(5),
                        SourceDevice = canon
                    });
                }

                foreach (var v in vitalsTask.Result)
                {
                    var canon = DeviceSource.From(v.SourceDeviceKey).DisplayName;
                    if (DeviceSource.IsVirtual(canon)) continue;
                    if (v.HourlySteps != null)
                    {
                        foreach (var hb in v.HourlySteps.Where(hb => hb.Steps > 0))
                        {
                            var hTime = start.Date.AddHours(hb.Hour);
                            list.Add(new HealthTelemetry
                            {
                                TypeString = "steps",
                                Value = hb.Steps,
                                Unit = "steps",
                                StartTime = hTime,
                                EndTime = hTime.AddHours(1),
                                SourceDevice = canon
                            });
                        }
                    }
                }

                if (!hrBucketsTask.Result.Any() || !vitalsTask.Result.Any())
                {
                    var singleSummary = await GetDailySummaryAsync(start.Date).ConfigureAwait(false);
                    if (singleSummary != null)
                    {
                        if (!hrBucketsTask.Result.Any() && singleSummary.Summary?.Cardiovascular?.IntradayHeartRate != null)
                        {
                            foreach (var pt in singleSummary.Summary.Cardiovascular.IntradayHeartRate)
                            {
                                if (DateTime.TryParse(pt.Timestamp, out var ts))
                                {
                                    var src = DeviceSource.From(pt.SourceDevice);
                                    list.Add(new HealthTelemetry
                                    {
                                        TypeString = "heart_rate",
                                        Value = pt.Bpm,
                                        Unit = "bpm",
                                        StartTime = ts,
                                        EndTime = ts,
                                        SourceDevice = src.IsVirtualEngine ? "" : src.DisplayName
                                    });
                                }
                            }
                        }

                        if (!vitalsTask.Result.Any() && singleSummary.Summary?.Activity?.HourlySteps != null && DateTime.TryParse(singleSummary.LocalDate, out var ld))
                        {
                            var actSrc = DeviceSource.From(singleSummary.Summary.Activity.SourceDevice);
                            var actCanon = actSrc.IsVirtualEngine ? "" : actSrc.DisplayName;
                            foreach (var b in singleSummary.Summary.Activity.HourlySteps)
                            {
                                var hTime = ld.Date.AddHours(b.Hour);
                                list.Add(new HealthTelemetry
                                {
                                    TypeString = "steps",
                                    Value = b.Steps,
                                    Unit = "steps",
                                    StartTime = hTime,
                                    EndTime = hTime.AddHours(1),
                                    SourceDevice = actCanon
                                });
                            }
                        }
                    }
                }

                return list;
            }

            var summaries = await GetDailySummariesRangeAsync(start.Date, end.Date).ConfigureAwait(false);
            foreach (var s in summaries)
            {
                if (s.Summary?.Cardiovascular?.IntradayHeartRate != null)
                {
                    foreach (var pt in s.Summary.Cardiovascular.IntradayHeartRate)
                    {
                        if (DateTime.TryParse(pt.Timestamp, out var ts))
                        {
                            var src = DeviceSource.From(pt.SourceDevice);
                            list.Add(new HealthTelemetry
                            {
                                TypeString = "heart_rate",
                                Value = pt.Bpm,
                                Unit = "bpm",
                                StartTime = ts,
                                EndTime = ts,
                                SourceDevice = src.IsVirtualEngine ? "" : src.DisplayName
                            });
                        }
                    }
                }

                if (s.Summary?.Activity?.HourlySteps != null && DateTime.TryParse(s.LocalDate, out var ld))
                {
                    var actSrc = DeviceSource.From(s.Summary.Activity.SourceDevice);
                    var actCanon = actSrc.IsVirtualEngine ? "" : actSrc.DisplayName;
                    foreach (var b in s.Summary.Activity.HourlySteps)
                    {
                        var hTime = ld.Date.AddHours(b.Hour);
                        list.Add(new HealthTelemetry
                        {
                            TypeString = "steps",
                            Value = b.Steps,
                            Unit = "steps",
                            StartTime = hTime,
                            EndTime = hTime.AddHours(1),
                            SourceDevice = actCanon
                        });
                    }
                }
            }

            return list;
        }

        public async Task<List<VitalMetric>> GetVitalsAsync(DateTime start, DateTime end)
        {
            var summaries = await GetDailySummariesRangeAsync(start, end);
            var list = new List<VitalMetric>();
            foreach (var s in summaries)
            {
                if (DateTime.TryParse(s.LocalDate, out var dt))
                {
                    list.AddRange(await FetchMetricsForDateAsync(dt));
                }
            }
            return list;
        }

        public async Task<VitalMetric?> GetLatestMetricAsync(VitalType type)
        {
            var metrics = await FetchMetricsForDateAsync(DateTime.Today);
            return metrics.FirstOrDefault(x => x.Type == type);
        }

        public Task SyncNativeHealthDataAsync()
        {
            return PullDeltasAsync();
        }

        public async Task PullDeltasAsync()
        {
            var today = DateTime.Today;
            var todayStr = today.ToString("yyyy-MM-dd");
            var selectedStr = _selectedDate.ToString("yyyy-MM-dd");

            _sleepCache.TryRemove(todayStr, out _);
            _vitalsCache.TryRemove(todayStr, out _);
            _hrCache.TryRemove(todayStr, out _);
            if (selectedStr != todayStr)
            {
                _sleepCache.TryRemove(selectedStr, out _);
                _vitalsCache.TryRemove(selectedStr, out _);
                _hrCache.TryRemove(selectedStr, out _);
            }
            InvalidateRangeCaches();

            if (!_hasLoadedSources || (DateTime.UtcNow - _lastSourcesFetchedUtc).TotalMinutes >= 15)
            {
                await GetHealthSourcesAsync(forceRefresh: true).ConfigureAwait(false);
            }
            await RefreshSummaryFromRemoteAsync(today).ConfigureAwait(false);
            if (_selectedDate.Date != today.Date)
            {
                await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
            }
        }
    }
}
