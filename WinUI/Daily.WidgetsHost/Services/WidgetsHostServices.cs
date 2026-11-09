using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Models.Finances;
using Daily.Models.Health;
using Daily.Services;
using Daily.Services.Finances;
using Daily.Services.Health;
using Daily_WinUI.Services;

namespace Daily_WinUI.WidgetsHost.Services
{
    // ══════════════════════════════════════════════════════════════════════════
    // 1. HABITS SERVICE (Lean SQLite reader for Bubbles & Smokes widgets)
    // ══════════════════════════════════════════════════════════════════════════
    public class WidgetsHostHabitsService : IHabitsService
    {
        private readonly IDatabaseService _db;
        public event Action? OnHabitsUpdated;
        public event Action? OnViewTypeChanged;

        private string _currentViewType = "water";
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

        public WidgetsHostHabitsService(IDatabaseService db)
        {
            _db = db;
        }

        public async Task<List<HabitLog>> GetLogsAsync(string habitType, DateTime date)
        {
            await _db.InitializeAsync();
            var localLogs = await _db.Connection.Table<LocalHabitLog>()
                .Where(l => l.HabitType == habitType && !l.IsDeleted)
                .ToListAsync();

            return localLogs
                .Select(l => new HabitLog
                {
                    Id = Guid.TryParse(l.Id, out var g) ? g : Guid.NewGuid(),
                    UserId = Guid.TryParse(l.UserId, out var uid) ? uid : Guid.Empty,
                    HabitType = l.HabitType,
                    Value = l.Value,
                    Unit = l.Unit,
                    LoggedAt = l.LoggedAt,
                    Metadata = l.Metadata
                })
                .Where(l => l.LoggedAt.ToLocalTime().Date == date.Date)
                .OrderByDescending(l => l.LoggedAt)
                .ToList();
        }

        public async Task<double> GetDailyProgressAsync(string habitType, DateTime date)
        {
            var logs = await GetLogsAsync(habitType, date);
            return logs.Sum(l => l.Value);
        }

        public async Task<HabitGoal> GetGoalAsync(string habitType)
        {
            await _db.InitializeAsync();
            var localGoal = await _db.Connection.Table<LocalHabitGoal>()
                .Where(g => g.HabitType == habitType)
                .FirstOrDefaultAsync();

            if (localGoal != null)
            {
                return new HabitGoal
                {
                    Id = Guid.TryParse(localGoal.Id, out var g) ? g : Guid.NewGuid(),
                    HabitType = localGoal.HabitType,
                    TargetValue = localGoal.TargetValue,
                    Unit = localGoal.Unit
                };
            }

            return new HabitGoal
            {
                HabitType = habitType,
                TargetValue = habitType == "smokes" ? 40 : 2500,
                Unit = habitType == "smokes" ? "smokes" : "ml"
            };
        }

        public async Task UpdateGoalAsync(string habitType, double target, string unit)
        {
            await _db.InitializeAsync();
            var localGoal = await _db.Connection.Table<LocalHabitGoal>()
                .Where(g => g.HabitType == habitType)
                .FirstOrDefaultAsync();

            if (localGoal == null)
            {
                localGoal = new LocalHabitGoal
                {
                    Id = Guid.NewGuid().ToString(),
                    HabitType = habitType,
                    TargetValue = target,
                    Unit = unit,
                    UpdatedAt = DateTime.UtcNow
                };
                await _db.Connection.InsertAsync(localGoal);
            }
            else
            {
                localGoal.TargetValue = target;
                localGoal.Unit = unit;
                localGoal.UpdatedAt = DateTime.UtcNow;
                await _db.Connection.UpdateAsync(localGoal);
            }
            OnHabitsUpdated?.Invoke();
        }

        public async Task<Dictionary<string, double>> GetDailyBreakdownAsync(string habitType, DateTime date)
        {
            var logs = await GetLogsAsync(habitType, date);
            var breakdown = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);

            foreach (var log in logs)
            {
                string keyName = habitType == "smokes" ? "cigarette" : "water";
                if (!string.IsNullOrEmpty(log.Metadata))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(log.Metadata);
                        if (doc.RootElement.TryGetProperty("drink", out var d))
                        {
                            keyName = d.GetString() ?? keyName;
                        }
                    }
                    catch { }
                }
                else if (!string.IsNullOrEmpty(log.Unit))
                {
                    keyName = log.Unit;
                }

