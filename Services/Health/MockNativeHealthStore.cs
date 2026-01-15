using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models.Health;

namespace Daily.Services.Health
{
    public class MockNativeHealthStore : INativeHealthStore
    {
        public bool IsSupported => true; // Set to true to verify UI flow

        public Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            var metrics = new List<VitalMetric>
            {
                new() { TypeString = "Steps", Value = 7243, Unit = "count", Date = date },
                new() { TypeString = "HeartRate", Value = 68, Unit = "bpm", Date = date },
                new() { TypeString = "Sleep", Value = 7.5, Unit = "hours", Date = date },
                new() { TypeString = "Calories", Value = 2450, Unit = "kcal", Date = date }
            };
            return Task.FromResult(metrics);
        }

        public Task<bool> RequestPermissionsAsync()
        {
            return Task.FromResult(true);
        }
    }
}
