using System;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.Extensions.DependencyInjection;
using Daily.Models;
using Daily.Models.Health;
using Daily.Services;
using Daily.Services.Health;
using Daily_WinUI.Services;

namespace Daily_WinUI.Controls
{
    public sealed partial class TaskbarGlanceFlyoutControl : UserControl
    {
        public enum TagdosEntryMode
        {
            Note,
            Tagdo
        }

        private IHabitsService? _habitsService;
        private ITagdosService? _tagdosService;
        private IHealthService? _healthService;
        private IHealthHubService? _healthHubService;
        private ISettingsService? _settingsService;
        private IRefreshService? _refreshService;
        private DispatcherTimer? _liveRefreshTimer;
        private bool _eventsSubscribed = false;
        private DateTime _lastRemoteSyncUtc = DateTime.MinValue;
        private readonly WeatherClient _weatherClient = new();
        private readonly LocationService _locationService = new();

        private TagdosEntryMode _tagdosMode = TagdosEntryMode.Note;
        private double _currentWaterTotal = 0;
        private double _waterGoal = 2000;
        private double _currentSmokesTotal = 0;
        private int _smokesBaseline = 12;

        public event EventHandler? RequestCloseFlyout;

        public TaskbarGlanceFlyoutControl()
        {
            this.InitializeComponent();
            this.Loaded += TaskbarGlanceFlyoutControl_Loaded;
        }

        private void TaskbarGlanceFlyoutControl_Loaded(object sender, RoutedEventArgs e)
        {
            ResolveServices();
            _ = LoadTelemetryAsync(forceRemoteHealth: true);
        }

        private void ResolveServices()
        {
            try
            {
                var sp = App.Current?.Services;
                if (sp != null)
                {
                    _habitsService = sp.GetService<IHabitsService>();
                    _tagdosService = sp.GetService<ITagdosService>();
                    _healthService = sp.GetService<IHealthService>();
                    _healthHubService = sp.GetService<IHealthHubService>() ?? (_healthService as IHealthHubService);
                    _settingsService = sp.GetService<ISettingsService>();
                    _refreshService = sp.GetService<IRefreshService>();
                    SubscribeLiveEvents();
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] ResolveServices error: {ex.Message}");
            }
        }

        private void SubscribeLiveEvents()
        {
            if (_eventsSubscribed) return;
            if (_healthHubService == null && _refreshService == null) return;

            if (_healthHubService != null)
            {
                _healthHubService.OnDailySummaryChanged += OnHealthDailySummaryChanged;
            }

            if (_refreshService != null)
            {
                _refreshService.RefreshRequested += OnAppRefreshRequested;
                _refreshService.HealthRefreshRequested += OnAppRefreshRequested;
                _refreshService.DetailRefreshRequested += OnAppRefreshRequested;
            }

            _eventsSubscribed = true;
        }

        private void OnHealthDailySummaryChanged(HealthDailySummaryRecord? summary)
        {
            DispatcherQueue?.TryEnqueue(async () =>
            {
                await ApplyHealthSummaryToUiAsync(summary);
            });
        }

        private Task OnAppRefreshRequested()
        {
            DispatcherQueue?.TryEnqueue(() =>
            {
                _ = LoadTelemetryAsync(forceRemoteHealth: false);
            });
            return Task.CompletedTask;
        }

        public void OnFlyoutOpened()
        {
            ResolveServices();

            // 1. Instant UI update from local/memory cache (<5ms)
            _ = LoadTelemetryAsync(forceRemoteHealth: false);

            // 2. Throttled background remote sync from Supabase (2-min cooldown to protect Kong & PostgREST log ingestion)
            if ((DateTime.UtcNow - _lastRemoteSyncUtc) > TimeSpan.FromSeconds(120))
            {
                _lastRemoteSyncUtc = DateTime.UtcNow;
                _ = RefreshRemoteHealthInBackgroundAsync();
            }

            // 3. Keep telemetry live while the Glance flyout remains open (5-min interval)
            if (_liveRefreshTimer == null)
            {
                _liveRefreshTimer = new DispatcherTimer
                {
                    Interval = TimeSpan.FromMinutes(5)
                };
                _liveRefreshTimer.Tick += (_, _) =>
                {
                    _lastRemoteSyncUtc = DateTime.UtcNow;
                    _ = RefreshRemoteHealthInBackgroundAsync();
                    _ = LoadTelemetryAsync(forceRemoteHealth: false);
                };
            }
            _liveRefreshTimer.Start();
        }

