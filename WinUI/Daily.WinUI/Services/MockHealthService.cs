using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;

namespace Daily_WinUI.Services
{
    public class MockHealthService : Daily.Services.Health.IHealthService
    {
        public Task<List<VitalMetric>> GetVitalsAsync(DateTime start, DateTime end)
        {
            return Task.FromResult(new List<VitalMetric>());
        }

        public Task SyncNativeHealthDataAsync()
        {
            return Task.CompletedTask;
        }

        public Task<VitalMetric?> GetLatestMetricAsync(VitalType type)
        {
            return Task.FromResult<VitalMetric?>(null);
        }

        public Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            return Task.FromResult(new List<VitalMetric>());
        }

        public Task<List<VitalMetric>> GetHistoryAsync(VitalType type, int days = 7)
        {
            return Task.FromResult(new List<VitalMetric>());
        }
    }
}
