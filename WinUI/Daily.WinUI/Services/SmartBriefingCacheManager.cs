using System;
using System.Text.Json;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Services;
using Supabase;
using System.Diagnostics;
using System.Collections.Generic;
using System.Text;
using System.Linq;

namespace Daily_WinUI.Services
{
    public enum DayTimeSlot
    {
        Morning,      // 5:00 - 11:59
        MidDay,       // 12:00 - 16:59
        Evening,      // 17:00 - 21:59
        Night         // 22:00 - 4:59
    }

    public sealed class SmartBriefingCacheManager
    {
        private readonly IDatabaseService _db;
        private readonly Supabase.Client _supabase;
        private readonly SmartBriefingService _briefingService;

        public SmartBriefingCacheManager(
            IDatabaseService db, 
            Supabase.Client supabase, 
            SmartBriefingService briefingService)
        {
            _db = db;
            _supabase = supabase;
            _briefingService = briefingService;
        }

        private DayTimeSlot GetDayTimeSlot(DateTime utcDateTime)
        {
            // Convert to local time to align with user's day
            int hour = utcDateTime.ToLocalTime().Hour;
            if (hour >= 5 && hour < 12) return DayTimeSlot.Morning;
            if (hour >= 12 && hour < 17) return DayTimeSlot.MidDay;
            if (hour >= 17 && hour < 22) return DayTimeSlot.Evening;
            return DayTimeSlot.Night;
        }

        // Retrieves from cache if fresh and metrics didn't change significantly, or regenerates
        public async Task<SmartBriefingData> GetOrGenerateBriefingAsync(string userName, bool forceRefresh = false)
        {
            var settings = SettingsService.Load();
            string userId = _supabase.Auth?.CurrentUser?.Id ?? "local_user";

            await _db.InitializeAsync();

            // 1. Load local cache from SQLite (fallback to AppSettings memory)
            CachedSmartBriefing? localCached = null;
            try
            {
                localCached = await _db.Connection.Table<CachedSmartBriefing>()
                    .Where(c => c.UserId == userId)
                    .FirstOrDefaultAsync();
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] SQLite Read Error: {ex.Message}");
            }

            SmartBriefingData? cachedData = null;
            DateTime? cacheTime = null;

            if (localCached != null)
            {
                try
                {
                    cachedData = JsonSerializer.Deserialize<SmartBriefingData>(localCached.SerializedData);
                    cacheTime = localCached.Timestamp;
                }
                catch { }
            }

            // Fallback to Settings cache if SQLite fails
            if (cachedData == null && !string.IsNullOrEmpty(settings.CachedBriefingJson) && settings.CachedBriefingTime.HasValue)
            {
                try
                {
                    cachedData = JsonSerializer.Deserialize<SmartBriefingData>(settings.CachedBriefingJson);
                    cacheTime = settings.CachedBriefingTime;
                }
                catch { }
            }

            DateTime now = DateTime.UtcNow;

            // 1.1 Load local metrics first (cheap query)
            Debug.WriteLine("[SmartBriefingCacheManager] Loading current local telemetry metrics...");
            var currentMetrics = await _briefingService.LoadBriefingMetricsAsync(userName, onlyLocal: true);

            // Check if we can use the cached version directly (Age < 15 minutes)
            if (!forceRefresh && cachedData != null && cacheTime.HasValue && (now - cacheTime.Value).TotalMinutes < 15)
            {
                if (GetDayTimeSlot(cacheTime.Value) != GetDayTimeSlot(now))
                {
                    Debug.WriteLine("[SmartBriefingCacheManager] Day time slot changed since cache generation. Resetting cache for new context.");
                    forceRefresh = true;
                }
                else
                {
                    bool hasChanged = ShouldRegenerate(cachedData, currentMetrics, onlyLocal: true);
                    if (!hasChanged)
                    {
                        Debug.WriteLine("[SmartBriefingCacheManager] Serving briefing from local cache (under 15 min age gate) with updated local metrics.");
                        // Merge cached narrative, advice, and network-bound telemetry into currentMetrics
                        currentMetrics.BriefingText = cachedData.BriefingText;
                        currentMetrics.IntroText = cachedData.IntroText;
                        currentMetrics.OutroText = cachedData.OutroText;
                        currentMetrics.WeatherAdvice = cachedData.WeatherAdvice;
                        currentMetrics.HealthAdvice = cachedData.HealthAdvice;
                        currentMetrics.FinanceAdvice = cachedData.FinanceAdvice;
                        currentMetrics.HabitsAdvice = cachedData.HabitsAdvice;

                        // Network-bound telemetry
                        currentMetrics.WeatherTemp = cachedData.WeatherTemp;
                        currentMetrics.WeatherCondition = cachedData.WeatherCondition;
                        currentMetrics.WeatherSummary = cachedData.WeatherSummary;
                        currentMetrics.WeatherForecast = cachedData.WeatherForecast;
                        currentMetrics.WeatherHourlyDetails = cachedData.WeatherHourlyDetails;
                        currentMetrics.WeatherFiveDayDetails = cachedData.WeatherFiveDayDetails;
                        currentMetrics.WatchlistStocks = cachedData.WatchlistStocks;
                        currentMetrics.NewsRecommendations = cachedData.NewsRecommendations;

                        currentMetrics.WasRegenerated = false; // Served from cache
                        return currentMetrics;
                    }
                    else
                    {
                        Debug.WriteLine("[SmartBriefingCacheManager] Local metrics changed significantly under the 15-minute gate. Forcing refresh to regenerate narrative.");
                        forceRefresh = true;
                    }
                }
            }

