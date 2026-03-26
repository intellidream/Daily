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
        public bool IsReady => _initialized && !string.IsNullOrEmpty(_userId);

        // Frequency map: (DayOfWeek, HourBucket) -> WidgetType -> count
        private readonly Dictionary<(int Day, int HourBucket), Dictionary<string, int>> _frequencyMap = new();

        // Transition map: FromWidget -> ToWidget -> count (Markov chain)
        private readonly Dictionary<string, Dictionary<string, int>> _transitionMap = new();

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

        private static readonly Dictionary<string, (int StartHour, int EndHour, double Boost)[]> TimePriors = new()
        {
            ["HealthWidget"] = new[] { (6, 10, 0.3) },
            ["HabitsWidget"] = new[] { (7, 11, 0.2), (18, 23, 0.2) },
            ["RssFeedWidget"] = new[] { (7, 9, 0.15), (12, 14, 0.15), (19, 22, 0.15) },
            ["FinancesWidget"] = new[] { (8, 10, 0.1), (16, 18, 0.1) },
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
            await _db.Connection.CreateTableAsync<LocalNavigationTransition>();

            _userId = _supabase.Auth?.CurrentUser?.Id;
            if (string.IsNullOrEmpty(_userId)) return;

            var cutoff = DateTime.UtcNow.AddDays(-30);

            // Load behavior events
            var events = await _db.Connection.Table<LocalBehaviorEvent>()
                .Where(e => e.UserId == _userId && e.Timestamp > cutoff)
                .ToListAsync();

            foreach (var ev in events)
                AddToFrequencyMap(ev.DayOfWeek, ev.HourOfDay, ev.WidgetType);

            // Load navigation transitions
            var transitions = await _db.Connection.Table<LocalNavigationTransition>()
                .Where(t => t.UserId == _userId && t.Timestamp > cutoff)
                .ToListAsync();

            foreach (var tr in transitions)
                AddToTransitionMap(tr.FromWidget, tr.ToWidget);

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

            var pruneDate = now.AddDays(-90);
            await _db.Connection.Table<LocalBehaviorEvent>()
                .DeleteAsync(e => e.Timestamp < pruneDate);

            OnSuggestionChanged?.Invoke();
        }

        public async Task RecordTransitionAsync(string fromWidget, string toWidget)
        {
            _userId = _supabase.Auth?.CurrentUser?.Id;
            if (string.IsNullOrEmpty(_userId)) return;
            if (fromWidget == toWidget) return;

            if (!_initialized) await InitializeAsync();

            var now = DateTime.UtcNow;
            var tr = new LocalNavigationTransition
            {
                UserId = _userId,
                FromWidget = fromWidget,
                ToWidget = toWidget,
                DayOfWeek = (int)now.DayOfWeek,
                HourOfDay = now.Hour,
                Timestamp = now
            };

            await _db.Connection.InsertAsync(tr);
            AddToTransitionMap(fromWidget, toWidget);

            var pruneDate = now.AddDays(-90);
            await _db.Connection.Table<LocalNavigationTransition>()
                .DeleteAsync(t => t.Timestamp < pruneDate);
        }

        public Task<WidgetSuggestion?> GetSuggestionAsync(string? currentVisibleWidget = null)
        {
            _userId = _supabase.Auth?.CurrentUser?.Id;
            if (string.IsNullOrEmpty(_userId))
                return Task.FromResult<WidgetSuggestion?>(null);

            var now = DateTime.Now;
            var day = (int)now.DayOfWeek;
            var hour = now.Hour;
            var bucket = GetHourBucket(hour);

            // --- 1. Score each widget by time-based frequency ---
            var timeScores = new Dictionary<string, double>();

            foreach (var widget in WidgetMeta.Keys)
            {
                double score = 0;

                var key = (day, bucket);
                if (_frequencyMap.TryGetValue(key, out var widgetCounts))
                {
                    var total = widgetCounts.Values.Sum();
                    if (total > 0 && widgetCounts.TryGetValue(widget, out var count))
                        score = (double)count / total;
                }

                foreach (var adjBucket in new[] { bucket - 1, bucket + 1 })
                {
                    var adjKey = (day, adjBucket);
                    if (_frequencyMap.TryGetValue(adjKey, out var adjCounts))
                    {
                        var adjTotal = adjCounts.Values.Sum();
                        if (adjTotal > 0 && adjCounts.TryGetValue(widget, out var adjCount))
                            score += 0.3 * ((double)adjCount / adjTotal);
                    }
                }

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

                timeScores[widget] = score;
            }

            var bestTime = timeScores.OrderByDescending(kv => kv.Value).First();

            // --- 2. Transition-based suggestion ("from here, you usually go to...") ---
            WidgetSuggestion? transitionSuggestion = null;
            if (!string.IsNullOrEmpty(currentVisibleWidget) &&
                _transitionMap.TryGetValue(currentVisibleWidget, out var destinations))
            {
                var totalTransitions = destinations.Values.Sum();
                if (totalTransitions >= 3) // Need at least 3 transitions to be meaningful
                {
                    var bestDest = destinations
                        .Where(kv => kv.Key != currentVisibleWidget)
                        .OrderByDescending(kv => kv.Value)
                        .FirstOrDefault();

                    if (bestDest.Key != null && bestDest.Value >= 2)
                    {
                        var transitionConfidence = (double)bestDest.Value / totalTransitions;
                        if (transitionConfidence >= 0.40 && WidgetMeta.TryGetValue(bestDest.Key, out var tMeta))
                        {
                            transitionSuggestion = new WidgetSuggestion
                            {
                                WidgetType = bestDest.Key,
                                Confidence = transitionConfidence,
                                Icon = tMeta.Icon,
                                Label = $"Go to {tMeta.Label}",
                                IsTransitionBased = true
                            };
                        }
                    }
                }
            }

            // --- 3. Decision: use transition if available, otherwise strong time-based, otherwise fallback ---

            // Use transition suggestion first if available (immediate context beats time-of-day)
            if (transitionSuggestion != null)
                return Task.FromResult<WidgetSuggestion?>(transitionSuggestion);

            // Strong time signal
            if (bestTime.Value >= 0.25 && WidgetMeta.TryGetValue(bestTime.Key, out var bestMeta))
            {
                // Don't suggest the widget the user is already looking at
                if (bestTime.Key != currentVisibleWidget)
                {
                    return Task.FromResult<WidgetSuggestion?>(new WidgetSuggestion
                    {
                        WidgetType = bestTime.Key,
                        Confidence = Math.Min(bestTime.Value, 1.0),
                        Icon = bestMeta.Icon,
                        Label = bestMeta.Label
                    });
                }
            }

            // Weak time signal (still better than nothing)
            if (bestTime.Value >= 0.05 && WidgetMeta.TryGetValue(bestTime.Key, out var weakMeta))
            {
                if (bestTime.Key != currentVisibleWidget)
                {
                    return Task.FromResult<WidgetSuggestion?>(new WidgetSuggestion
                    {
                        WidgetType = bestTime.Key,
                        Confidence = Math.Min(bestTime.Value, 1.0),
                        Icon = weakMeta.Icon,
                        Label = weakMeta.Label
                    });
                }
            }

            // Fallback: time-of-day heuristic
            var fallback = GetTimeBasedFallback(hour);
            if (fallback != null && fallback != currentVisibleWidget && WidgetMeta.TryGetValue(fallback, out var fMeta))
            {
                return Task.FromResult<WidgetSuggestion?>(new WidgetSuggestion
                {
                    WidgetType = fallback,
                    Confidence = 0.2,
                    Icon = fMeta.Icon,
                    Label = fMeta.Label
                });
            }

            // Absolute fallback: generic "explore" state (prevents FAB from disappearing)
            return Task.FromResult<WidgetSuggestion?>(new WidgetSuggestion
            {
                WidgetType = "",
                Confidence = 0.0,
                Icon = Icons.Material.Filled.AutoAwesome,
                Label = "What's next?"
            });
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

        private void AddToTransitionMap(string from, string to)
        {
            if (!_transitionMap.TryGetValue(from, out var destinations))
            {
                destinations = new Dictionary<string, int>();
                _transitionMap[from] = destinations;
            }
            destinations.TryGetValue(to, out var count);
            destinations[to] = count + 1;
        }

        private static int GetHourBucket(int hour) => hour / 2;

        private static string? GetTimeBasedFallback(int hour) => hour switch
        {
            >= 6 and <= 9 => "HealthWidget",
            >= 10 and <= 11 => "HabitsWidget",
            >= 12 and <= 14 => "RssFeedWidget",
            >= 15 and <= 17 => "FinancesWidget",
            >= 18 and <= 21 => "HabitsWidget",
            _ => "RssFeedWidget",
        };
    }
}
