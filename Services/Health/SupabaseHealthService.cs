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
                    
                    var metrics = new List<VitalMetric>();
                    if (metricsToday != null) metrics.AddRange(metricsToday);
                    if (metricsYesterday != null) metrics.AddRange(metricsYesterday);
                    
                    if (!metrics.Any())
                    {
                        log("No health metrics found locally (Today or Yesterday).");
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
                        // 1. Fetch range (Yesterday/Today) to catch Timezone-shifted records.
                        // 2. Exact Match in Memory (C#) to avoid SQL query nuances.
                        // 3. Explicit Update vs Insert.

                        var searchStart = DateTime.Today.AddDays(-1);
                        var searchEnd = DateTime.Today.AddDays(1);
                        
                        var existingResult = await _supabase.From<VitalMetric>()
                            .Where(x => x.Date >= searchStart && x.Date <= searchEnd && x.UserId == uid)
                            .Get();
                        
                        var existingList = existingResult.Models;
                        log($"[Sync] Nuclear Strategy: Found {existingList.Count} cloud records to check against.");

                        var idsToDelete = new List<Guid>();
                        var recordsToInsert = new List<VitalMetric>();

                        foreach (var m in metrics)
                        {
                            m.UserId = uid;
                            
                            // Find ANY existing record for this Type on this Day
                            // We will DELETE it and replace it with the new value.
                            var match = existingList.FirstOrDefault(x => 
                                x.TypeString == m.TypeString && 
                                x.Date.Date == m.Date.Date);

                            if (match != null)
                            {
                                idsToDelete.Add(match.Id);
                                log($"[Sync] MARKED FOR DELETE: {m.TypeString} (Old ID: {match.Id})");
                            }
                            
                            // Always insert the new metric as a fresh record
                            // Reset ID to ensure it's treated as new
                            m.Id = Guid.NewGuid();
                            m.CreatedAt = DateTime.UtcNow;
                            m.UpdatedAt = DateTime.UtcNow;
                            recordsToInsert.Add(m);
                        }
                        
                        // 1. Execute Deletes (Clean the slate)
                        if (idsToDelete.Any())
                        {
                            // Batch delete not natively supported easily by ID list in explicit Filter syntax sometimes
                            // But we can loop for reliability or use 'in' filter if supported.
                            // Let's use loop for absolute safety to avoid syntax errors.
                            foreach(var delId in idsToDelete)
                            {
                                await _supabase.From<VitalMetric>().Where(x => x.Id == delId).Delete();
                            }
                            log($"[Sync] Deleted {idsToDelete.Count} stale records.");
                        }

                        // 2. Execute Inserts (Fresh Write)
                        if (recordsToInsert.Any())
                        {
                            var insertResponse = await _supabase.From<VitalMetric>().Insert(recordsToInsert);
                            log($"[Sync] Inserted {insertResponse.Models.Count} fresh records.");
                        }
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
