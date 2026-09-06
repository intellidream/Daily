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
    public sealed partial class HealthTelemetryWidgetControl : UserControl, INotifyPropertyChanged
    {
        private IHealthService? _healthService;
        private IRefreshService? _refreshService;
        private List<HealthTelemetry> _telemetryData = new();
        private SleepSession? _primarySleep;
        private List<SleepSession> _allSleepSessions = new();
        private List<VitalMetric> _metrics = new();

        public HealthTelemetryWidgetControl()
        {
            this.InitializeComponent();
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch (Exception ex) { Console.WriteLine("HEALTHTELEMETRYWIDGET ERROR: " + ex); }
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
                    Console.WriteLine($"[HealthTelemetryWidget] Refresh error: {ex.Message}");
                }
            });
            return Task.CompletedTask;
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

                var startOfDay = selDate;
                var endOfDay = selDate.AddDays(1).AddTicks(-1);
                _telemetryData = await _healthService.GetHealthTelemetryAsync(startOfDay, endOfDay);

                OnPropertyChanged(string.Empty);

                DrawMiniHypnogram();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthTelemetryWidget] Error loading data: {ex.Message}");
            }
        }

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

        public List<HealthTelemetry> HeartRateData
        {
            get
            {
                var selDate = _healthService?.SelectedDate.Date ?? DateTime.Today;
                return _telemetryData
                    .Where(x => x.IsHeartRate && x.Value.HasValue && x.LocalStartTime.Date == selDate)
                    .OrderBy(x => x.StartTime)
                    .ToList();
            }
        }

        public string HrRangeText
        {
            get
            {
                var hr = HeartRateData;
                if (!hr.Any()) return string.Empty;
                var min = hr.Min(x => x.Value!.Value);
                var max = hr.Max(x => x.Value!.Value);
                return $"Range: {min:N0} - {max:N0} bpm";
            }
        }

        public string AvgHrText
        {
            get
            {
                var hr = HeartRateData;
                if (!hr.Any()) return "--";
                return $"{Math.Round(hr.Average(x => x.Value!.Value), 0):N0} bpm";
            }
        }

        public string HrCountText => HeartRateData.Count > 0 ? HeartRateData.Count.ToString() : "--";

        public string StressText
        {
            get
            {
                var m = _metrics.FirstOrDefault(x => x.MatchesType(VitalType.Stress));
                return m?.Value > 0 ? $"{m.Value:N0}" : "--";
            }
        }

        public SolidColorBrush StressBrush
        {
            get
            {
                var m = _metrics.FirstOrDefault(x => x.MatchesType(VitalType.Stress));
                var v = m?.Value ?? 0;
                if (v <= 0) return new SolidColorBrush(Color.FromArgb(255, 255, 255, 255));
                if (v < 30) return new SolidColorBrush(Color.FromArgb(255, 0, 230, 118));
                if (v < 60) return new SolidColorBrush(Color.FromArgb(255, 255, 213, 79));
                if (v < 80) return new SolidColorBrush(Color.FromArgb(255, 255, 152, 0));
                return new SolidColorBrush(Color.FromArgb(255, 255, 82, 82));
            }
        }

        public string PaiText
        {
            get
            {
                var m = _metrics.FirstOrDefault(x => x.MatchesType(VitalType.PAI));
                return m?.Value > 0 ? $"{m.Value:N0}" : "--";
            }
        }

        public string TotalSteps
        {
            get
            {
                var selDate = _healthService?.SelectedDate.Date ?? DateTime.Today;
                var m = _metrics.FirstOrDefault(x => x.MatchesType(VitalType.Steps));
                if (m?.Value > 0) return m.Value.ToString("N0");

                var steps = _telemetryData
                    .Where(x => x.IsSteps && x.LocalStartTime.Date == selDate)
                    .Sum(x => x.Value ?? 0);
                return steps > 0 ? steps.ToString("N0") : "--";
            }
        }

        public string StepGoalPercentText
        {
            get
            {
                var selDate = _healthService?.SelectedDate.Date ?? DateTime.Today;
                var m = _metrics.FirstOrDefault(x => x.MatchesType(VitalType.Steps));
                var steps = m?.Value ?? _telemetryData.Where(x => x.IsSteps && x.LocalStartTime.Date == selDate).Sum(x => x.Value ?? 0);
                var pct = Math.Min(100, (int)((steps / 10000.0) * 100));
                return $"{pct}%";
            }
        }

        public Visibility HasSleepSession => (_primarySleep != null && _primarySleep.DurationSeconds > 0) ? Visibility.Visible : Visibility.Collapsed;

        public string SleepScoreText => _primarySleep?.SleepScore > 0 ? $"Score: {_primarySleep.SleepScore}" : string.Empty;

        public string TotalSleep
        {
            get
            {
                if (_primarySleep != null && _primarySleep.DurationSeconds > 0)
                    return _primarySleep.TotalAsleepFormatted;

                var m = _metrics.FirstOrDefault(x => x.MatchesType(VitalType.SleepDuration));
                if (m?.Value > 0)
                {
                    double min = Daily_WinUI.Services.SettingsService.ConvertSleepToMinutes(m.Value, m.Unit);
                    var ts = TimeSpan.FromMinutes(min);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }

                return "--";
            }
        }

        public string SleepScheduleText
        {
            get
            {
                if (_primarySleep != null && _primarySleep.DurationSeconds > 0)
                    return $"{_primarySleep.BedtimeFormatted} - {_primarySleep.WakeTimeFormatted}";
                return string.Empty;
            }
        }

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

        private void Header_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            if (_healthService != null) _healthService.CurrentViewType = "Sensors";
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthTelemetryDetailPage));
        }

        private void Sleep_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            if (_healthService != null) _healthService.CurrentViewType = "Sleep";
            MainPage.Current?.OpenDetailWindow(typeof(Views.HealthDetailPage));
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
