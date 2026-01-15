using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;

namespace Daily.Services.Health
{
    /// <summary>
    /// Abstraction for platform-specific health stores (Apple HealthKit, Android Health Connect).
    /// </summary>
    public interface INativeHealthStore
    {
        /// <summary>
        /// Requests necessary permissions from the user to read health data.
        /// </summary>
        Task<bool> RequestPermissionsAsync();

        /// <summary>
        /// Fetches vital metrics for a specific date.
        /// </summary>
        Task<List<VitalMetric>> FetchMetricsAsync(DateTime date);

        /// <summary>
        /// Checks if the current platform supports Health integration.
        /// </summary>
        bool IsSupported { get; }
    }
}
