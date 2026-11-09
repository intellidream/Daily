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
                .Select(l => l.ToDomain())
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
                return localGoal.ToDomain();
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
                HabitType = habitType,
                Value = value,
                Unit = unit,
                LoggedAt = loggedAt.ToUniversalTime(),
                Metadata = metadata,
                IsDirty = true,
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
                item.IsDirty = true;
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

                if (entity != null)
                {
                    if (!string.IsNullOrWhiteSpace(entity.SummaryJson))
                    {
                        var rec = JsonSerializer.Deserialize<HealthDailySummaryRecord>(entity.SummaryJson, HealthJsonSerializer.DefaultOptions);
                        if (rec != null)
                        {
                            CurrentSummary = rec;
                            return rec;
                        }
                    }

                    var fallbackRec = new HealthDailySummaryRecord
                    {
                        LocalDate = entity.LocalDate,
                        Steps = entity.Steps,
                        ActiveKcal = entity.ActiveKcal,
                        SleepAsleepS = entity.SleepAsleepS,
                        SleepScore = entity.SleepScore,
                        StressAvg = entity.StressAvg,
                        Rhr = entity.Rhr,
                        HrvSdnn = entity.HrvSdnn,
                        HrvRmssd = entity.HrvRmssd,
                        Weight = entity.Weight,
                        Spo2 = entity.Spo2
                    };
                    CurrentSummary = fallbackRec;
                    return fallbackRec;
                }
            }
            catch { }

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
            int sleepSeconds = summary?.SleepAsleepS ?? 27600;
            if (sleepSeconds <= 0) sleepSeconds = 27600;

            var primary = new SleepSession
            {
                StartTime = date.Date.AddHours(-1).AddMinutes(15), // 23:15 previous day
                EndTime = date.Date.AddHours(7).AddMinutes(15),     // 07:15 today
                DeepSeconds = sleepSeconds * 0.22,
                RemSeconds = sleepSeconds * 0.25,
                LightSeconds = sleepSeconds * 0.45,
                AwakeSeconds = sleepSeconds * 0.08,
                SleepScore = summary?.SleepScore ?? 85,
                SourceDevice = "Daily Multi-Device Hub"
            };

            return (primary, new List<SleepSession> { primary });
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

        public Task<VitalMetric?> GetLatestMetricAsync(VitalType type) => Task.FromResult<VitalMetric?>(null);

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
                    return entities.Select(e => TagdosParser.Parse(e)).ToList();
                }
            }
            catch { }

            // Default seed streams
            return new List<TagDoStream>
            {
                TagdosParser.Parse(new LocalTagdoStream
                {
                    Id = Guid.NewGuid().ToString(),
                    DisplayTitle = "Focus Streams",
                    RawText = "WRK/PRJ & MET/ZOOM & BUG/FIX",
                    OrderIndex = 0
                })
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
                    .ThenByDescending(n => n.UpdatedAt)
                    .ToListAsync();

                return entities.Select(e => new TagDoQuickNote
                {
                    Id = e.Id,
                    Title = e.Title,
                    Content = e.Content,
                    IsPinned = e.IsPinned,
                    CreatedAt = e.CreatedAt,
                    UpdatedAt = e.UpdatedAt
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
