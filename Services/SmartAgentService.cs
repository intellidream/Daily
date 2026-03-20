using Daily.Models;
using MudBlazor;

namespace Daily.Services
{
    public class SmartAgentService : ISmartAgentService
    {
        private readonly IDatabaseService _db;
        private readonly Supabase.Client _supabase;
        private bool _initialized;
        private string? _userId;

        public event Action? OnSuggestionChanged;

        // Frequency map: (DayOfWeek, HourBucket) -> WidgetType -> count
        private readonly Dictionary<(int Day, int HourBucket), Dictionary<string, int>> _frequencyMap = new();

        // Widget metadata for icon/label mapping
        private static readonly Dictionary<string, (string Icon, string Label)> WidgetMeta = new()
        {
            ["HabitsWidget"] = (Icons.Material.Filled.LocalDrink, "Log habits"),
            ["RssFeedWidget"] = (Icons.Material.Filled.Article, "Read news"),
            ["HealthWidget"] = (Icons.Material.Filled.MonitorHeart, "Check vitals"),
            ["WeatherWidget"] = (Icons.Material.Filled.WbSunny, "Weather"),
            ["FinancesWidget"] = (Icons.Material.Filled.AccountBalance, "Finances"),
            ["CalendarWidget"] = (Icons.Material.Filled.CalendarMonth, "Calendar"),
            ["MediaWidget"] = (Icons.Material.Filled.OndemandVideo, "Watch media"),
            ["NotesWidget"] = (Icons.Material.Filled.StickyNote2, "Notes"),
            ["SystemInfoWidget"] = (Icons.Material.Filled.Memory, "System info"),
        };

        // Time-of-day priors: give a baseline boost to certain widgets at certain hours
        private static readonly Dictionary<string, (int StartHour, int EndHour, double Boost)[]> TimePriors = new()
        {
            ["HealthWidget"] = new[] { (6, 10, 0.3) },          // Mornings -> Vitals
            ["HabitsWidget"] = new[] { (7, 11, 0.2), (18, 23, 0.2) }, // Morning & evening -> Habits
            ["RssFeedWidget"] = new[] { (7, 9, 0.15), (12, 14, 0.15), (19, 22, 0.15) }, // Commute & lunch & evening -> News
            ["FinancesWidget"] = new[] { (8, 10, 0.1), (16, 18, 0.1) }, // Market hours
        };

        public SmartAgentService(IDatabaseService db, Supabase.Client supabase)
        {
            _db = db;
            _supabase = supabase;
        }

        public async Task InitializeAsync()
        {
            if (_initialized) return;

            await _db.InitializeAsync();
            await _db.Connection.CreateTableAsync<LocalBehaviorEvent>();

            _userId = _supabase.Auth?.CurrentUser?.Id;
            if (string.IsNullOrEmpty(_userId)) return;

            // Load last 30 days of events into frequency map
            var cutoff = DateTime.UtcNow.AddDays(-30);
            var events = await _db.Connection.Table<LocalBehaviorEvent>()
                .Where(e => e.UserId == _userId && e.Timestamp > cutoff)
                .ToListAsync();

            foreach (var ev in events)
            {
                AddToFrequencyMap(ev.DayOfWeek, ev.HourOfDay, ev.WidgetType);
            }

            _initialized = true;
        }

        public async Task RecordEventAsync(string widgetType, string action = "view")
        {
            _userId = _supabase.Auth?.CurrentUser?.Id;
            if (string.IsNullOrEmpty(_userId)) return;

            if (!_initialized) await InitializeAsync();

            var now = DateTime.UtcNow;
            var ev = new LocalBehaviorEvent
            {
                UserId = _userId,
                WidgetType = widgetType,
                Action = action,
                DayOfWeek = (int)now.DayOfWeek,
                HourOfDay = now.Hour,
                Timestamp = now
            };

            await _db.Connection.InsertAsync(ev);
            AddToFrequencyMap(ev.DayOfWeek, ev.HourOfDay, ev.WidgetType);

            // Prune old events (keep last 90 days)
            var pruneDate = now.AddDays(-90);
            await _db.Connection.Table<LocalBehaviorEvent>()
                .DeleteAsync(e => e.Timestamp < pruneDate);

            OnSuggestionChanged?.Invoke();
        }

