using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services.Health;

namespace Daily_WinUI.Services
{
    /// <summary>
    /// Contract for the WinUI Health Hub service providing access to canonical health daily summaries,
    /// per-device lean tables (sleep, vitals, intraday HR), offline SQLite caching, and live Supabase Realtime synchronization.
    /// Extends IHealthService to maintain seamless backwards compatibility with existing UI widgets.
    /// </summary>
    public interface IHealthHubService : IHealthService
    {
        Task<HealthDailySummaryRecord?> GetDailySummaryAsync(DateTime date, bool forceRefresh = false);

        Task<List<HealthDailySummaryRecord>> GetDailySummariesRangeAsync(DateTime startDate, DateTime endDate);

        Task<DailyHealthSummaryPayload?> GetPayloadForDateAsync(DateTime date);

        Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsAsync(DateTime date, bool forceRefresh = false);

        Task<List<HealthDailyVitalsRecord>> GetLeanDailyVitalsAsync(DateTime date, bool forceRefresh = false);

        Task<List<HealthIntradayHeartRateRecord>> GetLeanIntradayHeartRateAsync(DateTime date, bool forceRefresh = false);

        Task<List<HealthSleepSessionRecord>> GetLeanSleepSessionsRangeAsync(DateTime startDate, DateTime endDate);

        Task<List<HealthDailyVitalsRecord>> GetLeanDailyVitalsRangeAsync(DateTime startDate, DateTime endDate);

        HealthDailySummaryRecord? CurrentSummary { get; }

        event Action<HealthDailySummaryRecord?>? OnDailySummaryChanged;
    }
}