            // Load fresh metrics (full query with network calls)
            Debug.WriteLine("[SmartBriefingCacheManager] Loading current full telemetry metrics...");
            currentMetrics = await _briefingService.LoadBriefingMetricsAsync(userName, onlyLocal: false);

            // 2. Perform Telemetry Change Check (if cache exists but is older than 15 mins)
            if (!forceRefresh && cachedData != null)
            {
                if (cacheTime.HasValue && GetDayTimeSlot(cacheTime.Value) != GetDayTimeSlot(now))
                {
                    Debug.WriteLine("[SmartBriefingCacheManager] Day time slot changed since cache generation (past 15 mins). Resetting cache for new context.");
                    forceRefresh = true;
                }
                else
                {
                    bool hasChanged = ShouldRegenerate(cachedData, currentMetrics, onlyLocal: false);
                    if (!hasChanged)
                    {
                        Debug.WriteLine("[SmartBriefingCacheManager] Telemetry metrics unchanged. Serving cached briefing with updated metrics.");
                        // Update the numeric metrics of the cached briefing to the latest ones, but preserve the AI narrative
                        currentMetrics.BriefingText = cachedData.BriefingText;
                        currentMetrics.IntroText = cachedData.IntroText;
                        currentMetrics.OutroText = cachedData.OutroText;
                        currentMetrics.WeatherAdvice = cachedData.WeatherAdvice;
                        currentMetrics.HealthAdvice = cachedData.HealthAdvice;
                        currentMetrics.FinanceAdvice = cachedData.FinanceAdvice;
                        currentMetrics.HabitsAdvice = cachedData.HabitsAdvice;

                        currentMetrics.WasRegenerated = false; // Served from cache

                        // Save the updated model (updates timestamp to extend the cache lease)
                        await SaveBriefingToCacheAsync(userId, currentMetrics);
                        return currentMetrics;
                    }
                }
            }

            // 3. Generate new narrative via AI (either forced refresh, stale age, or changed metrics)
            Debug.WriteLine("[SmartBriefingCacheManager] Telemetry metrics changed or cache is stale. Regenerating AI narrative...");
            var regeneratedBriefing = await _briefingService.GenerateAiNarrativeAsync(currentMetrics, userName);
            regeneratedBriefing.WasRegenerated = true; // Mark as regenerated

            // Save to local SQLite, settings, and push to Supabase
            await SaveBriefingToCacheAsync(userId, regeneratedBriefing);
            
            return regeneratedBriefing;
        }

        // Predisposition: checks if prefetching is needed silently
        public async Task PrefetchIfNeededAsync(string userName)
        {
            try
            {
                var settings = SettingsService.Load();
                if (!settings.EnableSmartBriefing) return;

                string userId = _supabase.Auth?.CurrentUser?.Id ?? "local_user";
                await _db.InitializeAsync();

                var localCached = await _db.Connection.Table<CachedSmartBriefing>()
                    .Where(c => c.UserId == userId)
                    .FirstOrDefaultAsync();

                DateTime? cacheTime = localCached?.Timestamp ?? settings.CachedBriefingTime;

                // Only prefetch if cache is older than 15 mins
                if (cacheTime == null || (DateTime.UtcNow - cacheTime.Value).TotalMinutes >= 15)
                {
                    Debug.WriteLine("[SmartBriefingCacheManager] Prefetching briefing in background...");
                    await GetOrGenerateBriefingAsync(userName, forceRefresh: false);
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] Background prefetch failed: {ex.Message}");
            }
        }

