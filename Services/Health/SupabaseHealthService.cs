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
        private readonly IServiceProvider _serviceProvider; // Lazy Resolution

        // Simple memory cache to avoid excessive DB calls during session
        private  List<VitalMetric> _cache = new();
        private DateTime _lastCacheUpdate = DateTime.MinValue;

        public SupabaseHealthService(Supabase.Client supabase, INativeHealthStore nativeHealthStore, ILogger<SupabaseHealthService> logger, IServiceProvider serviceProvider)
        {
            Console.WriteLine("[SupabaseHealthService] Constructor Called.");
            try 
            {
                _supabase = supabase;
                _nativeHealthStore = nativeHealthStore;
                _logger = logger;
                _serviceProvider = serviceProvider;
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
                // MOCK MODE FOR DEBUGGING
                try 
                {
                    // Lazy Resolve SyncService to avoid Circular Dependency
                    var sync = _serviceProvider.GetService<ISyncService>();
                    Action<string> log = (msg) => 
                    {
                        Console.WriteLine($"[SupabaseHealthService] {msg}");
                        sync?.Log($"[Health] {msg}");
                    };

                    log("SyncNativeHealthDataAsync STARTED");

                    // REAL NATIVE FETCH (RESTORED)
                    if (!_nativeHealthStore.IsSupported)
                    {
                        log("Native Health Store not supported.");
                        return;
                    }

                    log("Requesting Permissions...");
                    var hasPermission = await _nativeHealthStore.RequestPermissionsAsync();
                    if (!hasPermission)
                    {
                        log("Permissions Denied.");
                        return;
                    }

                    log($"Fetching metrics for {DateTime.Today:d}...");
                    var metrics = await _nativeHealthStore.FetchMetricsAsync(DateTime.Today);
                    
                    if (metrics == null || !metrics.Any())
                    {
                        log("No health metrics found locally.");
                        return;
                    }

                    // 3. Upsert to Supabase
                    var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                    
                    if (user == null) 
                    {
                         log("ABORT: User is NULL.");
                         return;
                    }

                    log($"Upserting {metrics.Count} metrics for User {user.Id}..."); 
                    
                    var sample = metrics.First();
                    log($"Sample: {sample.TypeString}, Val={sample.Value}, Src={sample.SourceDevice}");

                    foreach (var m in metrics)
                    {
                        if (Guid.TryParse(user.Id, out var uid))
                        {
                            m.UserId = uid; // Ensure ownership
                        }
                        else
                        {
                            log($"Warning: Could not parse User ID '{user.Id}' to Guid. Using Empty.");
                            m.UserId = Guid.Empty;
                        }
                    }
                    
                    // Bulk Upsert with OnConflict strategy
                    // RETRY: Using Column Names WITHOUT SPACES. Constraint name might be missing on user DB.
                    var options = new Supabase.Postgrest.QueryOptions { OnConflict = "user_id,date,type" };
                    
                    try 
                    {
                        var response = await _supabase.From<VitalMetric>().Upsert(metrics, options);
                        
                        int inserted = response.Models.Count;
                        log($"Upsert Result: {inserted} rows returned.");
                        
                        if (inserted == 0)
                        {
                             log("WARNING: Upsert returned 0 rows. RLS might be blocking or OnConflict ignored update.");
                        }
                        else
                        {
                            log($"SUCCESS: Synced {inserted} vital metrics to Cloud.");
                        }
                    }
                    catch (Supabase.Postgrest.Exceptions.PostgrestException pex)
                    {
                         log($"Postgrest Error: {pex.Message}");
                         throw;
                    }
                }
                catch (Exception ex)
                {
                    // Re-resolve if needed, but 'log' delegate captures 'sync'
                    // If sync failed to resolve, we just Console.WriteLine.
                    var msg = $"Fatal Health Sync Error: {ex.Message}";
                    Console.WriteLine(msg);
                    _logger.LogError(ex, msg);
                    
                     var sync = _serviceProvider.GetService<ISyncService>();
                     sync?.Log($"[Health] {msg}");
                }
        }
    }
}
