using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services;
using Daily.Services.Health;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Daily_WinUI.Controls
{
    public sealed partial class HealthWidgetControl : UserControl, INotifyPropertyChanged
    {
        private IHealthService? _healthService;
        private IHealthHubService? _healthHubService;
        private IRefreshService? _refreshService;
        private HealthDailySummaryRecord? _currentSummary;
        private List<VitalMetric> _metrics = new();
        private SleepSession? _primarySleepSession;

        public HealthWidgetControl()
        {
            this.InitializeComponent();

            try { _healthHubService = App.Current.Services.GetService<IHealthHubService>(); } catch { }
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch { }
            try { _refreshService = App.Current.Services.GetService<IRefreshService>(); } catch { }
        }

        private async void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested += OnRefreshRequested;
                _refreshService.HealthRefreshRequested += OnRefreshRequested;
            }

            if (_healthHubService != null)
            {
                _healthHubService.OnDailySummaryChanged += OnDailySummaryChanged;
            }

            var task = LoadDataAsync();
            MainPage.Current?.RegisterLoadingTask(task);
            await task;
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested -= OnRefreshRequested;
                _refreshService.HealthRefreshRequested -= OnRefreshRequested;
            }

            if (_healthHubService != null)
            {
                _healthHubService.OnDailySummaryChanged -= OnDailySummaryChanged;
            }
        }

        private void OnDailySummaryChanged(HealthDailySummaryRecord? record)
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                _currentSummary = record;
                await RefreshDerivedDataAsync();
            });
        }

        private Task OnRefreshRequested()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                try
                {
                    await LoadDataAsync();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[HealthWidgetControl] Threaded refresh failed: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        public async Task RefreshAsync()
        {
            if (_healthHubService != null)
            {
                try
                {
                    await _healthHubService.PullDeltasAsync();
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[HealthWidgetControl] Sync/Pull deltas failed: {ex.Message}");
                }
            }
            await LoadDataAsync();
        }

        public async Task LoadDataAsync()
        {
            try
            {
                if (_healthHubService != null)
                {
                    _currentSummary = await _healthHubService.GetDailySummaryAsync(DateTime.Today);
                }

                if (_healthService != null)
                {
                    _metrics = await _healthService.FetchMetricsForDateAsync(DateTime.Today);
                    var (primary, _) = await _healthService.GetSleepSessionsAsync(DateTime.Today);
                    _primarySleepSession = primary;
                }

                await RefreshDerivedDataAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[HealthWidgetControl] Error loading data: {ex.Message}");
            }
        }

        private Task RefreshDerivedDataAsync()
        {
            CalculateDominantSource();

            OnPropertyChanged(nameof(DominantDeviceName));
            OnPropertyChanged(nameof(HasDeviceAttribution));

            OnPropertyChanged(nameof(StepsText));
            OnPropertyChanged(nameof(StepsProgressValue));
            OnPropertyChanged(nameof(CaloriesSummaryText));

            OnPropertyChanged(nameof(HeartRateText));
            OnPropertyChanged(nameof(RestingHeartRateSummaryText));

            OnPropertyChanged(nameof(SleepText));
            OnPropertyChanged(nameof(SleepEfficiencySummaryText));

            OnPropertyChanged(nameof(MonkeyMoodEmoji));
            OnPropertyChanged(nameof(StressScoreText));
            OnPropertyChanged(nameof(StressScoreBrush));
            OnPropertyChanged(nameof(StressLevelLabelText));

            OnPropertyChanged(nameof(HrvText));
            OnPropertyChanged(nameof(RhrText));
            OnPropertyChanged(nameof(Spo2Text));
            OnPropertyChanged(nameof(RespText));

            return Task.CompletedTask;
        }

        // --- Multi-Device Origin Detection ---

        private string _dominantDeviceName = "";
        public string DominantDeviceName => _dominantDeviceName;
        public bool HasDeviceAttribution => !string.IsNullOrWhiteSpace(_dominantDeviceName);

        private void CalculateDominantSource()
        {
            // 1. Try from primary sleep session source device
            if (!string.IsNullOrEmpty(_primarySleepSession?.SourceDevice) && !DeviceSource.IsVirtual(_primarySleepSession.SourceDevice))
            {
                _dominantDeviceName = _primarySleepSession.SourceDevice;
                return;
            }

            // 2. Try from summary vitals
            if (_currentSummary?.Summary?.Vitals != null)
            {
                var vitalDevices = _currentSummary.Summary.Vitals.Values
                    .Where(v => !string.IsNullOrEmpty(v.SourceDevice) && !DeviceSource.IsVirtual(v.SourceDevice))
                    .Select(v => v.SourceDevice!)
                    .GroupBy(d => d)
                    .OrderByDescending(g => g.Count())
                    .FirstOrDefault();

                if (vitalDevices != null)
                {
                    _dominantDeviceName = vitalDevices.Key;
                    return;
                }
            }

            // 3. Fallback from metrics collection
            var metricDev = _metrics
                .Where(m => !string.IsNullOrEmpty(m.SourceDevice) && !DeviceSource.IsVirtual(m.SourceDevice))
                .Select(m => m.SourceDevice!)
                .GroupBy(d => d)
                .OrderByDescending(g => g.Count())
                .FirstOrDefault();

            if (metricDev != null)
            {
                _dominantDeviceName = metricDev.Key;
            }
            else
            {
                _dominantDeviceName = "";
            }
        }

        // --- Bindable Metric Properties ---

        public string StepsText
        {
            get
            {
                double steps = _currentSummary?.Steps ?? GetMetric(VitalType.Steps)?.Value ?? 0;
                return steps > 0 ? steps.ToString("N0") : "--";
            }
        }

        public double StepsProgressValue
        {
            get
            {
                double steps = _currentSummary?.Steps ?? GetMetric(VitalType.Steps)?.Value ?? 0;
                return Math.Min(100.0, Math.Max(0.0, (steps / 10000.0) * 100.0));
            }
        }

        public string CaloriesSummaryText
        {
            get
            {
                double kcal = _currentSummary?.ActiveKcal ?? GetMetric(VitalType.ActiveEnergy)?.Value ?? 0;
                return kcal > 0 ? $"{kcal:N0} kcal" : "-- kcal";
            }
        }

        public string HeartRateText
        {
            get
            {
                // Priority 1: Intraday HR last point
                var intraday = _currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate;
                if (intraday != null && intraday.Any())
                {
                    var lastPt = intraday.LastOrDefault(p => p.Bpm > 0);
                    if (lastPt != null)
                    {
                        return $"{lastPt.Bpm:N0} bpm";
                    }
                }

                // Priority 2: Vital metric
                var m = GetMetric(VitalType.HeartRate);
                if (m?.Value > 0) return $"{m.Value:N0} bpm";

                // Priority 3: Resting Heart Rate fallback
                double rhr = _currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                return rhr > 0 ? $"{rhr:N0} bpm" : "--";
            }
        }

        public string RestingHeartRateSummaryText
        {
            get
            {
                double rhr = _currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                return rhr > 0 ? $"Rest {rhr:N0} bpm" : "Rest -- bpm";
            }
        }

        public string SleepText
        {
            get
            {
                if (_currentSummary?.SleepAsleepS.HasValue == true && _currentSummary.SleepAsleepS.Value > 0)
                {
                    var ts = TimeSpan.FromSeconds(_currentSummary.SleepAsleepS.Value);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }

                var m = GetMetric(VitalType.SleepDuration);
                if (m != null && m.Value > 0)
                {
                    double mins = Daily_WinUI.Services.SettingsService.ConvertSleepToMinutes(m.Value, m.Unit);
                    var ts = TimeSpan.FromMinutes(mins);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }

                return "--";
            }
        }

        public string SleepEfficiencySummaryText
        {
            get
            {
                int eff = _currentSummary?.Summary?.Sleep?.PrimarySession?.EfficiencyPercent ?? 0;
                if (eff > 0) return $"{eff}% eff";

                int score = _currentSummary?.SleepScore ?? 0;
                if (score > 0) return $"Score {score}";

                return "--";
            }
        }

        public string MonkeyMoodEmoji
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood;
                if (!string.IsNullOrEmpty(mood))
                {
                    return mood.ToLowerInvariant() switch
                    {
                        "zen" => "🧘",
                        "happy" => "🐵",
                        "curious" => "🐒",
                        "alert" => "👀",
                        "wired" => "⚡",
                        "exhausted" => "💤",
                        _ => "🐵"
                    };
                }

                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 0) return "🐵";
                if (score <= 25) return "🧘";
                if (score <= 50) return "🐵";
                if (score <= 75) return "⚡";
                return "💤";
            }
        }

        public string StressScoreText
        {
            get
            {
                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                return score > 0 ? score.ToString() : "--";
            }
        }

        public SolidColorBrush StressScoreBrush
        {
            get
            {
                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 0) return new SolidColorBrush(Color.FromArgb(180, 255, 255, 255));
                if (score <= 25) return new SolidColorBrush(Color.FromArgb(255, 52, 199, 89));   // Calm green
                if (score <= 50) return new SolidColorBrush(Color.FromArgb(255, 56, 151, 240));  // Low blue
                if (score <= 75) return new SolidColorBrush(Color.FromArgb(255, 255, 149, 0));  // Medium orange
                return new SolidColorBrush(Color.FromArgb(255, 255, 45, 85));                   // High pink/red
            }
        }

        public string StressLevelLabelText
        {
            get
            {
                var lvl = _currentSummary?.Summary?.Stress?.CurrentLevel;
                if (!string.IsNullOrEmpty(lvl)) return lvl;

                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 0) return "No Data";
                if (score <= 25) return "Calm";
                if (score <= 50) return "Low";
                if (score <= 75) return "Moderate";
                return "High";
            }
        }

        public string HrvText
        {
            get
            {
                double hrv = _currentSummary?.HrvSdnn ?? _currentSummary?.HrvRmssd ?? GetMetric(VitalType.HeartRateVariabilitySDNN)?.Value ?? 0;
                return hrv > 0 ? $"{hrv:F0} ms" : "--";
            }
        }

        public string RhrText
        {
            get
            {
                double rhr = _currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                return rhr > 0 ? $"{rhr:F0} bpm" : "--";
            }
        }

        public string Spo2Text
        {
            get
            {
                double spo2 = _currentSummary?.Spo2 ?? GetMetric(VitalType.OxygenSaturation)?.Value ?? 0;
                return spo2 > 0 ? $"{spo2:F0}%" : "--";
            }
        }

        public string RespText
        {
            get
            {
                var m = GetMetric(VitalType.RespiratoryRate);
                return m?.Value > 0 ? $"{m.Value:F0} br/m" : "--";
            }
        }

        private VitalMetric? GetMetric(VitalType type)
        {
            var m = _metrics.FirstOrDefault(x => x.MatchesType(type));
            return m?.Value > 0 ? m : null;
        }

        // --- Navigation Handlers ---

        private void Header_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            e.Handled = true;
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage), "Overview");
        }

        private void Sleep_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            e.Handled = true;
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage), "Sleep");
        }

        private void Stress_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            e.Handled = true;
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage), "Stress");
        }

        private void Vitals_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            e.Handled = true;
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage), "Vitals");
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
