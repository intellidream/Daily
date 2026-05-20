using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models.Health;
using Microsoft.Extensions.Logging;
using Supabase;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services;

namespace Daily.Services.Health
{
    public class SupabaseHealthService : IHealthService
    {
        private readonly Supabase.Client _supabase;
        private readonly INativeHealthStore _nativeHealthStore;
        private readonly ILogger<SupabaseHealthService> _logger;
        private readonly IServiceProvider _serviceProvider; // Lazy Resolution
        private readonly IRefreshService _refreshService;
        private Supabase.Realtime.RealtimeChannel? _vitalsChannel;

        // Simple memory cache to avoid excessive DB calls during session
        private  List<VitalMetric> _cache = new();
        private DateTime _lastCacheUpdate = DateTime.MinValue;

        private bool IsAuthenticated => _supabase.Auth.CurrentSession != null && _supabase.Auth.CurrentUser != null;

        public SupabaseHealthService(Supabase.Client supabase, INativeHealthStore nativeHealthStore, ILogger<SupabaseHealthService> logger, IServiceProvider serviceProvider, IRefreshService refreshService)
        {
            try 
            {
                _supabase = supabase;
                _nativeHealthStore = nativeHealthStore;
                _logger = logger;
                _serviceProvider = serviceProvider;
                _refreshService = refreshService;

                // Setup Auth Listener ONCE in Constructor
                _supabase.Auth.AddStateChangedListener((sender, state) => 
                {
                    Console.WriteLine($"[SupabaseHealthService] Auth State Changed: {state}");
                    if (state == Supabase.Gotrue.Constants.AuthState.SignedIn || state == Supabase.Gotrue.Constants.AuthState.SignedOut)
                    {
                         Task.Run(async () => 
                         {
                             try 
                             {
                                 await InitializeAsync();
                             }
                             catch(Exception ex)
                             {
                                 Console.WriteLine($"[SupabaseHealthService] Post-Auth Init Failed: {ex}");
                             }
                         });
                    }
                });
            }
            catch(Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Constructor FAULT: {ex}");
            }
        }

        public async Task InitializeAsync()
        {
            if (IsAuthenticated)
            {
                await SetupRealtimeAsync();
            }
            else
            {
                // Clean up channel if logged out
                if (_vitalsChannel != null)
                {
                    try
                    {
                        _vitalsChannel.Unsubscribe();
                    }
                    catch { }
                    _vitalsChannel = null;
                }
            }
        }

