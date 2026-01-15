using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models.Health;
using Microsoft.Extensions.Logging;
using Supabase;

namespace Daily.Services.Health
{
    public class SupabaseHealthService : IHealthService
    {
        private readonly Supabase.Client _supabase;
        private readonly INativeHealthStore _nativeHealthStore;
        private readonly ILogger<SupabaseHealthService> _logger;

        // Simple memory cache to avoid excessive DB calls during session
        private  List<VitalMetric> _cache = new();
        private DateTime _lastCacheUpdate = DateTime.MinValue;

        public SupabaseHealthService(Supabase.Client supabase, INativeHealthStore nativeHealthStore, ILogger<SupabaseHealthService> logger)
        {
            Console.WriteLine("[SupabaseHealthService] Constructor Called.");
            try 
            {
                _supabase = supabase;
                _nativeHealthStore = nativeHealthStore;
                _logger = logger;
                Console.WriteLine("[SupabaseHealthService] Dependencies Assigned.");
            }
            catch(Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Constructor FAULT: {ex}");
            }
        }

        public async Task<List<VitalMetric>> GetVitalsAsync(DateTime start, DateTime end)
        {
            try
            {
                // Retrieve from Supabase
                // Note: In a real scenario, we'd add offline database sync here (SQLite).
                // For now, we fetch directly from cloud.
                
                // TODO: Optimize RPC or specific query
                var result = await _supabase.From<VitalMetric>()
                                          .Where(v => v.Date >= start && v.Date <= end)
                                          .Order("date", Supabase.Postgrest.Constants.Ordering.Descending)
                                          .Get();
                
                var metrics = result.Models;
                
                // Update Cache (Merge)
                _cache = metrics;
                _lastCacheUpdate = DateTime.UtcNow;

                return metrics;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to fetch vitals from Supabase");
                return new List<VitalMetric>();
            }
        }

        public async Task<VitalMetric?> GetLatestMetricAsync(VitalType type)
        {
            try
            {
                var typeString = type.ToString();
                
                // Attempt Cache first
                var cached = _cache.FirstOrDefault(x => x.TypeString == typeString);
                if (cached != null && (DateTime.UtcNow - _lastCacheUpdate).TotalMinutes < 5)
                {
                    return cached;
                }

                var result = await _supabase.From<VitalMetric>()
                                          .Where(v => v.TypeString == typeString)
                                          .Order("date", Supabase.Postgrest.Constants.Ordering.Descending)
                                          .Limit(1)
                                          .Get();

                return result.Model;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Failed to fetch latest {type}");
                return null;
            }
        }

        public async Task<List<VitalMetric>> FetchMetricsAsync(DateTime date)
        {
            if (_nativeHealthStore == null || !_nativeHealthStore.IsSupported) return new List<VitalMetric>();

            // Ensure permissions are granted before attempting to fetch
            // This was the missing link causing SecurityException on Android
            var hasPermission = await _nativeHealthStore.RequestPermissionsAsync();
            if (!hasPermission)
            {
                _logger.LogWarning("FetchMetricsAsync: Permissions not granted.");
                return new List<VitalMetric>();
            }

            return await _nativeHealthStore.FetchMetricsAsync(date);
        }

        public async Task SyncNativeHealthDataAsync()
        {
            if (!_nativeHealthStore.IsSupported)
            {
                _logger.LogInformation("Native Health Store not supported on this platform.");
                return;
            }

            try
            {
                // 1. Request Permissions
                var hasPermission = await _nativeHealthStore.RequestPermissionsAsync();
                if (!hasPermission)
                {
                    _logger.LogWarning("Health Permissions denied.");
                    return;
                }

                // 2. Fetch Today's metrics for Sync
                var metrics = await _nativeHealthStore.FetchMetricsAsync(DateTime.Today);
                
                if (metrics == null || !metrics.Any())
                {
                    _logger.LogInformation("No new health metrics found.");
                    return;
                }

                // 3. Upsert to Supabase
                var currentUser = _supabase.Auth.CurrentUser;
                if (currentUser == null) return;

                foreach (var m in metrics)
                {
                    m.UserId = currentUser.Id; // Ensure ownership
                }
                
                // Bulk Upsert if possible, or loop
                // Supabase-csharp allows List upsert
                await _supabase.From<VitalMetric>().Upsert(metrics);
                
                _logger.LogInformation($"Synced {metrics.Count} vital metrics to Cloud.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error executing Native Health Sync");
            }
        }
    }
}
