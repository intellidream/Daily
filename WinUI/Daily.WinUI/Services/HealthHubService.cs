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
        private readonly ConcurrentDictionary<string, List<HealthSleepSessionRecord>> _sleepCache = new();
        private readonly ConcurrentDictionary<string, List<HealthDailyVitalsRecord>> _vitalsCache = new();
        private readonly ConcurrentDictionary<string, List<HealthIntradayHeartRateRecord>> _hrCache = new();
        private readonly ConcurrentDictionary<string, Task<HealthDailySummaryRecord?>> _inFlightFetches = new();
        private readonly System.Threading.SemaphoreSlim _realtimeSemaphore = new(1, 1);

        private DateTime _selectedDate = DateTime.Today;
        private string _currentViewType = "Overview";
        private HealthDailySummaryRecord? _currentSummary;
        private RealtimeChannel? _realtimeChannel;
        private RealtimeChannel? _vitalsRealtimeChannel;
        private RealtimeChannel? _sleepRealtimeChannel;
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
                        _ = Task.Run(async () =>
                        {
                            try
                            {
                                await SetupRealtimeSubscriptionAsync(forceRecreate: true).ConfigureAwait(false);
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

        public async Task InitializeAsync(bool forceRecreateRealtime = false)
        {
            if (_isInitialized && !forceRecreateRealtime) return;

            try
            {
                await _dbService.InitializeAsync().ConfigureAwait(false);

                // Purge pre-v2 cached summaries so canonical v2 unified data loads cleanly
                try
                {
                    await _dbService.Connection.ExecuteAsync(
                        "DELETE FROM health_daily_summary_cache WHERE EngineVersion IS NULL OR EngineVersion <> '2.0'"
                    ).ConfigureAwait(false);
                }
                catch { }

                await LoadSummaryFromLocalCacheAsync(_selectedDate).ConfigureAwait(false);

                _ = Task.Run(async () =>
                {
                    try
                    {
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
            if (_memoryCache.TryGetValue(dateStr, out var cached))
            {
                _currentSummary = cached;
                DispatchToUI(() => OnDailySummaryChanged?.Invoke(cached));
                return cached;
            }

            try
            {
                var entity = await _dbService.Connection.FindAsync<HealthDailySummaryEntity>(dateStr).ConfigureAwait(false);
                if (entity != null && entity.EngineVersion == "2.0")
                {
                    var record = MapEntityToRecord(entity);
                    _memoryCache[dateStr] = record;
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

            if (!forceRefresh && _memoryCache.TryGetValue(dateStr, out var cached))
            {
                return cached;
            }

            if (!forceRefresh)
            {
                try
                {
                    var entity = await _dbService.Connection.FindAsync<HealthDailySummaryEntity>(dateStr).ConfigureAwait(false);
                    if (entity != null && entity.EngineVersion == "2.0")
                    {
                        var record = MapEntityToRecord(entity);
                        _memoryCache[dateStr] = record;
                        return record;
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

            return cached ?? new List<HealthSleepSessionRecord>();
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

            return cached ?? new List<HealthDailyVitalsRecord>();
        }

        public async Task<List<HealthIntradayHeartRateRecord>> GetLeanIntradayHeartRateAsync(DateTime date, bool forceRefresh = false)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var hasCached = _hrCache.TryGetValue(dateStr, out var cached);
            if (!forceRefresh && hasCached && cached != null)
            {
                return cached;
            }

            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId))
            {
                return cached ?? new List<HealthIntradayHeartRateRecord>();
            }

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

            return cached ?? new List<HealthIntradayHeartRateRecord>();
        }

        public async Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsRangeAsync(DateTime startDate, DateTime endDate)
        {
            var startStr = startDate.ToString("yyyy-MM-dd");
            var endStr = endDate.ToString("yyyy-MM-dd");
            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (string.IsNullOrEmpty(currentUserId)) return new List<HealthSleepSessionRecord>();

            try
            {
                var fetchTask = _sessionGuardian != null
                    ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                        () => _supabaseClient.From<HealthSleepSessionRecord>()
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                            .Where(x => x.UserId == currentUserId)
                            .Get(),
                        "HealthHubService.GetLeanSleepSessionsRange")
                    : _supabaseClient.From<HealthSleepSessionRecord>()
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
                    foreach (var g in list.GroupBy(r => r.LocalDate))
                    {
                        _sleepCache[g.Key] = g.ToList();
                    }
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
                    return list;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] GetLeanDailyVitalsRange failed: {Message}", ex.Message);
            }

            return new List<HealthDailyVitalsRecord>();
        }

        public async Task<List<HealthDailySummaryRecord>> GetDailySummariesRangeAsync(DateTime startDate, DateTime endDate)
        {
            var startStr = startDate.ToString("yyyy-MM-dd");
            var endStr = endDate.ToString("yyyy-MM-dd");
            var results = new Dictionary<string, HealthDailySummaryRecord>(StringComparer.OrdinalIgnoreCase);

            try
            {
                var cached = await _dbService.Connection.QueryAsync<HealthDailySummaryEntity>(
                    "SELECT * FROM health_daily_summary_cache WHERE LocalDate >= ? AND LocalDate <= ? AND EngineVersion = '2.0' ORDER BY LocalDate",
                    startStr, endStr).ConfigureAwait(false);

                foreach (var entity in cached)
                {
                    var rec = MapEntityToRecord(entity);
                    results[rec.LocalDate] = rec;
                    _memoryCache[rec.LocalDate] = rec;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "[HealthHubService] Range cache read error: {Message}", ex.Message);
            }

            var currentUserId = await EnsureUserIdAsync().ConfigureAwait(false);
            if (!string.IsNullOrEmpty(currentUserId))
            {
                try
                {
                    var fetchTask = _sessionGuardian != null
                        ? _sessionGuardian.ExecuteWithAuthRetryAsync(
                            () => _supabaseClient.From<HealthDailySummaryRecord>()
                                .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                                .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                                .Where(x => x.UserId == currentUserId)
                                .Get(),
                            "HealthHubService.GetDailySummariesRange")
                        : _supabaseClient.From<HealthDailySummaryRecord>()
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                            .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                            .Where(x => x.UserId == currentUserId)
                            .Get();

                    var completed = await Task.WhenAny(fetchTask, Task.Delay(5000)).ConfigureAwait(false);
                    if (completed == fetchTask)
                    {
                        var resp = await fetchTask.ConfigureAwait(false);
                        foreach (var record in resp.Models)
                        {
                            results[record.LocalDate] = record;
                            _memoryCache[record.LocalDate] = record;
                            await SaveRecordToSqliteAsync(record).ConfigureAwait(false);
                        }
                    }
                    else
                    {
                        _logger?.LogWarning("[HealthHubService] Range remote read timed out for {Start} to {End}", startStr, endStr);
                    }
                }
                catch (Exception ex)
                {
                    _logger?.LogWarning(ex, "[HealthHubService] Range remote read error: {Message}", ex.Message);
                }
            }

            return results.Values.OrderBy(x => x.LocalDate).ToList();
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

                _realtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_daily_summary", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _realtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeSummaryReceived);

                _vitalsRealtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_daily_vitals", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _vitalsRealtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeLeanTableReceived);

                _sleepRealtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_sleep_sessions", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _sleepRealtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeLeanTableReceived);

                var subscribeTask = Task.WhenAll(
                    _realtimeChannel.Subscribe(),
                    _vitalsRealtimeChannel.Subscribe(),
                    _sleepRealtimeChannel.Subscribe()
                );
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
                    _memoryCache[record.LocalDate] = record;
                    _sleepCache.TryRemove(record.LocalDate, out _);
                    _vitalsCache.TryRemove(record.LocalDate, out _);
                    _hrCache.TryRemove(record.LocalDate, out _);
                    _ = SaveRecordToSqliteAsync(record);

                    if (record.LocalDate == _selectedDate.ToString("yyyy-MM-dd"))
                    {
                        _currentSummary = record;
                        DispatchToUI(() =>
                        {
                            OnDailySummaryChanged?.Invoke(record);
                            OnSelectedDateChanged?.Invoke();
                        });
                    }
                }
            }
            catch (Exception ex)
            {
                _logger?.LogError(ex, "[HealthHubService] Realtime change processing error: {Message}", ex.Message);
            }
        }

        private void OnRealtimeLeanTableReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            var nowTicks = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            var prev = System.Threading.Interlocked.Read(ref _lastRealtimeFetchTicks);
            if (nowTicks - prev < 3000) return;
            System.Threading.Interlocked.Exchange(ref _lastRealtimeFetchTicks, nowTicks);

            _ = Task.Run(async () =>
            {
                try
                {
                    var dateStr = _selectedDate.ToString("yyyy-MM-dd");
                    _sleepCache.TryRemove(dateStr, out _);
                    _vitalsCache.TryRemove(dateStr, out _);
                    _hrCache.TryRemove(dateStr, out _);
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
                var dispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
                if (dispatcher != null)
                {
                    dispatcher.TryEnqueue(() => action());
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
            await Task.WhenAll(summaryTask, leanVitalsTask, leanSleepTask).ConfigureAwait(false);

            var summary = summaryTask.Result;
            var leanVitals = leanVitalsTask.Result;
            var leanSleep = leanSleepTask.Result;
            var list = new List<VitalMetric>();
            var dateOnly = date.Date;

            // Emit per-device metrics from lean vitals first (ordered by canonical priority)
            foreach (var v in leanVitals.OrderByDescending(r => DeviceSource.From(r.SourceDeviceKey).SortPriority))
            {
                var canon = DeviceSource.From(v.SourceDeviceKey).DisplayName;
                if (DeviceSource.IsVirtual(canon)) continue;

                if (v.Steps > 0)
                    list.Add(new VitalMetric { Type = VitalType.Steps, Value = v.Steps, Unit = "steps", Date = dateOnly, SourceDevice = canon });
                if (v.ActiveKcal > 0)
                    list.Add(new VitalMetric { Type = VitalType.ActiveEnergy, Value = v.ActiveKcal, Unit = "kcal", Date = dateOnly, SourceDevice = canon });
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
                                       .OrderByDescending(s => DeviceSource.From(s.SourceDeviceKey).SortPriority))
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
            var leanRows = await GetLeanSleepSessionsAsync(date).ConfigureAwait(false);
            if (leanRows.Any())
            {
                var ordered = leanRows
                    .OrderByDescending(r => r.IsUserSelected)
                    .ThenByDescending(r => r.Stages != null && r.Stages.Count > 0)
                    .ThenByDescending(r => DeviceSource.From(r.SourceDeviceKey).SortPriority)
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

                if (list.Any()) return list;
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
            _memoryCache.Clear();
            _sleepCache.Clear();
            _vitalsCache.Clear();
            _hrCache.Clear();
            await LoadSummaryForSelectedDateAsync();
        }
    }
}
