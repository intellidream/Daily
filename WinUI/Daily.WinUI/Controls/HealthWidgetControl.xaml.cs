using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services.Health;
using Daily.Services;
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
        private IRefreshService? _refreshService;
        private List<VitalMetric> _metrics = new();
        private SleepSession? _primarySleep;
        private List<SleepSession> _allSleepSessions = new();

        public HealthWidgetControl()
        {
            this.InitializeComponent();
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch (Exception ex) { Console.WriteLine("HEALTHWIDGET ERROR: " + ex); }
            try { _refreshService = App.Current.Services.GetService<IRefreshService>(); } catch { }
        }

        private async void UserControl_Loaded(object sender, RoutedEventArgs e)
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

            if (_healthService != null)
            {
                _healthService.OnSelectedDateChanged -= OnSelectedDateChanged;
            }
        }

        private void OnSelectedDateChanged()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
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
                    Console.WriteLine($"[HealthWidgetControl] Threaded refresh failed: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        public async Task RefreshAsync()
        {
            if (_healthService == null) return;
            try
            {
                await _healthService.PullDeltasAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthWidgetControl] Sync/Pull deltas failed on refresh: {ex.Message}");
            }
            await LoadDataAsync();
        }

        public async Task LoadDataAsync()
        {
            if (_healthService == null) return;

            try
            {
                var selDate = _healthService.SelectedDate.Date;
                _metrics = await _healthService.FetchMetricsForDateAsync(selDate);

                var (primary, all) = await _healthService.GetSleepSessionsAsync(selDate);
                _primarySleep = primary;
                _allSleepSessions = all;

                CalculateDominantSource();

                OnPropertyChanged(string.Empty);

                DrawMiniHypnogram();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthWidget] Error loading data: {ex.Message}");
            }
        }

        private VitalMetric? GetMetric(VitalType type)
        {
            var m = _metrics.FirstOrDefault(x => x.MatchesType(type));
            return m?.Value > 0 ? m : null;
        }

        // --- Bindable Properties ---

        public string FormattedDate
        {
            get
            {
                var sel = _healthService?.SelectedDate.Date ?? DateTime.Today;
                var today = DateTime.Today;
                if (sel == today) return "Today";
                if (sel == today.AddDays(-1)) return "Yesterday";
                return sel.ToString("ddd, MMM d");
            }
        }

        private string _dominantSource = "Mixed";
        public string SourceTooltip { get; private set; } = "Source: Multiple";

        public SolidColorBrush SourceDotColor
        {
            get
            {
                var color = Microsoft.UI.Colors.Transparent;
                if (_dominantSource == "iOS") color = Color.FromArgb(255, 41, 121, 255);
                else if (_dominantSource == "Health Connect" || _dominantSource == "Android") color = Color.FromArgb(255, 0, 230, 118);
                return new SolidColorBrush(color);
            }
        }

        // 1. Activity Cluster
        public double StepProgressValue
        {
            get
            {
                var m = GetMetric(VitalType.Steps);
                var val = m?.Value ?? 0;
                return Math.Clamp((val / 10000.0) * 100.0, 0, 100);
            }
        }

        public string StepGoalPercentText => $"{(int)StepProgressValue}% of goal";

        public string StepsText
        {
            get
            {
                var m = GetMetric(VitalType.Steps);
                return FormatNumber(m?.Value ?? 0);
            }
        }

        public string CaloriesText
        {
            get
            {
                var m = GetMetric(VitalType.ActiveEnergy);
                return FormatNumber(m?.Value ?? 0);
            }
        }

        public string DistanceText
        {
            get
            {
                var m = GetMetric(VitalType.Distance);
                if (m == null || m.Value <= 0) return "--";
                var km = m.Unit == "m" ? m.Value / 1000.0 : m.Value;
                return $"{km:N1} km";
            }
        }

        public string FloorsText
        {
            get
            {
                var m = GetMetric(VitalType.FloorsClimbed);
                return m?.Value > 0 ? m.Value.ToString("N0") : "--";
            }
        }

        // 2. Sleep Architecture
        public Visibility HasSleepSession => (_primarySleep != null && _primarySleep.DurationSeconds > 0) ? Visibility.Visible : Visibility.Collapsed;

        public string SleepScoreBadgeText => _primarySleep?.SleepScore > 0 ? $"Score: {_primarySleep.SleepScore}" : string.Empty;

        public string SleepDurationText
        {
            get
            {
                if (_primarySleep != null && _primarySleep.DurationSeconds > 0)
                    return _primarySleep.TotalAsleepFormatted;

                var m = GetMetric(VitalType.SleepDuration);
                return FormatSleep(m?.Value ?? 0, m?.Unit);
            }
        }

        public string SleepScheduleText
        {
            get
            {
                if (_primarySleep != null && _primarySleep.DurationSeconds > 0)
                    return $"{_primarySleep.BedtimeFormatted} → {_primarySleep.WakeTimeFormatted} • {_primarySleep.EfficiencyPercent}% eff.";
                return "No sleep recorded for this night";
            }
        }

        public Visibility HasAwakeCount => (_primarySleep?.AwakeCount > 0) ? Visibility.Visible : Visibility.Collapsed;
        public string AwakeCountBadgeText => $"{_primarySleep?.AwakeCount} awakenings";
        public string AwakeDurationBadgeText => $"{FormatSecondsShort(_primarySleep?.AwakeSeconds ?? 0)} awake";

        public string DeepSleepMicroText => $"Deep {FormatSecondsShort(_primarySleep?.DeepSeconds ?? 0)}";
        public string RemSleepMicroText => $"REM {FormatSecondsShort(_primarySleep?.RemSeconds ?? 0)}";
        public string LightSleepMicroText => $"Core {FormatSecondsShort(_primarySleep?.LightSeconds ?? 0)}";
        public string AwakeSleepMicroText => $"Awake {FormatSecondsShort(_primarySleep?.AwakeSeconds ?? 0)}";

        // 3. Vitals & Sensors
        public string HeartRatePillText
        {
            get
            {
                var m = GetMetric(VitalType.HeartRate);
                return m?.Value > 0 ? $"{m.Value:N0} bpm" : "--";
            }
        }

        public string RhrText
        {
            get
            {
                var m = GetMetric(VitalType.RestingHeartRate);
                return m?.Value > 0 ? $"{m.Value:N0} bpm" : "--";
            }
        }

        public string HrvText
        {
            get
            {
                var m = GetMetric(VitalType.HeartRateVariabilitySDNN) ?? GetMetric(VitalType.HeartRateVariabilityRMSSD);
                return m?.Value > 0 ? $"{m.Value:N0} ms" : "--";
            }
        }

        public string Spo2Text
        {
            get
            {
                var m = GetMetric(VitalType.OxygenSaturation);
                return m?.Value > 0 ? $"{m.Value:N0}%" : "--";
            }
        }

        public string RespText
        {
            get
            {
                var m = GetMetric(VitalType.RespiratoryRate);
                return m?.Value > 0 ? $"{m.Value:N0} br/m" : "--";
            }
        }

        public Visibility HasExtraVitals => (HasStress == Visibility.Visible || HasPai == Visibility.Visible || HasBp == Visibility.Visible) ? Visibility.Visible : Visibility.Collapsed;

        public Visibility HasStress => (GetMetric(VitalType.Stress)?.Value > 0) ? Visibility.Visible : Visibility.Collapsed;
        public string StressText => $"Stress: {GetMetric(VitalType.Stress)?.Value:N0}";
        public SolidColorBrush StressBrush
        {
            get
            {
                var v = GetMetric(VitalType.Stress)?.Value ?? 0;
                if (v < 30) return new SolidColorBrush(Color.FromArgb(255, 0, 230, 118));
                if (v < 60) return new SolidColorBrush(Color.FromArgb(255, 255, 213, 79));
                if (v < 80) return new SolidColorBrush(Color.FromArgb(255, 255, 152, 0));
                return new SolidColorBrush(Color.FromArgb(255, 255, 82, 82));
            }
        }

        public Visibility HasPai => (GetMetric(VitalType.PAI)?.Value > 0) ? Visibility.Visible : Visibility.Collapsed;
        public string PaiText => $"{GetMetric(VitalType.PAI)?.Value:N0} PAI";

        public Visibility HasBp
        {
            get
            {
                var s = GetMetric(VitalType.BloodPressureSystolic);
                var d = GetMetric(VitalType.BloodPressureDiastolic);
                return (s?.Value > 0 && d?.Value > 0) ? Visibility.Visible : Visibility.Collapsed;
            }
        }
        public string BpText
        {
            get
            {
                var s = GetMetric(VitalType.BloodPressureSystolic)?.Value ?? 0;
                var d = GetMetric(VitalType.BloodPressureDiastolic)?.Value ?? 0;
                return $"BP: {s:N0}/{d:N0}";
            }
        }

        // 4. Hydration & Weight
        public double WaterProgressValue
        {
            get
            {
                var m = GetMetric(VitalType.Hydration);
                if (m == null || m.Value <= 0) return 0;
                var ml = m.Value > 20 ? m.Value : m.Value * 1000.0;
                return Math.Clamp((ml / 2500.0) * 100.0, 0, 100);
            }
        }

        public string WaterPercentText => $"{(int)WaterProgressValue}%";

        public string WaterText
        {
            get
            {
                var m = GetMetric(VitalType.Hydration);
                if (m == null || m.Value <= 0) return "--";
                var ml = m.Value > 20 ? m.Value : m.Value * 1000.0;
                return $"{ml:N0} / 2,500 ml";
            }
        }

        public string WeightText
        {
            get
            {
                var m = GetMetric(VitalType.Weight);
                return m?.Value > 0 ? $"{m.Value:N1} kg" : "--";
            }
        }

        public string BmiText
        {
            get
            {
                var m = GetMetric(VitalType.BodyMassIndex);
                return m?.Value > 0 ? $"BMI: {m.Value:N1}" : "--";
            }
        }

        public Visibility IsWeightHistorical
        {
            get
            {
                var m = GetMetric(VitalType.Weight);
                return m != null && m.IsHistorical ? Visibility.Visible : Visibility.Collapsed;
            }
        }

        public string WeightDateBadgeText
        {
            get
            {
                var m = GetMetric(VitalType.Weight);
                return m != null && m.IsHistorical ? m.Date.ToString("MMM d") : string.Empty;
            }
        }

        // --- Helpers ---

        private void MiniHypnogramCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            DrawMiniHypnogram();
        }

        private void DrawMiniHypnogram()
        {
            if (MiniHypnogramCanvas == null) return;
            MiniHypnogramCanvas.Children.Clear();

            if (_primarySleep == null || _primarySleep.DurationSeconds <= 0) return;

            double canvasWidth = MiniHypnogramCanvas.ActualWidth;
            double canvasHeight = MiniHypnogramCanvas.ActualHeight;
            if (canvasWidth <= 0 || canvasHeight <= 0) return;

            if (_primarySleep.Stages != null && _primarySleep.Stages.Any())
            {
                var start = _primarySleep.StartTime;
                var end = _primarySleep.EndTime;
                var totalSec = Math.Max(1.0, (end - start).TotalSeconds);

                foreach (var stg in _primarySleep.Stages.OrderBy(x => x.LocalStartTime))
                {
                    double left = ((stg.LocalStartTime - start).TotalSeconds / totalSec) * canvasWidth;
                    double dur = Math.Max((stg.LocalEndTime - stg.LocalStartTime).TotalSeconds, stg.DurationSeconds);
                    double width = Math.Max((dur / totalSec) * canvasWidth, 2.0);

                    var color = stg.SleepCategory switch
                    {
                        "Awake" => Color.FromArgb(255, 255, 112, 67),
                        "REM" => Color.FromArgb(255, 38, 198, 218),
                        "Deep" => Color.FromArgb(255, 57, 73, 171),
                        _ => Color.FromArgb(255, 66, 165, 245)
                    };

                    var rect = new Microsoft.UI.Xaml.Shapes.Rectangle
                    {
                        Width = width,
                        Height = canvasHeight,
                        Fill = new SolidColorBrush(color)
                    };
                    Canvas.SetLeft(rect, left);
                    Canvas.SetTop(rect, 0);
                    MiniHypnogramCanvas.Children.Add(rect);
                }
            }
            else
            {
                double totalSec = _primarySleep.DurationSeconds;
                if (totalSec <= 0) return;
                double curX = 0;
                void AddBlock(double sec, Color col)
                {
                    if (sec <= 0) return;
                    double w = (sec / totalSec) * canvasWidth;
                    var r = new Microsoft.UI.Xaml.Shapes.Rectangle { Width = w, Height = canvasHeight, Fill = new SolidColorBrush(col) };
                    Canvas.SetLeft(r, curX);
                    Canvas.SetTop(r, 0);
                    MiniHypnogramCanvas.Children.Add(r);
                    curX += w;
                }
                AddBlock(_primarySleep.DeepSeconds, Color.FromArgb(255, 57, 73, 171));
                AddBlock(_primarySleep.RemSeconds, Color.FromArgb(255, 38, 198, 218));
                AddBlock(_primarySleep.LightSeconds, Color.FromArgb(255, 66, 165, 245));
                AddBlock(_primarySleep.AwakeSeconds, Color.FromArgb(255, 255, 112, 67));
            }
        }

        private void CalculateDominantSource()
        {
            var sourced = _metrics.Where(m => !string.IsNullOrEmpty(m.SourceDevice)).ToList();
            if (sourced.Any())
            {
                int iosCount = sourced.Count(m => m.SourceDevice == "iOS");
                int androidCount = sourced.Count(m => m.SourceDevice == "Health Connect" || m.SourceDevice == "Android");
                int total = sourced.Count;
                if (total > 0 && (double)iosCount / total >= 0.70) _dominantSource = "iOS";
                else if (total > 0 && (double)androidCount / total >= 0.70) _dominantSource = "Health Connect";
                else _dominantSource = "Mixed";
                SourceTooltip = $"iOS: {iosCount}, Android: {androidCount}";
            }
            else
            {
                _dominantSource = "Mixed";
                SourceTooltip = "Source: Multiple";
            }
        }

        private string FormatNumber(double val)
        {
            if (val >= 1000) return (val / 1000.0).ToString("N1") + "k";
            return val > 0 ? val.ToString("N0") : "--";
        }

        private string FormatSleep(double rawValue, string? unit)
        {
            if (rawValue <= 0) return "--";
            double minutes = Daily_WinUI.Services.SettingsService.ConvertSleepToMinutes(rawValue, unit);
            var ts = TimeSpan.FromMinutes(minutes);
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
        }

        private string FormatSecondsShort(double sec)
        {
            if (sec <= 0) return "--";
            var ts = TimeSpan.FromSeconds(sec);
            if (ts.TotalHours >= 1) return $"{(int)ts.TotalHours}h{ts.Minutes}m";
            return $"{ts.Minutes}m";
        }

        private void Header_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            if (_healthService != null) _healthService.CurrentViewType = "Overview";
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage));
        }

        private void Sleep_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            if (_healthService != null) _healthService.CurrentViewType = "Sleep";
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage));
        }

        private void Sensors_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            if (_healthService != null) _healthService.CurrentViewType = "Sensors";
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage));
        }

        private void Nutrition_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            if (_healthService != null) _healthService.CurrentViewType = "Nutrition";
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage));
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}


