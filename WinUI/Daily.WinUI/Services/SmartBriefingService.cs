using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Daily.Services;
using Daily.Services.Health;
using Daily.Services.Finances;
using Daily.Models;
using Daily.Models.Health;
using Daily.Models.Finances;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI.Services
{
    public sealed class ForecastDayData
    {
        public string DayName { get; set; } = string.Empty;
        public double Temp { get; set; }
        public string Icon { get; set; } = string.Empty; // e.g. Glyph representable
        public string ColorHex { get; set; } = string.Empty;
    }

    public sealed class StockBriefingData
    {
        public string Symbol { get; set; } = string.Empty;
        public decimal Price { get; set; }
        public decimal PercentChange { get; set; }
        public bool IsPositive => PercentChange >= 0;
        public string FormattedChange => (PercentChange >= 0 ? "+" : "") + PercentChange.ToString("F2") + "%";
    }

    public sealed class NewsRecommendationData
    {
        public string Title { get; set; } = string.Empty;
        public string Source { get; set; } = string.Empty;
        public string Reason { get; set; } = string.Empty;
    }

    public sealed class SmartBriefingData
    {
        public string Greeting { get; set; } = string.Empty;
        public string IntroText { get; set; } = string.Empty;
        public string BriefingText { get; set; } = string.Empty;
        public string OutroText { get; set; } = string.Empty;
        
        // Weather
        public string WeatherSummary { get; set; } = string.Empty;
        public double WeatherTemp { get; set; }
        public string WeatherCondition { get; set; } = string.Empty;
        public List<ForecastDayData> WeatherForecast { get; set; } = new();

        // Health
        public int HealthSteps { get; set; }
        public double HealthSleepHours { get; set; }
        public int HealthAvgHr { get; set; }
        public double HealthWeight { get; set; }
        public double HealthActiveEnergy { get; set; }
        public double HealthHrv { get; set; }
        public double HealthBpSystolic { get; set; }
        public double HealthBpDiastolic { get; set; }
        public double HealthSpO2 { get; set; }

        // Finances
        public decimal NetWorth { get; set; }
        public bool HasLedgerData { get; set; }
        public List<StockBriefingData> WatchlistStocks { get; set; } = new();

        // Habits
        public int HabitsTotal { get; set; }
        public int HabitsCompleted { get; set; }
        public double HabitsWaterProgress { get; set; }
        public double HabitsWaterGoal { get; set; }
        public double HabitsSmokesProgress { get; set; }
        public double HabitsSmokesGoal { get; set; }

        // Insights/Advice
        public string WeatherAdvice { get; set; } = string.Empty;
        public string HealthAdvice { get; set; } = string.Empty;
        public string FinanceAdvice { get; set; } = string.Empty;
        public string HabitsAdvice { get; set; } = string.Empty;

        // News Recommendations
        public List<NewsRecommendationData> NewsRecommendations { get; set; } = new();
    }

    public sealed class SmartBriefingService
    {
        private readonly WeatherClient _weatherClient = new();
        private readonly LocationService _locationService = new();
        private readonly IHealthService? _healthService;
        private readonly IFinancesService? _financesService;
        private readonly IHabitsService? _habitsService;
        private readonly IRssFeedService? _rssFeedService;
        private readonly IRssArticleService? _rssArticleService;
        private readonly ISmartIntelligenceService _smartService;
        private readonly IBehaviorService _behaviorService;

        public SmartBriefingService(
            ISmartIntelligenceService smartService,
            IBehaviorService behaviorService)
        {
            _smartService = smartService;
            _behaviorService = behaviorService;

            try
            {
                _healthService = App.Current.Services.GetService(typeof(IHealthService)) as IHealthService;
                _financesService = App.Current.Services.GetService(typeof(IFinancesService)) as IFinancesService;
                _habitsService = App.Current.Services.GetService(typeof(IHabitsService)) as IHabitsService;
                _rssFeedService = App.Current.Services.GetService(typeof(IRssFeedService)) as IRssFeedService;
                _rssArticleService = App.Current.Services.GetService(typeof(IRssArticleService)) as IRssArticleService;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Init Error: {ex.Message}");
            }
        }

        public async Task<SmartBriefingData> GenerateBriefingDataAsync(string userName)
        {
            var data = new SmartBriefingData();
            
            // 1. Time-of-day Greeting
            int hour = DateTime.Now.Hour;
            string greetingBase = "Good evening";
            if (hour >= 5 && hour < 12) greetingBase = "Good morning";
            else if (hour >= 12 && hour < 17) greetingBase = "Good afternoon";
            
            data.Greeting = $"{greetingBase}, {userName}!";

            // Kick off all background operations in parallel tasks
            var coordsTask = _locationService.GetCurrentCoordinatesAsync();
            var stepsTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.Steps) : Task.FromResult<VitalMetric?>(null);
            var sleepTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.SleepDuration) : Task.FromResult<VitalMetric?>(null);
            var hrTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.HeartRate) : Task.FromResult<VitalMetric?>(null);
            var weightTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.Weight) : Task.FromResult<VitalMetric?>(null);
            var activeEnergyTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.ActiveEnergy) : Task.FromResult<VitalMetric?>(null);
            var hrvTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.HeartRateVariabilitySDNN) : Task.FromResult<VitalMetric?>(null);
            var bpSystolicTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.BloodPressureSystolic) : Task.FromResult<VitalMetric?>(null);
            var bpDiastolicTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.BloodPressureDiastolic) : Task.FromResult<VitalMetric?>(null);
            var oxygenTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.OxygenSaturation) : Task.FromResult<VitalMetric?>(null);

            var netWorthTask = _financesService != null ? _financesService.GetNetWorthAsync() : Task.FromResult(0m);
            var symbolsTask = _financesService != null ? _financesService.GetWatchlistSymbolsAsync() : Task.FromResult<List<string>?>(null);
            
            var hydrationTask = _habitsService != null ? _habitsService.GetDailyProgressAsync("water", DateTime.Today) : Task.FromResult(0.0);
            var smokesTask = _habitsService != null ? _habitsService.GetDailyProgressAsync("smokes", DateTime.Today) : Task.FromResult(0.0);
            var waterGoalTask = _habitsService != null ? _habitsService.GetGoalAsync("water") : Task.FromResult<HabitGoal?>(null);

            // 2. Weather Aggregation
            double temp = 21.5;
            string condition = "sunny";
            string weatherSentence = "The weather today looks warm and sunny, perfect for outdoor activities.";
            string hourlyWeatherDetails = "No hourly data available.";
            string fiveDayWeatherDetails = "No 5-day forecast available.";
            
            try
            {
                var coords = await coordsTask;
                var settings = SettingsService.Load();
                if (!coords.HasValue && settings.LastLatitude.HasValue && settings.LastLongitude.HasValue)
                {
                    coords = (settings.LastLatitude.Value, settings.LastLongitude.Value);
                    Console.WriteLine($"[SmartBriefingService] Location detection timed out/failed. Falling back to cached coords: {coords.Value.Latitude}, {coords.Value.Longitude}");
                }

                if (coords.HasValue)
                {
                    var weatherTask = _weatherClient.GetCurrentWeatherAsync(coords.Value.Latitude, coords.Value.Longitude, settings.UnitSystem);
                    var forecastTask = _weatherClient.GetFiveDayForecastAsync(coords.Value.Latitude, coords.Value.Longitude, settings.UnitSystem);
                    var hourlyTask = _weatherClient.GetHourlyForecastAsync(coords.Value.Latitude, coords.Value.Longitude, settings.UnitSystem, 8);
                    
                    await Task.WhenAll(weatherTask, forecastTask, hourlyTask);
                    
                    var snapshot = weatherTask.Result;
                    if (snapshot != null)
                    {
                        temp = snapshot.Temperature;
                        condition = snapshot.Description;
                        
                        if (condition.Contains("rain", StringComparison.OrdinalIgnoreCase) || condition.Contains("drizzle", StringComparison.OrdinalIgnoreCase))
                        {
                            weatherSentence = $"The weather today is rainy ({temp:F1}°C), so we recommend keeping your habits and workouts indoors.";
                        }
                        else if (temp < 10)
                        {
                            weatherSentence = $"It's quite cold outside ({temp:F1}°C) with {condition} skies. Layer up if you're heading out.";
                        }
                        else
                        {
                            weatherSentence = $"Expect a pleasant day today with {condition} skies and a temperature of {temp:F1}°C.";
                        }
                    }

                    var hourlyList = hourlyTask.Result;
                    if (hourlyList != null && hourlyList.Count > 0)
                    {
                        var sb = new StringBuilder();
                        foreach (var hourData in hourlyList)
                        {
                            sb.AppendLine($"- {hourData.HourLabel}: {hourData.Temperature}°C (Feels like {hourData.FeelsLike}°C, Precip: {hourData.PrecipitationChance}%)");
                        }
                        hourlyWeatherDetails = sb.ToString();
                    }

                    var forecastList = forecastTask.Result;
                    if (forecastList != null && forecastList.Count > 0)
                    {
                        var sb = new StringBuilder();
                        int added = 0;
                        foreach (var day in forecastList)
                        {
                            string iconGlyph = "\uE706"; // default sun
                            string colorHex = "#FF9800"; // sunny orange
                            string cond = day.Description;
                            if (cond.Contains("Rain", StringComparison.OrdinalIgnoreCase) || cond.Contains("Drizzle", StringComparison.OrdinalIgnoreCase))
                            {
                                iconGlyph = "\uE774"; // rain
                                colorHex = "#2196F3"; // blue
                            }
                            else if (cond.Contains("Cloud", StringComparison.OrdinalIgnoreCase))
                            {
                                iconGlyph = "\uE753"; // cloudy
                                colorHex = "#B0BEC5"; // grey-blue
                            }
                            else if (cond.Contains("Snow", StringComparison.OrdinalIgnoreCase))
                            {
                                iconGlyph = "\uE77C"; // snow
                                colorHex = "#90CAF9"; // light blue
                            }
                            
                            data.WeatherForecast.Add(new ForecastDayData
                            {
                                DayName = day.DayLabel,
                                Temp = day.MaxTemp,
                                Icon = iconGlyph,
                                ColorHex = colorHex
                            });
                            
                            sb.AppendLine($"- {day.DayLabel}: Max {day.MaxTemp:F0}°C, Min {day.MinTemp:F0}°C, {day.Description} (Precip: {day.PrecipitationChance}%)");
                            added++;
                            if (added >= 5) break;
                        }
                        fiveDayWeatherDetails = sb.ToString();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Weather Fetch Error: {ex.Message}");
            }

            // Fallback weather forecast if empty
            if (data.WeatherForecast.Count == 0)
            {
                data.WeatherForecast.Add(new ForecastDayData { DayName = "Tomorrow", Temp = temp + 1, Icon = "\uE706", ColorHex = "#FF9800" });
                data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(2).ToString("dddd"), Temp = temp - 1, Icon = "\uE753", ColorHex = "#B0BEC5" });
                data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(3).ToString("dddd"), Temp = temp, Icon = "\uE774", ColorHex = "#2196F3" });
                data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(4).ToString("dddd"), Temp = temp + 2, Icon = "\uE706", ColorHex = "#FF9800" });
                data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(5).ToString("dddd"), Temp = temp + 1, Icon = "\uE753", ColorHex = "#B0BEC5" });
            }

            data.WeatherTemp = temp;
            data.WeatherCondition = condition;
            data.WeatherSummary = weatherSentence;


            // 3. Health Aggregation
            int steps = 2450;
            double sleep = 7.5;
            int heartRate = 68;
            double weightVal = 0;
            double caloriesVal = 0;
            double hrvVal = 0;
            double bpSystolic = 0;
            double bpDiastolic = 0;
            double oxygenVal = 0;
            string healthSentence = "";

            try
            {
                await Task.WhenAll(stepsTask, sleepTask, hrTask, weightTask, activeEnergyTask, hrvTask, bpSystolicTask, bpDiastolicTask, oxygenTask);
                
                var stepsMetric = stepsTask.Result;
                if (stepsMetric != null) steps = (int)stepsMetric.Value;
                
                var sleepMetric = sleepTask.Result;
                if (sleepMetric != null) sleep = SettingsService.ConvertSleepToHours(sleepMetric.Value, sleepMetric.Unit);

                var hrMetric = hrTask.Result;
                if (hrMetric != null) heartRate = (int)hrMetric.Value;

                var weightMetric = weightTask.Result;
                if (weightMetric != null) weightVal = weightMetric.Value;

                var aeMetric = activeEnergyTask.Result;
                if (aeMetric != null) caloriesVal = aeMetric.Value;

                var hrvMetric = hrvTask.Result;
                if (hrvMetric != null) hrvVal = hrvMetric.Value;

                var bpSysMetric = bpSystolicTask.Result;
                if (bpSysMetric != null) bpSystolic = bpSysMetric.Value;

                var bpDiaMetric = bpDiastolicTask.Result;
                if (bpDiaMetric != null) bpDiastolic = bpDiaMetric.Value;

                var oxMetric = oxygenTask.Result;
                if (oxMetric != null) oxygenVal = oxMetric.Value;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Health Fetch Error: {ex.Message}");
            }
            
            data.HealthSteps = steps;
            data.HealthSleepHours = sleep;
            data.HealthAvgHr = heartRate;
            data.HealthWeight = weightVal;
            data.HealthActiveEnergy = caloriesVal;
            data.HealthHrv = hrvVal;
            data.HealthBpSystolic = bpSystolic;
            data.HealthBpDiastolic = bpDiastolic;
            data.HealthSpO2 = oxygenVal;

            if (steps < 4000)
            {
                healthSentence = $"So far you've taken {steps:N0} steps today. Let's aim to get moving and hit your steps goal later.";
            }
            else
            {
                healthSentence = $"Great job! You've already reached {steps:N0} steps today, keeping up a healthy active baseline.";
            }

            if (sleep > 0)
            {
                healthSentence += $" You got {sleep:F1} hours of sleep last night, providing a solid foundation for your recovery.";
            }


            // 4. Finances Aggregation
            decimal netWorth = 0;
            bool hasLedgerData = false;
            string financeSentence = "";
            try
            {
                await Task.WhenAll(netWorthTask, symbolsTask);
                netWorth = netWorthTask.Result;

                var accounts = _financesService != null ? await _financesService.GetAccountsAsync() : null;
                var holdings = _financesService != null ? await _financesService.GetHoldingsWithQuotesAsync() : null;
                hasLedgerData = (accounts != null && accounts.Count > 0) || (holdings != null && holdings.Count > 0);

                if (!hasLedgerData)
                {
                    netWorth = 0; // True 0 if ledger is uninitialized
                }

                data.NetWorth = netWorth;
                data.HasLedgerData = hasLedgerData;

                var symbols = symbolsTask.Result;
                if (symbols != null && symbols.Count > 0)
                {
                    var quotes = await _financesService.GetStockQuotesAsync(symbols);
                    if (quotes != null)
                    {
                        int count = 0;
                        foreach (var q in quotes)
                        {
                            data.WatchlistStocks.Add(new StockBriefingData
                            {
                                Symbol = q.Symbol,
                                Price = (decimal)q.CurrentPrice,
                                PercentChange = (decimal)q.PercentChange
                            });
                            count++;
                            if (count >= 2) break; // keep top 2
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Finance Error: {ex.Message}");
            }

            // Fallback stocks if empty
            if (data.WatchlistStocks.Count == 0)
            {
                data.WatchlistStocks.Add(new StockBriefingData { Symbol = "MSFT", Price = 421.90m, PercentChange = 1.45m });
                data.WatchlistStocks.Add(new StockBriefingData { Symbol = "AAPL", Price = 189.84m, PercentChange = -0.32m });
            }

            if (hasLedgerData)
            {
                financeSentence = $"Your ledger net worth is looking healthy at {netWorth:C0}. Markets are showing active movements: {data.WatchlistStocks[0].Symbol} is at {data.WatchlistStocks[0].Price:C2} ({data.WatchlistStocks[0].FormattedChange}).";
            }
            else
            {
                financeSentence = "You haven't set up your financial ledger yet. Add accounts to start tracking your net worth!";
            }


            // 5. Habits Aggregation
            double waterProgress = 0;
            double waterGoal = 2000;
            double smokesProgress = 0;
            double smokesGoal = 0;
            string habitsSentence = "";

            try
            {
                waterProgress = await hydrationTask;
                var waterGoalObj = await waterGoalTask;
                waterGoal = waterGoalObj?.TargetValue > 0 ? waterGoalObj.TargetValue : 2000;

                smokesProgress = smokesTask != null ? await smokesTask : 0;
                var settingsService = App.Current.Services.GetService(typeof(ISettingsService)) as ISettingsService;
                smokesGoal = settingsService?.Settings?.SmokesBaselineDaily ?? 20;

                data.HabitsWaterProgress = waterProgress;
                data.HabitsWaterGoal = waterGoal;
                data.HabitsSmokesProgress = smokesProgress;
                data.HabitsSmokesGoal = smokesGoal;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Habits Error: {ex.Message}");
            }

            // Calculate completed/total habits dynamically
            int habitsTotal = 1; // Hydration is always present
            int habitsCompleted = 0;
            if (waterProgress >= waterGoal) habitsCompleted++;

            if (smokesGoal > 0 || smokesProgress > 0)
            {
                habitsTotal++;
                // Smokes habit: succeed/complete if we haven't exceeded baseline
                if (smokesProgress <= smokesGoal) habitsCompleted++;
            }

            data.HabitsTotal = habitsTotal;
            data.HabitsCompleted = habitsCompleted;

            if (waterProgress < waterGoal)
            {
                habitsSentence = $"You've logged {waterProgress:F0} ml of water today out of your {waterGoal:F0} ml goal. Remember to hydrate!";
            }
            else
            {
                habitsSentence = $"Great job on hydration! You reached your {waterGoal:F0} ml water goal today.";
            }

            if (smokesGoal > 0 || smokesProgress > 0)
            {
                if (smokesProgress > smokesGoal)
                {
                    habitsSentence += $" You have smoked {smokesProgress} today, which exceeds your target limit of {smokesGoal}. Try to resist logging any more.";
                }
                else
                {
                    habitsSentence += $" You have smoked {smokesProgress} out of your daily limit of {smokesGoal}. Keep up the control!";
                }
            }


            // 6. News AI Recommendations with Source Diversity & Interest Matching
            // 6. News AI Recommendations with Source Diversity & Interest Matching
            if (_rssFeedService != null && _rssFeedService.Feeds != null && _rssFeedService.Feeds.Count > 0)
            {
                var allFeedItems = new List<RssItem>();
                
                // Add current feed items if populated
                if (_rssFeedService.Items != null)
                {
                    allFeedItems.AddRange(_rssFeedService.Items);
                }

                // Fetch other feeds in parallel to construct a rich recommendation pool
                var otherFeeds = _rssFeedService.Feeds
                    .Where(f => _rssFeedService.CurrentFeed == null || !string.Equals(f.Url, _rssFeedService.CurrentFeed.Url, StringComparison.OrdinalIgnoreCase))
                    .ToList();

                if (otherFeeds.Count > 0)
                {
                    try
                    {
                        var tasks = otherFeeds.Select(async feed =>
                        {
                            try
                            {
                                return await _rssFeedService.FetchFeedItemsAsync(feed);
                            }
                            catch (Exception ex)
                            {
                                Console.WriteLine($"[SmartBriefingService] Feed fetch error for {feed.Name}: {ex.Message}");
                                return new List<RssItem>();
                            }
                        });
                        var results = await Task.WhenAll(tasks);
                        foreach (var list in results)
                        {
                            if (list != null)
                            {
                                allFeedItems.AddRange(list);
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] Parallel feed fetch error: {ex.Message}");
                    }
                }

                // Deduplicate by URL or title
                var uniqueItems = allFeedItems
                    .GroupBy(item => item.Link ?? item.Title)
                    .Select(g => g.First())
                    .ToList();

                var readSources = new List<string>();
                var readTitles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                try
                {
                    var dbService = App.Current.Services.GetService(typeof(Daily.Services.IDatabaseService)) as Daily.Services.IDatabaseService;
                    if (dbService != null)
                    {
                        await dbService.InitializeAsync();
                        var cutoff = DateTime.UtcNow.AddDays(-7);
                        string userId = App.Current.Services.GetRequiredService<Supabase.Client>().Auth?.CurrentUser?.Id ?? "local_user";
                        var recentEvents = await dbService.Connection.Table<SmartBehaviorEvent>()
                            .Where(e => e.UserId == userId && e.Feature == "News" && e.ActionType == "ReadArticle" && e.Timestamp > cutoff)
                            .ToListAsync();

                        if (recentEvents != null)
                        {
                            foreach (var ev in recentEvents)
                            {
                                try
                                {
                                    using var doc = System.Text.Json.JsonDocument.Parse(ev.Metadata);
                                    if (doc.RootElement.TryGetProperty("source", out var srcProp))
                                    {
                                        readSources.Add(srcProp.GetString() ?? "");
                                    }
                                    if (doc.RootElement.TryGetProperty("title", out var titleProp))
                                    {
                                        readTitles.Add(titleProp.GetString() ?? "");
                                    }
                                }
                                catch { }
                            }
                        }
                    }
                }
                catch { }

                // Fetch favorite and read-later articles to match themes and publications
                var favorites = _rssArticleService?.FavoriteItems ?? new List<LocalSavedArticle>();
                var readLater = _rssArticleService?.ReadLaterItems ?? new List<LocalSavedArticle>();
                
                var favPublications = new HashSet<string>(favorites.Select(f => f.PublicationName), StringComparer.OrdinalIgnoreCase);
                var rlPublications = new HashSet<string>(readLater.Select(r => r.PublicationName), StringComparer.OrdinalIgnoreCase);
                
                // Collect keywords from titles of saved articles to match interests
                var savedKeywords = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var commonWords = new HashSet<string>(new[] { "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "with", "of", "is", "are", "was", "were", "it", "its" }, StringComparer.OrdinalIgnoreCase);
                
                foreach (var title in favorites.Concat(readLater).Select(a => a.Title))
                {
                    var words = title.Split(new[] { ' ', ',', '.', '-', ':', '?', '!' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var w in words)
                    {
                        if (w.Length > 3 && !commonWords.Contains(w))
                        {
                            savedKeywords.Add(w);
                        }
                    }
                }

                // Score all available feed items
                var scoredItems = new List<(RssItem Item, double Score, string Reason)>();
                foreach (var item in uniqueItems)
                {
                    if (string.IsNullOrEmpty(item.Title) || readTitles.Contains(item.Title))
                        continue;

                    double score = 0;
                    string reason = $"Top story from {item.PublicationName ?? "Feed"}";
                    string pub = item.PublicationName ?? "";
                    
                    // Match behavior history
                    int historyCount = readSources.Count(s => string.Equals(s, pub, StringComparison.OrdinalIgnoreCase));
                    if (historyCount > 0)
                    {
                        score += 3 + Math.Min(3, historyCount); // Caps history boost
                        reason = $"Based on your interest in {pub}";
                    }
                    
                    // Match favorites
                    if (favPublications.Contains(pub))
                    {
                        score += 5;
                        reason = $"From your favorite publication: {pub}";
                    }
                    
                    // Match read later
                    if (rlPublications.Contains(pub))
                    {
                        score += 4;
                        reason = $"Matches your Read Later source: {pub}";
                    }

                    // Match title keywords for semantic recommendation
                    int keywordMatches = 0;
                    var itemWords = item.Title.Split(new[] { ' ', ',', '.', '-', ':', '?', '!' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var w in itemWords)
                    {
                        if (savedKeywords.Contains(w))
                        {
                            keywordMatches++;
                        }
                    }

                    if (keywordMatches > 0)
                    {
                        score += 2 * keywordMatches;
                        if (score >= 5)
                        {
                            reason = "Matches your reading interests";
                        }
                    }

                    scoredItems.Add((item, score, reason));
                }

                // Order by score and take top, ensuring source diversity if possible
                var selected = new List<(RssItem Item, string Reason)>();
                var ordered = scoredItems.OrderByDescending(x => x.Score).ToList();
                if (ordered.Count > 0)
                {
                    var first = ordered[0];
                    selected.Add((first.Item, first.Reason));

                    if (ordered.Count > 1)
                    {
                        var second = ordered.Skip(1).FirstOrDefault(x => 
                            !string.Equals(x.Item.PublicationName, first.Item.PublicationName, StringComparison.OrdinalIgnoreCase));
                        
                        if (second.Item != null)
                        {
                            selected.Add((second.Item, second.Reason));
                        }
                        else
                        {
                            var secondOverall = ordered[1];
                            selected.Add((secondOverall.Item, secondOverall.Reason));
                        }
                    }
                }

                foreach (var sel in selected)
                {
                    data.NewsRecommendations.Add(new NewsRecommendationData
                    {
                        Title = sel.Item.Title,
                        Source = sel.Item.PublicationName ?? "RSS Feed",
                        Reason = sel.Reason
                    });
                }
            }

            if (data.NewsRecommendations.Count == 0)
            {
                data.NewsRecommendations.Add(new NewsRecommendationData
                {
                    Title = "The Rise of On-Device AI: NPUs and Privacy",
                    Source = "Wired",
                    Reason = "Top story in Technology"
                });
                data.NewsRecommendations.Add(new NewsRecommendationData
                {
                    Title = "Global Markets Rally Amid Economic Forecasts",
                    Source = "Bloomberg",
                    Reason = "Based on your Finance watchlist interest"
                });
            }

            // 7. Generate AI narrative or fallback
            string fallbackBriefing = $"{weatherSentence} {healthSentence}\n\n{financeSentence} {habitsSentence}\n\nLastly, we found a couple of interesting articles in your feed you might like: \"{data.NewsRecommendations[0].Title}\" from {data.NewsRecommendations[0].Source}, and \"{data.NewsRecommendations[1].Title}\" from {data.NewsRecommendations[1].Source}.";

            bool useAi = false;
            try
            {
                useAi = await _smartService.IsModelReadyAsync();
            }
            catch { }

            string weatherAdvice = "";
            string healthAdvice = "";
            string financeAdvice = "";
            string habitsAdvice = "";

            if (useAi)
            {
                try
                {
                    string behaviorSummary = await _behaviorService.GetWeeklyBehaviorSummaryAsync();
                    
                    StringBuilder stocksBuilder = new StringBuilder();
                    foreach (var stock in data.WatchlistStocks)
                    {
                        stocksBuilder.Append($"{stock.Symbol}: {stock.Price:F2} ({stock.FormattedChange}), ");
                    }
                    string watchlistDetails = stocksBuilder.Length > 0 ? stocksBuilder.ToString().TrimEnd(',', ' ') : "None";

                    string systemPrompt = 
                        "You are DayOne, a helpful personal assistant AI running locally on the user's device. " +
                        "Generate a concise, natural, and friendly daily briefing narrative based on the user's data. " +
                        "Analyze their weather, habits, finances, health, and 7-day behavior logs to provide cohesive insights and encouraging advice.\n" +
                        "Rules:\n" +
                        "- Jump straight into the greeting and the narrative briefing. Do NOT write introductory filler like 'Here is your briefing tailored for you' or 'Based on your data'.\n" +
                        "- Keep the briefing structured in 2-3 short paragraphs of conversational flowing text. Do not use markdown headers or lists.\n" +
                        "- Format your paragraphs clearly, using double newlines (\n\n) to separate them.\n" +
                        "- If finance data is marked as UNINITIALIZED, do not congratulate the user on net worth or mention a $0 net worth. Suggest setting up their ledger or adding an account instead.\n" +
                        "- If smoking habit data is present, treat it as a negative target (reduction/cessation). Do NOT congratulate the user for smoking or logging smokes; instead, encourage reduction or praise staying under limit.\n" +
                        "- Evaluate the weather forecast over the next hours and next 5 days, highlighting key transitions (e.g. if it will rain later, recommend taking an umbrella or exercising indoors).\n\n" +
                        "At the very end of your response, you MUST append a JSON block enclosed in <insights> and </insights> tags. The JSON must contain short advice strings (1 sentence each) for the widgets: " +
                        "{\n" +
                        "  \"weatherAdvice\": \"short advice based on weather forecast\",\n" +
                        "  \"healthAdvice\": \"short advice based on vitals/sleep\",\n" +
                        "  \"financeAdvice\": \"short advice based on ledger/watchlist\",\n" +
                        "  \"habitsAdvice\": \"short advice based on water/smoking\"\n" +
                        "}\n" +
                        "Do not write any introductory or transition text before or after the JSON block. Go directly from the end of your narrative text to the <insights> tag. Do not write any text after the </insights> tag.";

                    string userPrompt = 
                        $"User Name: {userName}\n" +
                        $"Current Time: {DateTime.Now:f}\n\n" +
                        $"--- WEATHER DATA ---\n" +
                        $"Condition: {data.WeatherCondition} (Temp: {data.WeatherTemp}°C)\n" +
                        $"Hourly Forecast (next 8 hours):\n{hourlyWeatherDetails}\n" +
                        $"5-Day Forecast:\n{fiveDayWeatherDetails}\n\n" +
                        $"--- HEALTH DATA ---\n" +
                        $"Steps Today: {data.HealthSteps}\n" +
                        $"Sleep Last Night: {data.HealthSleepHours:F1} hours\n" +
                        $"Average Heart Rate: {data.HealthAvgHr} BPM\n" +
                        (data.HealthWeight > 0 ? $"Weight: {data.HealthWeight:F1} kg\n" : "") +
                        (data.HealthActiveEnergy > 0 ? $"Active Energy Burned: {data.HealthActiveEnergy:F0} kcal\n" : "") +
                        (data.HealthHrv > 0 ? $"Heart Rate Variability (HRV): {data.HealthHrv:F0} ms\n" : "") +
                        (data.HealthBpSystolic > 0 && data.HealthBpDiastolic > 0 ? $"Blood Pressure: {data.HealthBpSystolic:F0}/{data.HealthBpDiastolic:F0} mmHg\n" : "") +
                        (data.HealthSpO2 > 0 ? $"Oxygen Saturation (SpO2): {data.HealthSpO2:F1}%\n" : "") + "\n" +
                        $"--- FINANCE DATA ---\n" +
                        (data.HasLedgerData 
                            ? $"Net Worth: {data.NetWorth:C0}\nWatchlist stocks info: {watchlistDetails}\n" 
                            : "Ledger status: UNINITIALIZED (No accounts or transactions logged yet. Do not mention a $0 net worth; suggest setting up their ledger or adding their first account/transaction instead)\n") + "\n" +
                        $"--- HABITS DATA ---\n" +
                        $"Water target: {data.HabitsWaterGoal:F0} ml, Drank today: {data.HabitsWaterProgress:F0} ml\n" +
                        (data.HabitsSmokesGoal > 0 || data.HabitsSmokesProgress > 0 
                            ? $"Cigarettes limit/baseline: {data.HabitsSmokesGoal:F0} today, Smoked today: {data.HabitsSmokesProgress:F0}\n"
                             : "") + "\n" +
                        $"--- RECENT USER BEHAVIOR TELEMETRY (Last 7 Days) ---\n" +
                        $"{behaviorSummary}";

                    Console.WriteLine($"[SmartBriefingService] Calling GenerateResponseAsync...");
                    string responseText = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                    Console.WriteLine($"[SmartBriefingService] Response received. Length: {responseText?.Length ?? 0}");
                    Console.WriteLine($"[SmartBriefingService] Raw Response:\n{responseText}\n[End Raw Response]");
                    
                    // Parse insights tag
                    string cleanBriefingText = responseText;
                    int startIndex = responseText.IndexOf("<insights>");
                    int endIndex = responseText.IndexOf("</insights>");
                    string jsonContent = "";
                    
                    if (startIndex >= 0)
                    {
                        if (endIndex > startIndex)
                        {
                            jsonContent = responseText.Substring(startIndex + 10, endIndex - (startIndex + 10)).Trim();
                        }
                        else
                        {
                            jsonContent = responseText.Substring(startIndex + 10).Trim();
                        }
                        
                        // Strip any potential trailing tag if it was partially generated or present
                        if (jsonContent.EndsWith("</insights>"))
                        {
                            jsonContent = jsonContent.Substring(0, jsonContent.Length - 11).Trim();
                        }
                        else if (jsonContent.Contains("</insights>"))
                        {
                            int idx = jsonContent.IndexOf("</insights>");
                            jsonContent = jsonContent.Substring(0, idx).Trim();
                        }

                        Console.WriteLine($"[SmartBriefingService] Extracted JSON content:\n{jsonContent}\n[End JSON content]");
                        cleanBriefingText = responseText.Substring(0, startIndex).Trim();
                        
                        // Clean up trailing metadata transition lines (e.g. "Here is the JSON block...", "Below are the insights...")
                        var lines = cleanBriefingText.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None).ToList();
                        while (lines.Count > 0)
                        {
                            var lastLine = lines.Last().Trim();
                            if (string.IsNullOrWhiteSpace(lastLine))
                            {
                                lines.RemoveAt(lines.Count - 1);
                                continue;
                            }
                            
                            if (lastLine.Contains("json", StringComparison.OrdinalIgnoreCase) || 
                                lastLine.Contains("insights", StringComparison.OrdinalIgnoreCase) || 
                                lastLine.Contains("enclosed", StringComparison.OrdinalIgnoreCase) ||
                                lastLine.Contains("below", StringComparison.OrdinalIgnoreCase) ||
                                lastLine.Contains("<insights", StringComparison.OrdinalIgnoreCase))
                            {
                                lines.RemoveAt(lines.Count - 1);
                            }
                            else
                            {
                                break;
                            }
                        }
                        cleanBriefingText = string.Join("\n", lines).Trim();
                        
                        bool parsed = false;
                        try
                        {
                            using var doc = System.Text.Json.JsonDocument.Parse(jsonContent);
                            var root = doc.RootElement;
                            if (root.TryGetProperty("weatherAdvice", out var w)) weatherAdvice = w.GetString() ?? "";
                            if (root.TryGetProperty("healthAdvice", out var h)) healthAdvice = h.GetString() ?? "";
                            if (root.TryGetProperty("financeAdvice", out var f)) financeAdvice = f.GetString() ?? "";
                            if (root.TryGetProperty("habitsAdvice", out var hb)) habitsAdvice = hb.GetString() ?? "";
                            parsed = true;
                        }
                        catch
                        {
                            Console.WriteLine("[SmartBriefingService] JSON parsing failed. Attempting robust line-based key-value extraction for insights.");
                        }

                        if (!parsed)
                        {
                            try
                            {
                                var jsonLines = jsonContent.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                                foreach (var line in jsonLines)
                                {
                                    int colonIdx = line.IndexOf(':');
                                    if (colonIdx > 0)
                                    {
                                        string key = line.Substring(0, colonIdx).Trim(' ', '"', '\'', '{', '}', ',', '\t');
                                        string val = line.Substring(colonIdx + 1).Trim(' ', '"', '\'', '{', '}', ',', '\t');
                                        
                                        if (key.Equals("weatherAdvice", StringComparison.OrdinalIgnoreCase)) weatherAdvice = val;
                                        else if (key.Equals("healthAdvice", StringComparison.OrdinalIgnoreCase)) healthAdvice = val;
                                        else if (key.Equals("financeAdvice", StringComparison.OrdinalIgnoreCase)) financeAdvice = val;
                                        else if (key.Equals("habitsAdvice", StringComparison.OrdinalIgnoreCase)) habitsAdvice = val;
                                    }
                                }
                            }
                            catch (Exception ex)
                            {
                                Console.WriteLine($"[SmartBriefingService] Robust parsing also failed: {ex.Message}");
                            }
                        }
                    }
                    
                    data.IntroText = "";
                    data.BriefingText = cleanBriefingText;
                    data.OutroText = "Have a highly productive day!";
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[SmartBriefingService] AI Generation failed: {ex.Message}. Falling back to template.");
                    try
                    {
                        var settings = SettingsService.Load();
                        settings.LastExecutionExplanation = $"AI Generation failed: {ex.Message}\n{ex.StackTrace}";
                        SettingsService.Save(settings);
                    }
                    catch { }

                    data.IntroText = "";
                    data.BriefingText = fallbackBriefing;
                    data.OutroText = "Have a highly productive day!";
                }
            }
            else
            {
                data.IntroText = "";
                data.BriefingText = fallbackBriefing;
                data.OutroText = "Have a highly productive day!";
            }

            // Apply rule-based fallbacks for advice if they are empty
            if (string.IsNullOrEmpty(weatherAdvice))
            {
                if (data.WeatherCondition.Contains("rain", StringComparison.OrdinalIgnoreCase) || data.WeatherCondition.Contains("drizzle", StringComparison.OrdinalIgnoreCase))
                    weatherAdvice = "Rain expected today, keep an umbrella handy.";
                else if (data.WeatherTemp < 10)
                    weatherAdvice = "It's cold today, dress in warm layers.";
                else
                    weatherAdvice = "Weather looks pleasant for outdoor activities.";
            }

            if (string.IsNullOrEmpty(healthAdvice))
            {
                if (data.HealthSteps < 4000)
                    healthAdvice = "You are behind on steps today. Let's aim to reach your target baseline!";
                else if (data.HealthSleepHours < 7 && data.HealthSleepHours > 0)
                    healthAdvice = "You got less than 7 hours of sleep. Prioritize rest and recovery.";
                else
                    healthAdvice = "Vitals are looking good. Keep up the active baseline!";
            }

            if (string.IsNullOrEmpty(financeAdvice))
            {
                if (!data.HasLedgerData)
                    financeAdvice = "Your ledger is empty. Tap the widget to configure your accounts!";
                else
                    financeAdvice = "Watchlist is active. Markets are showing movements.";
            }

            if (string.IsNullOrEmpty(habitsAdvice))
            {
                if (data.HabitsWaterProgress < data.HabitsWaterGoal)
                    habitsAdvice = $"Hydration: you need {(data.HabitsWaterGoal - data.HabitsWaterProgress):F0} ml more water today.";
                else if (data.HabitsSmokesProgress > data.HabitsSmokesGoal && data.HabitsSmokesGoal > 0)
                    habitsAdvice = "Smokes limit exceeded! Try to resist logging any more units today.";
                else
                    habitsAdvice = "Habits are on track today. Stay consistent!";
            }

            data.WeatherAdvice = weatherAdvice;
            data.HealthAdvice = healthAdvice;
            data.FinanceAdvice = financeAdvice;
            data.HabitsAdvice = habitsAdvice;

            return data;
        }
    }
}
