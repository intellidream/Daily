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
        public RssItem? RssItem { get; set; }
    }

    public sealed class SmartBriefingData
    {
        public string Greeting { get; set; } = string.Empty;
        public string IntroText { get; set; } = string.Empty;
        public string BriefingText { get; set; } = string.Empty;
        public string OutroText { get; set; } = string.Empty;

        // Micro-inference slots
        public string WeatherBriefing { get; set; } = string.Empty;
        public string CalendarBriefing { get; set; } = string.Empty;
        public string TodosBriefing { get; set; } = string.Empty;
        public string HealthBriefing { get; set; } = string.Empty;
        public string HabitsBriefing { get; set; } = string.Empty;
        public string FinanceBriefing { get; set; } = string.Empty;
        public string NewsBriefing { get; set; } = string.Empty;
        
        // Weather
        public string WeatherSummary { get; set; } = string.Empty;
        public double WeatherTemp { get; set; }
        public string WeatherCondition { get; set; } = string.Empty;
        public List<ForecastDayData> WeatherForecast { get; set; } = new();

        // Health
        public int HealthSteps { get; set; }
        public double HealthSleepHours { get; set; }
        public double HealthSleepDeep { get; set; }
        public double HealthSleepLight { get; set; }
        public double HealthSleepRem { get; set; }
        public double HealthSleepAwake { get; set; }
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

        // Calendars & Todos & News Headlines
        public List<LocalCalendarEvent> CalendarEventsToday { get; set; } = new();
        public List<LocalCalendarTodo> ActiveTodos { get; set; } = new();
        public List<string> TopNewsHeadlines { get; set; } = new();

        // Weather Details
        public string WeatherHourlyDetails { get; set; } = string.Empty;
        public string WeatherFiveDayDetails { get; set; } = string.Empty;

        // Caching metadata
        public bool WasRegenerated { get; set; }
        public string RawContext { get; set; } = string.Empty;
    }

    public sealed class UserData
    {
        public string UserName { get; set; } = string.Empty;
        public SmartBriefingData Metrics { get; set; } = new();
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
        private readonly ICalendarService? _calendarService;
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
                _calendarService = App.Current.Services.GetService(typeof(ICalendarService)) as ICalendarService;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Init Error: {ex.Message}");
            }
        }

        public async Task<List<RssItem>> ExtractRoundRobinHeadlinesAsync()
        {
            if (_rssFeedService == null || _rssFeedService.Feeds == null || _rssFeedService.Feeds.Count == 0)
            {
                return new List<RssItem>();
            }

            var tasks = _rssFeedService.Feeds.Select(async feed =>
            {
                try
                {
                    var items = await _rssFeedService.FetchFeedItemsAsync(feed);
                    return items ?? new List<RssItem>();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[SmartBriefingService News Extract] Error fetching {feed.Name}: {ex.Message}");
                    return new List<RssItem>();
                }
            }).ToList();

            var results = await Task.WhenAll(tasks);
            var displayItems = new List<RssItem>();

            int maxItemsPerFeed = results.Any() ? results.Max(r => r.Count) : 0;
            for (int i = 0; i < maxItemsPerFeed; i++)
            {
                foreach (var items in results)
                {
                    if (i < items.Count)
                    {
                        displayItems.Add(items[i]);
                    }
                }
                if (displayItems.Count >= 15) // Stop early to avoid taking too many
                    break;
            }

            return displayItems.OrderByDescending(i => i.PublishDate).Take(5).ToList();
        }

        public async Task<SmartBriefingData> GenerateBriefingDataAsync(string userName)
        {
            var data = await LoadBriefingMetricsAsync(userName);
            var userData = new UserData { UserName = userName, Metrics = data };
            return await GenerateSmartBriefingAsync(userData);
        }

        public async Task<SmartBriefingData> LoadBriefingMetricsAsync(string userName, bool onlyLocal = false)
        {
            var data = new SmartBriefingData();
            
            // 1. Time-of-day Greeting
            int hour = DateTime.Now.Hour;
            string greetingBase = "Good evening";
            if (hour >= 5 && hour < 12) greetingBase = "Good morning";
            else if (hour >= 12 && hour < 17) greetingBase = "Good afternoon";
            
            data.Greeting = $"{greetingBase}, {userName}!";

            // Kick off all background operations in parallel tasks
            var coordsTask = !onlyLocal ? _locationService.GetCurrentCoordinatesAsync() : Task.FromResult<(double Latitude, double Longitude)?>(null);
            var stepsTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.Steps) : Task.FromResult<VitalMetric?>(null);
            var sleepTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.SleepDuration) : Task.FromResult<VitalMetric?>(null);
            var hrTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.HeartRate) : Task.FromResult<VitalMetric?>(null);
            var weightTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.Weight) : Task.FromResult<VitalMetric?>(null);
            var activeEnergyTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.ActiveEnergy) : Task.FromResult<VitalMetric?>(null);
            var sleepDeepTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.SleepDeep) : Task.FromResult<VitalMetric?>(null);
            var sleepLightTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.SleepLight) : Task.FromResult<VitalMetric?>(null);
            var sleepRemTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.SleepREM) : Task.FromResult<VitalMetric?>(null);
            var sleepAwakeTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.SleepAwake) : Task.FromResult<VitalMetric?>(null);
            var hrvTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.HeartRateVariabilitySDNN) : Task.FromResult<VitalMetric?>(null);
            var bpSystolicTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.BloodPressureSystolic) : Task.FromResult<VitalMetric?>(null);
            var bpDiastolicTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.BloodPressureDiastolic) : Task.FromResult<VitalMetric?>(null);
            var oxygenTask = _healthService != null ? _healthService.GetLatestMetricAsync(VitalType.OxygenSaturation) : Task.FromResult<VitalMetric?>(null);

            var netWorthTask = _financesService != null ? _financesService.GetNetWorthAsync() : Task.FromResult(0m);
            var symbolsTask = _financesService != null ? _financesService.GetWatchlistSymbolsAsync() : Task.FromResult<List<string>?>(null);
            
            var hydrationTask = _habitsService != null ? _habitsService.GetDailyProgressAsync("water", DateTime.Today) : Task.FromResult(0.0);
            var smokesTask = _habitsService != null ? _habitsService.GetDailyProgressAsync("smokes", DateTime.Today) : Task.FromResult(0.0);
            var waterGoalTask = _habitsService != null ? _habitsService.GetGoalAsync("water") : Task.FromResult<HabitGoal?>(null);

            var start = DateTime.Today;
            var end = DateTime.Today.AddDays(1).AddTicks(-1);
            var calendarTask = _calendarService != null ? _calendarService.GetCachedEventsAsync(start, end) : Task.FromResult(new List<LocalCalendarEvent>());
            var todosTask = _calendarService != null ? _calendarService.GetCachedTodosAsync() : Task.FromResult(new List<LocalCalendarTodo>());

            // 2. Weather Aggregation
            double temp = 21.5;
            string condition = "sunny";
            string weatherSentence = "The weather today looks warm and sunny, perfect for outdoor activities.";
            string hourlyWeatherDetails = "No hourly data available.";
            string fiveDayWeatherDetails = "No 5-day forecast available.";
            
            if (!onlyLocal)
            {
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
                                string iconCode = day.IconCode ?? "";
                                
                                if (iconCode.StartsWith("01"))
                                {
                                    if (iconCode.EndsWith("n"))
                                    {
                                        iconGlyph = "\uE708"; // Moon (QuietHours)
                                        colorHex = "#90CAF9"; // soft blue
                                    }
                                    else
                                    {
                                        iconGlyph = "\uE706"; // Sun (Brightness)
                                        colorHex = "#FF9800"; // orange
                                    }
                                }
                                else if (iconCode.StartsWith("02"))
                                {
                                    iconGlyph = "\uE753"; // Cloud (using color to differentiate partly cloudy)
                                    if (iconCode.EndsWith("n"))
                                    {
                                        colorHex = "#90CAF9"; // dim blue-grey night cloud
                                    }
                                    else
                                    {
                                        colorHex = "#FFE082"; // warm amber sun-kissed day cloud
                                    }
                                }
                                else if (iconCode.StartsWith("03") || iconCode.StartsWith("04"))
                                {
                                    iconGlyph = "\uE753"; // Cloud
                                    colorHex = "#B0BEC5"; // grey-blue
                                }
                                else if (iconCode.StartsWith("09") || iconCode.StartsWith("10"))
                                {
                                    iconGlyph = "\uEB42"; // Drop (Rain/Showers)
                                    colorHex = "#2196F3"; // blue
                                }
                                else if (iconCode.StartsWith("11"))
                                {
                                    iconGlyph = "\uE945"; // LightningBolt
                                    colorHex = "#FFEB3B"; // bright yellow
                                }
                                else if (iconCode.StartsWith("13"))
                                {
                                    iconGlyph = "\uEA38"; // Asterisk (Snowflake)
                                    colorHex = "#80DEEA"; // ice blue
                                }
                                else if (iconCode.StartsWith("50"))
                                {
                                    iconGlyph = "\uE81E"; // MapLayers (Mist/Fog/Haze)
                                    colorHex = "#CFD8DC"; // misty grey
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
            }

            if (!onlyLocal)
            {
                // Fallback weather forecast if empty
                if (data.WeatherForecast.Count == 0)
                {
                    data.WeatherForecast.Add(new ForecastDayData { DayName = "Tomorrow", Temp = temp + 1, Icon = "\uE706", ColorHex = "#FF9800" });
                    data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(2).ToString("dddd"), Temp = temp - 1, Icon = "\uE753", ColorHex = "#B0BEC5" });
                    data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(3).ToString("dddd"), Temp = temp, Icon = "\uEB42", ColorHex = "#2196F3" });
                    data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(4).ToString("dddd"), Temp = temp + 2, Icon = "\uE706", ColorHex = "#FF9800" });
                    data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(5).ToString("dddd"), Temp = temp + 1, Icon = "\uE753", ColorHex = "#B0BEC5" });
                }

                data.WeatherTemp = temp;
                data.WeatherCondition = condition;
                data.WeatherSummary = weatherSentence;
            }


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
                await Task.WhenAll(stepsTask, sleepTask, hrTask, weightTask, activeEnergyTask, hrvTask, bpSystolicTask, bpDiastolicTask, oxygenTask, sleepDeepTask, sleepLightTask, sleepRemTask, sleepAwakeTask);
                
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

                var deepMetric = sleepDeepTask.Result;
                if (deepMetric != null) data.HealthSleepDeep = deepMetric.Value;

                var lightMetric = sleepLightTask.Result;
                if (lightMetric != null) data.HealthSleepLight = lightMetric.Value;

                var remMetric = sleepRemTask.Result;
                if (remMetric != null) data.HealthSleepRem = remMetric.Value;

                var awakeMetric = sleepAwakeTask.Result;
                if (awakeMetric != null) data.HealthSleepAwake = awakeMetric.Value;
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
                if (!onlyLocal && symbols != null && symbols.Count > 0)
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

            if (!onlyLocal)
            {
                // Fallback stocks if empty
                if (data.WatchlistStocks.Count == 0)
                {
                    data.WatchlistStocks.Add(new StockBriefingData { Symbol = "MSFT", Price = 421.90m, PercentChange = 1.45m });
                    data.WatchlistStocks.Add(new StockBriefingData { Symbol = "AAPL", Price = 189.84m, PercentChange = -0.32m });
                }
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

            // 5.1 Calendars & Todos Aggregation
            try
            {
                var todayEvents = await calendarTask;
                data.CalendarEventsToday = todayEvents ?? new List<LocalCalendarEvent>();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Calendar Load Error: {ex.Message}");
            }

            try
            {
                var allTodos = await todosTask;
                data.ActiveTodos = allTodos?.Where(t => !t.IsCompleted).ToList() ?? new List<LocalCalendarTodo>();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] Todos Load Error: {ex.Message}");
            }

            string calendarSummary = "";
            if (data.CalendarEventsToday.Count > 0)
            {
                calendarSummary = $"You have {data.CalendarEventsToday.Count} calendar event(s) scheduled for today.";
            }
            else
            {
                calendarSummary = "Your calendar is clear for today.";
            }

            string todoSummary = "";
            if (data.ActiveTodos.Count > 0)
            {
                var highPriority = data.ActiveTodos.Count(t => t.Importance?.ToLower() == "high");
                if (highPriority > 0)
                {
                    todoSummary = $"You have {data.ActiveTodos.Count} active task(s) on your agenda, including {highPriority} high priority task(s).";
                }
                else
                {
                    todoSummary = $"You have {data.ActiveTodos.Count} active task(s) on your agenda.";
                }
            }
            else
            {
                todoSummary = "You have no pending tasks today.";
            }


            // 6. News AI Recommendations with Source Diversity & Interest Matching
            if (!onlyLocal && _rssFeedService != null && _rssFeedService.Feeds != null && _rssFeedService.Feeds.Count > 0)
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

                // Populate TopNewsHeadlines and NewsRecommendations with exactly the 5 newest headlines using Round-Robin selection
                var roundRobinHeadlines = await ExtractRoundRobinHeadlinesAsync();
                data.NewsRecommendations.Clear();
                foreach (var h in roundRobinHeadlines)
                {
                    data.TopNewsHeadlines.Add($"- {h.Title} (Source: {h.PublicationName ?? "Feed"})");
                    data.NewsRecommendations.Add(new NewsRecommendationData
                    {
                        Title = h.Title,
                        Source = h.PublicationName ?? "RSS Feed",
                        Reason = $"Top headline from {h.PublicationName ?? "Feed"}",
                        RssItem = h
                    });
                }
            }

            if (!onlyLocal)
            {
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
            }

            // 7. Generate AI narrative or fallback
            data.WeatherHourlyDetails = hourlyWeatherDetails;
            data.WeatherFiveDayDetails = fiveDayWeatherDetails;

            string wBrief = weatherSentence;
            string cBrief = calendarSummary;
            string tBrief = todoSummary;
            string hBrief = healthSentence;
            string fBrief = financeSentence;
            string hbBrief = habitsSentence;
            
            // Combine health and habits
            string healthHabitsCombined = $"{hBrief} {hbBrief}".Trim();
            
            string nBrief = $"We found a couple of interesting articles in your feed you might like: \"{(data.NewsRecommendations.Count > 0 ? data.NewsRecommendations[0].Title : "No recommendations")}\" from {(data.NewsRecommendations.Count > 0 ? data.NewsRecommendations[0].Source : "N/A")}, and \"{(data.NewsRecommendations.Count > 1 ? data.NewsRecommendations[1].Title : "No recommendations")}\" from {(data.NewsRecommendations.Count > 1 ? data.NewsRecommendations[1].Source : "N/A")}.";
            string indentedBrief = nBrief.Replace("\n", "\n    ");

            string fallbackBriefing = $"\uE706  {wBrief}\n\n\uE787  {cBrief}\n\n\uE73A  {tBrief}\n\n\uEC92  {healthHabitsCombined}\n\n\uE8C7  {fBrief}\n\n\uE7C3  Headlines Summary:\n    _\"{indentedBrief}\"_";
            data.BriefingText = fallbackBriefing;
            data.IntroText = "";
            data.OutroText = "Have a highly productive day!";
            return data;
        }

        public async Task<SmartBriefingData> GenerateSmartBriefingAsync(UserData data)
        {
            if (data == null) throw new ArgumentNullException(nameof(data));

            LlmDebugLogger.Clear();

            var metrics = data.Metrics;
            string userName = data.UserName;

            bool useAi = false;
            try
            {
                useAi = await _smartService.IsModelReadyAsync();
                if (useAi)
                {
                    await _smartService.InitializeAsync();
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[SmartBriefingService] AI initialization error: {ex.Message}");
            }

            // Fallback generation logic (used if AI is disabled or fails)
            string weatherFallback = string.IsNullOrEmpty(metrics.WeatherSummary) ? "Weather information is currently unavailable." : metrics.WeatherSummary;
            if (metrics.WeatherTemp == 0 && string.IsNullOrEmpty(metrics.WeatherCondition)) weatherFallback = "Weather information is currently unavailable.";
            
            var now = DateTime.Now;
            var upcomingEvents = metrics.CalendarEventsToday
                .Where(e => e.IsAllDay || e.End.ToLocalTime() >= now)
                .Where(e => e.Start.ToLocalTime() <= now.AddDays(7))
                .OrderBy(e => e.IsAllDay ? 0 : 1).ThenBy(e => e.Start).ToList();
            string calendarFallback = upcomingEvents.Count == 0 ? "Your calendar is clear. Enjoy your free time!" : $"You have {upcomingEvents.Count} upcoming calendar events scheduled.";

            var upcomingTodos = metrics.ActiveTodos
                .Where(t => !t.DueDate.HasValue || (t.DueDate.Value.ToLocalTime() >= now && t.DueDate.Value.ToLocalTime() <= now.AddDays(7)))
                .OrderByDescending(t => t.Importance?.ToLower() == "high").ThenBy(t => t.DueDate ?? DateTime.MaxValue).ToList();
            string todosFallback = "You have no pending tasks or notes.";
            if (upcomingTodos.Count > 0)
            {
                var titles = upcomingTodos.Take(5).Select(t => t.Title).ToList();
                todosFallback = $"You have {upcomingTodos.Count} active tasks on your agenda: {string.Join(", ", titles)}" + (upcomingTodos.Count > 5 ? $" and {upcomingTodos.Count - 5} more." : "");
            }

            string healthFallback = (metrics.HealthSteps == 0 && metrics.HealthSleepHours == 0) ? "Keep moving and stay active today!" : $"You've taken {metrics.HealthSteps:N0} steps, slept {metrics.HealthSleepHours:F1} hours.";
            
            string habitsFallback = (metrics.HabitsWaterProgress == 0 && metrics.HabitsSmokesProgress == 0) ? "Remember to track your daily habits and stay hydrated!" : $"You drank {metrics.HabitsWaterProgress:F0}/{metrics.HabitsWaterGoal:F0} ml of water.";
            if (metrics.HabitsSmokesGoal > 0 || metrics.HabitsSmokesProgress > 0) habitsFallback += $" Smoked {metrics.HabitsSmokesProgress} out of limit {metrics.HabitsSmokesGoal}.";

            string financeFallback = "You haven't set up your financial ledger yet. Add accounts to start tracking your net worth!";
            if (metrics.HasLedgerData)
            {
                financeFallback = $"Your ledger net worth is looking healthy at {metrics.NetWorth:C0}.";
                if (metrics.WatchlistStocks.Count > 0) financeFallback += $" Watchlist: " + string.Join(", ", metrics.WatchlistStocks.Select(s => $"{s.Symbol} ({s.FormattedChange})")) + ".";
            }

            string newsFallback = "No new articles in your feeds today.";
            if (metrics.TopNewsHeadlines != null && metrics.TopNewsHeadlines.Count > 0)
            {
                var top5 = metrics.TopNewsHeadlines.Take(5).ToList();
                newsFallback = "Your top headlines today: " + string.Join("; ", top5.Select(h => h.TrimStart('-', ' '))) + ".";
            }

            string wBrief = weatherFallback;
            string cBrief = calendarFallback;
            string tBrief = todosFallback;
            string hBrief = healthFallback;
            string hbBrief = habitsFallback;
            string fBrief = financeFallback;
            string nBrief = newsFallback;

            if (useAi)
            {
                // Trimming Strategy: Cap events, todos, and news text lengths.
                var sbEvents = new StringBuilder();
                foreach (var ev in upcomingEvents.Take(5)) // Max 5 events
                {
                    string timeStr = ev.IsAllDay ? "All Day" : $"{ev.Start.ToLocalTime():t} - {ev.End.ToLocalTime():t}";
                    string titleStr = ev.Title.Length > 50 ? ev.Title.Substring(0, 47) + "..." : ev.Title;
                    sbEvents.AppendLine($"- {titleStr} ({timeStr})");
                }
                string eventsList = sbEvents.Length > 0 ? sbEvents.ToString() : "None";

                var sbTodos = new StringBuilder();
                foreach (var t in upcomingTodos.Take(5)) // Max 5 tasks
                {
                    string titleStr = t.Title.Length > 50 ? t.Title.Substring(0, 47) + "..." : t.Title;
                    sbTodos.AppendLine($"- {titleStr}");
                }
                string todosList = sbTodos.Length > 0 ? sbTodos.ToString() : "None";

                var sbNews = new StringBuilder();
                if (metrics.TopNewsHeadlines != null)
                {
                    foreach (var h in metrics.TopNewsHeadlines.Take(3)) // Max 3 news headlines for AI context safety
                    {
                        string headlineStr = h.Length > 100 ? h.Substring(0, 97) + "..." : h;
                        sbNews.AppendLine(headlineStr);
                    }
                }
                string headlinesList = sbNews.Length > 0 ? sbNews.ToString() : "None";

                var sbStocks = new StringBuilder();
                foreach (var stock in metrics.WatchlistStocks)
                {
                    sbStocks.Append($"{stock.Symbol}: {stock.Price:C2} ({stock.FormattedChange}), ");
                }
                string stocksList = sbStocks.Length > 0 ? sbStocks.ToString().TrimEnd(',', ' ') : "None";

                string systemPrompt = @"Do not include any of the prompting as a formulation inside the summary. Do not salute me or get conversational, we do that separately. Do not say any other things that suggest you are prompted, talk to me naturally, using second person and/or my name!

You are an intelligent personal assistant. Review the user's daily data and write a single, natural, and highly engaging paragraph (2-3 sentences max) summarizing the day. Do not list the data points. Pick out the 2 most interesting or critical anomalies across all data points (e.g., bad weather, an important meeting, or falling behind on habits) and weave them into a conversational morning greeting.

CRITICAL INSTRUCTION: Do NOT mix up values from different categories. For example, never compare sleep hours to step targets, and never mention hydration limits when talking about finances. Keep the metrics isolated to their respective categories.

EXAMPLE RESPONSE 1 (BUSY DAY):
It looks like a clear day with a high of 31°C, perfect for outdoor activities! However, you have a busy schedule today with several high-priority tasks, so let's focus up and get them done.

EXAMPLE RESPONSE 2 (EMPTY CALENDAR/TASKS):
Expect a rainy afternoon with temperatures dropping to 15°C, so grab an umbrella. You have a completely free schedule today and no pending tasks, giving you a chance to relax and enjoy your free time!";

                string userPrompt = $"Data:\n[WEATHER]\n- Current Condition: {metrics.WeatherCondition}, Temperature is {metrics.WeatherTemp}°C.\n- Forecast: {metrics.WeatherFiveDayDetails}\n\n[FINANCES]\n- Ledger Net Worth: {metrics.NetWorth:C0}.\n- Stocks: {stocksList}\n\n[VITALS]\n- Steps taken today: {metrics.HealthSteps}. The daily step goal is 10,000 steps.\n- Hours of sleep last night: {metrics.HealthSleepHours:F1} hours.\n\n[HABITS]\n- Liquids consumed: {metrics.HabitsWaterProgress:F0} ml. The daily hydration goal is {metrics.HabitsWaterGoal:F0} ml.\n- Smokes had today: {metrics.HabitsSmokesProgress:F0}. The daily smoking limit is {metrics.HabitsSmokesGoal:F0}.\n\n[CALENDAR]\nUpcoming meetings:\n{eventsList}\n\n[TODOS]\nActive tasks:\n{todosList}\n\n[NEWS]\nTop Headlines:\n{headlinesList}";

                metrics.RawContext = userPrompt;

                // Fallback to safety trim if total length is absurdly high (unlikely, but safe)
                if (userPrompt.Length > 10000)
                {
                    userPrompt = userPrompt.Substring(0, 10000) + "... (truncated)";
                }

                try
                {
                    var sw = System.Diagnostics.Stopwatch.StartNew();
                    string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                    sw.Stop();
                    System.Diagnostics.Debug.WriteLine($"[SmartBriefing-DEBUG] CONSOLIDATED Task | Duration: {sw.ElapsedMilliseconds} ms | SysPrompt Len: {systemPrompt.Length} | UserPrompt Len: {userPrompt.Length}");

                    if (!string.IsNullOrWhiteSpace(result))
                    {
                        metrics.BriefingText = result.Trim();
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"[SmartBriefingService] Consolidated AI Prompt Error: {ex.Message}");
                }
            }

            metrics.WeatherBriefing = $"\uE706  {wBrief}";
            metrics.FinanceBriefing = $"\uE8C7  {fBrief}";
            metrics.HealthBriefing = $"\uEC92  {hBrief}";
            metrics.HabitsBriefing = $"\uE1A5  {hbBrief}";
            metrics.CalendarBriefing = $"\uE787  {cBrief}";
            metrics.TodosBriefing = $"\uE73A  {tBrief}";
            
            string indentedNews = nBrief.Replace("\n", "\n    ");
            metrics.NewsBriefing = $"\uE7C3  Headlines Summary:\n    _\"{indentedNews}\"_";

            // Concatenate all parts in the requested order: Weather, Finances, Vitals, Habits, Calendar, Todos, News
            if (string.IsNullOrEmpty(metrics.BriefingText))
            {
                metrics.BriefingText = $"{metrics.WeatherBriefing}\n\n{metrics.FinanceBriefing}\n\n{metrics.HealthBriefing}\n\n{metrics.HabitsBriefing}\n\n{metrics.CalendarBriefing}\n\n{metrics.TodosBriefing}\n\n{metrics.NewsBriefing}";
            }

            metrics.IntroText = "";
            metrics.OutroText = "Have a highly productive day!";

            // Maintain advice using rule-based fallbacks since they are extremely reliable
            string weatherAdvice = string.Empty;
            string healthAdvice = string.Empty;
            string financeAdvice = string.Empty;
            string habitsAdvice = string.Empty;

            if (metrics.WeatherCondition.Contains("rain", StringComparison.OrdinalIgnoreCase) || metrics.WeatherCondition.Contains("drizzle", StringComparison.OrdinalIgnoreCase))
                weatherAdvice = "Rain expected today, keep an umbrella handy.";
            else if (metrics.WeatherTemp < 10)
                weatherAdvice = "It's cold today, dress in warm layers.";
            else
                weatherAdvice = "Weather looks pleasant for outdoor activities.";

            if (metrics.HealthSteps < 4000)
                healthAdvice = "You are behind on steps today. Let's aim to reach your target baseline!";
            else if (metrics.HealthSleepHours < 7 && metrics.HealthSleepHours > 0)
                healthAdvice = "You got less than 7 hours of sleep. Prioritize rest and recovery.";
            else
                healthAdvice = "Vitals are looking good. Keep up the active baseline!";

            if (!metrics.HasLedgerData)
                financeAdvice = "Your ledger is empty. Tap the widget to configure your accounts!";
            else
                financeAdvice = "Watchlist is active. Markets are showing movements.";

            if (metrics.HabitsWaterProgress < metrics.HabitsWaterGoal)
                habitsAdvice = $"Hydration: you need {(metrics.HabitsWaterGoal - metrics.HabitsWaterProgress):F0} ml more water today.";
            else if (metrics.HabitsSmokesProgress > metrics.HabitsSmokesGoal && metrics.HabitsSmokesGoal > 0)
                habitsAdvice = "Smokes limit exceeded! Try to resist logging any more units today.";
            else
                habitsAdvice = "Habits are on track today. Stay consistent!";

            metrics.WeatherAdvice = weatherAdvice;
            metrics.HealthAdvice = healthAdvice;
            metrics.FinanceAdvice = financeAdvice;
            metrics.HabitsAdvice = habitsAdvice;

            return metrics;
        }
    }
}
