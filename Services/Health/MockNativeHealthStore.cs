using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;

namespace Daily.Services.Health
{
    public class MockNativeHealthStore : INativeHealthStore
    {
        public bool IsSupported => false; // Set to false to verify Fallback to Supabase Read on Desktop

        public Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            var metrics = new List<VitalMetric>
            {
                new() { TypeString = VitalType.Steps.ToString(), Value = 7243, Unit = "count", Date = date, SourceDevice = "Mock Device" },
                new() { TypeString = VitalType.HeartRate.ToString(), Value = 68, Unit = "bpm", Date = date, SourceDevice = "Mock Device" },
                new() { TypeString = VitalType.SleepDuration.ToString(), Value = 450, Unit = "min", Date = date, SourceDevice = "Mock Device" }, // 7.5 hours
                new() { TypeString = VitalType.ActiveEnergy.ToString(), Value = 2450, Unit = "kcal", Date = date, SourceDevice = "Mock Device" }
            };
            return Task.FromResult(metrics);
        }

        public Task<bool> RequestPermissionsAsync()
        {
            return Task.FromResult(true);
        }
    }
}
