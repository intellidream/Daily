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

namespace Daily_WinUI.Views
{
    public sealed partial class HealthTelemetryDetailPage : Page, INotifyPropertyChanged
    {
        private IHealthService? _healthService;
        private IRefreshService? _refreshService;
        private List<HealthTelemetry> _telemetryData = new();

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
                    Console.WriteLine($"[HealthTelemetryDetail] Refresh error: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        private void SleepChartContainer_SizeChanged(object sender, Microsoft.UI.Xaml.SizeChangedEventArgs e)
        {
            DrawSleepTimeline();
        }

        private void DrawSleepTimeline()
        {
            SleepChartContainer.Children.Clear();
            var data = SleepData;
            if (data == null || !data.Any()) return;

            var width = SleepChartContainer.ActualWidth;
            if (width <= 0) return;

            foreach (var item in data)
            {
                var leftOffset = (item.LeftPercentage / 100.0) * width;
                var rectWidth = Math.Max((item.WidthPercentage / 100.0) * width, 2.0);

                var border = new Border
                {
                    Background = item.ColorBrush,
                    Width = rectWidth,
                    Height = SleepChartContainer.Height,
                    HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Left,
                    Margin = new Microsoft.UI.Xaml.Thickness(leftOffset, 0, 0, 0),
                    CornerRadius = new CornerRadius(2)
                };
                ToolTipService.SetToolTip(border, $"{item.Category}: {item.StartDateTime:HH:mm} - {item.EndDateTime:HH:mm}");
                SleepChartContainer.Children.Add(border);
            }
        }

        public async Task LoadDataAsync()
        {
            if (_healthService == null) return;

            try
            {
                var yesterdayEvening = DateTime.Today.AddDays(-1).AddHours(18); // Check from 6 PM yesterday for sleep
                var endOfToday = DateTime.Today.AddDays(1).AddTicks(-1);

                _telemetryData = await _healthService.GetHealthTelemetryAsync(yesterdayEvening, endOfToday);

                OnPropertyChanged(nameof(HeartRateData));
                OnPropertyChanged(nameof(StepsData));
                OnPropertyChanged(nameof(SleepData));
                DrawSleepTimeline();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthTelemetryDetail] Error loading data: {ex.Message}");
            }
        }

        public List<HealthTelemetry> HeartRateData
        {
            get
            {
                var today = DateTime.Today;
                return _telemetryData
                    .Where(x => x.IsHeartRate && x.Value.HasValue && x.LocalStartTime >= today)
                    .OrderBy(x => x.StartTime)
                    .ToList();
            }
        }

        public List<HealthTelemetry> StepsData
        {
            get
            {
                var today = DateTime.Today;
                return _telemetryData
                    .Where(x => x.IsSteps && x.Value.HasValue && x.LocalStartTime >= today)
                    .OrderBy(x => x.StartTime)
                    .ToList();
            }
        }

        public List<SleepChartItem> SleepData
        {
            get
            {
                var items = new List<SleepChartItem>();
                var sleepEntries = _telemetryData
                    .Where(x => x.IsSleep)
                    .OrderBy(x => x.StartTime)
                    .ToList();

                if (sleepEntries.Any())
                {
                    var firstSleep = sleepEntries.Min(x => x.LocalStartTime);
                    var lastSleep = sleepEntries.Max(x => x.LocalEndTime);
                    var totalDuration = (lastSleep - firstSleep).TotalSeconds;

                    foreach (var entry in sleepEntries)
                    {
                        Brush color = entry.SleepCategory switch
                        {
                            "Deep" => new SolidColorBrush(Windows.UI.Color.FromArgb(255, 63, 81, 181)), // #3F51B5
                            "REM" => new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 188, 212)), // #00BCD4
                            "Awake" => new SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 152, 0)), // #FF9800
                            _ => new SolidColorBrush(Windows.UI.Color.FromArgb(255, 124, 77, 255)) // Core / Light #7C4DFF
                        };

                        var endTime = entry.LocalEndTime;
                        double left = totalDuration > 0 ? (entry.LocalStartTime - firstSleep).TotalSeconds / totalDuration * 100.0 : 0;
                        double width = totalDuration > 0 ? (endTime - entry.LocalStartTime).TotalSeconds / totalDuration * 100.0 : 0;

                        items.Add(new SleepChartItem
                        {
                            Category = entry.SleepCategory,
                            StartDateTime = entry.LocalStartTime,
                            EndDateTime = endTime,
                            ColorBrush = color,
                            LeftPercentage = Math.Max(left, 0),
                            WidthPercentage = Math.Max(width, 1.0)
                        });
                    }
                }
                return items;
            }
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    public class SleepChartItem
    {
        public string Category { get; set; }
        public DateTime StartDateTime { get; set; }
        public DateTime EndDateTime { get; set; }
        public Brush ColorBrush { get; set; }
        public double LeftPercentage { get; set; }
        public double WidthPercentage { get; set; }
    }
}
