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
    public sealed partial class HealthWidgetControl : UserControl, INotifyPropertyChanged
    {
        private IHealthService _healthService;
        private IRefreshService _refreshService;
        private List<VitalMetric> _metrics = new();

        public HealthWidgetControl()
        {
            this.InitializeComponent();
            
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch (Exception ex) { Console.WriteLine("HEALTHWIDGET ERROR: " + ex); }
            _refreshService = App.Current.Services.GetService<IRefreshService>();
        }

        private async void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested += OnRefreshRequested;
                _refreshService.HealthRefreshRequested += OnRefreshRequested;
            }
            await LoadDataAsync();
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
                    Console.WriteLine($"[HealthWidgetControl] Threaded refresh failed: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        public async Task LoadDataAsync()
        {
            if (_healthService == null) return;

            try
            {
                _metrics = await _healthService.FetchMetricsAsync(DateTime.Now);

                CalculateDominantSource();

                // Notify UI
                OnPropertyChanged(nameof(SourceTooltip));
                OnPropertyChanged(nameof(SourceDotColor));

                OnPropertyChanged(nameof(StepsText));
                OnPropertyChanged(nameof(CaloriesText));
                OnPropertyChanged(nameof(HeartRateText));

                OnPropertyChanged(nameof(SleepText));
                OnPropertyChanged(nameof(DeepSleepText));
                OnPropertyChanged(nameof(LightSleepText));
                OnPropertyChanged(nameof(RemSleepText));
                OnPropertyChanged(nameof(AwakeSleepText));

                OnPropertyChanged(nameof(HrvText));
                OnPropertyChanged(nameof(RhrText));
                OnPropertyChanged(nameof(RespText));
                OnPropertyChanged(nameof(Spo2Text));
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthWidget] Error loading data: {ex.Message}");
            }
        }

        private VitalMetric GetMetric(VitalType type)
        {
            var m = _metrics.FirstOrDefault(x => x.TypeString == type.ToString());
            return m?.Value > 0 ? m : null;
        }

        // --- Bindable Properties ---

        private string _dominantSource = "Mixed";
        public string SourceTooltip { get; private set; } = "Source: Multiple";

        public Microsoft.UI.Xaml.Media.SolidColorBrush SourceDotColor
        {
            get
            {
                var color = Microsoft.UI.Colors.Transparent;
                if (_dominantSource == "iOS") color = Microsoft.UI.ColorHelper.FromArgb(255, 41, 121, 255);
                else if (_dominantSource == "Health Connect" || _dominantSource == "Android") color = Microsoft.UI.ColorHelper.FromArgb(255, 0, 230, 118);
                return new Microsoft.UI.Xaml.Media.SolidColorBrush(color);
            }
        }

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

        public string HeartRateText
        {
            get
            {
                var m = GetMetric(VitalType.HeartRate);
                return m?.Value > 0 ? m.Value.ToString("N0") : "--";
            }
        }

        public string SleepText
        {
            get
            {
                var m = GetMetric(VitalType.SleepDuration);
                return FormatSleep(m?.Value ?? 0);
            }
        }

        public string DeepSleepText => FormatSleepShort(GetMetric(VitalType.SleepDeep)?.Value ?? 0);
        public string LightSleepText => FormatSleepShort(GetMetric(VitalType.SleepLight)?.Value ?? 0);
        public string RemSleepText => FormatSleepShort(GetMetric(VitalType.SleepREM)?.Value ?? 0);
        public string AwakeSleepText => FormatSleepShort(GetMetric(VitalType.SleepAwake)?.Value ?? 0);

        public string HrvText
        {
            get
            {
                var m = GetMetric(VitalType.HeartRateVariabilitySDNN) ?? GetMetric(VitalType.HeartRateVariabilityRMSSD);
                return m?.Value > 0 ? m.Value + " ms" : "--";
            }
        }

        public string RhrText
        {
            get
            {
                var m = GetMetric(VitalType.RestingHeartRate);
                return m?.Value > 0 ? m.Value + " bpm" : "--";
            }
        }

        public string RespText
        {
            get
            {
                var m = GetMetric(VitalType.RespiratoryRate);
                return m?.Value > 0 ? m.Value + " br/m" : "--";
            }
        }

        public string Spo2Text
        {
            get
            {
                var m = GetMetric(VitalType.OxygenSaturation);
                return m?.Value > 0 ? m.Value + "%" : "--";
            }
        }

        // --- Helpers ---

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

        private string FormatSleep(double minutes)
        {
            if (minutes <= 0) return "--";
            var ts = TimeSpan.FromMinutes(minutes);
            return $"{ts.Hours}h {ts.Minutes}m";
        }

        private string FormatSleepShort(double minutes)
        {
            if (minutes <= 0) return "--";
            if (minutes < 60) return $"{(int)minutes}m";
            var ts = TimeSpan.FromMinutes(minutes);
            return $"{ts.Hours}h{ts.Minutes}m";
        }

        public event PropertyChangedEventHandler PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}


