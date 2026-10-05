using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services.Health;

namespace Daily_WinUI.Services
{
    /// <summary>
    /// Contract for the WinUI Health Hub service providing access to canonical health daily summaries,
    /// offline SQLite caching, and live Supabase Realtime synchronization.
    /// Extends IHealthService to maintain seamless backwards compatibility with existing UI widgets.
    /// </summary>
    public interface IHealthHubService : IHealthService
    {
        /// <summary>
        /// Retrieves the canonical daily summary for a specific date.
        /// Priority:
        /// 1. Memory cache
        /// 2. Local SQLite cache (<300ms)
        /// 3. Remote Supabase public.health_daily_summary
        /// </summary>
        Task<HealthDailySummaryRecord?> GetDailySummaryAsync(DateTime date, bool forceRefresh = false);

        /// <summary>
        /// Retrieves daily summaries for a given date range (used for trends and analytics).
        /// </summary>
        Task<List<HealthDailySummaryRecord>> GetDailySummariesRangeAsync(DateTime startDate, DateTime endDate);

        /// <summary>
        /// Retrieves the detailed payload (sleep, activity, stress, cardio, vitals) for a specific date.
        /// </summary>
        Task<DailyHealthSummaryPayload?> GetPayloadForDateAsync(DateTime date);

        /// <summary>
        /// The currently loaded daily summary corresponding to SelectedDate.
        /// </summary>
        HealthDailySummaryRecord? CurrentSummary { get; }

        /// <summary>
        /// Fired when the active daily summary changes (date switch or incoming Realtime event).
        /// </summary>
        event Action<HealthDailySummaryRecord?>? OnDailySummaryChanged;
    }
}
