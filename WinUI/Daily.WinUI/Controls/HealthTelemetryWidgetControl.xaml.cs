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
        private IHealthService? _healthService;
        private IRefreshService? _refreshService;
        private List<HealthTelemetry> _telemetryData = new();

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
                var yesterdayEvening = DateTime.Today.AddDays(-1).AddHours(18);
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
                return _telemetryData
                    .Where(x => x.IsHeartRate && x.Value.HasValue && x.LocalStartTime >= today)
                    .OrderBy(x => x.StartTime)
                    .ToList();
            }
        }

        public string TotalSteps
        {
            get
            {
                var today = DateTime.Today;
                var steps = _telemetryData
                    .Where(x => x.IsSteps && x.LocalStartTime >= today)
                    .Sum(x => x.Value ?? 0);
                return steps > 0 ? steps.ToString("N0") : "--";
            }
        }

        public string TotalSleep
        {
            get
            {
                var sleepSeconds = _telemetryData
                    .Where(x => x.IsSleep)
                    .Sum(x => x.DurationSeconds);

                if (sleepSeconds <= 0) return "--";

                var ts = TimeSpan.FromSeconds(sleepSeconds);
                return $"{(int)ts.TotalHours}h {ts.Minutes}m";
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