        public void OnFlyoutClosed()
        {
            _liveRefreshTimer?.Stop();
        }

        private Task RefreshRemoteHealthInBackgroundAsync()
        {
            return Task.Run(async () =>
            {
                try
                {
                    if (_healthHubService == null) ResolveServices();
                    if (_healthHubService != null)
                    {
                        var fresh = await _healthHubService.GetDailySummaryAsync(DateTime.Today, forceRefresh: true);
                        DispatcherQueue?.TryEnqueue(async () =>
                        {
                            await ApplyHealthSummaryToUiAsync(fresh);
                        });
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] Remote health refresh warning: {ex.Message}");
                }
            });
        }

        private async Task ApplyHealthSummaryToUiAsync(HealthDailySummaryRecord? summary)
        {
            try
            {
                if (_healthHubService == null && _healthService == null)
                {
                    ResolveServices();
                }

                if (_healthHubService == null && _healthService == null)
                {
                    return;
                }

                if (summary == null && _healthHubService != null)
                {
                    try
                    {
                        summary = await _healthHubService.GetDailySummaryAsync(DateTime.Today);
                    }
                    catch { }
                }

                System.Collections.Generic.List<VitalMetric>? todayMetrics = null;
                if (_healthService != null)
                {
                    try
                    {
                        todayMetrics = await _healthService.FetchMetricsForDateAsync(DateTime.Today);
                    }
                    catch { }
                }

                double liveBpm = 0;

                // Priority 1: Intraday HR latest point from canonical Daily Summary (1:1 with HealthWidgetControl)
                var intraday = summary?.Summary?.Cardiovascular?.IntradayHeartRate;
                if (intraday != null && intraday.Count > 0)
                {
                    var lastPt = intraday.LastOrDefault(p => p.Bpm > 0);
                    if (lastPt != null && lastPt.Bpm > 0)
                    {
                        liveBpm = lastPt.Bpm;
                    }
                }

                // Priority 2: Today's VitalType.HeartRate metric (matching HealthWidgetControl.GetMetric) or latest metric
                if (liveBpm <= 0)
                {
                    var todayHr = todayMetrics?.FirstOrDefault(m => m.Type == VitalType.HeartRate && m.Value > 0);
                    if (todayHr != null)
                    {
                        liveBpm = todayHr.Value;
                    }
                    else if (_healthService != null)
                    {
                        var hrMetric = await _healthService.GetLatestMetricAsync(VitalType.HeartRate);
                        if (hrMetric != null && hrMetric.Value > 0)
                        {
                            liveBpm = hrMetric.Value;
                        }
                    }
                }

                // Priority 3: Resting Heart Rate fallback
                if (liveBpm <= 0)
                {
                    double rhr = summary?.Rhr ?? 0;
                    if (rhr <= 0)
                    {
                        var todayRhr = todayMetrics?.FirstOrDefault(m => m.Type == VitalType.RestingHeartRate && m.Value > 0);
                        if (todayRhr != null)
                        {
                            rhr = todayRhr.Value;
                        }
                        else if (_healthService != null)
                        {
                            var rhrMetric = await _healthService.GetLatestMetricAsync(VitalType.RestingHeartRate);
                            if (rhrMetric != null && rhrMetric.Value > 0)
                            {
                                rhr = rhrMetric.Value;
                            }
                        }
                    }
                    if (rhr > 0)
                    {
                        liveBpm = rhr;
                    }
                }

                VitalsHeartRateText.Text = liveBpm > 0 ? $"{liveBpm:N0}" : "--";

                // Steps
                double steps = summary?.Steps ?? 0;
                if (steps <= 0)
                {
                    var todaySteps = todayMetrics?.FirstOrDefault(m => m.Type == VitalType.Steps && m.Value > 0);
                    if (todaySteps != null)
                    {
                        steps = todaySteps.Value;
                    }
                    else if (_healthService != null)
                    {
                        var stepsMetric = await _healthService.GetLatestMetricAsync(VitalType.Steps);
                        if (stepsMetric != null && stepsMetric.Value > 0)
                        {
                            steps = stepsMetric.Value;
                        }
                    }
                }
                VitalsStepsText.Text = steps > 0 ? $"{steps:N0}" : "--";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] ApplyHealthSummaryToUi error: {ex.Message}");
            }
        }

