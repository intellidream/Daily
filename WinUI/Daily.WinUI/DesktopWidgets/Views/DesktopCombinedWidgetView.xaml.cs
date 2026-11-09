using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services;
using Daily.Services.Finances;
using Daily.Services.Health;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;
#if !WIDGETS_HOST
using Daily_WinUI.Controls;
#endif

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopCombinedWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;

        private IHabitsService? _habitsService;
        private IFinancesService? _financesService;
        private IHealthHubService? _healthHubService;
        private ITagdosService? _tagdosService;

        public DesktopCombinedWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            _model = model;
            _hostWindow = hostWindow;
            this.InitializeComponent();

            ApplySizeLayout();
        }

        private void ApplySizeLayout()
        {
            if (_model.Size == DesktopWidgetSize.Large)
            {
                MediumLayout.Visibility = Visibility.Collapsed;
                LargeLayout.Visibility = Visibility.Visible;
            }
            else
            {
                MediumLayout.Visibility = Visibility.Visible;
                LargeLayout.Visibility = Visibility.Collapsed;
            }
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _habitsService = App.Current.Services?.GetService<IHabitsService>();
                if (_habitsService != null)
                {
                    _habitsService.OnHabitsUpdated += OnServiceDataChanged;
                }

                _financesService = App.Current.Services?.GetService<IFinancesService>();
                if (_financesService != null)
                {
                    _financesService.OnSmartLedgerUpdated += OnServiceDataChanged;
                    _financesService.OnQuotesUpdated += OnServiceDataChanged;
                }

                _healthHubService = App.Current.Services?.GetService<IHealthHubService>();
                if (_healthHubService != null)
                {
                    _healthHubService.OnDailySummaryChanged += (s) => OnServiceDataChanged();
                }

                _tagdosService = App.Current.Services?.GetService<ITagdosService>();
                if (_tagdosService != null)
                {
                    _tagdosService.DataChanged += (s, ev) => OnServiceDataChanged();
                }
            }
            catch { }

            RefreshData();
        }

        private void OnServiceDataChanged()
        {
            DispatcherQueue.TryEnqueue(RefreshData);
        }

        public void Detach()
        {
            if (_habitsService != null)
            {
                _habitsService.OnHabitsUpdated -= OnServiceDataChanged;
            }
            if (_financesService != null)
            {
                _financesService.OnSmartLedgerUpdated -= OnServiceDataChanged;
                _financesService.OnQuotesUpdated -= OnServiceDataChanged;
            }
        }

        public async void RefreshData()
        {
            try
            {
                var now = DateTime.Now;
                string greeting = now.Hour < 12 ? "Good Morning" : (now.Hour < 18 ? "Good Afternoon" : "Good Evening");
                GreetingText.Text = $"DayOne {greeting}";
                DateSubtitleText.Text = $"{now:dddd, MMM d} · Daily Highlights";

                LargeGreetingText.Text = $"DayOne {greeting}";
                LargeDateSubtitleText.Text = $"{now:dddd, MMMM d} · Full Day Intelligence";

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
                        string weatherStr = $"{temp}°C · {weather.Description ?? "Partly Cloudy"}";
                        WeatherHeaderBadge.Text = weatherStr;
                        LargeWeatherHeaderBadge.Text = weatherStr;
                    }
                }
                catch { }

                // 2. Hydration & Smokes
                try
                {
                    if (_habitsService == null)
                    {
                        _habitsService = App.Current.Services?.GetService<IHabitsService>();
                    }

                    if (_habitsService != null)
                    {
                        var water = await _habitsService.GetDailyProgressAsync("water", DateTime.Today);
                        var goal = await _habitsService.GetGoalAsync("water");
                        var target = goal?.TargetValue > 0 ? goal.TargetValue : 2500;
                        string waterStr = $"{(int)water:N0} / {(int)target:N0} ml";
                        HydrationMetricText.Text = waterStr;
                        LargeHydrationMetricText.Text = waterStr;

                        double waterPct = target > 0 ? Math.Min(100.0, (water / target) * 100.0) : 0;
                        LargeHydrationPercentText.Text = $"{(int)waterPct}% of daily goal";

                        var smokes = await _habitsService.GetLogsAsync("smokes", DateTime.Today);
                        int smokeCount = smokes?.Count ?? 0;
                        var settingsService = App.Current.Services?.GetService<Daily.Services.ISettingsService>();
                        int maxSmokes = (settingsService?.Settings?.SmokesBaselineDaily > 0) ? settingsService.Settings.SmokesBaselineDaily : 40;
                        
                        string smokesStr = smokeCount == 0 ? "Smoke-Free 🌟" : $"{smokeCount} / {maxSmokes} smokes";
                        SmokesMetricText.Text = smokesStr;
                        LargeSmokesMetricText.Text = smokeCount == 0 ? "Smoke-Free Today 🌟" : $"{smokeCount} smokes logged";
                        LargeSmokesSubtitleText.Text = smokeCount == 0 ? "Clean air: All day" : $"Limit: {maxSmokes} smokes";
                    }
                }
                catch { }

                // 3. Money
                try
                {
                    decimal totalNet = 0;
#if !WIDGETS_HOST
                    var snapshot = FinancesWidgetControl.SharedSnapshot;
                    if (snapshot != null && snapshot.NetWorth > 0)
                    {
                        totalNet = snapshot.NetWorth;
                    }
#endif
                    if (totalNet <= 0)
                    {
                        if (_financesService == null)
                        {
                            _financesService = App.Current.Services?.GetService<IFinancesService>();
                        }
                        if (_financesService != null)
                        {
                            var ledger = await _financesService.GetSmartLedgerAsync();
                            if (ledger != null && !string.IsNullOrWhiteSpace(ledger.LedgerText))
                            {
                                var parsed = SmartLedgerParser.Parse(ledger.LedgerText);
                                totalNet = parsed.NetWorth;
                            }
                            else
                            {
                                var net = await _financesService.GetNetWorthAsync();
                                if (net > 0) totalNet = net;
                            }
                        }
                    }

                    decimal eurEst = totalNet > 0 ? totalNet / 4.97m : 0;
                    string moneyStr = totalNet > 0 ? $"{totalNet:N0} Lei" : "0 Lei";
                    MoneyMetricText.Text = moneyStr;
                    LargeMoneyMetricText.Text = moneyStr;
                    LargeMoneyEurText.Text = $"~{eurEst:N0} € balance";
                }
                catch { }

                // 4. Sleep & Vitals
                try
                {
                    if (_healthHubService == null)
                    {
                        _healthHubService = App.Current.Services?.GetService<IHealthHubService>();
                    }

                    if (_healthHubService != null)
                    {
                        var summary = await _healthHubService.GetDailySummaryAsync(DateTime.Today);
                        if (summary == null || ((summary.SleepScore == null || summary.SleepScore == 0) && (summary.SleepAsleepS == null || summary.SleepAsleepS == 0)))
                        {
                            var yesterday = await _healthHubService.GetDailySummaryAsync(DateTime.Today.AddDays(-1));
                            if (yesterday != null && ((yesterday.SleepScore > 0) || (yesterday.SleepAsleepS > 0)))
                            {
                                summary = yesterday;
                            }
                        }

                        int score = summary?.SleepScore ?? 85;
                        int durationMins = ((summary?.SleepAsleepS ?? 0) / 60);
                        if (durationMins <= 0) durationMins = 465;
                        string sleepStr = $"{score}/100 · {durationMins / 60}h {durationMins % 60}m";
                        SleepMetricText.Text = sleepStr;
                        LargeSleepMetricText.Text = sleepStr;

                        int stress = summary?.StressAvg ?? 22;
                        int pulse = (int)Math.Round(summary?.Rhr ?? 62);
                        string stressLabel = stress < 30 ? "Low" : (stress < 60 ? "Balanced" : "High");
                        LargeVitalsText.Text = $"{stressLabel} ({stress}) · {pulse} bpm";
                    }
                }
                catch { }

                // 5. Large Extra: TagDoS & Cosmos
                if (_model.Size == DesktopWidgetSize.Large)
                {
                    try
                    {
                        if (_tagdosService == null)
                        {
                            _tagdosService = App.Current.Services?.GetService<ITagdosService>();
                        }
                        if (_tagdosService != null)
                        {
                            var streams = await _tagdosService.GetStreamsAsync() ?? new System.Collections.Generic.List<Daily.Models.TagDoStream>();
                            var activePills = streams.SelectMany(s => s.AllPills.Where(p => !p.IsCompleted)).ToList();
                            LargeTagdosTasksText.Text = $"{activePills.Count} tasks open";
                        }
                    }
                    catch { }

                    try
                    {
                        double lat = 44.4323;
                        double lon = 26.1063;
                        try
                        {
                            var settings = SettingsService.Load();
                            if (settings.LastLatitude.HasValue && settings.LastLatitude.Value != 0)
                            {
                                lat = settings.LastLatitude.Value;
                                lon = settings.LastLongitude ?? 26.1063;
                            }
                        }
                        catch { }

                        var astro = AstronomyService.Shared;
                        var moonPhase = astro.GetMoonPhase(now, lat, lon);
                        string glyph = GetMoonGlyph(moonPhase.IlluminatedFraction);
                        string phaseDesc = !string.IsNullOrWhiteSpace(moonPhase.Description) ? moonPhase.Description : "Moon";
                        LargeMoonIcon.Text = glyph;

                        int? cloudCover = null;
                        try
                        {
                            var weatherClient = App.Current.Services?.GetService<WeatherClient>();
                            var snapshot = weatherClient?.GetCachedSnapshot();
                            if (snapshot != null)
                            {
                                cloudCover = snapshot.Clouds;
                            }
                        }
                        catch { }

                        var conditions = astro.EvaluateStargazingConditions(lat, lon, now, cloudCoverTotal: cloudCover, bortleClass: 4);
                        int skyScore = conditions.Score;

                        LargeCosmosText.Text = $"{phaseDesc} · {skyScore} Sky";
                    }
                    catch { }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopCombinedWidget] Error refreshing: {ex.Message}");
            }
        }

        private static string GetMoonGlyph(double fraction)
        {
            if (fraction < 0.05) return "🌑";
            if (fraction < 0.25) return "🌒";
            if (fraction < 0.45) return "🌓";
            if (fraction < 0.75) return "🌔";
            if (fraction < 0.95) return "🌕";
            return "🌖";
        }
    }
}
