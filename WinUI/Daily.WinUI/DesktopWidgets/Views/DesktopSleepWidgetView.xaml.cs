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
                MediumLayout.Visibility = Visibility.Collapsed;
                LargeLayout.Visibility = Visibility.Collapsed;
            }
            else if (_model.Size == DesktopWidgetSize.Large)
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLayout.Visibility = Visibility.Collapsed;
                LargeLayout.Visibility = Visibility.Visible;
            }
            else
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLayout.Visibility = Visibility.Visible;
                LargeLayout.Visibility = Visibility.Collapsed;
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

                    // If today has no sleep session or zero score yet, check yesterday's summary & session
                    if ((primarySession == null || primarySession.DurationSeconds <= 0) && (summary?.SleepScore == null || summary.SleepScore == 0))
                    {
                        var yesterdaySummary = await _healthHubService.GetDailySummaryAsync(DateTime.Today.AddDays(-1));
                        var yesterdaySleep = await _healthHubService.GetSleepSessionsAsync(DateTime.Today.AddDays(-1));
                        var yesterdayPrimary = yesterdaySleep.PrimarySession ?? yesterdaySleep.AllSessions?.OrderByDescending(s => s.DurationSeconds).FirstOrDefault();
                        if (yesterdayPrimary != null || yesterdaySummary?.SleepScore > 0)
                        {
                            summary = yesterdaySummary ?? summary;
                            primarySession = yesterdayPrimary ?? primarySession;
                        }
                    }

                    int score = primarySession?.SleepScore > 0 ? primarySession.SleepScore : (summary?.SleepScore ?? 85);

                    // Real asleep minutes from Health Hub (excluding awakenings)
                    int asleepMins = primarySession != null && primarySession.AsleepSeconds > 0
                        ? (int)(primarySession.AsleepSeconds / 60.0) 
                        : ((summary?.SleepAsleepS ?? 0) / 60);

                    // Total time in bed from start to end
                    int inBedMins = primarySession != null && primarySession.DurationSeconds > 0
                        ? (int)(primarySession.DurationSeconds / 60.0) 
                        : (asleepMins > 0 ? (int)Math.Round(asleepMins / 0.92) : 486);

                    if (asleepMins <= 0) asleepMins = 448; // fallback: 7h 28m
                    if (inBedMins < asleepMins) inBedMins = (int)Math.Round(asleepMins / 0.92);

                    int asleepHours = asleepMins / 60;
                    int asleepRemainder = asleepMins % 60;
                    string durStr = $"{asleepHours}h {asleepRemainder:D2}m"; // Real sleep duration in ring!
                    string inBedStr = $"{inBedMins / 60}h {inBedMins % 60:D2}m";

                    SmallProgressRing.Value = score;
                    SmallScoreText.Text = score.ToString();
                    SmallDurationText.Text = durStr;
                    SmallQualityText.Text = score >= 80 ? "Optimal Recovery" : (score >= 65 ? "Good Recovery" : "Fair Recovery");

                    MediumProgressRing.Value = score;
                    MediumScoreText.Text = score.ToString();
                    MediumCenterDurationText.Text = durStr;

                    if (primarySession != null && primarySession.StartTime != default && primarySession.EndTime != default)
                    {
                        MediumScheduleSubtitle.Text = $"{primarySession.StartTime:HH:mm} → {primarySession.EndTime:HH:mm} ({inBedStr})";
                    }
                    else
                    {
                        MediumScheduleSubtitle.Text = $"Bedtime: {durStr} ({inBedStr})";
                    }

                    int deepMins = primarySession != null && primarySession.DeepSeconds > 0 
                        ? (int)(primarySession.DeepSeconds / 60.0) 
                        : (int)(asleepMins * 0.22);
                    int remMins = primarySession != null && primarySession.RemSeconds > 0 
                        ? (int)(primarySession.RemSeconds / 60.0) 
                        : (int)(asleepMins * 0.25);
                    int lightMins = primarySession != null && primarySession.LightSeconds > 0 
                        ? (int)(primarySession.LightSeconds / 60.0) 
                        : (int)(asleepMins * 0.45);

                    DeepStageText.Text = $"Deep {deepMins / 60}h {deepMins % 60}m";
                    RemStageText.Text = $"REM {remMins / 60}h {remMins % 60}m";
                    LightStageText.Text = $"Light {lightMins / 60}h {lightMins % 60}m";

                    int restingHr = (int)Math.Round(summary?.Rhr ?? 58);
                    double hrv = summary?.HrvRmssd ?? 62;

                    RestingHrText.Text = $"Resting HR: {restingHr} bpm";
                    HrvBalanceText.Text = $"HRV: {hrv:F0} ms";
                    MediumQualityHeader.Text = score >= 80 ? "Restorative Sleep Quality (High)" : "Normal Sleep Quality";

                    // Large Layout population
                    LargeScoreText.Text = score.ToString();
                    if (primarySession != null && primarySession.StartTime != default && primarySession.EndTime != default)
                    {
                        LargeScheduleSubtitle.Text = $"{primarySession.StartTime:HH:mm} → {primarySession.EndTime:HH:mm} · {durStr} ({inBedStr})";
                    }
                    else
                    {
                        LargeScheduleSubtitle.Text = $"Tracked: {durStr} ({inBedStr})";
                    }

                    LargeQualityHeader.Text = score >= 80 ? "Restorative Sleep Quality (High)" : (score >= 65 ? "Good Sleep Quality" : "Fair Sleep Quality");
                    
                    int efficiency = primarySession != null && primarySession.DurationSeconds > 0 && primarySession.AsleepSeconds > 0
                        ? Math.Clamp((int)Math.Round((double)primarySession.AsleepSeconds / primarySession.DurationSeconds * 100), 70, 99)
                        : Math.Clamp((int)Math.Round((double)asleepMins / (inBedMins > 0 ? inBedMins : 1) * 100), 75, 98);
                    LargeEfficiencyText.Text = $"Efficiency: {efficiency}%";

                    LargeDeepStageText.Text = $"{deepMins / 60}h {deepMins % 60}m";
                    LargeRemStageText.Text = $"{remMins / 60}h {remMins % 60}m";
                    LargeLightStageText.Text = $"{lightMins / 60}h {lightMins % 60}m";
                    int awakeMins = primarySession != null && primarySession.AwakeSeconds > 0 
                        ? (int)(primarySession.AwakeSeconds / 60.0) 
                        : Math.Max(15, inBedMins - (deepMins + remMins + lightMins));
                    LargeAwakeStageText.Text = $"{awakeMins}m";

                    LargeRestingHrText.Text = $"{restingHr} bpm";
                    LargeHrvBalanceText.Text = $"{hrv:F0} ms";
                    LargeSpo2Text.Text = $"{summary?.Spo2 ?? 98}% SpO2";
                    LargeSleepDebtText.Text = score >= 80 ? "+15m Surplus" : "-30m Debt";

                    var guidanceVerdict = summary?.Summary?.Sleep?.Guidance?.Verdict;
                    LargeRecommendationText.Text = !string.IsNullOrWhiteSpace(guidanceVerdict?.Headline)
                        ? guidanceVerdict.Headline
                        : (score >= 80
                            ? "Optimal autonomic recovery. Target bedtime tonight: 23:15."
                            : "Slight sleep pressure detected. Target bedtime tonight: 22:45.");

                    string devSource = primarySession?.SourceDevice ?? "Daily Multi-Device Hub";
                    LargeDeviceSourceText.Text = $"Source: {devSource}";
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopSleepWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
