using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.Extensions.DependencyInjection;
using Daily.Models;
using Daily.Services;
using Daily.Services.Health;

namespace Daily_WinUI.Controls
{
    public sealed partial class TaskbarGlanceFlyoutControl : UserControl
    {
        private IHabitsService? _habitsService;
        private ITagdosService? _tagdosService;
        private IWeatherService? _weatherService;
        private IHealthService? _healthService;

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
                    _weatherService = sp.GetService<IWeatherService>();
                    _healthService = sp.GetService<IHealthService>();
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
                if (_weatherService != null)
                {
                    var location = _weatherService.CurrentLocationName;
                    if (!string.IsNullOrEmpty(location))
                    {
                        WeatherLocationText.Text = location;
                    }
                }

                if (_healthService != null)
                {
                    var today = DateTime.Today;
                    var summary = await _healthService.GetDailySummaryAsync(today);
                    if (summary != null && summary.Steps > 0)
                    {
                        VitalsStepsText.Text = $"{summary.Steps:N0} steps";
                        VitalsSubText.Text = $"{summary.ActiveCalories:N0} kcal active";
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] LoadTelemetry error: {ex.Message}");
            }
        }

        private void OpenFullAppButton_Click(object sender, RoutedEventArgs e)
        {
            RequestCloseFlyout?.Invoke(this, EventArgs.Empty);
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.ShowAndActivate();
            }
        }

        private async void LogWater250Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(250);
        }

        private async void LogWater500Btn_Click(object sender, RoutedEventArgs e)
        {
            await LogWaterAsync(500);
        }

        private async Task LogWaterAsync(double amountMl)
        {
            if (_habitsService == null) ResolveServices();
            if (_habitsService != null)
            {
                try
                {
                    await _habitsService.AddLogAsync("water", amountMl, "ml", DateTime.Now);
                    WaterStatusText.Text = $"+{amountMl:N0} ml logged!";
                    await Task.Delay(2000);
                    WaterStatusText.Text = "";
                }
                catch (Exception ex)
                {
                    WaterStatusText.Text = "Failed to log";
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] LogWater error: {ex.Message}");
                }
            }
        }

        private async void LogSmokeBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_habitsService == null) ResolveServices();
            if (_habitsService != null)
            {
                try
                {
                    await _habitsService.AddLogAsync("smokes", 1, "smokes", DateTime.Now);
                    WaterStatusText.Text = "+1 smoke logged!";
                    await Task.Delay(2000);
                    WaterStatusText.Text = "";
                }
                catch (Exception ex)
                {
                    WaterStatusText.Text = "Failed to log";
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] LogSmoke error: {ex.Message}");
                }
            }
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
                    var note = new TagDoQuickNote
                    {
                        Title = text.Length > 24 ? text.Substring(0, 24) + "..." : text,
                        Content = text,
                        CreatedAt = DateTime.UtcNow,
                        UpdatedAt = DateTime.UtcNow
                    };
                    await _tagdosService.SaveQuickNoteAsync(note);
                    QuickNoteInputBox.Text = "";
                    NoteSavedFeedbackText.Text = "Saved to TagDoS!";
                    await Task.Delay(2500);
                    NoteSavedFeedbackText.Text = "";
                }
                catch (Exception ex)
                {
                    NoteSavedFeedbackText.Text = "Save error";
                    System.Diagnostics.Debug.WriteLine($"[TaskbarGlance] SaveQuickNote error: {ex.Message}");
                }
            }
        }

        private void NavJump_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tagStr && int.TryParse(tagStr, out int tabIndex))
            {
                RequestCloseFlyout?.Invoke(this, EventArgs.Empty);
                if (App.Current?.MainWindow is MainWindow mw)
                {
                    mw.ShowAndActivate();
                    mw.NavigateToTab(tabIndex);
                }
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
    }
}
