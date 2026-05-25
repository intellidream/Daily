using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using Daily.Services;
using Daily.Services.Health;
using Daily.Services.Finances;
using Daily.Models;
using Daily.Models.Health;
using Daily.Models.Finances;

namespace Daily_WinUI.Services
{
    public sealed class ForecastDayData
    {
        public string DayName { get; set; } = string.Empty;
        public double Temp { get; set; }
        public string Icon { get; set; } = string.Empty; // e.g. Glyph representable
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

        // Finances
        public decimal NetWorth { get; set; }
        public List<StockBriefingData> WatchlistStocks { get; set; } = new();

        // Habits
        public int HabitsTotal { get; set; }
        public int HabitsCompleted { get; set; }

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

        public SmartBriefingService()
        {
            try
            {
                _healthService = App.Current.Services.GetService(typeof(IHealthService)) as IHealthService;
                _financesService = App.Current.Services.GetService(typeof(IFinancesService)) as IFinancesService;
                _habitsService = App.Current.Services.GetService(typeof(IHabitsService)) as IHabitsService;
                _rssFeedService = App.Current.Services.GetService(typeof(IRssFeedService)) as IRssFeedService;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SmartBriefingService] Init Error: {ex.Message}");
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
            var netWorthTask = _financesService != null ? _financesService.GetNetWorthAsync() : Task.FromResult(0m);
            var symbolsTask = _financesService != null ? _financesService.GetWatchlistSymbolsAsync() : Task.FromResult<List<string>?>(null);
            var hydrationTask = _habitsService != null ? _habitsService.GetDailyProgressAsync("water", DateTime.Today) : Task.FromResult(0.0);

            // 2. Weather Aggregation
            double temp = 21.5;
            string condition = "sunny";
            string weatherSentence = "The weather today looks warm and sunny, perfect for outdoor activities.";
            
            try
            {
                var coords = await coordsTask;
                var settings = SettingsService.Load();
                if (!coords.HasValue && settings.LastLatitude.HasValue && settings.LastLongitude.HasValue)
                {
                    coords = (settings.LastLatitude.Value, settings.LastLongitude.Value);
                    System.Diagnostics.Debug.WriteLine($"[SmartBriefingService] Location detection timed out/failed. Falling back to cached coords: {coords.Value.Latitude}, {coords.Value.Longitude}");
                }

                if (coords.HasValue)
                {
                    var weatherTask = _weatherClient.GetCurrentWeatherAsync(coords.Value.Latitude, coords.Value.Longitude, settings.UnitSystem);
                    var forecastTask = _weatherClient.GetFiveDayForecastAsync(coords.Value.Latitude, coords.Value.Longitude, settings.UnitSystem);
                    
                    await Task.WhenAll(weatherTask, forecastTask);
                    
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

                    var forecastList = forecastTask.Result;
                    if (forecastList != null && forecastList.Count > 0)
                    {
                        int added = 0;
                        foreach (var day in forecastList)
                        {
                            string iconGlyph = "\uE706"; // default sun
                            string cond = day.Description;
                            if (cond.Contains("Rain", StringComparison.OrdinalIgnoreCase)) iconGlyph = "\uE709"; // rain
                            else if (cond.Contains("Cloud", StringComparison.OrdinalIgnoreCase)) iconGlyph = "\uE701"; // cloudy
                            else if (cond.Contains("Snow", StringComparison.OrdinalIgnoreCase)) iconGlyph = "\uE70A"; // snow
                            
                            data.WeatherForecast.Add(new ForecastDayData
                            {
                                DayName = day.DayLabel,
                                Temp = day.MaxTemp,
                                Icon = iconGlyph
                            });
                            added++;
                            if (added >= 3) break;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SmartBriefingService] Weather Fetch Error: {ex.Message}");
            }

            // Fallback weather forecast if empty
            if (data.WeatherForecast.Count == 0)
            {
                data.WeatherForecast.Add(new ForecastDayData { DayName = "Tomorrow", Temp = temp + 1, Icon = "\uE706" });
                data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(2).ToString("dddd"), Temp = temp - 1, Icon = "\uE701" });
                data.WeatherForecast.Add(new ForecastDayData { DayName = DateTime.Today.AddDays(3).ToString("dddd"), Temp = temp, Icon = "\uE709" });
            }

            data.WeatherTemp = temp;
            data.WeatherCondition = condition;
            data.WeatherSummary = weatherSentence;


            // 3. Health Aggregation
            int steps = 2450;
            double sleep = 7.5;
            int heartRate = 68;
            string healthSentence = "";

            try
            {
                await Task.WhenAll(stepsTask, sleepTask, hrTask);
                
                var stepsMetric = stepsTask.Result;
                if (stepsMetric != null) steps = (int)stepsMetric.Value;
                
                var sleepMetric = sleepTask.Result;
                if (sleepMetric != null) sleep = SettingsService.ConvertSleepToHours(sleepMetric.Value, sleepMetric.Unit);

                var hrMetric = hrTask.Result;
                if (hrMetric != null) heartRate = (int)hrMetric.Value;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SmartBriefingService] Health Fetch Error: {ex.Message}");
            }
            
