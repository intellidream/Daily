using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services.Health;
using Daily_WinUI.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopSleepWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private IHealthHubService? _healthHubService;

        public DesktopSleepWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            _model = model;
            _hostWindow = hostWindow;
            this.InitializeComponent();

            ApplySizeLayout();
        }

        private void ApplySizeLayout()
        {
            if (_model.Size == DesktopWidgetSize.Small)
            {
                SmallLayout.Visibility = Visibility.Visible;
                MediumLargeLayout.Visibility = Visibility.Collapsed;
            }
            else
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLargeLayout.Visibility = Visibility.Visible;
            }
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                _healthHubService = App.Current.Services?.GetService<IHealthHubService>();
                if (_healthHubService != null)
                {
                    _healthHubService.OnDailySummaryChanged += HealthHubService_OnDailySummaryChanged;
                }
            }
            catch { }

            RefreshData();
        }

        private void HealthHubService_OnDailySummaryChanged(Daily.Models.Health.HealthDailySummaryRecord obj)
        {
            DispatcherQueue.TryEnqueue(RefreshData);
        }

        public void Detach()
        {
            if (_healthHubService != null)
            {
                _healthHubService.OnDailySummaryChanged -= HealthHubService_OnDailySummaryChanged;
            }
        }

        public async void RefreshData()
        {
            if (_healthHubService == null)
            {
                try { _healthHubService = App.Current.Services?.GetService<IHealthHubService>(); } catch { }
            }

            try
            {
                if (_healthHubService != null)
                {
                    var summary = await _healthHubService.GetDailySummaryAsync(DateTime.Today);
                    var sleepResult = await _healthHubService.GetSleepSessionsAsync(DateTime.Today);
                    var primarySession = sleepResult.PrimarySession ?? sleepResult.AllSessions?.OrderByDescending(s => s.DurationSeconds).FirstOrDefault();

                    int score = summary?.SleepScore ?? 85;
                    int durationMins = primarySession != null ? (int)(primarySession.DurationSeconds / 60.0) : ((summary?.SleepAsleepS ?? 0) / 60);
                    if (durationMins <= 0) durationMins = 460;
                    int hours = durationMins / 60;
                    int mins = durationMins % 60;
                    string durStr = $"{hours}h {mins:D2}m";

                    SmallProgressRing.Value = score;
                    SmallScoreText.Text = score.ToString();
                    SmallDurationText.Text = durStr;
                    SmallQualityText.Text = score >= 80 ? "Optimal Recovery" : (score >= 65 ? "Good Recovery" : "Fair Recovery");

                    MediumProgressRing.Value = score;
                    MediumScoreText.Text = score.ToString();
                    MediumCenterDurationText.Text = durStr;

                    if (primarySession != null)
                    {
                        MediumScheduleSubtitle.Text = $"{primarySession.StartTime:HH:mm} → {primarySession.EndTime:HH:mm} ({durStr})";
                    }
                    else
                    {
                        MediumScheduleSubtitle.Text = $"Duration: {durStr}";
                    }

                    int deepMins = primarySession != null ? (int)(primarySession.DeepSeconds / 60.0) : (int)(durationMins * 0.22);
                    int remMins = primarySession != null ? (int)(primarySession.RemSeconds / 60.0) : (int)(durationMins * 0.25);
                    int lightMins = primarySession != null ? (int)(primarySession.LightSeconds / 60.0) : (int)(durationMins * 0.45);

                    DeepStageText.Text = $"Deep {deepMins / 60}h {deepMins % 60}m";
                    RemStageText.Text = $"REM {remMins / 60}h {remMins % 60}m";
                    LightStageText.Text = $"Light {lightMins / 60}h {lightMins % 60}m";

                    int restingHr = (int)Math.Round(summary?.Rhr ?? 58);
                    double hrv = summary?.HrvRmssd ?? 62;

                    RestingHrText.Text = $"Resting HR: {restingHr} bpm";
                    HrvBalanceText.Text = $"HRV: {hrv:F0} ms";
                    MediumQualityHeader.Text = score >= 80 ? "Restorative Sleep Quality (High)" : "Normal Sleep Quality";
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopSleepWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