                if (!breakdown.ContainsKey(keyName))
                    breakdown[keyName] = 0;
                breakdown[keyName] += log.Value;
            }

            return breakdown;
        }

        public async Task AddLogAsync(string habitType, double value, string unit, DateTime loggedAt, string? metadata = null)
        {
            await _db.InitializeAsync();
            var log = new LocalHabitLog
            {
                Id = Guid.NewGuid().ToString(),
                UserId = string.Empty,
                HabitType = habitType,
                Value = value,
                Unit = unit,
                LoggedAt = loggedAt.ToUniversalTime(),
                Metadata = metadata,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
                SyncedAt = null,
                IsDeleted = false
            };
            await _db.Connection.InsertAsync(log);
            OnHabitsUpdated?.Invoke();
        }

        public async Task DeleteLogAsync(Guid logId)
        {
            await _db.InitializeAsync();
            var strId = logId.ToString();
            var item = await _db.Connection.Table<LocalHabitLog>().Where(l => l.Id == strId).FirstOrDefaultAsync();
            if (item != null)
            {
                item.IsDeleted = true;
                item.SyncedAt = null;
                item.UpdatedAt = DateTime.UtcNow;
                await _db.Connection.UpdateAsync(item);
                OnHabitsUpdated?.Invoke();
            }
        }

        public Task<List<DailySummary>> GetHistoryAsync(string habitType, DateTime startDate, DateTime endDate) =>
            Task.FromResult(new List<DailySummary>());

        public Task<List<DailySummary>> GetConsistencyAsync(string habitType, DateTime startDate, DateTime endDate) =>
            Task.FromResult(new List<DailySummary>());

        public Task<(double TotalSmoked, int DaysTracked)> GetSmokesFinancialsAsync(DateTime sinceDate) =>
            Task.FromResult((0.0, 0));

        public Task InitializeAsync(bool forceRecreateRealtime = false) => Task.CompletedTask;

        public Task<Dictionary<string, int>> GetSmokesBreakdownAsync(DateTime sinceDate) =>
            Task.FromResult(new Dictionary<string, int>());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 2. HEALTH SERVICE (Lean SQLite reader for Sleep & Stress widgets)
    // ══════════════════════════════════════════════════════════════════════════
    public class WidgetsHostHealthService : IHealthHubService
    {
        private readonly IDatabaseService _db;
        public event Action<HealthDailySummaryRecord?>? OnDailySummaryChanged;
        public event Action? OnHealthSourcesChanged;
        public event Action? OnViewTypeChanged;
        public event Action? OnSelectedDateChanged;

        public string CurrentViewType { get; set; } = "Overview";
        public DateTime SelectedDate { get; set; } = DateTime.Today;
        public HealthDailySummaryRecord? CurrentSummary { get; private set; }

        public WidgetsHostHealthService(IDatabaseService db)
        {
            _db = db;
        }

        public async Task<HealthDailySummaryRecord?> GetDailySummaryAsync(DateTime date, bool forceRefresh = false)
        {
            await _db.InitializeAsync();
            string dateStr = date.ToString("yyyy-MM-dd");

            try
            {
                var entity = await _db.Connection.Table<HealthDailySummaryEntity>()
                    .Where(e => e.LocalDate == dateStr)
                    .FirstOrDefaultAsync();

                // If today has no summary yet or has zero sleep & stress, check yesterday's summary
                if (entity == null || ((entity.SleepScore == null || entity.SleepScore == 0) && (entity.SleepAsleepS == null || entity.SleepAsleepS == 0) && string.IsNullOrWhiteSpace(entity.SummaryJson)))
                {
                    string prevDateStr = date.AddDays(-1).ToString("yyyy-MM-dd");
                    var prevEntity = await _db.Connection.Table<HealthDailySummaryEntity>()
                        .Where(e => e.LocalDate == prevDateStr)
                        .FirstOrDefaultAsync();

                    if (prevEntity != null && ((prevEntity.SleepScore > 0) || (prevEntity.SleepAsleepS > 0) || !string.IsNullOrWhiteSpace(prevEntity.SummaryJson)))
                    {
                        entity = prevEntity;
                    }
                    else if (entity == null)
                    {
                        // Fall back to the most recent day's real summary
                        entity = await _db.Connection.Table<HealthDailySummaryEntity>()
                            .OrderByDescending(e => e.LocalDate)
                            .FirstOrDefaultAsync();
                    }
                }

                if (entity != null)
                {
                    DailyHealthSummaryPayload? payload = null;
                    if (!string.IsNullOrWhiteSpace(entity.SummaryJson))
                    {
                        try
                        {
                            payload = HealthJsonSerializer.Deserialize<DailyHealthSummaryPayload>(entity.SummaryJson);
                        }
                        catch (Exception ex)
                        {
                            System.Diagnostics.Debug.WriteLine($"[WidgetsHostHealthService] JSON parse error: {ex.Message}");
                        }
                    }

                    var primarySleep = payload?.Sleep?.PrimarySession;
                    int? sleepAsleep = entity.SleepAsleepS > 0 
                        ? entity.SleepAsleepS 
                        : (primarySleep?.AsleepSeconds > 0 ? primarySleep.AsleepSeconds : primarySleep?.DurationSeconds);
                    int? sleepScore = entity.SleepScore > 0 
                        ? entity.SleepScore 
                        : (primarySleep?.SleepScore > 0 ? primarySleep.SleepScore : payload?.Sleep?.Guidance?.Verdict?.ReadinessScore);
                    int? stressScore = entity.StressAvg > 0 
                        ? entity.StressAvg 
                        : (payload?.Stress?.EffectiveScore > 0 ? payload.Stress.EffectiveScore : (payload?.Stress?.Score > 0 ? payload.Stress.Score : (int?)null));
                    double? rhr = entity.Rhr > 0 
                        ? entity.Rhr 
                        : (payload?.Cardiovascular?.RestingHeartRate > 0 ? payload.Cardiovascular.RestingHeartRate : (double?)null);
                    double? hrv = entity.HrvRmssd > 0 
                        ? entity.HrvRmssd 
                        : (payload?.Stress?.RestingHrvRmssd > 0 ? payload.Stress.RestingHrvRmssd : (double?)null);

                    // If stress score is not explicitly in summary, estimate dynamically from HRV RMSSD
                    if (stressScore == null && hrv.HasValue && hrv.Value > 0)
                    {
                        stressScore = hrv.Value switch
                        {
                            >= 70 => 18,
                            >= 55 => 26,
                            >= 40 => 38,
                            >= 25 => 58,
                            _ => 76
                        };
                    }

                    var rec = new HealthDailySummaryRecord
                    {
                        LocalDate = entity.LocalDate,
                        UserId = entity.UserId,
                        ComputedAt = entity.ComputedAt,
                        EngineVersion = entity.EngineVersion,
                        Steps = entity.Steps ?? payload?.Activity?.TotalSteps,
                        ActiveKcal = entity.ActiveKcal ?? payload?.Activity?.EffectiveActiveCalories,
                        SleepAsleepS = sleepAsleep,
                        SleepScore = sleepScore,
                        StressAvg = stressScore,
                        Rhr = rhr,
                        HrvSdnn = entity.HrvSdnn,
                        HrvRmssd = hrv,
                        Weight = entity.Weight,
                        Spo2 = entity.Spo2,
                        Summary = payload
                    };

                    // Check if we have a recent live pulse/heart rate recorded in LocalVitalMetric
                    try
                    {
                        var latestHr = await _db.Connection.Table<LocalVitalMetric>()
                            .Where(v => v.TypeString == "HeartRate" || v.TypeString == "RestingHeartRate")
                            .OrderByDescending(v => v.Date)
                            .FirstOrDefaultAsync();

                        if (latestHr != null && latestHr.Value > 35 && latestHr.Value < 220)
                        {
                            rec.Rhr = (int)Math.Round(latestHr.Value);
                        }
                    }
                    catch { }

                    CurrentSummary = rec;
                    return rec;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[WidgetsHostHealthService] SQLite read error: {ex.Message}");
            }

            // Default balanced fallback
            var def = new HealthDailySummaryRecord
            {
                LocalDate = dateStr,
                SleepScore = 85,
                SleepAsleepS = 27600, // 7h 40m
                StressAvg = 24,
                Rhr = 58,
                HrvRmssd = 64
            };
            CurrentSummary = def;
            return def;
        }

        public async Task<(SleepSession? PrimarySession, List<SleepSession> AllSessions)> GetSleepSessionsAsync(DateTime date)
        {
            var summary = await GetDailySummaryAsync(date);

            // 1. If payload contains granular primary session, extract full domain session
            if (summary?.Summary?.Sleep?.PrimarySession != null && summary.Summary.Sleep.PrimarySession.DurationSeconds > 0)
            {
                var primary = summary.Summary.Sleep.PrimarySession;
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
                    AsleepSeconds = primary.AsleepSeconds > 0 ? primary.AsleepSeconds : primary.DurationSeconds,
                    DeepSeconds = primary.DeepSeconds,
                    RemSeconds = primary.RemSeconds,
                    LightSeconds = primary.LightSeconds,
                    AwakeSeconds = primary.AwakeSeconds,
                    SleepScore = primary.SleepScore > 0 ? primary.SleepScore : (summary.SleepScore ?? 85),
                    SourceDevice = primary.EffectiveSourceDevice,
                    HasGranularHypnogram = primary.HasGranularHypnogram
                };

                if (primary.Stages != null && primary.Stages.Any())
                {
                    session.Stages = primary.Stages.Select(st =>
                    {
                        DateTimeOffset.TryParse(st.StartTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var sTimeDto);
                        DateTimeOffset.TryParse(st.EndTime, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var eTimeDto);
                        var sTime = sTimeDto != default ? sTimeDto.LocalDateTime : start;
                        var eTime = eTimeDto != default ? eTimeDto.LocalDateTime : sTime.AddSeconds(st.DurationSeconds);
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
                            EndTime = eTime,
                            SourceDevice = primary.EffectiveSourceDevice
                        };
                    }).ToList();
                }

                return (session, new List<SleepSession> { session });
            }

            // 2. Otherwise derive session from daily summary metrics
            int sleepSeconds = summary?.SleepAsleepS ?? 27600;
            if (sleepSeconds <= 0) sleepSeconds = 27600;

            var derivedPrimary = new SleepSession
            {
                StartTime = date.Date.AddHours(-1).AddMinutes(15), // 23:15 previous day
                EndTime = date.Date.AddHours(7).AddMinutes(15),     // 07:15 today
                DurationSeconds = (int)(sleepSeconds / 0.92),
                AsleepSeconds = sleepSeconds,
                DeepSeconds = sleepSeconds * 0.22,
                RemSeconds = sleepSeconds * 0.25,
                LightSeconds = sleepSeconds * 0.45,
                AwakeSeconds = sleepSeconds * 0.08,
                SleepScore = summary?.SleepScore ?? 85,
                SourceDevice = "Daily Health Hub"
            };

            return (derivedPrimary, new List<SleepSession> { derivedPrimary });
        }

        public Task<List<HealthDailySummaryRecord>> GetDailySummariesRangeAsync(DateTime startDate, DateTime endDate) =>
            Task.FromResult(new List<HealthDailySummaryRecord>());

        public Task<DailyHealthSummaryPayload?> GetPayloadForDateAsync(DateTime date) =>
            Task.FromResult<DailyHealthSummaryPayload?>(null);

        public Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsAsync(DateTime date, bool forceRefresh = false) =>
            Task.FromResult(new List<HealthSleepSessionRecord>());

        public Task<List<HealthDailyVitalsRecord>> GetLeanDailyVitalsAsync(DateTime date, bool forceRefresh = false) =>
            Task.FromResult(new List<HealthDailyVitalsRecord>());

        public Task<List<HealthIntradayHeartRateRecord>> GetLeanIntradayHeartRateAsync(DateTime date, bool forceRefresh = false) =>
            Task.FromResult(new List<HealthIntradayHeartRateRecord>());

        public Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsRangeAsync(DateTime startDate, DateTime endDate) =>
            Task.FromResult(new List<HealthSleepSessionRecord>());

        public Task<List<HealthDailyVitalsRecord>> GetLeanDailyVitalsRangeAsync(DateTime startDate, DateTime endDate) =>
            Task.FromResult(new List<HealthDailyVitalsRecord>());

        public Task<List<HealthSourceRecord>> GetHealthSourcesAsync(bool forceRefresh = false) =>
            Task.FromResult(new List<HealthSourceRecord>());

        public Task<bool> SaveDevicePriorityOrderAsync(IReadOnlyList<string> orderedSourceIds) => Task.FromResult(true);

        public Task<bool> ResetDevicePriorityOrderAsync() => Task.FromResult(true);

        public int GetEffectivePriorityRank(string? deviceName) => 0;

        public Task<List<VitalMetric>> GetVitalsAsync(DateTime start, DateTime end) => Task.FromResult(new List<VitalMetric>());

        public Task SyncNativeHealthDataAsync() => Task.CompletedTask;

        public async Task<VitalMetric?> GetLatestMetricAsync(VitalType type)
        {
            await _db.InitializeAsync();
            try
            {
                string typeStr = type.ToString();
                var local = await _db.Connection.Table<LocalVitalMetric>()
                    .Where(v => v.TypeString == typeStr)
                    .OrderByDescending(v => v.Date)
                    .FirstOrDefaultAsync();

                if (local != null)
                {
                    return new VitalMetric
                    {
                        Id = Guid.TryParse(local.Id, out var g) ? g : Guid.NewGuid(),
                        UserId = Guid.TryParse(local.UserId, out var u) ? u : Guid.Empty,
                        Type = type,
                        Value = local.Value,
                        Unit = local.Unit,
                        Date = local.Date,
                        SourceDevice = local.SourceDevice
                    };
                }
            }
            catch { }
            return null;
        }

        public Task<List<VitalMetric>> FetchMetricsAsync(DateTime date) => Task.FromResult(new List<VitalMetric>());

        public Task<List<VitalMetric>> FetchMetricsForDateAsync(DateTime date) => Task.FromResult(new List<VitalMetric>());

        public Task<List<VitalMetric>> GetHistoryAsync(VitalType type, int days = 7) => Task.FromResult(new List<VitalMetric>());

        public Task InitializeAsync(bool forceRecreateRealtime = false) => Task.CompletedTask;

        public Task PullDeltasAsync() => Task.CompletedTask;

        public Task<List<HealthTelemetry>> GetHealthTelemetryAsync(DateTime start, DateTime end) => Task.FromResult(new List<HealthTelemetry>());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 3. FINANCES SERVICE (Lean SQLite reader for Money widget)
    // ══════════════════════════════════════════════════════════════════════════
    public class WidgetsHostFinancesService : IFinancesService
    {
        private readonly IDatabaseService _db;
        public string CurrentViewType { get; set; } = "World";
        public event Action? OnViewTypeChanged;
        public event Action? OnQuotesUpdated;
        public event Action? OnSmartLedgerUpdated;

        public WidgetsHostFinancesService(IDatabaseService db)
        {
            _db = db;
        }

        public async Task<LocalSmartLedger?> GetSmartLedgerAsync(bool forceRefresh = false)
        {
            await _db.InitializeAsync();
            try
            {
                return await _db.Connection.Table<LocalSmartLedger>()
                    .OrderByDescending(l => l.UpdatedAt)
                    .FirstOrDefaultAsync();
            }
            catch
            {
                return null;
            }
        }

        public async Task<List<LocalAccount>> GetAccountsAsync()
        {
            await _db.InitializeAsync();
            try
            {
                return await _db.Connection.Table<LocalAccount>().ToListAsync();
            }
            catch
            {
                return new List<LocalAccount>();
            }
        }

        public async Task<decimal> GetNetWorthAsync()
        {
            var accounts = await GetAccountsAsync();
            return accounts.Sum(a => a.CurrentBalance);
        }

        public Task<List<StockQuote>> GetStockQuotesAsync(List<string> symbols, bool forceRefresh = false) =>
            Task.FromResult(new List<StockQuote>());

        public Task<MoneyData> GetMoneyDataAsync() => Task.FromResult(new MoneyData());

        public Task SaveSmartLedgerAsync(string ledgerText) => Task.CompletedTask;

        public Task<List<LocalLedgerTransaction>> GetLedgerTransactionsAsync() =>
            Task.FromResult(new List<LocalLedgerTransaction>());

        public Task SaveLedgerTransactionAsync(LocalLedgerTransaction transaction) => Task.CompletedTask;

        public Task<List<LocalRecurringTransaction>> GetRecurringTransactionsAsync() =>
            Task.FromResult(new List<LocalRecurringTransaction>());

        public Task SaveRecurringTransactionAsync(LocalRecurringTransaction transaction) => Task.CompletedTask;

        public Task ProcessRecurringTransactionsAsync() => Task.CompletedTask;

        public Task AddAccountAsync(LocalAccount account) => Task.CompletedTask;

        public Task<List<LocalTransaction>> GetTransactionsAsync(string accountId) =>
            Task.FromResult(new List<LocalTransaction>());

        public Task AddTransactionAsync(LocalTransaction transaction) => Task.CompletedTask;

        public Task<List<StockQuote>> GetHoldingsWithQuotesAsync() => Task.FromResult(new List<StockQuote>());

        public Task<List<string>> GetWatchlistSymbolsAsync(bool forceRefresh = false) => Task.FromResult(new List<string>());
    }

    // ══════════════════════════════════════════════════════════════════════════
    // 4. TAGDOS SERVICE (Lean SQLite reader for TagDos widget)
    // ══════════════════════════════════════════════════════════════════════════
    public class WidgetsHostTagdosService : ITagdosService
    {
        private readonly IDatabaseService _db;
        public event EventHandler? DataChanged;

        public WidgetsHostTagdosService(IDatabaseService db)
        {
            _db = db;
        }

        public async Task<List<TagDoStream>> GetStreamsAsync()
        {
            await _db.InitializeAsync();
            try
            {
                var entities = await _db.Connection.Table<LocalTagdoStream>()
                    .OrderBy(s => s.OrderIndex)
                    .ToListAsync();

                if (entities.Count > 0)
                {
                    return entities.Select(s =>
                    {
                        DateTime? reminder = s.StreamReminderTicks.HasValue
                            ? new DateTime(s.StreamReminderTicks.Value, DateTimeKind.Utc)
                            : null;
                        var parsed = TagdosParser.ParseStream(s.RawText, s.OrderIndex, s.Title, reminder, s.ActiveMemos, s.AttachmentsJson, s.CustomTitle);
                        parsed.Id = s.Id;
                        return parsed;
                    }).ToList();
                }
            }
            catch { }

            // Default seed streams
            return new List<TagDoStream>
            {
                TagdosParser.ParseStream("WRK/PRJ & MET/ZOOM & BUG/FIX", 0, "Focus Streams", null, "", "[]", null)
            };
        }

        public async Task<TagDoStream?> GetStreamByIndexAsync(int orderIndex)
        {
            var streams = await GetStreamsAsync();
            return streams.FirstOrDefault(s => s.OrderIndex == orderIndex);
        }

        public Task SaveStreamAsync(TagDoStream stream) => Task.CompletedTask;
        public Task UpdateStreamRawTextAsync(string streamId, string newRawText) => Task.CompletedTask;
        public Task UpdateStreamTitleAsync(string streamId, string newTitle) => Task.CompletedTask;
        public Task SetStreamReminderAsync(string streamId, DateTime? reminder) => Task.CompletedTask;
        public Task UpdateStreamMemosAsync(string streamId, string memos, string attachmentsJson) => Task.CompletedTask;

        public async Task<List<TagDoQuickNote>> GetQuickNotesAsync()
        {
            await _db.InitializeAsync();
            try
            {
                var entities = await _db.Connection.Table<LocalTagdoQuickNote>()
                    .OrderByDescending(n => n.IsPinned)
                    .ThenByDescending(n => n.UpdatedAtTicks)
                    .ToListAsync();

                return entities.Select(e => new TagDoQuickNote
                {
                    Id = e.Id,
                    Title = e.Title,
                    Content = e.Content,
                    IsPinned = e.IsPinned,
                    CreatedAt = new DateTime(e.CreatedAtTicks, DateTimeKind.Utc),
                    UpdatedAt = new DateTime(e.UpdatedAtTicks, DateTimeKind.Utc)
                }).ToList();
            }
            catch
            {
                return new List<TagDoQuickNote>();
            }
        }

        public Task<TagDoQuickNote> CreateQuickNoteAsync(string title, string content, bool isPinned = false) =>
            Task.FromResult(new TagDoQuickNote { Title = title, Content = content, IsPinned = isPinned });

        public Task UpdateQuickNoteAsync(TagDoQuickNote note) => Task.CompletedTask;
        public Task TogglePinQuickNoteAsync(string noteId) => Task.CompletedTask;
        public Task DeleteQuickNoteAsync(string noteId) => Task.CompletedTask;
        public Task SyncWithRemoteAsync() => Task.CompletedTask;
    }
}