        private async Task LoadTelemetryAsync(bool forceRemoteHealth = false)
        {
            try
            {
                // 1. Health Vitals (Heart Rate + Steps) - Instant <3ms local cache first so UI never waits on Weather HTTP
                if (_healthHubService == null && _healthService == null)
                {
                    ResolveServices();
                }

                HealthDailySummaryRecord? summary = null;
                if (_healthHubService != null)
                {
                    try
                    {
                        summary = await _healthHubService.GetDailySummaryAsync(DateTime.Today, forceRefresh: forceRemoteHealth);
                        if (forceRemoteHealth)
                        {
                            _lastRemoteSyncUtc = DateTime.UtcNow;
                        }
                    }
                    catch { }
                }
                await ApplyHealthSummaryToUiAsync(summary);

                // 2. Hydration & Smokes Telemetry (fast local SQLite)
                if (_habitsService != null)
                {
                    try
                    {
                        _currentWaterTotal = await _habitsService.GetDailyProgressAsync("water", DateTime.Today);
                        try
                        {
                            var goal = await _habitsService.GetGoalAsync("water");
                            if (goal != null && goal.TargetValue > 0)
                            {
                                _waterGoal = goal.TargetValue;
                            }
                        }
                        catch { }

                        UpdateWaterUi();

                        _currentSmokesTotal = await _habitsService.GetDailyProgressAsync("smokes", DateTime.Today);
                        try
                        {
                            int baseline = _settingsService?.Settings?.SmokesBaselineDaily ?? 0;
                            if (baseline <= 0)
                            {
                                var smokeGoal = await _habitsService.GetGoalAsync("smokes");
                                if (smokeGoal != null && smokeGoal.TargetValue > 0 && smokeGoal.TargetValue <= 100 && smokeGoal.TargetValue != 12)
                                {
                                    baseline = (int)smokeGoal.TargetValue;
                                }
                            }
                            _smokesBaseline = baseline > 0 ? baseline : 20;
                        }
                        catch { }

                        UpdateSmokesUi();
                    }
                    catch { }
                }

                // 3. Weather & Cosmos Ephemeris Telemetry (network-bound, isolated try/catch)
                try
                {
                    var coords = await _locationService.GetCurrentCoordinatesAsync();
                    var savedSettings = Daily_WinUI.Services.SettingsService.Load();
                    double obsLat = coords?.Latitude ?? savedSettings.LastLatitude ?? 44.4323;
                    double obsLon = coords?.Longitude ?? savedSettings.LastLongitude ?? 26.1063;
                    int? liveClouds = null;
                    if (coords.HasValue)
                    {
                        var snapshot = await _weatherClient.GetCurrentWeatherAsync(coords.Value.Latitude, coords.Value.Longitude, "metric");
                        if (snapshot != null)
                        {
                            WeatherTempText.Text = $"{Math.Round(snapshot.Temperature):F0}°C";
                            WeatherLocationText.Text = string.IsNullOrWhiteSpace(snapshot.LocationName) ? "Weather" : snapshot.LocationName;
                            liveClouds = snapshot.Clouds;
                        }
                    }

                    var astro = Daily_WinUI.Services.Cosmos.AstronomyService.Shared;
                    var cat = Daily_WinUI.Services.Cosmos.CosmosCatalogRepository.Shared;
                    await cat.EnsureLoadedAsync();
                    int bortle = cat.GetBortleClass(obsLat, obsLon);
                    var moon = astro.GetMoonPhase(DateTime.UtcNow, obsLat, obsLon);
                    var cond = astro.EvaluateStargazingConditions(obsLat, obsLon, DateTime.UtcNow, liveClouds, null, null, null, bortle);
                    int upCount = astro.GetAllVisibleBodies(DateTime.UtcNow, obsLat, obsLon)
                        .FindAll(b => b.Body != CelestialBody.Sun && b.Body != CelestialBody.Moon && b.IsAboveHorizon)
                        .Count;
                    CosmosSubtitleText.Text = $"{moon.Description} ({moon.IlluminationPercent}%) • {upCount} planets above horizon";
                    CosmosScoreBadgeText.Text = $"{cond.Score}/100";
                }
                catch { }

                try
                {
                    var prism = App.Current?.Services?.GetService<IPrismService>();
                    if (prism != null)
                    {
                        await prism.EnsureLoadedAsync();
                        int clipCount = prism.Clips.Count;
                        PrismVaultBadgeText.Text = clipCount > 0 ? $"{clipCount} Saved" : "Ctrl+0";
                    }
                }
                catch { }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] LoadTelemetry error: {ex.Message}");
            }
        }

        private void UpdateWaterUi()
        {
            WaterProgressText.Text = $"{_currentWaterTotal:F0} / {_waterGoal:F0} ml";
            double pct = _waterGoal > 0 ? Math.Min(100.0, (_currentWaterTotal / _waterGoal) * 100.0) : 0;
            WaterProgressBar.Value = pct;
        }

        private void UpdateSmokesUi()
        {
            SmokesTotalText.Text = $"{_currentSmokesTotal:F0}";
            SmokesBaselineText.Text = $"/ {_smokesBaseline}";
            double pct = _smokesBaseline > 0 ? Math.Min(100.0, (_currentSmokesTotal / _smokesBaseline) * 100.0) : 0;
            SmokesProgressBar.Value = pct;
        }

        // ── Navigation & Window Actions ──────────────────────────────────────

        private void OpenFullAppButton_Click(object sender, RoutedEventArgs e)
        {
            RequestCloseFlyout?.Invoke(this, EventArgs.Empty);
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.ShowAndActivate();
            }
        }

        private void WeatherCard_Click(object sender, RoutedEventArgs e)
        {
            NavigateToTab(6); // Weather Hub
        }

        private void CosmosCard_Click(object sender, RoutedEventArgs e)
        {
            NavigateToTab(9); // Cosmos Hub
        }

        private void PrismCard_Click(object sender, RoutedEventArgs e)
        {
            NavigateToTab(10); // Prism Assisted Web Studio
        }

        private void HealthCard_Click(object sender, RoutedEventArgs e)
        {
            NavigateToTab(4); // Health Hub
        }

        private void TagdosHubLink_Click(object sender, RoutedEventArgs e)
        {
            NavigateToTab(3); // TagDoS Hub
        }

        private void NavJump_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tagStr && int.TryParse(tagStr, out int tabIndex))
            {
                NavigateToTab(tabIndex);
            }
        }

        private void NavigateToTab(int tabIndex)
        {
            RequestCloseFlyout?.Invoke(this, EventArgs.Empty);
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.ShowAndActivate();
                mw.NavigateToTab(tabIndex);
            }
        }

        private void ExitAppBtn_Click(object sender, RoutedEventArgs e)
        {
            RequestCloseFlyout?.Invoke(this, EventArgs.Empty);
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.ExitApp();
            }
        }

        // ── Hydration Logging (Mac Parity: +100 Coffee, +150 Water, +300 Water) ──

        private async void LogCoffee100Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(100, "Coffee");
        }

        private async void LogWater150Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(150, "Water");
        }

        private async void LogWater300Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(300, "Water");
        }

        private async Task LogWaterAsync(double amountMl, string drink)
        {
            if (_habitsService == null) ResolveServices();
            if (_habitsService != null)
            {
                try
                {
                    await _habitsService.AddLogAsync("water", amountMl, "ml", DateTime.Now, "{\"drink\":\"" + drink + "\"}");
                    _currentWaterTotal += amountMl;
                    UpdateWaterUi();

                    WaterStatusText.Text = $"+{amountMl:F0} ml";
                    await Task.Delay(2000);
                    WaterStatusText.Text = "";
                }
                catch (Exception ex)
                {
                    WaterStatusText.Text = "Failed";
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] LogWater error: {ex.Message}");
                }
            }
        }

        // ── Smokes Logging (Mac Parity: Cig & Heat) ─────────────────────────

        private async void LogCigBtn_Click(object sender, RoutedEventArgs e)
        {
            await LogSmokeAsync("Cigarette", "Cig");
        }

        private async void LogHeatBtn_Click(object sender, RoutedEventArgs e)
        {
            await LogSmokeAsync("Heated Tobacco", "Heat");
        }

        private async Task LogSmokeAsync(string type, string label)
        {
            if (_habitsService == null) ResolveServices();
            if (_habitsService != null)
            {
                try
                {
                    await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"" + type + "\"}");
                    _currentSmokesTotal += 1;
                    UpdateSmokesUi();

                    SmokesStatusText.Text = $"+1 {label}";
                    await Task.Delay(2000);
                    SmokesStatusText.Text = "";
                }
                catch (Exception ex)
                {
                    SmokesStatusText.Text = "Failed";
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] LogSmoke error: {ex.Message}");
                }
            }
        }

        // ── TagDoS Quick Entry (Dual Mode: Note vs TagDo) ────────────────────

        private void TagdosModeNote_Click(object sender, RoutedEventArgs e)
        {
            _tagdosMode = TagdosEntryMode.Note;
            TagdosModeNoteBtn.Background = new SolidColorBrush(ColorHelper.FromArgb(0x40, 0x10, 0xB9, 0x81));
            TagdosModeNoteBtn.BorderBrush = new SolidColorBrush(ColorHelper.FromArgb(0x80, 0x10, 0xB9, 0x81));
            TagdosModeNoteBtn.BorderThickness = new Thickness(1);

            TagdosModeTagdoBtn.Background = new SolidColorBrush(ColorHelper.FromArgb(0x14, 0xFF, 0xFF, 0xFF));
            TagdosModeTagdoBtn.BorderBrush = null;
            TagdosModeTagdoBtn.BorderThickness = new Thickness(0);

            QuickNoteInputBox.PlaceholderText = "Add note (saved to TagDoS Notes tab)...";
            TagdosContextHelperText.Text = "Saves to TagDoS Notes tab (accessible in Ctrl+3 -> Notes)";
        }

        private void TagdosModeTagdo_Click(object sender, RoutedEventArgs e)
        {
            _tagdosMode = TagdosEntryMode.Tagdo;
            TagdosModeTagdoBtn.Background = new SolidColorBrush(ColorHelper.FromArgb(0x40, 0x10, 0xB9, 0x81));
            TagdosModeTagdoBtn.BorderBrush = new SolidColorBrush(ColorHelper.FromArgb(0x80, 0x10, 0xB9, 0x81));
            TagdosModeTagdoBtn.BorderThickness = new Thickness(1);

            TagdosModeNoteBtn.Background = new SolidColorBrush(ColorHelper.FromArgb(0x14, 0xFF, 0xFF, 0xFF));
            TagdosModeNoteBtn.BorderBrush = null;
            TagdosModeNoteBtn.BorderThickness = new Thickness(0);

            QuickNoteInputBox.PlaceholderText = "Add mental tag (e.g. BUY/GROC, CALL/MOM)...";
            TagdosContextHelperText.Text = "Adds as an active task pill to TagDoS Stream 1 (Ctrl+3)";
        }

        private void QuickNoteInputBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            bool hasText = !string.IsNullOrWhiteSpace(QuickNoteInputBox.Text);
            SaveQuickNoteBtn.Opacity = hasText ? 1.0 : 0.5;
        }

        private void QuickNoteInputBox_KeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                e.Handled = true;
                SaveQuickNoteBtn_Click(sender, e);
            }
        }

        private async void SaveQuickNoteBtn_Click(object sender, RoutedEventArgs e)
        {
            var text = QuickNoteInputBox.Text?.Trim();
            if (string.IsNullOrWhiteSpace(text)) return;

            if (_tagdosService == null) ResolveServices();
            if (_tagdosService != null)
            {
                try
                {
                    if (_tagdosMode == TagdosEntryMode.Note)
                    {
                        var title = text.Length > 24 ? text.Substring(0, 24) + "..." : text;
                        await _tagdosService.CreateQuickNoteAsync(title, text, false);
                        QuickNoteInputBox.Text = "";
                        TagdosStatusText.Text = "✓ Saved to Notes!";
                    }
                    else
                    {
                        var streams = await _tagdosService.GetStreamsAsync();
                        if (streams != null && streams.Count > 0)
                        {
                            var first = streams[0];
                            TagdosParser.AddPill(first, 0, text);
                            await _tagdosService.UpdateStreamRawTextAsync(first.Id, first.RawText);
                            QuickNoteInputBox.Text = "";
                            TagdosStatusText.Text = "✓ Added to Stream 1!";
                        }
                        else
                        {
                            await _tagdosService.CreateQuickNoteAsync("Quick Memo", text, false);
                            QuickNoteInputBox.Text = "";
                            TagdosStatusText.Text = "✓ Saved to Notes!";
                        }
                    }

                    await Task.Delay(2500);
                    TagdosStatusText.Text = "";
                }
                catch (Exception ex)
                {
                    TagdosStatusText.Text = "Error";
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] Save error: {ex.Message}");
                }
            }
        }

        // ── Desktop Widgets Management from Taskbar Companion ──
        private void GlanceToggleDesktopWidgets_Click(object sender, RoutedEventArgs e)
        {
            DesktopWidgets.DesktopWidgetManager.Instance.ToggleVisibility();
        }

        private void GlanceToggleLockWidgets_Click(object sender, RoutedEventArgs e)
        {
            var settings = Services.SettingsService.Load();
            settings.DesktopWidgetsLocked = !settings.DesktopWidgetsLocked;
            Services.SettingsService.Save(settings);
            DesktopWidgets.DesktopWidgetManager.Instance.SetAllLocked(settings.DesktopWidgetsLocked);
        }

        private void GlanceRefreshWidgets_Click(object sender, RoutedEventArgs e)
        {
            DesktopWidgets.DesktopWidgetManager.Instance.RefreshAllWidgets();
        }

        private void GlanceResetWidgets_Click(object sender, RoutedEventArgs e)
        {
            DesktopWidgets.DesktopWidgetManager.Instance.ResetToDefaults();
        }

        private void GlanceAddCombinedWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Combined, DesktopWidgets.DesktopWidgetSize.Medium, 100, 100);

        private void GlanceAddBubblesWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Bubbles, DesktopWidgets.DesktopWidgetSize.Small, 100, 100);

        private void GlanceAddSmokesWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Smokes, DesktopWidgets.DesktopWidgetSize.Small, 100, 100);

        private void GlanceAddMoneyWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Money, DesktopWidgets.DesktopWidgetSize.Medium, 100, 100);

        private void GlanceAddSleepWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Sleep, DesktopWidgets.DesktopWidgetSize.Medium, 100, 100);

        private void GlanceAddStressWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Stress, DesktopWidgets.DesktopWidgetSize.Small, 100, 100);

        private void GlanceAddCosmosWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Cosmos, DesktopWidgets.DesktopWidgetSize.Small, 100, 100);

        private void GlanceAddTagdosWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.TagDos, DesktopWidgets.DesktopWidgetSize.Medium, 100, 100);

        private void GlanceAddWeatherWidget_Click(object sender, RoutedEventArgs e) =>
            DesktopWidgets.DesktopWidgetManager.Instance.AddWidget(DesktopWidgets.DesktopWidgetType.Weather, DesktopWidgets.DesktopWidgetSize.Medium, 100, 100);
    }
}
