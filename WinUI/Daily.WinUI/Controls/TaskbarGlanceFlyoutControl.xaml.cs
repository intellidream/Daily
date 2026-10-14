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
        private ISettingsService? _settingsService;
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
            _ = LoadTelemetryAsync();
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
                    _settingsService = sp.GetService<ISettingsService>();
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] ResolveServices error: {ex.Message}");
            }
        }

        private async Task LoadTelemetryAsync()
        {
            try
            {
                // 1. Weather Telemetry
                var coords = await _locationService.GetCurrentCoordinatesAsync();
                if (coords.HasValue)
                {
                    var snapshot = await _weatherClient.GetCurrentWeatherAsync(coords.Value.Latitude, coords.Value.Longitude, "metric");
                    if (snapshot != null)
                    {
                        WeatherTempText.Text = $"{Math.Round(snapshot.Temperature):F0}°C";
                        WeatherLocationText.Text = string.IsNullOrWhiteSpace(snapshot.LocationName) ? "Weather" : snapshot.LocationName;
                    }
                }

                // 2. Health Vitals (Heart Rate + Steps)
                if (_healthService != null)
                {
                    var hrMetric = await _healthService.GetLatestMetricAsync(VitalType.HeartRate);
                    if (hrMetric == null || hrMetric.Value <= 0)
                    {
                        hrMetric = await _healthService.GetLatestMetricAsync(VitalType.RestingHeartRate);
                    }

                    if (hrMetric != null && hrMetric.Value > 0)
                    {
                        VitalsHeartRateText.Text = $"{hrMetric.Value:F0}";
                    }
                    else
                    {
                        VitalsHeartRateText.Text = "--";
                    }

                    var stepsMetric = await _healthService.GetLatestMetricAsync(VitalType.Steps);
                    if (stepsMetric != null && stepsMetric.Value > 0)
                    {
                        VitalsStepsText.Text = $"{stepsMetric.Value:N0}";
                    }
                    else
                    {
                        VitalsStepsText.Text = "--";
                    }
                }

                // 3. Hydration Telemetry
                if (_habitsService != null)
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

                    // 4. Smokes Telemetry
                    _currentSmokesTotal = await _habitsService.GetDailyProgressAsync("smokes", DateTime.Today);
                    try
                    {
                        int fallbackBaseline = _settingsService?.Settings?.SmokesBaselineDaily > 0
                            ? _settingsService.Settings.SmokesBaselineDaily
                            : 12;

                        var smokeGoal = await _habitsService.GetGoalAsync("smokes");
                        if (smokeGoal != null && smokeGoal.TargetValue > 0 && smokeGoal.TargetValue <= 100)
                        {
                            _smokesBaseline = (int)smokeGoal.TargetValue;
                        }
                        else
                        {
                            _smokesBaseline = fallbackBaseline;
                        }
                    }
                    catch { }

                    UpdateSmokesUi();
                }
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

        // ── Hydration Logging (Mac Parity: +100 Water, +150 Coffee, +300 Water) ──

        private async void LogWater100Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(100, "Water");
        }

        private async void LogCoffee150Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(150, "Coffee");
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
    }
}
