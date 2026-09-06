using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;

namespace Daily.Services.Health
{
    public interface IHealthService
    {
        /// <summary>
        /// Retrieves vitals for a specific date range.
        /// Prioritizes checking local cache/Supabase first.
        /// </summary>
        Task<List<VitalMetric>> GetVitalsAsync(DateTime start, DateTime end);

        /// <summary>
        /// Triggers a synchronization with the native platform's health store (HealthKit/HealthConnect).
        /// Only functional on iOS/Android. No-op on Desktop.
        /// </summary>
        Task SyncNativeHealthDataAsync();

        /// <summary>
        /// Gets the latest value for a specific metric type (e.g., today's steps).
        /// </summary>
        Task<VitalMetric?> GetLatestMetricAsync(VitalType type);

        /// <summary>
        /// Direct fetch from native store (bypass Sync/Supabase) for UI display.
        /// </summary>
        Task<List<VitalMetric>> FetchMetricsAsync(DateTime date);

        /// <summary>
        /// Retrieves daily values for a specific metric type over a date range (for trend charts).
        /// </summary>
        Task<List<VitalMetric>> GetHistoryAsync(VitalType type, int days = 7);

        /// <summary>
        /// Initializes the service, e.g., registers realtime subscriptions.
        /// </summary>
        Task InitializeAsync(bool forceRecreateRealtime = false);

        /// <summary>
        /// Pulls delta records from Supabase since the latest local record to catch up.
        /// </summary>
        Task PullDeltasAsync();

        /// <summary>
        /// Retrieves granular health telemetry for a specific date range.
        /// </summary>
        Task<List<HealthTelemetry>> GetHealthTelemetryAsync(DateTime start, DateTime end);

        /// <summary>
        /// Current active tab / view category (Overview, Sleep, Sensors, Nutrition).
        /// </summary>
        string CurrentViewType { get; set; }

        /// <summary>
        /// Event fired when the active tab / view category changes.
        /// </summary>
        event Action? OnViewTypeChanged;

        /// <summary>
        /// Current selected date for Health views (defaults to DateTime.Today).
        /// </summary>
        DateTime SelectedDate { get; set; }

        /// <summary>
        /// Event fired when the selected date changes.
        /// </summary>
        event Action? OnSelectedDateChanged;

        /// <summary>
        /// Fetches metrics strictly for a specific date, with historical fallback flags for spot metrics.
        /// </summary>
        Task<List<VitalMetric>> FetchMetricsForDateAsync(DateTime date);

        /// <summary>
        /// Retrieves and clusters nocturnal sleep session and naps for a given date.
        /// </summary>
        Task<(SleepSession? PrimarySession, List<SleepSession> AllSessions)> GetSleepSessionsAsync(DateTime date);
    }
}
