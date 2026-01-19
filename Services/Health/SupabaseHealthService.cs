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
            try 
            {
                _supabase = supabase;
                _nativeHealthStore = nativeHealthStore;
                _logger = logger;
                _serviceProvider = serviceProvider;
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
            // V49 LOGIC: UNIFIED READ
            // User Request: "read from Supabase" on Mobile too, to match Desktop behavior.
            // Native Sync is handled separately by SyncService.SyncNativeHealthDataAsync().
            
            /* 
            // 1. Try Native Store (Mobile) - DISABLED for V49 to enforce Cloud Truth
            if (_nativeHealthStore != null && _nativeHealthStore.IsSupported)
            {
                var hasPermission = await _nativeHealthStore.RequestPermissionsAsync();
                if (hasPermission)
                {
                     return await _nativeHealthStore.FetchMetricsAsync(date);
                }
                else
                {
                     _logger.LogWarning("FetchMetricsAsync: Permissions not granted.");
                     return new List<VitalMetric>();
                }
            }
            */
            
            // 2. Fallback: Read from Supabase (Desktop)
            // "On Mac and Windows just read them"
            try 
            {
                // Lazy Resolve SyncService for Diagnostics
                var sync = _serviceProvider.GetService<ISyncService>();
                
                // Date Logic: Robust Range Query (Widen to 30 days for Desktop "Latest Available")
                // User Request: "read the last one available"
                var start = date.Date.AddDays(-30); 
                var end = date.Date.AddDays(2);
                
                var result = await _supabase.From<VitalMetric>()
                                      .Where(v => v.Date >= start && v.Date < end)
                                      .Order("date", Supabase.Postgrest.Constants.Ordering.Descending)
                                      .Get();
                
                if (result.Models.Count > 0)
                {
                    // Group by Type and take the Latest one
                    var latestMetrics = result.Models
                        .GroupBy(m => m.TypeString)
                        .Select(g => g.OrderByDescending(x => x.Date).First())
                        .ToList();

                    sync?.Log($"[Read] Found {latestMetrics.Count} recent metrics (Window: -30 days).");
                    return latestMetrics;
                }
                
                return new List<VitalMetric>();
            }
            catch(Exception ex)
            {
                var msg = $"Failed to read metrics from Supabase: {ex.Message}";
                Console.WriteLine(msg);
                _logger.LogError(ex, msg);
                return new List<VitalMetric>();
            }
        }

        public async Task SyncNativeHealthDataAsync()
        {
                try 
                {
                    var sync = _serviceProvider.GetService<ISyncService>();
                    Action<string> log = (msg) => 
                    {
                        Console.WriteLine($"[SupabaseHealthService] {msg}");
                        sync?.Log($"[Health] {msg}");
                    };

                    log("SyncNativeHealthDataAsync STARTED");

                    if (!_nativeHealthStore.IsSupported)
                    {
                        log("Native Health Store not supported (Skipping Upload). Reading handled by Widget.");
                        return;
                    }

                    log("Requesting Permissions...");
                    var hasPermission = await _nativeHealthStore.RequestPermissionsAsync();
                    if (!hasPermission)
                    {
                        log("Permissions Denied.");
                        return;
                    }

                    // V48 LOGIC: Sync Today AND Yesterday (Backfill)
                    log($"Fetching metrics for Today ({DateTime.Today:d}) AND Yesterday...");
                    
                    var metricsToday = await _nativeHealthStore.FetchMetricsAsync(DateTime.Today);
                    var metricsYesterday = await _nativeHealthStore.FetchMetricsAsync(DateTime.Today.AddDays(-1));
                    
                    int countToday = metricsToday?.Count ?? 0;
                    int countYesterday = metricsYesterday?.Count ?? 0;
                    
                    log($"[Fetch] Today: {countToday} items, Yesterday: {countYesterday} items.");
                    
                    if (countToday > 0)
                    {
                        var types = string.Join(", ", metricsToday.Select(x => x.TypeString).Distinct());
                        log($"[Fetch] Today's Types: {types}");
                    }

                    var metrics = new List<VitalMetric>();
                    if (metricsToday != null) metrics.AddRange(metricsToday);
                    if (metricsYesterday != null) metrics.AddRange(metricsYesterday);
                    
                    if (!metrics.Any())
                    {
                        log("No health metrics found locally (Today or Yesterday). Aborting Upload.");
                        return;
                    }

                    var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                    
                    if (user == null) 
                    {
                         log("ABORT: User is NULL.");
                         return;
                    }

                    if (!Guid.TryParse(user.Id, out var uid))
                    {
                        log("ABORT: Invalid User ID.");
                        return;
                    }

                    // 2a. Fetch EXISTING records for Today to get their Primary Keys (Ids)
                    // This ensures that 'Upsert' acts as an UPDATE, not a failed INSERT due to conflicts.
                    try 
                    {
                        // ROBUST SYNC STRATEGY: 
                        // ROBUST SYNC STRATEGY (V56): UPSERT (Insert or Update on Conflict)
                        // This bypasses the need for accurate "Read" filters which are proving fragile across platforms/date formats.
                        // We rely on the Unique Constraint 'vitals_user_date_type_key' to handle the merge.

                        foreach (var m in metrics)
                        {
                            m.UserId = uid;
                            // Ensure timestamps are fresh
                            m.UpdatedAt = DateTime.UtcNow;
                            // Note: CreatedAt will be preserved by Postgres on Update, or set on Insert.
                        }

                        // Upsert with OnConflict strategy
                        var upsertOptions = new Supabase.Postgrest.QueryOptions
                        {
                            Upsert = true,
                            OnConflict = "user_id, date, type" // The columns that define uniqueness (vitals_user_date_type_key)
                        };

                        var response = await _supabase.From<VitalMetric>().Upsert(metrics, upsertOptions);
                        log($"[Sync] Upserted {response.Models.Count} records successfully.");
                    }
                    catch (Supabase.Postgrest.Exceptions.PostgrestException pex)
                    {
                         log($"Postgrest Error: {pex.Message}");
                         throw;
                    }
                    catch (Exception ex)
                    {
                        log($"Sync Preparation/Execution Failed: {ex.Message}");
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
