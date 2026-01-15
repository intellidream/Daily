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
    }
}
