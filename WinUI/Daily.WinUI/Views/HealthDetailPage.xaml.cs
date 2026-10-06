using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services.Health;
using Daily.Services;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace Daily_WinUI.Views
{
    public sealed partial class HealthDetailPage : Page, INotifyPropertyChanged
    {
        private IHealthService? _healthService;
        private IHealthHubService? _healthHubService;
        private IRefreshService? _refreshService;

        private DateTime _selectedDate = DateTime.Today;
        private HealthDailySummaryRecord? _currentSummary;
        private List<VitalMetric> _metrics = new();
        private List<HealthTelemetry> _telemetryData = new();
        private SleepSession? _primarySleepSession;
        private List<SleepSession> _allSleepSessions = new();

        private bool _isSyncing = false;
        public bool IsNotSyncing => !_isSyncing;

        // Chart Data Collections
        public ObservableCollection<HealthChartData> HourlyStepsCollection { get; } = new();
        public ObservableCollection<HealthTelemetry> HeartRateCollection { get; } = new();
        public ObservableCollection<HealthChartData> StepsHistory { get; } = new();
        public ObservableCollection<HealthChartData> HrHistory { get; } = new();
        public ObservableCollection<HealthChartData> SleepHistory { get; } = new();
        public ObservableCollection<HealthChartData> CaloriesHistory { get; } = new();
        public ObservableCollection<HealthChartData> WeightHistory { get; } = new();
        public ObservableCollection<HealthChartData> HrvHistory { get; } = new();

        // Box Breathing State
        private DispatcherTimer? _breathingTimer;
        private int _breathingPhase = 0; // 0=Inhale, 1=Hold, 2=Exhale, 3=Hold
        private int _breathingSecondsLeft = 4;
        private bool _isBreathingActive = false;

        public HealthDetailPage()
        {
            this.InitializeComponent();

            try { _healthHubService = App.Current.Services.GetService<IHealthHubService>(); } catch { }
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch { }
            try { _refreshService = App.Current.Services.GetService<IRefreshService>(); } catch { }

            if (_healthService != null)
            {
                _selectedDate = _healthService.SelectedDate.Date;
            }
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);

            if (e.Parameter is string tabName)
            {
                switch (tabName.ToLowerInvariant())
                {
                    case "sleep":
                    case "sleepstudio":
                        HealthPivot.SelectedIndex = 1;
                        break;
                    case "stress":
                    case "stressstudio":
                        HealthPivot.SelectedIndex = 2;
                        break;
                    case "heart":
                    case "vitals":
                    case "sensors":
                        HealthPivot.SelectedIndex = 3;
                        break;
                    case "trends":
                        HealthPivot.SelectedIndex = 4;
                        break;
                    default:
                        HealthPivot.SelectedIndex = 0;
                        break;
                }
            }
            else if (e.Parameter is int tabIdx && tabIdx >= 0 && tabIdx < 5)
            {
                HealthPivot.SelectedIndex = tabIdx;
            }
        }

        private async void Page_Loaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested += OnRefreshRequested;
                _refreshService.HealthRefreshRequested += OnRefreshRequested;
            }

            if (_healthService != null)
            {
                _healthService.OnSelectedDateChanged += OnSelectedDateChanged;
            }

            UpdateDayNavigatorUi();
            await LoadDataAsync();
        }

        private void Page_Unloaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested -= OnRefreshRequested;
                _refreshService.HealthRefreshRequested -= OnRefreshRequested;
            }

            if (_healthService != null)
            {
                _healthService.OnSelectedDateChanged -= OnSelectedDateChanged;
            }

            StopBreathingExercise();
        }

        private void OnSelectedDateChanged()
        {
            if (_healthService == null) return;
            DispatcherQueue.TryEnqueue(async () =>
            {
                _selectedDate = _healthService.SelectedDate.Date;
                UpdateDayNavigatorUi();
                await LoadDataAsync();
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
                    System.Diagnostics.Debug.WriteLine($"[HealthDetailPage] Refresh error: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        private void UpdateDayNavigatorUi()
        {
            var today = DateTime.Today;
            if (_selectedDate == today)
            {
                SelectedDateTextBlock.Text = $"Today, {_selectedDate:ddd, MMM d, yyyy}";
                if (NextDayButton != null) NextDayButton.IsEnabled = false;
                if (JumpTodayButton != null) JumpTodayButton.Visibility = Visibility.Collapsed;
            }
            else if (_selectedDate == today.AddDays(-1))
            {
                SelectedDateTextBlock.Text = $"Yesterday, {_selectedDate:ddd, MMM d, yyyy}";
                if (NextDayButton != null) NextDayButton.IsEnabled = true;
                if (JumpTodayButton != null) JumpTodayButton.Visibility = Visibility.Visible;
            }
            else
            {
                SelectedDateTextBlock.Text = $"{_selectedDate:ddd, MMM d, yyyy}";
                if (NextDayButton != null) NextDayButton.IsEnabled = _selectedDate < today;
                if (JumpTodayButton != null) JumpTodayButton.Visibility = Visibility.Visible;
            }
        }

        private void PrevDayButton_Click(object sender, RoutedEventArgs e)
        {
            _selectedDate = _selectedDate.AddDays(-1);
            if (_healthService != null) _healthService.SelectedDate = _selectedDate;
            else
            {
                UpdateDayNavigatorUi();
                _ = LoadDataAsync();
            }
        }

        private void NextDayButton_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedDate < DateTime.Today)
            {
                _selectedDate = _selectedDate.AddDays(1);
                if (_healthService != null) _healthService.SelectedDate = _selectedDate;
                else
                {
                    UpdateDayNavigatorUi();
                    _ = LoadDataAsync();
                }
            }
        }

        private void JumpTodayButton_Click(object sender, RoutedEventArgs e)
        {
            _selectedDate = DateTime.Today;
            if (_healthService != null) _healthService.SelectedDate = _selectedDate;
            else
            {
                UpdateDayNavigatorUi();
                _ = LoadDataAsync();
            }
        }

        private async void SyncButton_Click(object sender, RoutedEventArgs e)
        {
            await RefreshFromTitleBarAsync();
        }

        public async Task RefreshFromTitleBarAsync()
        {
            if (_isSyncing) return;
            _isSyncing = true;
            OnPropertyChanged(nameof(IsNotSyncing));

            try
            {
                if (_healthService != null)
                {
                    await _healthService.PullDeltasAsync();
                }
                await LoadDataAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[HealthDetailPage] Sync failed: {ex.Message}");
            }
            finally
            {
                _isSyncing = false;
                OnPropertyChanged(nameof(IsNotSyncing));
            }
        }

        public async Task LoadDataAsync()
        {
            try
            {
                // 1. Load canonical daily summary record from HealthHubService
                if (_healthHubService != null)
                {
                    _currentSummary = await _healthHubService.GetDailySummaryAsync(_selectedDate);
                }

                // 2. Load metrics list
                if (_healthService != null)
                {
                    _metrics = await _healthService.FetchMetricsForDateAsync(_selectedDate);
                }

                // 3. Load sleep session & hypnogram
                if (_healthService != null)
                {
                    var (primary, all) = await _healthService.GetSleepSessionsAsync(_selectedDate);
                    _primarySleepSession = primary;
                    _allSleepSessions = all;
                }

                // 4. Load intraday telemetry for continuous HR and steps
                if (_healthService != null)
                {
                    var startOfDay = _selectedDate.Date;
                    var endOfDay = startOfDay.AddDays(1).AddTicks(-1);
                    _telemetryData = await _healthService.GetHealthTelemetryAsync(startOfDay, endOfDay);
                }

                PopulateHourlySteps();
                PopulateHeartRate();
                await LoadTrendsHistoryAsync();

                NotifyAllProperties();
                DrawSleepHypnogram();
                DrawSleepXAxis();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[HealthDetailPage] LoadDataAsync error: {ex.Message}");
            }
        }

        private void PopulateHourlySteps()
        {
            HourlyStepsCollection.Clear();

            var hourlyBuckets = _currentSummary?.Summary?.Activity?.HourlySteps;
            if (hourlyBuckets != null && hourlyBuckets.Any())
            {
                for (int h = 0; h < 24; h++)
                {
                    var bucket = hourlyBuckets.FirstOrDefault(b => b.Hour == h);
                    double steps = bucket?.Steps ?? 0;
                    HourlyStepsCollection.Add(new HealthChartData
                    {
                        Label = $"{h:D2}",
                        Value = steps,
                        FormattedValue = steps > 0 ? steps.ToString("N0") : ""
                    });
                }
            }
            else
            {
                var stepsTelemetry = _telemetryData
                    .Where(x => x.IsSteps && x.LocalStartTime.Date == _selectedDate.Date)
                    .GroupBy(x => x.LocalStartTime.Hour)
                    .ToDictionary(g => g.Key, g => g.Sum(x => x.Value ?? 0));

                for (int h = 0; h < 24; h++)
                {
                    double steps = stepsTelemetry.TryGetValue(h, out var s) ? s : 0;
                    HourlyStepsCollection.Add(new HealthChartData
                    {
                        Label = $"{h:D2}",
                        Value = steps,
                        FormattedValue = steps > 0 ? steps.ToString("N0") : ""
                    });
                }
            }
        }

        private void PopulateHeartRate()
        {
            HeartRateCollection.Clear();

            var intradayHr = _currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate;
            if (intradayHr != null && intradayHr.Any())
            {
                foreach (var pt in intradayHr)
                {
                    if (DateTime.TryParse(pt.Timestamp, out var ts) && pt.Bpm > 0)
                    {
                        HeartRateCollection.Add(new HealthTelemetry
                        {
                            TypeString = "heart_rate",
                            Value = pt.Bpm,
                            Unit = "bpm",
                            StartTime = ts,
                            EndTime = ts,
                            SourceDevice = "Canonical"
                        });
                    }
                }
            }
            else
            {
                var hrPoints = _telemetryData
                    .Where(x => x.IsHeartRate && x.LocalStartTime.Date == _selectedDate.Date && x.Value.HasValue && x.Value > 0)
                    .OrderBy(x => x.LocalStartTime)
                    .ToList();

                foreach (var item in hrPoints)
                {
                    HeartRateCollection.Add(item);
                }
            }
        }

        private async Task LoadTrendsHistoryAsync()
        {
            StepsHistory.Clear();
            HrHistory.Clear();
            SleepHistory.Clear();
            CaloriesHistory.Clear();
            WeightHistory.Clear();
            HrvHistory.Clear();

            var endDate = _selectedDate.Date;
            var startDate = endDate.AddDays(-6);

            List<HealthDailySummaryRecord> rangeSummaries = new();
            if (_healthHubService != null)
            {
                rangeSummaries = await _healthHubService.GetDailySummariesRangeAsync(startDate, endDate);
            }

            for (int i = 6; i >= 0; i--)
            {
                var day = endDate.AddDays(-i);
                var dayStr = day.ToString("yyyy-MM-dd");
                var dayLabel = day.ToString("ddd");

                var summary = rangeSummaries.FirstOrDefault(s => s.LocalDate == dayStr);

                // Steps
                double steps = summary?.Steps ?? 0;
                StepsHistory.Add(new HealthChartData { Label = dayLabel, Value = steps, FormattedValue = steps > 0 ? steps.ToString("N0") : "--" });

                // HR
                double rhr = summary?.Rhr ?? 0;
                HrHistory.Add(new HealthChartData { Label = dayLabel, Value = rhr, FormattedValue = rhr > 0 ? $"{rhr:F0}" : "--" });

                // Sleep (hours)
                double sleepHours = summary?.SleepAsleepS.HasValue == true ? Math.Round(summary.SleepAsleepS.Value / 3600.0, 1) : 0;
                SleepHistory.Add(new HealthChartData { Label = dayLabel, Value = sleepHours, FormattedValue = sleepHours > 0 ? $"{sleepHours:F1}h" : "--" });

                // Calories
                double cal = summary?.ActiveKcal ?? 0;
                CaloriesHistory.Add(new HealthChartData { Label = dayLabel, Value = cal, FormattedValue = cal > 0 ? $"{cal:F0}" : "--" });

                // Weight
                double wt = summary?.Weight ?? 0;
                WeightHistory.Add(new HealthChartData { Label = dayLabel, Value = wt, FormattedValue = wt > 0 ? $"{wt:F1}" : "--" });

                // HRV
                double hrv = summary?.HrvSdnn ?? summary?.HrvRmssd ?? 0;
                HrvHistory.Add(new HealthChartData { Label = dayLabel, Value = hrv, FormattedValue = hrv > 0 ? $"{hrv:F0}" : "--" });
            }
        }

        // ==========================================
        // OVERVIEW TAB PROPERTIES
        // ==========================================

        public string StepsText => _currentSummary?.Steps?.ToString("N0") ?? GetMetricValueString(VitalType.Steps, "N0");
        public string CaloriesText => _currentSummary?.ActiveKcal?.ToString("N0") ?? GetMetricValueString(VitalType.ActiveEnergy, "N0");
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

        public string DistanceText => GetMetricValueWithUnit(VitalType.Distance, "km", 2);
        public string FloorsText => GetMetricValueWithUnit(VitalType.FloorsClimbed, "fl", 0);
        public string SpeedText => GetMetricValueWithUnit(VitalType.WalkingSpeed, "km/h", 1);

        public string HourlyStepsMaxText
        {
            get
            {
                var max = HourlyStepsCollection.Any() ? HourlyStepsCollection.Max(x => x.Value) : 0;
                return max > 0 ? $"Peak: {max:N0} steps/hr" : "";
            }
        }

        // 8 Vitals
        public string HeartRateText => GetMetricValueWithUnit(VitalType.HeartRate, "bpm", 0);
        public string RhrText => _currentSummary?.Rhr.HasValue == true ? $"{_currentSummary.Rhr.Value:F0} bpm" : GetMetricValueWithUnit(VitalType.RestingHeartRate, "bpm", 0);
        public string HrvText => _currentSummary?.HrvSdnn.HasValue == true ? $"{_currentSummary.HrvSdnn.Value:F0} ms" : GetMetricValueWithUnit(VitalType.HeartRateVariabilitySDNN, "ms", 0);
        public string Spo2Text => _currentSummary?.Spo2.HasValue == true ? $"{_currentSummary.Spo2.Value:F0}%" : GetMetricValueWithUnit(VitalType.OxygenSaturation, "%", 0);
        public string BloodPressureText
        {
            get
            {
                var sys = GetMetric(VitalType.BloodPressureSystolic);
                var dia = GetMetric(VitalType.BloodPressureDiastolic);
                if (sys != null && dia != null) return $"{sys.Value:F0}/{dia.Value:F0}";
                return "--";
            }
        }
        public string RespText => GetMetricValueWithUnit(VitalType.RespiratoryRate, "br/m", 1);
        public string GlucoseText => GetMetricValueWithUnit(VitalType.BloodGlucose, "mg/dL", 0);
        public string WeightText => _currentSummary?.Weight.HasValue == true ? $"{_currentSummary.Weight.Value:F1} kg" : GetMetricValueWithUnit(VitalType.Weight, "kg", 1);

        // Body Composition
        public string BodyFatText => GetMetricValueWithUnit(VitalType.BodyFatPercentage, "%", 1);
        public string BmiText => GetMetricValueWithUnit(VitalType.BodyMassIndex, "", 1);
        public string LeanMassText => GetMetricValueWithUnit(VitalType.LeanBodyMass, "kg", 1);

        // ==========================================
        // SLEEP STUDIO TAB PROPERTIES
        // ==========================================

        public string SleepScoreText
        {
            get
            {
                var score = _currentSummary?.SleepScore ?? _primarySleepSession?.SleepScore;
                return (score.HasValue && score.Value > 0) ? score.Value.ToString() : "--";
            }
        }

        public string SleepScheduleText
        {
            get
            {
                if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0)
                {
                    return $"{_primarySleepSession.BedtimeFormatted} - {_primarySleepSession.WakeTimeFormatted}";
                }
                var primary = _currentSummary?.Summary?.Sleep?.PrimarySession;
                if (primary != null && DateTime.TryParse(primary.StartTime, out var s) && DateTime.TryParse(primary.EndTime, out var e))
                {
                    return $"{s:HH:mm} - {e:HH:mm}";
                }
                return "No Sleep Logged";
            }
        }

        public string SleepEfficiencyText
        {
            get
            {
                if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0)
                {
                    return $"Efficiency: {_primarySleepSession.EfficiencyPercent}%";
                }
                return "Efficiency: --";
            }
        }

        public string TotalSleepText => _primarySleepSession?.TotalAsleepFormatted ?? "--";
        public string TimeInBedText => _primarySleepSession?.TimeInBedFormatted ?? "--";
        public string AwakeCountText => _primarySleepSession != null ? _primarySleepSession.AwakeCount.ToString() : "--";
        public string RestorativePctText => _primarySleepSession != null && _primarySleepSession.DurationSeconds > 0 ? $"{_primarySleepSession.RestorativePercent}%" : "--";

        public string SleepVerdictQualityText
        {
            get
            {
                var verdict = _currentSummary?.Summary?.Sleep?.Guidance?.Verdict;
                if (verdict != null && !string.IsNullOrEmpty(verdict.Headline))
                {
                    return verdict.Headline;
                }
                int score = _currentSummary?.SleepScore ?? _primarySleepSession?.SleepScore ?? 0;
                return score switch
                {
                    >= 85 => "Optimal Sleep Quality",
                    >= 75 => "Good Recovery",
                    >= 60 => "Fair / Suboptimal",
                    > 0 => "Restless / Low Recovery",
                    _ => "Awaiting Telemetry"
                };
            }
        }

        public string SleepVerdictSummaryText
        {
            get
            {
                var verdict = _currentSummary?.Summary?.Sleep?.Guidance?.Verdict;
                if (verdict != null && !string.IsNullOrEmpty(verdict.Narrative))
                {
                    return verdict.Narrative;
                }
                int score = _currentSummary?.SleepScore ?? _primarySleepSession?.SleepScore ?? 0;
                return score switch
                {
                    >= 85 => "Excellent restorative architecture with solid deep and REM cycles.",
                    >= 75 => "Healthy restorative stages supporting autonomic nervous balance.",
                    >= 60 => "Elevated wakefulness or delayed sleep onset observed.",
                    > 0 => "Short duration or insufficient deep sleep stages.",
                    _ => "Wear your smartwatch or fitness ring tonight to track sleep stages."
                };
            }
        }

        public string DeepDurationText => _primarySleepSession != null ? _primarySleepSession.DeepFormatted : "--";
        public string DeepPercentText => _primarySleepSession != null && _primarySleepSession.AsleepSeconds > 0 ? $"{_primarySleepSession.DeepPercent}%" : "--";
        public string RemDurationText => _primarySleepSession != null ? _primarySleepSession.RemFormatted : "--";
        public string RemPercentText => _primarySleepSession != null && _primarySleepSession.AsleepSeconds > 0 ? $"{_primarySleepSession.RemPercent}%" : "--";
        public string LightDurationText => _primarySleepSession != null ? _primarySleepSession.LightFormatted : "--";
        public string LightPercentText => _primarySleepSession != null && _primarySleepSession.AsleepSeconds > 0 ? $"{_primarySleepSession.LightPercent}%" : "--";
        public string AwakeDurationText => _primarySleepSession != null ? _primarySleepSession.AwakeFormatted : "--";
        public string AwakePercentText => _primarySleepSession != null && _primarySleepSession.DurationSeconds > 0 ? $"{_primarySleepSession.AwakePercent}%" : "--";

        // ==========================================
        // STRESS STUDIO TAB PROPERTIES
        // ==========================================

        public string StressScoreText => _currentSummary?.StressAvg?.ToString() ?? GetMetricValueString(VitalType.Stress, "0");

        public string MonkeyMoodEmoji
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood?.ToLowerInvariant() ?? "zen";
                return mood switch
                {
                    "zen" => "🧘",
                    "calm" => "🍵",
                    "alert" => "👀",
                    "agitated" => "🐒",
                    _ => "🐵"
                };
            }
        }

        public string MonkeyMoodLabelText
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood?.ToLowerInvariant() ?? "zen";
                return mood switch
                {
                    "zen" => "Zen Monkey (Rest & Recovery)",
                    "calm" => "Calm Monkey (Steady Balance)",
                    "alert" => "Alert Monkey (Active Demand)",
                    "agitated" => "Agitated Monkey (High Stress)",
                    _ => "Baseline"
                };
            }
        }

        public string MonkeyMoodDescriptionText
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood?.ToLowerInvariant() ?? "zen";
                return mood switch
                {
                    "zen" => "Deeply relaxed. Your parasympathetic nervous system is dominating recovery.",
                    "calm" => "Balanced autonomic tone. Steady cognitive flow without notable strain.",
                    "alert" => "Elevated sympathetic activation. Productive drive with moderate metabolic strain.",
                    "agitated" => "Sympathetic spike detected. Take 4 minutes for box breathing to re-center.",
                    _ => "Autonomic telemetry logged regularly from your wearable sensor."
                };
            }
        }

        public SolidColorBrush MonkeyMoodBackgroundBrush
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood?.ToLowerInvariant() ?? "zen";
                return mood switch
                {
                    "zen" => new SolidColorBrush(Color.FromArgb(30, 76, 175, 80)),
                    "calm" => new SolidColorBrush(Color.FromArgb(30, 0, 188, 212)),
                    "alert" => new SolidColorBrush(Color.FromArgb(30, 255, 179, 0)),
                    "agitated" => new SolidColorBrush(Color.FromArgb(30, 244, 67, 54)),
                    _ => new SolidColorBrush(Color.FromArgb(30, 150, 150, 150))
                };
            }
        }

        public SolidColorBrush MonkeyMoodBorderBrush
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood?.ToLowerInvariant() ?? "zen";
                return mood switch
                {
                    "zen" => new SolidColorBrush(Color.FromArgb(255, 76, 175, 80)),
                    "calm" => new SolidColorBrush(Color.FromArgb(255, 0, 188, 212)),
                    "alert" => new SolidColorBrush(Color.FromArgb(255, 255, 179, 0)),
                    "agitated" => new SolidColorBrush(Color.FromArgb(255, 244, 67, 54)),
                    _ => new SolidColorBrush(Color.FromArgb(255, 150, 150, 150))
                };
            }
        }

        public string AutonomicDominantText
        {
            get
            {
                var ab = _currentSummary?.Summary?.Stress?.AutonomicBalance;
                if (ab != null)
                {
                    return ab.ParasympatheticPercent >= ab.SympatheticPercent
                        ? "Parasympathetic Dominant (Recovery)"
                        : "Sympathetic Dominant (Activation)";
                }
                return "Balanced Autonomic State";
            }
        }

        public double ParasympatheticRatioPct
        {
            get
            {
                var ab = _currentSummary?.Summary?.Stress?.AutonomicBalance;
                if (ab != null && (ab.ParasympatheticPercent > 0 || ab.SympatheticPercent > 0))
                {
                    return ab.ParasympatheticPercent;
                }
                return 65;
            }
        }

        public string SympatheticLabelText
        {
            get
            {
                double sym = 100 - ParasympatheticRatioPct;
                return $"Sympathetic: {sym:F0}%";
            }
        }

        public string ParasympatheticLabelText => $"Parasympathetic: {ParasympatheticRatioPct:F0}%";

        // Drivers
        public string DriverActivityText => $"{DriverActivityPct:F0}%";
        public double DriverActivityPct => 25.0;

        public string DriverSleepText => $"{DriverSleepPct:F0}%";
        public double DriverSleepPct => 20.0;

        public string DriverHrvText
        {
            get
            {
                var d = _currentSummary?.Summary?.Stress?.BiometricDrivers;
                if (d != null && d.CurrentHrvMs.HasValue && d.BaselineHrvMs > 0)
                {
                    double diff = Math.Max(0, (1.0 - (d.CurrentHrvMs.Value / d.BaselineHrvMs)) * 100);
                    return $"{diff:F0}%";
                }
                return "15%";
            }
        }

        public double DriverHrvPct
        {
            get
            {
                var d = _currentSummary?.Summary?.Stress?.BiometricDrivers;
                if (d != null && d.CurrentHrvMs.HasValue && d.BaselineHrvMs > 0)
                {
                    return Math.Clamp((1.0 - (d.CurrentHrvMs.Value / d.BaselineHrvMs)) * 100, 0, 100);
                }
                return 15.0;
            }
        }

        public string DriverSpikesText => $"{DriverSpikesPct:F0}%";
        public double DriverSpikesPct => 10.0;

        // Box Breathing
        public string BreathingButtonText => _isBreathingActive ? "Stop Exercise" : "Start Box Breathing";

        private void BreathingButton_Click(object sender, RoutedEventArgs e)
        {
            if (_isBreathingActive)
            {
                StopBreathingExercise();
            }
            else
            {
                StartBreathingExercise();
            }
        }

        private void StartBreathingExercise()
        {
            _isBreathingActive = true;
            _breathingPhase = 0;
            _breathingSecondsLeft = 4;
            UpdateBreathingUi();

            _breathingTimer ??= new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _breathingTimer.Tick += BreathingTimer_Tick;
            _breathingTimer.Start();

            OnPropertyChanged(nameof(BreathingButtonText));
        }

        private void StopBreathingExercise()
        {
            if (_breathingTimer != null)
            {
                _breathingTimer.Stop();
                _breathingTimer.Tick -= BreathingTimer_Tick;
            }
            _isBreathingActive = false;
            BreathingPhaseText.Text = "Ready";
            BreathingTimerText.Text = "4s";
            BreathingCircle.Width = 90;
            BreathingCircle.Height = 90;
            BreathingCircle.CornerRadius = new CornerRadius(45);

            OnPropertyChanged(nameof(BreathingButtonText));
        }

        private void BreathingTimer_Tick(object? sender, object e)
        {
            _breathingSecondsLeft--;
            if (_breathingSecondsLeft <= 0)
            {
                _breathingPhase = (_breathingPhase + 1) % 4;
                _breathingSecondsLeft = 4;
            }
            UpdateBreathingUi();
        }

        private void UpdateBreathingUi()
        {
            string phaseName = _breathingPhase switch
            {
                0 => "Inhale...",
                1 => "Hold Breath",
                2 => "Exhale...",
                _ => "Hold Empty"
            };

            BreathingPhaseText.Text = phaseName;
            BreathingTimerText.Text = $"{_breathingSecondsLeft}s";

            // Visual expansion / contraction
            double targetSize = _breathingPhase switch
            {
                0 => 90 + ((4 - _breathingSecondsLeft) * 7.5),
                1 => 120,
                2 => 120 - ((4 - _breathingSecondsLeft) * 7.5),
                _ => 90
            };

            BreathingCircle.Width = targetSize;
            BreathingCircle.Height = targetSize;
            BreathingCircle.CornerRadius = new CornerRadius(targetSize / 2.0);
        }

        // ==========================================
        // HEART & VITALS TAB PROPERTIES
        // ==========================================

        public string AvgHeartRateText
        {
            get
            {
                if (HeartRateCollection.Any())
                {
                    double avg = Math.Round(HeartRateCollection.Average(x => x.Value ?? 0), 0);
                    return $"{avg:F0} bpm avg";
                }
                return "-- bpm avg";
            }
        }

        public string HrRestingPctText => CalculateHrZonePercent(0, 100);
        public string HrFatBurnPctText => CalculateHrZonePercent(100, 120);
        public string HrCardioPctText => CalculateHrZonePercent(120, 150);
        public string HrPeakPctText => CalculateHrZonePercent(150, 250);

        private string CalculateHrZonePercent(double min, double max)
        {
            if (!HeartRateCollection.Any()) return "--%";
            int total = HeartRateCollection.Count;
            int count = HeartRateCollection.Count(x => (x.Value ?? 0) >= min && (x.Value ?? 0) < max);
            return total > 0 ? $"{((double)count / total) * 100:F0}%" : "0%";
        }

        // ==========================================
        // TRENDS TAB PROPERTIES
        // ==========================================

        public string StepsAvgText => CalculateTrendAvg(StepsHistory, "N0");
        public string StepsMaxText => CalculateTrendMax(StepsHistory, "N0");
        public string StepsMinText => CalculateTrendMin(StepsHistory, "N0");
        public string StepsTotalText => StepsHistory.Any(x => x.Value > 0) ? StepsHistory.Sum(x => x.Value).ToString("N0") : "--";

        public string SleepAvgText => CalculateTrendAvg(SleepHistory, "F1", "h");
        public string SleepMaxText => CalculateTrendMax(SleepHistory, "F1", "h");
        public string SleepMinText => CalculateTrendMin(SleepHistory, "F1", "h");

        public string HrAvgText => CalculateTrendAvg(HrHistory, "F0", " bpm");
        public string HrMaxText => CalculateTrendMax(HrHistory, "F0", " bpm");
        public string HrMinText => CalculateTrendMin(HrHistory, "F0", " bpm");

        public string CaloriesAvgText => CalculateTrendAvg(CaloriesHistory, "N0");
        public string CaloriesMaxText => CalculateTrendMax(CaloriesHistory, "N0");
        public string CaloriesMinText => CalculateTrendMin(CaloriesHistory, "N0");
        public string CaloriesTotalText => CaloriesHistory.Any(x => x.Value > 0) ? CaloriesHistory.Sum(x => x.Value).ToString("N0") : "--";

        private string CalculateTrendAvg(ObservableCollection<HealthChartData> coll, string format, string suffix = "")
        {
            var nonZero = coll.Where(x => x.Value > 0).ToList();
            return nonZero.Any() ? $"{nonZero.Average(x => x.Value).ToString(format)}{suffix}" : "--";
        }

        private string CalculateTrendMax(ObservableCollection<HealthChartData> coll, string format, string suffix = "")
        {
            var nonZero = coll.Where(x => x.Value > 0).ToList();
            return nonZero.Any() ? $"{nonZero.Max(x => x.Value).ToString(format)}{suffix}" : "--";
        }

        private string CalculateTrendMin(ObservableCollection<HealthChartData> coll, string format, string suffix = "")
        {
            var nonZero = coll.Where(x => x.Value > 0).ToList();
            return nonZero.Any() ? $"{nonZero.Min(x => x.Value).ToString(format)}{suffix}" : "--";
        }

        // ==========================================
        // HYPNOGRAM CANVAS RENDERING
        // ==========================================

        private void SleepHypnogramCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            DrawSleepHypnogram();
            DrawSleepXAxis();
        }

        private void DrawSleepHypnogram()
        {
            if (SleepHypnogramCanvas == null) return;
            SleepHypnogramCanvas.Children.Clear();

            var stages = _primarySleepSession?.Stages;
            if (stages == null || !stages.Any()) return;

            double canvasWidth = SleepHypnogramCanvas.ActualWidth;
            double canvasHeight = SleepHypnogramCanvas.ActualHeight;
            if (canvasWidth <= 0 || canvasHeight <= 0) return;

            var minTime = _primarySleepSession!.StartTime;
            var maxTime = _primarySleepSession.EndTime;
            double totalSeconds = (maxTime - minTime).TotalSeconds;
            if (totalSeconds <= 0) return;

            double rowHeight = 32;
            double[] rowTops = new double[] { 6, 46, 86, 126 };

            // Horizontal lane guide lines
            for (int r = 0; r < 4; r++)
            {
                var guide = new Rectangle
                {
                    Width = canvasWidth,
                    Height = 1,
                    Fill = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255))
                };
                Canvas.SetLeft(guide, 0);
                Canvas.SetTop(guide, rowTops[r] + rowHeight + 2);
                SleepHypnogramCanvas.Children.Add(guide);
            }

            // Sleep stage blocks
            foreach (var item in stages)
            {
                double left = ((item.LocalStartTime - minTime).TotalSeconds / totalSeconds) * canvasWidth;
                double duration = Math.Max((item.LocalEndTime - item.LocalStartTime).TotalSeconds, item.DurationSeconds);
                double width = Math.Max((duration / totalSeconds) * canvasWidth, 3.0);

                int rowIndex = item.SleepCategory switch
                {
                    "Awake" => 0,
                    "REM" => 1,
                    "Deep" => 3,
                    _ => 2 // Core / Light
                };

                var color = item.SleepCategory switch
                {
                    "Awake" => Color.FromArgb(255, 255, 112, 67),
                    "REM" => Color.FromArgb(255, 38, 198, 218),
                    "Deep" => Color.FromArgb(255, 57, 73, 171),
                    _ => Color.FromArgb(255, 66, 165, 245)
                };

                var block = new Border
                {
                    Width = width,
                    Height = rowHeight,
                    Background = new SolidColorBrush(color),
                    CornerRadius = new CornerRadius(4)
                };
                ToolTipService.SetToolTip(block, $"{item.SleepCategory}: {item.LocalStartTime:HH:mm} - {item.LocalEndTime:HH:mm} ({(int)(duration / 60)} min)");

                Canvas.SetLeft(block, left);
                Canvas.SetTop(block, rowTops[rowIndex]);
                SleepHypnogramCanvas.Children.Add(block);
            }
        }

        private void DrawSleepXAxis()
        {
            if (SleepXAxisCanvas == null) return;
            SleepXAxisCanvas.Children.Clear();

            var stages = _primarySleepSession?.Stages;
            if (stages == null || !stages.Any()) return;

            double canvasWidth = SleepXAxisCanvas.ActualWidth;
            if (canvasWidth <= 0) return;

            var minTime = _primarySleepSession!.StartTime;
            var maxTime = _primarySleepSession.EndTime;
            double totalSeconds = (maxTime - minTime).TotalSeconds;
            if (totalSeconds <= 0) return;

            var startHour = new DateTime(minTime.Year, minTime.Month, minTime.Day, minTime.Hour, 0, 0);
            var endHour = maxTime.AddHours(1);

            for (var cur = startHour; cur <= endHour; cur = cur.AddHours(1))
            {
                if (cur >= minTime && cur <= maxTime)
                {
                    double left = ((cur - minTime).TotalSeconds / totalSeconds) * canvasWidth;
                    var tb = new TextBlock
                    {
                        Text = cur.ToString("HH:mm"),
                        FontSize = 10,
                        Opacity = 0.5,
                        Foreground = (Brush)Application.Current.Resources["AppFgMutedColorBrush"]
                    };
                    Canvas.SetLeft(tb, Math.Max(0, left - 14));
                    Canvas.SetTop(tb, 2);
                    SleepXAxisCanvas.Children.Add(tb);
                }
            }
        }

        // ==========================================
        // TAB SELECTION & NAVIGATION
        // ==========================================

        private void HealthPivot_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (HealthPivot.SelectedIndex == 1)
            {
                DrawSleepHypnogram();
                DrawSleepXAxis();
            }
        }

        private void SleepPreview_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            HealthPivot.SelectedIndex = 1;
        }

        private void StressPreview_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            HealthPivot.SelectedIndex = 2;
        }

        // ==========================================
        // HELPERS & PROPERTY CHANGED NOTIFICATIONS
        // ==========================================

        private VitalMetric? GetMetric(VitalType type)
        {
            return _metrics.FirstOrDefault(x => x.MatchesType(type) && x.Value > 0);
        }

        private string GetMetricValueString(VitalType type, string format)
        {
            var m = GetMetric(type);
            return m?.Value.ToString(format) ?? "--";
        }

        private string GetMetricValueWithUnit(VitalType type, string fallbackUnit, int decimals)
        {
            var m = GetMetric(type);
            if (m == null || m.Value <= 0) return "--";
            string format = decimals > 0 ? $"F{decimals}" : "F0";
            string unit = !string.IsNullOrEmpty(m.Unit) ? m.Unit : fallbackUnit;
            return string.IsNullOrEmpty(unit) ? m.Value.ToString(format) : $"{m.Value.ToString(format)} {unit}";
        }

        private void NotifyAllProperties()
        {
            OnPropertyChanged(string.Empty);
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    public class HealthChartData
    {
        public string Label { get; set; } = string.Empty;
        public double Value { get; set; }
        public string FormattedValue { get; set; } = string.Empty;
    }
}