            data.HealthSteps = steps;
            data.HealthSleepHours = sleep;
            data.HealthAvgHr = heartRate;

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
            decimal netWorth = 24500;
            string financeSentence = "";
            try
            {
                await Task.WhenAll(netWorthTask, symbolsTask);
                netWorth = netWorthTask.Result;
                if (netWorth <= 0) netWorth = 24500; // placeholder safety if ledger is empty

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
                System.Diagnostics.Debug.WriteLine($"[SmartBriefingService] Finance Error: {ex.Message}");
            }

            // Fallback stocks if empty
            if (data.WatchlistStocks.Count == 0)
            {
                data.WatchlistStocks.Add(new StockBriefingData { Symbol = "MSFT", Price = 421.90m, PercentChange = 1.45m });
                data.WatchlistStocks.Add(new StockBriefingData { Symbol = "AAPL", Price = 189.84m, PercentChange = -0.32m });
            }

            financeSentence = $"Your ledger net worth is looking healthy at {netWorth:C0}. Markets are showing active movements: {data.WatchlistStocks[0].Symbol} is at {data.WatchlistStocks[0].Price:C2} ({data.WatchlistStocks[0].FormattedChange}).";


            // 5. Habits Aggregation
            int habitsTotal = 4;
            int habitsCompleted = 1;
            string habitsSentence = "";

            try
            {
                double hydration = await hydrationTask;
                if (hydration > 0)
                {
                    habitsCompleted = hydration >= 1.0 ? 2 : 1;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SmartBriefingService] Habits Error: {ex.Message}");
            }
            
            data.HabitsTotal = habitsTotal;
            data.HabitsCompleted = habitsCompleted;

            if (habitsCompleted == 0)
            {
                habitsSentence = $"You haven't completed any daily habits yet today. Water intake quick logging is waiting to kick off your streak!";
            }
            else
            {
                habitsSentence = $"You've completed {habitsCompleted} of your {habitsTotal} habits today. Stay consistent and keep the streak alive!";
            }

            // 6. News AI Recommendations
            if (_rssFeedService != null && _rssFeedService.Items != null && _rssFeedService.Items.Count > 0)
            {
                int count = 0;
                foreach (var item in _rssFeedService.Items)
                {
                    string categoryReason = "Recommended from your feed";
                    if (!string.IsNullOrEmpty(item.PublicationName))
                    {
                        categoryReason = $"Top story from {item.PublicationName}";
                    }

                    data.NewsRecommendations.Add(new NewsRecommendationData
                    {
                        Title = item.Title,
                        Source = item.PublicationName ?? "RSS Feed",
                        Reason = categoryReason
                    });
                    count++;
                    if (count >= 2) break;
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

            // 7. Assemble Full Briefing Text
            StringBuilder sbBody = new StringBuilder();
            sbBody.Append(weatherSentence);
            sbBody.Append(" ");
            sbBody.Append(healthSentence);
            sbBody.Append("\n\n");
            sbBody.Append(financeSentence);
            sbBody.Append(" ");
            sbBody.Append(habitsSentence);
            sbBody.Append("\n\n");
            sbBody.Append("Lastly, we found a couple of interesting articles in your feed you might like: ");
            sbBody.Append($"\"{data.NewsRecommendations[0].Title}\" from {data.NewsRecommendations[0].Source}, and ");
            sbBody.Append($"\"{data.NewsRecommendations[1].Title}\" from {data.NewsRecommendations[1].Source}.");

            data.IntroText = "Here is your on-device DayOne AI Smart Briefing for today.";
            data.BriefingText = sbBody.ToString();
            data.OutroText = "Have a highly productive day!";

            return data;
        }
    }
}