        public Task<WidgetSuggestion?> GetSuggestionAsync()
        {
            _userId = _supabase.Auth?.CurrentUser?.Id;
            if (string.IsNullOrEmpty(_userId))
                return Task.FromResult<WidgetSuggestion?>(null);

            var now = DateTime.Now; // Local time for user context
            var day = (int)now.DayOfWeek;
            var hour = now.Hour;
            var bucket = GetHourBucket(hour);

            // Score each widget
            var scores = new Dictionary<string, double>();

            foreach (var widget in WidgetMeta.Keys)
            {
                double score = 0;

                // 1. Frequency-based score from learned patterns
                var key = (day, bucket);
                if (_frequencyMap.TryGetValue(key, out var widgetCounts))
                {
                    var total = widgetCounts.Values.Sum();
                    if (total > 0 && widgetCounts.TryGetValue(widget, out var count))
                    {
                        score = (double)count / total;
                    }
                }

                // Also check adjacent buckets with decay
                foreach (var adjBucket in new[] { bucket - 1, bucket + 1 })
                {
                    var adjKey = (day, adjBucket);
                    if (_frequencyMap.TryGetValue(adjKey, out var adjCounts))
                    {
                        var adjTotal = adjCounts.Values.Sum();
                        if (adjTotal > 0 && adjCounts.TryGetValue(widget, out var adjCount))
                        {
                            score += 0.3 * ((double)adjCount / adjTotal);
                        }
                    }
                }

                // 2. Time-of-day prior boost
                if (TimePriors.TryGetValue(widget, out var priors))
                {
                    foreach (var (startH, endH, boost) in priors)
                    {
                        if (hour >= startH && hour <= endH)
                        {
                            score += boost;
                            break;
                        }
                    }
                }

                scores[widget] = score;
            }

            // Pick highest scoring widget
            var best = scores.OrderByDescending(kv => kv.Value).FirstOrDefault();

            if (best.Value < 0.05) // Minimum threshold
            {
                // Fallback: use pure time-of-day heuristic
                var fallback = GetTimeBasedFallback(hour);
                if (fallback != null && WidgetMeta.TryGetValue(fallback, out var meta))
                {
                    return Task.FromResult<WidgetSuggestion?>(new WidgetSuggestion
                    {
                        WidgetType = fallback,
                        Confidence = 0.3,
                        Icon = meta.Icon,
                        Label = meta.Label
                    });
                }
                return Task.FromResult<WidgetSuggestion?>(null);
            }

            if (WidgetMeta.TryGetValue(best.Key, out var bestMeta))
            {
                return Task.FromResult<WidgetSuggestion?>(new WidgetSuggestion
                {
                    WidgetType = best.Key,
                    Confidence = Math.Min(best.Value, 1.0),
                    Icon = bestMeta.Icon,
                    Label = bestMeta.Label
                });
            }

            return Task.FromResult<WidgetSuggestion?>(null);
        }

        private void AddToFrequencyMap(int day, int hour, string widgetType)
        {
            var bucket = GetHourBucket(hour);
            var key = (day, bucket);
            if (!_frequencyMap.TryGetValue(key, out var widgetCounts))
            {
                widgetCounts = new Dictionary<string, int>();
                _frequencyMap[key] = widgetCounts;
            }
            widgetCounts.TryGetValue(widgetType, out var count);
            widgetCounts[widgetType] = count + 1;
        }

        /// <summary>
        /// Groups hours into 2-hour buckets for smoother patterns.
        /// 0-1 -> 0, 2-3 -> 1, ... 22-23 -> 11
        /// </summary>
        private static int GetHourBucket(int hour) => hour / 2;

        private static string? GetTimeBasedFallback(int hour) => hour switch
        {
            >= 6 and <= 9 => "HealthWidget",     // Morning -> Vitals
            >= 10 and <= 11 => "HabitsWidget",    // Late morning -> Habits
            >= 12 and <= 14 => "RssFeedWidget",   // Lunch -> News
            >= 15 and <= 17 => "FinancesWidget",  // Afternoon -> Markets
            >= 18 and <= 21 => "HabitsWidget",    // Evening -> Habits
            _ => "RssFeedWidget",                  // Night/early morning -> Read
        };
    }
}