        private async Task SetupRealtimeAsync()
        {
            if (!IsAuthenticated) return;

            try
            {
                if (_vitalsChannel == null)
                {
                    _vitalsChannel = _supabase.Realtime.Channel("realtime", "public", "vitals");
                    _vitalsChannel.AddPostgresChangeHandler(Supabase.Realtime.PostgresChanges.PostgresChangesOptions.ListenType.All, OnVitalReceived);
                    await _vitalsChannel.Subscribe();
                    Console.WriteLine("[SupabaseHealthService] Realtime subscribed to vitals");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime setup failed: {ex.Message}");
            }
        }

        private void OnVitalReceived(object sender, Supabase.Realtime.PostgresChanges.PostgresChangesResponse e)
        {
            try
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime Vital Postgres Change received! Event: {e.Event}, Topic: {e.Topic}");
                var remoteVital = e.Model<VitalMetric>();
                if (remoteVital == null)
                {
                    Console.WriteLine("[SupabaseHealthService] Realtime: remoteVital is NULL! Cannot parse database change.");
                    return;
                }

                var user = _supabase.Auth.CurrentUser ?? _supabase.Auth.CurrentSession?.User;
                string currentUserIdStr = user?.Id ?? "NULL";
                Console.WriteLine($"[SupabaseHealthService] Realtime parsed remoteVital: Id={remoteVital.Id}, UserId={remoteVital.UserId}, Type={remoteVital.TypeString}, Value={remoteVital.Value}, CurrentUserId={currentUserIdStr}");

                bool isMatch = false;
                if (user != null && Guid.TryParse(user.Id, out var uid))
                {
                    isMatch = remoteVital.UserId == uid;
                }

                if (isMatch)
                {
                    Console.WriteLine($"[SupabaseHealthService] Realtime: Match found. Invalidating cache and triggering refresh.");
                    _cache.Clear();
                    _lastCacheUpdate = DateTime.MinValue;
                    
                    // Trigger UI refresh
                    _ = _refreshService.TriggerRefreshAsync();
                }
                else
                {
                    Console.WriteLine($"[SupabaseHealthService] Realtime: User ID mismatch. remoteVital.UserId={remoteVital.UserId}, uid={user?.Id}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SupabaseHealthService] Realtime Vital Error in OnVitalReceived: {ex}");
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

                    // 2a. Fetch EXISTING records for the date range (Today/Yesterday) to Merge
                    // This prevents overwriting high values (e.g. 5000 steps from Android) with low values (e.g. 200 steps from iOS)
                    try 
                    {
                        var minDate = metrics.Min(m => m.Date);
                        var maxDate = metrics.Max(m => m.Date);


                        var minDateStr = minDate.ToString("O");
                        var maxDateStr = maxDate.ToString("O");

                        var existingResult = await _supabase.From<VitalMetric>()
                                                  .Filter("user_id", Supabase.Postgrest.Constants.Operator.Equals, uid.ToString())
                                                  .Filter("date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, minDateStr)
                                                  .Filter("date", Supabase.Postgrest.Constants.Operator.LessThanOrEqual, maxDateStr)
                                                  .Get();
                        
                        var existingMetrics = existingResult.Models;

                        // MERGE LOGIC: Smart Strategy
                        // - Cumulative (Steps, Calories): Max Wins (prevents partial sync overwrites)
                        // - Spot (Weight, HR): Last Write Wins (implicit via Upsert, unless we skip)
                        
                        foreach (var local in metrics)
                        {
                            local.UserId = uid;
                            local.UpdatedAt = DateTime.UtcNow;
                            local.SyncedAt = DateTime.Now; // Local device time

                            var remote = existingMetrics.FirstOrDefault(e => e.Date == local.Date && e.TypeString == local.TypeString);
                            if (remote != null)
                            {
                                if (IsCumulative(local.TypeString))
                                {
                                    // MAX WINS for Cumulative
                                    if (remote.Value > local.Value)
                                    {
                                        log($"[Sync] Keeping Remote (Cumulative) {local.TypeString}: {remote.Value} (Local: {local.Value})");
                                        local.Value = remote.Value;
                                        local.SourceDevice = remote.SourceDevice;
                                        local.Unit = remote.Unit;
                                    }
                                }
                                else
                                {
                                    // SPOT METRICS (Weight, HR, etc.)
                                    // Default: Last Write Wins (Local overwrites Remote). 
                                    // However, check if Remote is significantly "newer" to avoid race conditions? 
                                    // For simplicity and user expectation: The device performing the sync is authoritative for Spot metrics 
                                    // UNLESS the remote value is identical (optimization).
                                    
                                    // Warning: If Android has Weight 80kg and iOS has Weight 85kg (old), and iOS syncs, it overwrites Android.
                                    // Ideally we compare 'CreatedAt' or 'Source Timestamp', but we lack granular source timestamps in this simple model.
                                    // We will stick to "Local Wins" for Spot, as user requested "Max Wins" check.
                                }
                            }
                        }

                        // Upsert with OnConflict strategy (vitals_user_date_type_key)
                        var upsertOptions = new Supabase.Postgrest.QueryOptions
                        {
                            Upsert = true,
                            OnConflict = "user_id, date, type" 
                        };

                        var response = await _supabase.From<VitalMetric>().Upsert(metrics, upsertOptions);
                        log($"[Sync] Upserted {response.Models.Count} merged records successfully.");
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

        public async Task<List<VitalMetric>> GetHistoryAsync(VitalType type, int days = 7)
        {
            try
            {
                var typeString = type.ToString();
                var start = DateTime.UtcNow.Date.AddDays(-days);
                var end = DateTime.UtcNow.Date.AddDays(1);

                var startStr = start.ToString("yyyy-MM-dd");
                var endStr = end.ToString("yyyy-MM-dd");

                Console.WriteLine($"[Health History] Querying {typeString} from {startStr} to {endStr}");

                var result = await _supabase.From<VitalMetric>()
                    .Filter("type", Supabase.Postgrest.Constants.Operator.Equals, typeString)
                    .Filter("date", Supabase.Postgrest.Constants.Operator.GreaterThanOrEqual, startStr)
                    .Filter("date", Supabase.Postgrest.Constants.Operator.LessThan, endStr)
                    .Order("date", Supabase.Postgrest.Constants.Ordering.Ascending)
                    .Get();

                Console.WriteLine($"[Health History] Got {result.Models.Count} records for {typeString}");
                return result.Models;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Failed to fetch history for {type}");
                Console.WriteLine($"[Health History] ERROR for {type}: {ex.Message}");
                return new List<VitalMetric>();
            }
        }

        private bool IsCumulative(string typeString)
        {
            if (Enum.TryParse<VitalType>(typeString, out var type))
            {
                return type switch
                {
                    VitalType.Steps => true,
                    VitalType.ActiveEnergy => true,
                    VitalType.BasalEnergyBurned => true, // Resting Cal
                    VitalType.Distance => true,
                    VitalType.FloorsClimbed => true,
                    VitalType.Hydration => true, 
                    VitalType.Carbs => true,
                    VitalType.Fat => true,
                    VitalType.Protein => true,
                    VitalType.Caffeine => true,
                    VitalType.SleepDuration => true, // Usually we want the longest recorded sleep session if multiple devices track? Or Max.
                    _ => false // Weight, HR, BP, BodyFat, Speed, etc. are SPOT measurements.
                };
            }
            return false;
        }
    }
}