        // Bidirectional sync: Pull remote cache from Supabase to SQLite & settings on boot / login
        public async Task PullRemoteCacheAsync()
        {
            try
            {
                string? userId = _supabase.Auth?.CurrentUser?.Id;
                if (string.IsNullOrEmpty(userId)) return;

                Debug.WriteLine("[SmartBriefingCacheManager] Fetching remote briefing cache from Supabase...");
                var response = await _supabase.From<Daily.Models.SmartBriefingRemote>()
                    .Where(b => b.UserId == userId)
                    .Get();

                var remote = response.Model;
                if (remote != null)
                {
                    await _db.InitializeAsync();
                    
                    // Check if remote timestamp is newer than local
                    var localCached = await _db.Connection.Table<CachedSmartBriefing>()
                        .Where(c => c.UserId == userId)
                        .FirstOrDefaultAsync();

                    if (localCached == null || remote.Timestamp > localCached.Timestamp)
                      {
                        Debug.WriteLine("[SmartBriefingCacheManager] Remote cache is newer. Updating local SQLite cache...");
                        
                        var newCache = new CachedSmartBriefing
                        {
                            UserId = userId,
                            SerializedData = remote.SerializedData,
                            Timestamp = remote.Timestamp
                        };

                        await _db.Connection.InsertOrReplaceAsync(newCache);

                        var settings = SettingsService.Load();
                        settings.CachedBriefingJson = remote.SerializedData;
                        settings.CachedBriefingTime = remote.Timestamp;
                        SettingsService.Save(settings);
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] PullRemoteCacheAsync Error: {ex.Message}");
            }
        }

        // Save briefing locally and remotely
        private async Task SaveBriefingToCacheAsync(string userId, SmartBriefingData data)
        {
            try
            {
                string serialized = JsonSerializer.Serialize(data);
                DateTime now = DateTime.UtcNow;

                // 1. SQLite
                var cacheObj = new CachedSmartBriefing
                {
                    UserId = userId,
                    SerializedData = serialized,
                    Timestamp = now
                };
                await _db.Connection.InsertOrReplaceAsync(cacheObj);

                // 2. Settings (fast reload)
                var settings = SettingsService.Load();
                settings.CachedBriefingJson = serialized;
                settings.CachedBriefingTime = now;
                SettingsService.Save(settings);

                // 3. Supabase Upsert (async in background to avoid blocking UI)
                if (!string.IsNullOrEmpty(userId) && userId != "local_user")
                {
                    _ = Task.Run(async () =>
                    {
                        try
                        {
                            var remoteObj = new Daily.Models.SmartBriefingRemote
                            {
                                UserId = userId,
                                SerializedData = serialized,
                                Timestamp = now
                            };
                            await _supabase.From<Daily.Models.SmartBriefingRemote>().Upsert(remoteObj);
                            Debug.WriteLine("[SmartBriefingCacheManager] Briefing cache synced to Supabase successfully.");
                        }
                        catch (Exception ex)
                        {
                            Debug.WriteLine($"[SmartBriefingCacheManager] Supabase cache push error: {ex.Message}");
                        }
                    });
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] SaveBriefingToCacheAsync Error: {ex.Message}");
            }
        }

        // Checks if metrics changed significantly enough to warrant AI regeneration
        private bool ShouldRegenerate(SmartBriefingData cached, SmartBriefingData current, bool onlyLocal = false)
        {
            // 1. Weather temperature delta > 1.5 degrees (only check if we retrieved weather)
            if (!onlyLocal && Math.Abs(cached.WeatherTemp - current.WeatherTemp) > 1.5)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] Regenerating: Weather Temp delta = {Math.Abs(cached.WeatherTemp - current.WeatherTemp):F1}°C");
                return true;
            }

            // 2. Step count delta > 1000
            if (Math.Abs(cached.HealthSteps - current.HealthSteps) > 1000)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] Regenerating: Step count delta = {Math.Abs(cached.HealthSteps - current.HealthSteps)}");
                return true;
            }

            // 3. Habits delta (total or completed changes)
            if (cached.HabitsTotal != current.HabitsTotal || cached.HabitsCompleted != current.HabitsCompleted)
            {
                Debug.WriteLine($"[SmartBriefingCacheManager] Regenerating: Habits Count changed ({cached.HabitsCompleted}/{cached.HabitsTotal} vs {current.HabitsCompleted}/{current.HabitsTotal})");
                return true;
            }

            // 4. News recommendations change (only check if we retrieved news)
            if (!onlyLocal)
            {
                if (cached.NewsRecommendations.Count != current.NewsRecommendations.Count)
                {
                    Debug.WriteLine($"[SmartBriefingCacheManager] Regenerating: News Recommendation count changed");
                    return true;
                }

                for (int i = 0; i < Math.Min(cached.NewsRecommendations.Count, current.NewsRecommendations.Count); i++)
                {
                    if (cached.NewsRecommendations[i].Title != current.NewsRecommendations[i].Title)
                    {
                        Debug.WriteLine($"[SmartBriefingCacheManager] Regenerating: News Recommendation item changed");
                        return true;
                    }
                }
            }

            return false;
        }
    }
}
