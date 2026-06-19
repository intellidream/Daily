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
        public string HealthHabitsBriefing { get; set; } = string.Empty;
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

                foreach (var sel in selected)
                {
                    data.NewsRecommendations.Add(new NewsRecommendationData
                    {
                        Title = sel.Item.Title,
                        Source = sel.Item.PublicationName ?? "RSS Feed",
                        Reason = sel.Reason,
                        RssItem = sel.Item
                    });
                }

                // Populate TopNewsHeadlines with exactly the 5 newest headlines using Round-Robin selection
                var roundRobinHeadlines = await ExtractRoundRobinHeadlinesAsync();
                foreach (var h in roundRobinHeadlines)
                {
                    data.TopNewsHeadlines.Add($"- {h.Title} (Source: {h.PublicationName ?? "Feed"})");
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

            string fallbackBriefing = $"{weatherSentence} {healthSentence}\n\n{calendarSummary} {todoSummary}\n\n{financeSentence} {habitsSentence}\n\nLastly, we found a couple of interesting articles in your feed you might like: \"{(data.NewsRecommendations.Count > 0 ? data.NewsRecommendations[0].Title : "No recommendations")}\" from {(data.NewsRecommendations.Count > 0 ? data.NewsRecommendations[0].Source : "N/A")}, and \"{(data.NewsRecommendations.Count > 1 ? data.NewsRecommendations[1].Title : "No recommendations")}\" from {(data.NewsRecommendations.Count > 1 ? data.NewsRecommendations[1].Source : "N/A")}.";
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

            // Generate slots in parallel
            var weatherTask = Task.Run(async () =>
            {
                string fallback = string.IsNullOrEmpty(metrics.WeatherSummary) 
                    ? "Weather information is currently unavailable." 
                    : metrics.WeatherSummary;

                bool isWeatherEmpty = metrics.WeatherTemp == 0 && string.IsNullOrEmpty(metrics.WeatherCondition);
                if (isWeatherEmpty)
                {
                    return "Weather information is currently unavailable.";
                }

                if (useAi)
                {
                    try
                    {
                        string systemPrompt = "System: You are a weather briefing assistant. Summarize today's weather in one concise, natural, and encouraging sentence.";
                        string userPrompt = $"Weather: {metrics.WeatherCondition}, {metrics.WeatherTemp}°C. Hourly forecast:\n{metrics.WeatherHourlyDetails}\n5-day forecast:\n{metrics.WeatherFiveDayDetails}";
                        string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                        if (!string.IsNullOrWhiteSpace(result))
                        {
                            return result.Trim();
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] Weather AI Prompt Error: {ex.Message}");
                    }
                }
                return fallback;
            });

            var calendarTask = Task.Run(async () =>
            {
                if (metrics.CalendarEventsToday == null || metrics.CalendarEventsToday.Count == 0)
                {
                    return "Your calendar is clear today. Enjoy your free time!";
                }

                var sbEvents = new StringBuilder();
                foreach (var ev in metrics.CalendarEventsToday)
                {
                    string timeStr = ev.IsAllDay ? "All Day" : $"{ev.Start.ToLocalTime():t} - {ev.End.ToLocalTime():t}";
                    sbEvents.AppendLine($"- {ev.Title} ({timeStr}){(string.IsNullOrEmpty(ev.Location) ? "" : $" at {ev.Location}")}");
                }
                string eventsList = sbEvents.ToString();

                string fallback = $"You have {metrics.CalendarEventsToday.Count} calendar event(s) scheduled for today: " +
                                  string.Join(", ", metrics.CalendarEventsToday.Select(e => $"{e.Title} at {(e.IsAllDay ? "All Day" : e.Start.ToLocalTime().ToString("t"))}")) + ".";

                if (useAi)
                {
                    try
                    {
                        string systemPrompt = "System: Summarize the user's calendar events for today into one concise sentence.";
                        string userPrompt = $"Events:\n{eventsList}";
                        string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                        if (!string.IsNullOrWhiteSpace(result))
                        {
                            return result.Trim();
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] Calendar AI Prompt Error: {ex.Message}");
                    }
                }
                return fallback;
            });

            var todosTask = Task.Run(async () =>
            {
                if (metrics.ActiveTodos == null || metrics.ActiveTodos.Count == 0)
                {
                    return "You have no pending tasks today.";
                }

                var sbTodos = new StringBuilder();
                foreach (var td in metrics.ActiveTodos.OrderByDescending(t => t.Importance?.ToLower() == "high"))
                {
                    string dueStr = td.DueDate.HasValue ? $"Due: {td.DueDate.Value.ToLocalTime():d}" : "No due date";
                    sbTodos.AppendLine($"- {td.Title} ({dueStr}, Priority: {td.Importance}) - Notes: {td.Notes}");
                }
                string todosList = sbTodos.ToString();

                string fallback = $"You have {metrics.ActiveTodos.Count} active task(s) on your agenda: " +
                                  string.Join(", ", metrics.ActiveTodos.Take(3).Select(t => t.Title)) + (metrics.ActiveTodos.Count > 3 ? "..." : "") + ".";

                if (useAi)
                {
                    try
                    {
                        string systemPrompt = "System: Summarize the user's active tasks and priorities into one concise sentence focusing on urgent ones.";
                        string userPrompt = $"Tasks:\n{todosList}";
                        string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                        if (!string.IsNullOrWhiteSpace(result))
                        {
                            return result.Trim();
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] Todos AI Prompt Error: {ex.Message}");
                    }
                }
                return fallback;
            });

            var healthTask = Task.Run(async () =>
            {
                bool isHealthEmpty = metrics.HealthSteps == 0 && metrics.HealthSleepHours == 0 &&
                                     metrics.HabitsWaterProgress == 0 && metrics.HabitsSmokesProgress == 0;
                if (isHealthEmpty)
                {
                    return "Keep moving and remember to stay hydrated today!";
                }

                string fallback = $"You've taken {metrics.HealthSteps:N0} steps, slept {metrics.HealthSleepHours:F1} hours, and drank {metrics.HabitsWaterProgress:F0}/{metrics.HabitsWaterGoal:F0} ml of water.";
                if (metrics.HabitsSmokesGoal > 0 || metrics.HabitsSmokesProgress > 0)
                {
                    fallback += $" Smoked {metrics.HabitsSmokesProgress} out of limit {metrics.HabitsSmokesGoal}.";
                }

                if (useAi)
                {
                    try
                    {
                        string systemPrompt = "System: Write exactly one concise, encouraging sentence analyzing the user's health metrics.\n" +
                                               "Rules:\n" +
                                               "- You MUST explicitly reference steps as \"steps\", sleep as \"hours of sleep\", and water as \"ml of water\". Never output numbers without their units.\n" +
                                               "- Assess the step count realistically: under 5,000 steps is low, while 10,000 steps is the target. If steps are low (e.g. 2,000 steps), do not congratulate the user; instead, gently encourage them to walk more.\n" +
                                               "- Assess sleep duration realistically: under 7 hours of sleep is low.\n" +
                                               "- Treat smoking cigarettes as a negative habit to reduce or eliminate. If the user smoked, do not congratulate them; encourage reduction or staying below their daily limit.";
                        
                        string userPrompt = $"Here are the user's health metrics for today:\n" +
                                            $"- Steps taken: {metrics.HealthSteps} steps (Target: 10,000 steps)\n" +
                                            $"- Sleep last night: {metrics.HealthSleepHours:F1} hours (Target: 7-8 hours)\n" +
                                            $"- Water intake: {metrics.HabitsWaterProgress:F0} ml (Goal: {metrics.HabitsWaterGoal:F0} ml)\n" +
                                            $"- Cigarettes smoked: {metrics.HabitsSmokesProgress:F0} cigarettes (Limit: {metrics.HabitsSmokesGoal:F0} cigarettes)";

                        string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                        if (!string.IsNullOrWhiteSpace(result))
                        {
                            return result.Trim();
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] Health AI Prompt Error: {ex.Message}");
                    }
                }
                return fallback;
            });

            var financeTask = Task.Run(async () =>
            {
                if (!metrics.HasLedgerData)
                {
                    return "You haven't set up your financial ledger yet. Add accounts to start tracking your net worth!";
                }

                var sbStocks = new StringBuilder();
                foreach (var stock in metrics.WatchlistStocks)
                {
                    sbStocks.Append($"{stock.Symbol}: {stock.Price:C2} ({stock.FormattedChange}), ");
                }
                string stocksList = sbStocks.ToString().TrimEnd(',', ' ');

                string fallback = $"Your ledger net worth is looking healthy at {metrics.NetWorth:C0}.";
                if (metrics.WatchlistStocks.Count > 0)
                {
                    fallback += $" Watchlist: " + string.Join(", ", metrics.WatchlistStocks.Select(s => $"{s.Symbol} ({s.FormattedChange})")) + ".";
                }

                if (useAi)
                {
                    try
                    {
                        string systemPrompt = "System: Summarize the user's financial state into one concise sentence based on net worth and stock tickers.";
                        string userPrompt = $"Net Worth: {metrics.NetWorth:C0}. Stocks: {stocksList}";
                        string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                        if (!string.IsNullOrWhiteSpace(result))
                        {
                            return result.Trim();
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] Finance AI Prompt Error: {ex.Message}");
                    }
                }
                return fallback;
            });

            var newsTask = Task.Run(async () =>
            {
                if (metrics.TopNewsHeadlines == null || metrics.TopNewsHeadlines.Count == 0)
                {
                    return "No new articles in your feeds today.";
                }

                string headlinesList = string.Join("\n", metrics.TopNewsHeadlines);
                string fallback = "Your top headlines today: " + string.Join("; ", metrics.TopNewsHeadlines.Select(h => h.TrimStart('-', ' '))) + ".";

                if (useAi)
                {
                    try
                    {
                        string systemPrompt = "System: Summarize these 5 headlines into one concise sentence extracting the main topic.";
                        string userPrompt = $"Headlines:\n{headlinesList}";
                        string result = await _smartService.GenerateResponseAsync(systemPrompt, userPrompt);
                        if (!string.IsNullOrWhiteSpace(result))
                        {
                            return result.Trim();
                        }
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"[SmartBriefingService] News AI Prompt Error: {ex.Message}");
                    }
                }
                return fallback;
            });

            await Task.WhenAll(weatherTask, calendarTask, todosTask, healthTask, financeTask, newsTask);

            // Assign values to slots
            metrics.WeatherBriefing = weatherTask.Result;
            metrics.CalendarBriefing = calendarTask.Result;
            metrics.TodosBriefing = todosTask.Result;
            metrics.HealthHabitsBriefing = healthTask.Result;
            metrics.FinanceBriefing = financeTask.Result;
            metrics.NewsBriefing = newsTask.Result;

            // Concatenate all 6 parts
            metrics.BriefingText = $"{metrics.WeatherBriefing}\n\n{metrics.CalendarBriefing}\n\n{metrics.TodosBriefing}\n\n{metrics.HealthHabitsBriefing}\n\n{metrics.FinanceBriefing}\n\n{metrics.NewsBriefing}";

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
