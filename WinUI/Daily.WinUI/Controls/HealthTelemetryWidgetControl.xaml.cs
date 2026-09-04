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

namespace Daily_WinUI.Controls
{
    public sealed partial class HealthTelemetryWidgetControl : UserControl, INotifyPropertyChanged
    {
        private IHealthService _healthService;
        private List<HealthTelemetry> _telemetryData = new();

        public HealthTelemetryWidgetControl()
        {
            this.InitializeComponent();
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch (Exception ex) { Console.WriteLine("HEALTHTELEMETRYWIDGET ERROR: " + ex); }
        }

        private async void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            var task = LoadDataAsync();
            MainPage.Current?.RegisterLoadingTask(task);
            await task;
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
        }

        public async Task LoadDataAsync()
        {
            if (_healthService == null) return;

            try
            {
                var yesterdayEvening = DateTime.Today.AddDays(-1).AddHours(20);
                var endOfToday = DateTime.Today.AddDays(1).AddTicks(-1);

                _telemetryData = await _healthService.GetHealthTelemetryAsync(yesterdayEvening, endOfToday);

                OnPropertyChanged(nameof(HeartRateData));
                OnPropertyChanged(nameof(TotalSteps));
                OnPropertyChanged(nameof(TotalSleep));
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthTelemetryWidget] Error loading data: {ex.Message}");
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

        public string TotalSteps
        {
            get
            {
                var today = DateTime.Today;
                var steps = _telemetryData.Where(x => x.TypeString == "Steps" && x.StartTime >= today).Sum(x => x.Value);
                return steps > 0 ? steps.ToString("N0") : "--";
            }
        }

        public string TotalSleep
        {
            get
            {
                var sleepTypes = new[] { "SleepAsleep", "SleepDeep", "SleepLight", "SleepREM", "SleepCore" };
                // Calculate total duration in hours where type is a sleep type (excluding Awake)
                var sleepDurationSeconds = _telemetryData
                    .Where(x => sleepTypes.Contains(x.TypeString))
                    .Sum(x => (x.EndTime - x.StartTime).TotalSeconds);

                if (sleepDurationSeconds <= 0) return "--";

                var ts = TimeSpan.FromSeconds(sleepDurationSeconds);
                return $"{(int)ts.TotalHours}h {ts.Minutes}m";
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}
