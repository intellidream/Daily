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
    /// Pure canonical renderer data service for WinUI 3 Health Hub.
    /// Provides instant local SQLite loading (<300ms), live Supabase Realtime synchronization,
    /// and strict adherence to zero-synthetic honest health metrics.
    /// </summary>
    public class HealthHubService : IHealthHubService
    {
        private readonly Supabase.Client _supabaseClient;
        private readonly IDatabaseService _dbService;
        private readonly ISettingsService _settingsService;
        private readonly ILogger<HealthHubService>? _logger;
        private readonly ConcurrentDictionary<string, HealthDailySummaryRecord> _memoryCache = new();
        private readonly ConcurrentDictionary<string, Task<HealthDailySummaryRecord?>> _inFlightFetches = new();
        private readonly System.Threading.SemaphoreSlim _realtimeSemaphore = new(1, 1);

        private DateTime _selectedDate = DateTime.Today;
        private string _currentViewType = "Overview";
        private HealthDailySummaryRecord? _currentSummary;
        private RealtimeChannel? _realtimeChannel;
        private bool _isInitialized = false;

        public HealthHubService(
            Supabase.Client supabaseClient,
            IDatabaseService dbService,
            ISettingsService settingsService,
            ILogger<HealthHubService>? logger = null)
        {
            _supabaseClient = supabaseClient;
            _dbService = dbService;
            _settingsService = settingsService;
            _logger = logger;

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
                // 1. Guarantee local database table is initialized (<5ms)
                await _dbService.InitializeAsync().ConfigureAwait(false);

                // 2. Load initial date summary from FAST local SQLite/memory cache (<10ms)
                await LoadSummaryFromLocalCacheAsync(_selectedDate).ConfigureAwait(false);

                // 3. Fire-and-forget remote synchronization in background - NEVER block startup
                _ = Task.Run(async () =>
                {
                    try
                    {
                        await RefreshSummaryFromRemoteAsync(_selectedDate).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        _logger?.LogWarning(ex, "[HealthHubService] Background initial summary fetch error: {Message}", ex.Message);
                    }
                });

                // 4. Fire-and-forget Realtime setup with timeout protection - NEVER block startup
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
                if (entity != null)
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
                // First load instantly from local SQLite/memory cache
                var cached = await LoadSummaryFromLocalCacheAsync(_selectedDate).ConfigureAwait(false);

                // Asynchronously pull latest from remote in background
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

        private async Task<HealthDailySummaryRecord?> RefreshSummaryFromRemoteAsync(DateTime date)
        {
            var dateStr = date.ToString("yyyy-MM-dd");
            var currentUserId = _supabaseClient.Auth.CurrentSession?.User?.Id;
            if (string.IsNullOrEmpty(currentUserId))
            {
                return _memoryCache.TryGetValue(dateStr, out var fallback) ? fallback : null;
            }

            try
            {
                var fetchTask = _supabaseClient.From<HealthDailySummaryRecord>()
                    .Where(x => x.UserId == currentUserId && x.LocalDate == dateStr)
                    .Get();

                var completed = await Task.WhenAny(fetchTask, Task.Delay(4000)).ConfigureAwait(false);
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

            // 1. Fast memory cache (<0.1ms)
            if (!forceRefresh && _memoryCache.TryGetValue(dateStr, out var cached))
            {
                return cached;
            }

            // 2. Offline SQLite cache (<10ms)
            if (!forceRefresh)
            {
                try
                {
                    var entity = await _dbService.Connection.FindAsync<HealthDailySummaryEntity>(dateStr).ConfigureAwait(false);
                    if (entity != null)
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

            // 3. Remote Supabase fetch with single-flight deduplication (prevents parallel storm)
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

        public async Task<List<HealthDailySummaryRecord>> GetDailySummariesRangeAsync(DateTime startDate, DateTime endDate)
        {
            var startStr = startDate.ToString("yyyy-MM-dd");
            var endStr = endDate.ToString("yyyy-MM-dd");
            var results = new Dictionary<string, HealthDailySummaryRecord>(StringComparer.OrdinalIgnoreCase);

            // Read from SQLite first (<20ms)
            try
            {
                var cached = await _dbService.Connection.QueryAsync<HealthDailySummaryEntity>(
                    "SELECT * FROM health_daily_summary_cache WHERE LocalDate >= ? AND LocalDate <= ? ORDER BY LocalDate",
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

            // Sync missing from remote with timeout
            var currentUserId = _supabaseClient.Auth.CurrentSession?.User?.Id;
            if (!string.IsNullOrEmpty(currentUserId))
            {
                try
                {
                    var fetchTask = _supabaseClient.From<HealthDailySummaryRecord>()
                        .Filter("local_date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                        .Filter("local_date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, endStr)
                        .Where(x => x.UserId == currentUserId)
                        .Get();

                    var completed = await Task.WhenAny(fetchTask, Task.Delay(4000)).ConfigureAwait(false);
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

                if (_realtimeChannel != null)
                {
                    try { _realtimeChannel.Unsubscribe(); } catch { }
                    try { _supabaseClient.Realtime.Remove(_realtimeChannel); } catch { }
                    _realtimeChannel = null;
                }

                _realtimeChannel = _supabaseClient.Realtime.Channel("realtime", "public", "health_daily_summary", $"user_id=eq.{userId}", null, new Dictionary<string, string>());
                _realtimeChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnRealtimeSummaryReceived);

                var subscribeTask = _realtimeChannel.Subscribe();
                var completed = await Task.WhenAny(subscribeTask, Task.Delay(3000)).ConfigureAwait(false);
                if (completed != subscribeTask)
                {
                    _logger?.LogWarning("[HealthHubService] Realtime channel subscribe timed out after 3000ms. Will retry on socket open.");
                }
                else
                {
                    _logger?.LogInformation("[HealthHubService] Realtime channel subscribed to health_daily_summary");
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
                    EngineVersion = record.EngineVersion,
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
            var summary = await GetDailySummaryAsync(date);
            if (summary == null) return new List<VitalMetric>();

            var list = new List<VitalMetric>();
            var dateOnly = date.Date;

            if (summary.Steps.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.Steps, Value = summary.Steps.Value, Unit = "steps", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.ActiveKcal.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.ActiveEnergy, Value = summary.ActiveKcal.Value, Unit = "kcal", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.SleepAsleepS.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.SleepDuration, Value = summary.SleepAsleepS.Value / 60.0, Unit = "min", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.Rhr.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.RestingHeartRate, Value = summary.Rhr.Value, Unit = "bpm", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.HrvSdnn.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.HeartRateVariabilitySDNN, Value = summary.HrvSdnn.Value, Unit = "ms", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.HrvRmssd.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.HeartRateVariabilityRMSSD, Value = summary.HrvRmssd.Value, Unit = "ms", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.Weight.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.Weight, Value = summary.Weight.Value, Unit = "kg", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.Spo2.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.OxygenSaturation, Value = summary.Spo2.Value, Unit = "%", Date = dateOnly, SourceDevice = "Canonical" });
            }
            if (summary.StressAvg.HasValue)
            {
                list.Add(new VitalMetric { Type = VitalType.Stress, Value = summary.StressAvg.Value, Unit = "score", Date = dateOnly, SourceDevice = "Canonical" });
            }

            // Extract extra items from vitals dictionary
            if (summary.Summary?.Vitals != null)
            {
                foreach (var (k, v) in summary.Summary.Vitals)
                {
                    if (HealthMetricRegistry.TryResolve(k, out var canMetric))
                    {
                        var vt = VitalMetric.ParseVitalType(canMetric.ToKey());
                        if (!list.Any(x => x.Type == vt))
                        {
                            list.Add(new VitalMetric
                            {
                                Type = vt,
                                Value = v.Value,
                                Unit = v.Unit ?? "",
                                Date = dateOnly,
                                SourceDevice = v.SourceDevice ?? "Canonical"
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
                    result.Add(new VitalMetric
                    {
                        Type = type,
                        Value = val.Value,
                        Date = dt.Date,
                        SourceDevice = "Canonical"
                    });
                }
            }

            return result;
        }

        public async Task<(SleepSession? PrimarySession, List<SleepSession> AllSessions)> GetSleepSessionsAsync(DateTime date)
        {
            var summary = await GetDailySummaryAsync(date);
            var primary = summary?.Summary?.Sleep?.PrimarySession;

            if (primary == null || primary.DurationSeconds <= 0)
            {
                return (null, new List<SleepSession>());
            }

            DateTime.TryParse(primary.StartTime, out var start);
            DateTime.TryParse(primary.EndTime, out var end);

            var session = new SleepSession
            {
                StartTime = start != default ? start : date.Date.AddHours(23),
                EndTime = end != default ? end : date.Date.AddDays(1).AddHours(7),
                IsNap = false,
                DurationSeconds = primary.DurationSeconds,
                AsleepSeconds = primary.AsleepSeconds,
                SleepScore = primary.SleepScore > 0 ? primary.SleepScore : (summary?.SleepScore ?? 0)
            };

            if (primary.Stages != null && primary.Stages.Any())
            {
                session.Stages = primary.Stages.Select(st =>
                {
                    DateTime.TryParse(st.StartTime, out var sTime);
                    DateTime.TryParse(st.EndTime, out var eTime);
                    var stageKey = st.Stage.ToLowerInvariant() switch
                    {
                        "deep" => "sleep_stage_deep",
                        "rem" => "sleep_stage_rem",
                        "light" or "core" => "sleep_stage_light",
                        _ => "sleep_stage_awake"
                    };

                    return new HealthTelemetry
                    {
                        TypeString = stageKey,
                        Value = st.DurationSeconds,
                        Unit = "sec",
                        StartTime = sTime,
                        EndTime = eTime != default ? eTime : sTime.AddSeconds(st.DurationSeconds),
                        SourceDevice = primary.Tracker ?? "Canonical"
                    };
                }).ToList();
            }

            var all = new List<SleepSession> { session };
            return (session, all);
        }

        public async Task<List<HealthTelemetry>> GetHealthTelemetryAsync(DateTime start, DateTime end)
        {
            var summaries = await GetDailySummariesRangeAsync(start.Date, end.Date);
            var list = new List<HealthTelemetry>();

            foreach (var s in summaries)
            {
                if (s.Summary?.Cardiovascular?.IntradayHeartRate != null)
                {
                    foreach (var pt in s.Summary.Cardiovascular.IntradayHeartRate)
                    {
                        if (DateTime.TryParse(pt.Timestamp, out var ts))
                        {
                            list.Add(new HealthTelemetry
                            {
                                TypeString = "heart_rate",
                                Value = pt.Bpm,
                                Unit = "bpm",
                                StartTime = ts,
                                EndTime = ts,
                                SourceDevice = "Canonical"
                            });
                        }
                    }
                }

                if (s.Summary?.Activity?.HourlySteps != null)
                {
                    if (DateTime.TryParse(s.LocalDate, out var ld))
                    {
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
                                SourceDevice = "Canonical"
                            });
                        }
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
            // Desktop renderer - pulls latest from Supabase
            return PullDeltasAsync();
        }

        public async Task PullDeltasAsync()
        {
            _memoryCache.Clear();
            await LoadSummaryForSelectedDateAsync();
        }
    }
}
