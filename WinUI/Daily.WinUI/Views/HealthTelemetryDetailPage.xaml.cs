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
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace Daily_WinUI.Views
{
    public sealed partial class HealthTelemetryDetailPage : Page, INotifyPropertyChanged
    {
        private IHealthService? _healthService;
        private IRefreshService? _refreshService;
        private List<HealthTelemetry> _telemetryData = new();
        private List<HealthTelemetry> _sleepEntries = new();

        public List<HealthTelemetry> HeartRateData { get; private set; } = new();
        public List<HealthTelemetry> StepsData { get; private set; } = new();

        private DateTime _sleepMinTime = DateTime.MinValue;
        private DateTime _sleepMaxTime = DateTime.MinValue;

        private int _sleepScore = 0;
        private int _sleepEfficiency = 0;
        private int _restorativePct = 0;
        private int _awakeCount = 0;
        private string _totalSleepFormatted = "--";
        private string _timeInBedFormatted = "--";
        private string _deepDurationFormatted = "--";
        private string _remDurationFormatted = "--";
        private string _lightDurationFormatted = "--";
        private string _awakeDurationFormatted = "--";
        private int _deepPct = 0;
        private int _remPct = 0;
        private int _lightPct = 0;
        private int _awakePct = 0;

        private double _avgHr = 0;
        private int _hrRestingPct = 70;
        private int _hrFatBurnPct = 20;
        private int _hrCardioPct = 8;
        private int _hrPeakPct = 2;
        private double _totalSteps = 0;

        private SleepSession? _primarySleepSession;
        private List<SleepSession> _allSleepSessions = new();

        public HealthTelemetryDetailPage()
        {
            this.InitializeComponent();
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch { }
            try { _refreshService = App.Current.Services.GetService<IRefreshService>(); } catch { }
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
                UpdateDayNavigatorUi();
            }

            var task = LoadDataAsync();
            MainPage.Current?.RegisterLoadingTask(task);
            await task;
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
        }

        private void OnSelectedDateChanged()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                UpdateDayNavigatorUi();
                await LoadDataAsync();
            });
        }

        private void UpdateDayNavigatorUi()
        {
            if (_healthService == null || SelectedDateTextBlock == null) return;
            var sel = _healthService.SelectedDate.Date;
            var today = DateTime.Today;
            if (sel == today)
            {
                SelectedDateTextBlock.Text = $"Today, {sel:ddd, MMM d, yyyy}";
                if (NextDayButton != null) NextDayButton.IsEnabled = false;
                if (JumpTodayButton != null) JumpTodayButton.Visibility = Visibility.Collapsed;
            }
            else if (sel == today.AddDays(-1))
            {
                SelectedDateTextBlock.Text = $"Yesterday, {sel:ddd, MMM d, yyyy}";
                if (NextDayButton != null) NextDayButton.IsEnabled = true;
                if (JumpTodayButton != null) JumpTodayButton.Visibility = Visibility.Visible;
            }
            else
            {
                SelectedDateTextBlock.Text = $"{sel:ddd, MMM d, yyyy}";
                if (NextDayButton != null) NextDayButton.IsEnabled = sel < today;
                if (JumpTodayButton != null) JumpTodayButton.Visibility = Visibility.Visible;
            }
        }

        private void PrevDayButton_Click(object sender, RoutedEventArgs e)
        {
            if (_healthService != null)
            {
                _healthService.SelectedDate = _healthService.SelectedDate.AddDays(-1);
            }
        }

        private void NextDayButton_Click(object sender, RoutedEventArgs e)
        {
            if (_healthService != null && _healthService.SelectedDate.Date < DateTime.Today)
            {
                _healthService.SelectedDate = _healthService.SelectedDate.AddDays(1);
            }
        }

        private void JumpTodayButton_Click(object sender, RoutedEventArgs e)
        {
            if (_healthService != null)
            {
                _healthService.SelectedDate = DateTime.Today;
            }
        }

        private Task OnRefreshRequested()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                try { await LoadDataAsync(); }
                catch (Exception ex) { Console.WriteLine($"[HealthTelemetryDetail] Refresh error: {ex.Message}"); }
            });
            return Task.CompletedTask;
        }

        public async Task LoadDataAsync()
        {
            if (_healthService == null) return;

            try
            {
                var selDate = _healthService.SelectedDate.Date;

                var (primary, all) = await _healthService.GetSleepSessionsAsync(selDate);
                _primarySleepSession = primary;
                _allSleepSessions = all;

                var startOfDay = selDate;
                var endOfDay = selDate.AddDays(1).AddTicks(-1);
                _telemetryData = await _healthService.GetHealthTelemetryAsync(startOfDay, endOfDay);

                // Heart Rate - strictly bounded to selDate
                HeartRateData = _telemetryData
                    .Where(x => x.IsHeartRate && x.LocalStartTime.Date == selDate && x.Value.HasValue)
                    .OrderBy(x => x.LocalStartTime)
                    .ToList();

                if (HeartRateData.Any())
                {
                    _avgHr = Math.Round(HeartRateData.Average(x => x.Value!.Value), 0);
                    var total = HeartRateData.Count;
                    _hrRestingPct = (int)((HeartRateData.Count(x => x.Value < 100) / (double)total) * 100);
                    _hrFatBurnPct = (int)((HeartRateData.Count(x => x.Value >= 100 && x.Value < 120) / (double)total) * 100);
                    _hrCardioPct = (int)((HeartRateData.Count(x => x.Value >= 120 && x.Value < 150) / (double)total) * 100);
                    _hrPeakPct = Math.Max(0, 100 - (_hrRestingPct + _hrFatBurnPct + _hrCardioPct));
                }
                else
                {
                    _avgHr = 0;
                    _hrRestingPct = 0; _hrFatBurnPct = 0; _hrCardioPct = 0; _hrPeakPct = 0;
                }

                // Steps - strictly bounded to selDate
                StepsData = _telemetryData
                    .Where(x => x.IsSteps && x.LocalStartTime.Date == selDate && x.Value.HasValue)
                    .OrderBy(x => x.LocalStartTime)
                    .ToList();

                _totalSteps = StepsData.Sum(x => x.Value ?? 0);

                // Sleep - strictly bounded to the primary session for selDate
                if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0)
                {
                    _sleepEntries = _primarySleepSession.Stages;
                    _sleepMinTime = _primarySleepSession.StartTime;
                    _sleepMaxTime = _primarySleepSession.EndTime;

                    var asleepSec = _primarySleepSession.DurationSeconds - _primarySleepSession.AwakeSeconds;
                    var inBedSec = _primarySleepSession.DurationSeconds;

                    _totalSleepFormatted = _primarySleepSession.TotalAsleepFormatted;
                    _timeInBedFormatted = FormatSeconds(inBedSec);
                    _deepDurationFormatted = FormatSeconds(_primarySleepSession.DeepSeconds);
                    _remDurationFormatted = FormatSeconds(_primarySleepSession.RemSeconds);
                    _lightDurationFormatted = FormatSeconds(_primarySleepSession.LightSeconds);
                    _awakeDurationFormatted = FormatSeconds(_primarySleepSession.AwakeSeconds);

                    _awakeCount = _primarySleepSession.AwakeCount;
                    _deepPct = _primarySleepSession.DeepPercent;
                    _remPct = _primarySleepSession.RemPercent;
                    _lightPct = _primarySleepSession.LightPercent;
                    _awakePct = _primarySleepSession.AwakePercent;
                    _restorativePct = _primarySleepSession.RestorativePercent;
                    _sleepEfficiency = _primarySleepSession.EfficiencyPercent;
                    _sleepScore = _primarySleepSession.SleepScore;
                }
                else
                {
                    _sleepEntries = new();
                    _sleepMinTime = DateTime.MinValue;
                    _sleepMaxTime = DateTime.MinValue;
                    _totalSleepFormatted = "--";
                    _timeInBedFormatted = "--";
                    _deepDurationFormatted = "--";
                    _remDurationFormatted = "--";
                    _lightDurationFormatted = "--";
                    _awakeDurationFormatted = "--";
                    _awakeCount = 0;
                    _deepPct = 0; _remPct = 0; _lightPct = 0; _awakePct = 0;
                    _restorativePct = 0;
                    _sleepEfficiency = 0;
                    _sleepScore = 0;
                }

                OnPropertyChanged(string.Empty);

                DrawSleepHypnogram();
                DrawSleepXAxis();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthTelemetryDetail] LoadDataAsync error: {ex.Message}");
            }
        }

        private void SleepHypnogramCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            DrawSleepHypnogram();
            DrawSleepXAxis();
        }

        private void DrawSleepHypnogram()
        {
            if (SleepHypnogramCanvas == null) return;
            SleepHypnogramCanvas.Children.Clear();

            if (_sleepEntries == null || !_sleepEntries.Any()) return;

            double canvasWidth = SleepHypnogramCanvas.ActualWidth;
            double canvasHeight = SleepHypnogramCanvas.ActualHeight;
            if (canvasWidth <= 0 || canvasHeight <= 0) return;

            double totalSeconds = (_sleepMaxTime - _sleepMinTime).TotalSeconds;
            if (totalSeconds <= 0) return;

            double rowHeight = 32;
            double[] rowTops = new double[] { 6, 46, 86, 126 };

            // Horizontal dashed guideline borders
            for (int r = 0; r < 4; r++)
            {
                var laneGuide = new Microsoft.UI.Xaml.Shapes.Rectangle
                {
                    Width = canvasWidth,
                    Height = 1,
                    Fill = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255))
                };
                Canvas.SetLeft(laneGuide, 0);
                Canvas.SetTop(laneGuide, rowTops[r] + rowHeight + 2);
                SleepHypnogramCanvas.Children.Add(laneGuide);
            }

            // Vertical hourly grid lines
            var startHour = new DateTime(_sleepMinTime.Year, _sleepMinTime.Month, _sleepMinTime.Day, _sleepMinTime.Hour, 0, 0);
            var endHour = _sleepMaxTime.AddHours(1);
            for (var cur = startHour; cur <= endHour; cur = cur.AddHours(1))
            {
                if (cur >= _sleepMinTime && cur <= _sleepMaxTime)
                {
                    double left = ((cur - _sleepMinTime).TotalSeconds / totalSeconds) * canvasWidth;
                    var line = new Microsoft.UI.Xaml.Shapes.Rectangle
                    {
                        Width = 1,
                        Height = canvasHeight,
                        Fill = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255))
                    };
                    Canvas.SetLeft(line, left);
                    Canvas.SetTop(line, 0);
                    SleepHypnogramCanvas.Children.Add(line);
                }
            }

            // Sleep stage blocks
            foreach (var item in _sleepEntries)
            {
                double left = ((item.LocalStartTime - _sleepMinTime).TotalSeconds / totalSeconds) * canvasWidth;
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

            if (_sleepEntries == null || !_sleepEntries.Any()) return;

            double canvasWidth = SleepXAxisCanvas.ActualWidth;
            if (canvasWidth <= 0) return;

            double totalSeconds = (_sleepMaxTime - _sleepMinTime).TotalSeconds;
            if (totalSeconds <= 0) return;

            var startHour = new DateTime(_sleepMinTime.Year, _sleepMinTime.Month, _sleepMinTime.Day, _sleepMinTime.Hour, 0, 0);
            var endHour = _sleepMaxTime.AddHours(1);
            for (var cur = startHour; cur <= endHour; cur = cur.AddHours(1))
            {
                if (cur >= _sleepMinTime && cur <= _sleepMaxTime)
                {
                    double left = ((cur - _sleepMinTime).TotalSeconds / totalSeconds) * canvasWidth;
                    var tb = new TextBlock
                    {
                        Text = cur.ToString("HH:mm"),
                        FontSize = 10,
                        Opacity = 0.5
                    };
                    Canvas.SetLeft(tb, Math.Max(0, left - 14));
                    Canvas.SetTop(tb, 2);
                    SleepXAxisCanvas.Children.Add(tb);
                }
            }
        }

        private string FormatSeconds(double s)
        {
            if (s <= 0) return "--";
            var ts = TimeSpan.FromSeconds(s);
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
        }

        // Bindable properties
        public string SleepScoreText => _sleepScore > 0 ? _sleepScore.ToString() : "--";
        public string SleepScheduleText => _sleepMinTime != DateTime.MinValue && _sleepMaxTime != DateTime.MinValue
            ? $"Bed: {_sleepMinTime:HH:mm} • Wake: {_sleepMaxTime:HH:mm}"
            : "Wearable schedule not recorded";
        public string SleepEfficiencyText => $"Efficiency: {_sleepEfficiency}%";
        public string TotalSleepText => _totalSleepFormatted;
        public string TimeInBedText => _timeInBedFormatted;
        public string AwakeCountText => _awakeCount.ToString();
        public string RestorativePctText => $"{_restorativePct}%";

        public string DeepDurationText => _deepDurationFormatted;
        public string RemDurationText => _remDurationFormatted;
        public string LightDurationText => _lightDurationFormatted;
        public string AwakeDurationText => _awakeDurationFormatted;
        public string DeepPercentText => $"{_deepPct}% of total";
        public string RemPercentText => $"{_remPct}% of total";
        public string LightPercentText => $"{_lightPct}% of total";
        public string AwakePercentText => $"{_awakePct}% in bed";

        public string AvgHeartRateText => _avgHr > 0 ? $"{_avgHr:N0} BPM AVG" : "--";
        public string HrRestingPctText => $"{_hrRestingPct}%";
        public string HrFatBurnPctText => $"{_hrFatBurnPct}%";
        public string HrCardioPctText => $"{_hrCardioPct}%";
        public string HrPeakPctText => $"{_hrPeakPct}%";

        public string TotalStepsText => _totalSteps > 0 ? $"{_totalSteps:N0} steps" : "--";

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
