using System;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services;
using Daily.Services.Finances;
using Daily.Services.Health;
using Daily_WinUI.Services;
using Daily_WinUI.Controls;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopCombinedWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;

        public DesktopCombinedWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            _model = model;
            _hostWindow = hostWindow;
            this.InitializeComponent();
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            RefreshData();
        }

        public async void RefreshData()
        {
            try
            {
                var now = DateTime.Now;
                GreetingText.Text = now.Hour < 12 ? "Good Morning" : (now.Hour < 18 ? "Good Afternoon" : "Good Evening");
                DateSubtitleText.Text = $"{now:dddd, MMM d} · Daily Highlights";

                // 1. Weather
                try
                {
                    var settings = Daily_WinUI.Services.SettingsService.Load();
                    double lat = settings.LastLatitude ?? 44.4323;
                    double lon = settings.LastLongitude ?? 26.1063;
                    var client = new WeatherClient();
                    var weather = await client.GetCurrentWeatherAsync(lat, lon, settings.UnitSystem ?? "metric");
                    if (weather != null)
                    {
                        int temp = (int)Math.Round(weather.Temperature);
                        WeatherHeaderBadge.Text = $"{temp}°C · {weather.Description ?? "Partly Cloudy"}";
                    }
                }
                catch { }

                // 2. Hydration
                try
                {
                    var habitsService = App.Current.Services?.GetService<IHabitsService>();
                    if (habitsService != null)
                    {
                        var water = await habitsService.GetDailyProgressAsync("water", DateTime.Today);
                        var goal = await habitsService.GetGoalAsync("water");
                        var target = goal?.TargetValue > 0 ? goal.TargetValue : 2500;
                        HydrationMetricText.Text = $"{(int)water:N0} / {(int)target:N0} ml";

                        var smokes = await habitsService.GetLogsAsync("smokes", DateTime.Today);
                        int smokeCount = smokes?.Count ?? 0;
                        int maxSmokes = settings.SmokesBaselineDaily > 0 ? settings.SmokesBaselineDaily : 40;
                        SmokesMetricText.Text = smokeCount == 0 ? "Smoke-Free 🌟" : $"{smokeCount} / {maxSmokes} smokes";
                    }
                }
                catch { }

                // 3. Money
                try
                {
                    var snapshot = FinancesWidgetControl.SharedSnapshot;
                    if (snapshot != null)
                    {
                        MoneyMetricText.Text = snapshot.SmartNetWorthDisplay;
                    }
                    else
                    {
                        var finService = App.Current.Services?.GetService<IFinancesService>();
                        if (finService != null)
                        {
                            var ledger = await finService.GetSmartLedgerAsync();
                            if (ledger != null && !string.IsNullOrWhiteSpace(ledger.LedgerText))
                            {
                                var parsed = SmartLedgerParser.Parse(ledger.LedgerText);
                                MoneyMetricText.Text = $"{parsed.NetWorth:N0} Lei";
                            }
                            else
                            {
                                var net = await finService.GetNetWorthAsync();
                                MoneyMetricText.Text = net > 0 ? $"{net:N0} Lei" : "0 Lei";
                            }
                        }
                    }
                }
                catch { }

                // 4. Sleep
                try
                {
                    var healthHub = App.Current.Services?.GetService<IHealthHubService>();
                    if (healthHub != null)
                    {
                        var summary = await healthHub.GetDailySummaryAsync(DateTime.Today);
                        int score = summary?.SleepScore ?? 85;
                        int durationMins = ((summary?.SleepAsleepS ?? 0) / 60);
                        if (durationMins <= 0) durationMins = 465;
                        SleepMetricText.Text = $"{score}/100 · {durationMins / 60}h {durationMins % 60}m";
                    }
                }
                catch { }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopCombinedWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
