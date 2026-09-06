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

        public Task InitializeAsync(bool forceRecreateRealtime = false)
        {
            return Task.CompletedTask;
        }

        public Task PullDeltasAsync()
        {
            return Task.CompletedTask;
        }

        public Task<List<HealthTelemetry>> GetHealthTelemetryAsync(DateTime start, DateTime end)
        {
            return Task.FromResult(new List<HealthTelemetry>());
        }

        private string _currentViewType = "Overview";
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
        public event Action? OnViewTypeChanged;

        private DateTime _selectedDate = DateTime.Today;
        public DateTime SelectedDate
        {
            get => _selectedDate;
            set
            {
                if (_selectedDate.Date != value.Date)
                {
                    _selectedDate = value.Date;
                    OnSelectedDateChanged?.Invoke();
                }
            }
        }
        public event Action? OnSelectedDateChanged;

        public Task<List<VitalMetric>> FetchMetricsForDateAsync(DateTime date)
        {
            return Task.FromResult(new List<VitalMetric>());
        }

        public Task<(SleepSession? PrimarySession, List<SleepSession> AllSessions)> GetSleepSessionsAsync(DateTime date)
        {
            return Task.FromResult<(SleepSession?, List<SleepSession>)>((null, new List<SleepSession>()));
        }
    }
}
