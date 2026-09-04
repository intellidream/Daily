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
        private IHealthService _healthService;
        private List<HealthTelemetry> _telemetryData = new();

        public HealthTelemetryDetailPage()
        {
            this.InitializeComponent();
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch { }
        }

        private async void Page_Loaded(object sender, RoutedEventArgs e)
        {
            var task = LoadDataAsync();
            MainPage.Current?.RegisterLoadingTask(task);
            await task;
        }

        private void Page_Unloaded(object sender, RoutedEventArgs e)
        {
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
                return _telemetryData.Where(x => x.TypeString == "HeartRate" && x.StartTime >= today).ToList();
            }
        }

        public List<HealthTelemetry> StepsData
        {
            get
            {
                var today = DateTime.Today;
                return _telemetryData.Where(x => x.TypeString == "Steps" && x.StartTime >= today).ToList();
            }
        }

        public List<SleepChartItem> SleepData
        {
            get
            {
                var items = new List<SleepChartItem>();
                var sleepTypes = new[] { "SleepAsleep", "SleepDeep", "SleepLight", "SleepREM", "SleepCore", "SleepAwake" };
                var sleepEntries = _telemetryData
                    .Where(x => sleepTypes.Contains(x.TypeString))
                    .OrderBy(x => x.StartTime)
                    .ToList();

                foreach (var entry in sleepEntries)
                {
                    Brush color = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
                    switch (entry.TypeString)
                    {
                        case "SleepDeep": color = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 63, 81, 181)); break; // #3F51B5
                        case "SleepLight":
                        case "SleepCore": color = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 124, 77, 255)); break; // #7C4DFF
                        case "SleepREM": color = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 188, 212)); break; // #00BCD4
                        case "SleepAwake": color = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 152, 0)); break; // #FF9800
                        default: color = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 158, 158, 158)); break; // Gray
                    }

                    items.Add(new SleepChartItem
                    {
                        Category = "Sleep",
                        StartDateTime = entry.StartTime,
                        EndDateTime = entry.EndTime,
                        ColorBrush = color
                    });
                }
                return items;
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string propertyName = null)
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
    }
}
