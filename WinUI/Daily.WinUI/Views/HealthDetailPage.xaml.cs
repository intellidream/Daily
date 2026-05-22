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
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Views
{
    public sealed partial class HealthDetailPage : Page, INotifyPropertyChanged
    {
        private IHealthService _healthService;
        private IRefreshService _refreshService;
        private List<VitalMetric> _metrics = new();

        public HealthDetailPage()
        {
            this.InitializeComponent();
            _healthService = App.Current.Services.GetService<IHealthService>();
            _refreshService = App.Current.Services.GetService<IRefreshService>();
            
            StepsHistory = new ObservableCollection<ChartData>();
            HrHistory = new ObservableCollection<ChartData>();
        }

        private async void Page_Loaded(object sender, RoutedEventArgs e)
        {
            if (_refreshService != null)
            {
                _refreshService.RefreshRequested += OnRefreshRequested;
                _refreshService.HealthRefreshRequested += OnRefreshRequested;
            }
            await LoadDataAsync();
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
                    Console.WriteLine($"[HealthDetailPage] Threaded refresh failed: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (Frame.CanGoBack)
            {
                Frame.GoBack();
            }
        }

        private async void SyncButton_Click(object sender, RoutedEventArgs e)
        {
            await RefreshFromTitleBarAsync();
        }

        public async Task RefreshFromTitleBarAsync()
        {
            if (_isSyncing) return;
            IsSyncing = true;
            try
            {
                await _healthService.SyncNativeHealthDataAsync();
                await LoadDataAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthDetail] Sync failed: {ex.Message}");
            }
            finally
            {
                IsSyncing = false;
            }
        }

        private async Task LoadDataAsync()
        {
            try
            {
                _metrics = await _healthService.FetchMetricsAsync(DateTime.Now);
                CalculateDominantSource();
                NotifyAllProperties();

                // Load History
                await LoadHistoryAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthDetail] Error loading data: {ex.Message}");
            }
        }

        private async Task LoadHistoryAsync()
        {
            try
            {
                var stepsData = await _healthService.GetHistoryAsync(VitalType.Steps, 7);
                var hrData = await _healthService.GetHistoryAsync(VitalType.HeartRate, 7);
                var sleepData = await _healthService.GetHistoryAsync(VitalType.SleepDuration, 7);

                StepsHistory.Clear();
                HrHistory.Clear();
                SleepHistory.Clear();

                for (int i = 6; i >= 0; i--)
                {
                    var day = DateTime.Today.AddDays(-i);
                    var label = day.ToString("ddd");
                    
                    var stepValue = stepsData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    StepsHistory.Add(new ChartData { Label = label, Value = stepValue });

                    var hrValue = hrData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    HrHistory.Add(new ChartData { Label = label, Value = hrValue });

                    var sleepMin = sleepData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    SleepHistory.Add(new ChartData { Label = label, Value = Math.Round(sleepMin / 60.0, 1) });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthDetail] Error loading history: {ex.Message}");
            }
        }

        private VitalMetric GetMetric(VitalType type)
        {
            var m = _metrics.FirstOrDefault(x => x.TypeString == type.ToString());
            return m?.Value > 0 ? m : null;
        }

        // --- Bindable Properties ---

        private bool _isSyncing;
        public bool IsSyncing
        {
            get => _isSyncing;
            set
            {
                _isSyncing = value;
                OnPropertyChanged(nameof(IsSyncing));
                OnPropertyChanged(nameof(IsNotSyncing));
            }
        }
        public bool IsNotSyncing => !_isSyncing;

        public ObservableCollection<ChartData> StepsHistory { get; set; } = new();
        public ObservableCollection<ChartData> HrHistory { get; set; } = new();
        public ObservableCollection<ChartData> SleepHistory { get; set; } = new();

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

        public string StepsText => FormatNumber(GetMetric(VitalType.Steps)?.Value ?? 0);
        public string CaloriesText => FormatNumber(GetMetric(VitalType.ActiveEnergy)?.Value ?? 0);
        public double CaloriesPercent
        {
            get
            {
                var val = GetMetric(VitalType.ActiveEnergy)?.Value ?? 0;
                var goal = 2500.0;
                return Math.Min((val / goal) * 100, 100);
            }
        }
        public string SleepText => FormatSleep(GetMetric(VitalType.SleepDuration)?.Value ?? 0);
        
        public string DistanceText => GetMetric(VitalType.Distance)?.Value > 0 ? Math.Round(GetMetric(VitalType.Distance).Value / 1000.0, 2) + " km" : "--";
        public string FloorsText => GetMetric(VitalType.FloorsClimbed)?.Value > 0 ? GetMetric(VitalType.FloorsClimbed).Value.ToString("N0") : "--";
        public string SpeedText => GetMetric(VitalType.WalkingSpeed)?.Value > 0 ? GetMetric(VitalType.WalkingSpeed).Value + " m/s" : "--";

        public string HeartRateText => GetMetric(VitalType.HeartRate)?.Value > 0 ? GetMetric(VitalType.HeartRate).Value + " bpm" : "--";
        public string WeightText => GetMetric(VitalType.Weight)?.Value > 0 ? GetMetric(VitalType.Weight).Value + " kg" : "--";
        public string HrvText => (GetMetric(VitalType.HeartRateVariabilitySDNN) ?? GetMetric(VitalType.HeartRateVariabilityRMSSD))?.Value > 0 ? (GetMetric(VitalType.HeartRateVariabilitySDNN) ?? GetMetric(VitalType.HeartRateVariabilityRMSSD)).Value + " ms" : "--";
        
        public string BloodPressureText
        {
            get
            {
                var sys = GetMetric(VitalType.BloodPressureSystolic);
                var dia = GetMetric(VitalType.BloodPressureDiastolic);
                if (sys?.Value > 0 && dia?.Value > 0) return $"{sys.Value}/{dia.Value}";
                return "--";
            }
        }

        public string RhrText => GetMetric(VitalType.RestingHeartRate)?.Value > 0 ? GetMetric(VitalType.RestingHeartRate).Value + " bpm" : "--";
        public string RespText => GetMetric(VitalType.RespiratoryRate)?.Value > 0 ? GetMetric(VitalType.RespiratoryRate).Value + " br/m" : "--";
        public string Spo2Text => GetMetric(VitalType.OxygenSaturation)?.Value > 0 ? GetMetric(VitalType.OxygenSaturation).Value + "%" : "--";
        public string GlucoseText => GetMetric(VitalType.BloodGlucose)?.Value > 0 ? GetMetric(VitalType.BloodGlucose).Value + " mg/dL" : "--";

        // Body Composition
        public string BodyFatText => GetMetric(VitalType.BodyFatPercentage)?.Value > 0 ? GetMetric(VitalType.BodyFatPercentage).Value + "%" : "--";
        public string BmiText
        {
            get
            {
                var w = GetMetric(VitalType.Weight)?.Value ?? 0;
                var h = GetMetric(VitalType.Height)?.Value ?? 0;
                return w > 0 && h > 0 ? (w / (h * h)).ToString("N1") : "--";
            }
        }
        public string LeanMassText => GetMetric(VitalType.LeanBodyMass)?.Value > 0 ? GetMetric(VitalType.LeanBodyMass).Value + " kg" : "--";

        // Sleep Stages
        public string DeepSleepText => FormatSleep(GetMetric(VitalType.SleepDeep)?.Value ?? 0);
        public string LightSleepText => FormatSleep(GetMetric(VitalType.SleepLight)?.Value ?? 0);
        public string RemSleepText => FormatSleep(GetMetric(VitalType.SleepREM)?.Value ?? 0);
        public string AwakeSleepText => FormatSleep(GetMetric(VitalType.SleepAwake)?.Value ?? 0);
        public Microsoft.UI.Xaml.Visibility SleepStagesVisibility => ((GetMetric(VitalType.SleepDeep)?.Value ?? 0) > 0 || (GetMetric(VitalType.SleepLight)?.Value ?? 0) > 0) ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

        // Wellness
        public string MindText => GetMetric(VitalType.MindfulSession)?.Value > 0 ? GetMetric(VitalType.MindfulSession).Value + "m" : "--";
        public string TempText => GetMetric(VitalType.BodyTemperature)?.Value > 0 ? GetMetric(VitalType.BodyTemperature).Value + "°C" : "--";
        public string H2oText => GetMetric(VitalType.Hydration)?.Value > 0 ? GetMetric(VitalType.Hydration).Value + "L" : "--";


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

        private string FormatNumber(double val) => val >= 1000 ? (val / 1000.0).ToString("N1") + "k" : (val > 0 ? val.ToString("N0") : "--");
        
        private string FormatSleep(double minutes)
        {
            if (minutes <= 0) return "--";
            var ts = TimeSpan.FromMinutes(minutes);
            return $"{ts.Hours}h {ts.Minutes}m";
        }

        private void NotifyAllProperties()
        {
            OnPropertyChanged(nameof(SourceTooltip));
            OnPropertyChanged(nameof(SourceDotColor));

            OnPropertyChanged(nameof(StepsText));
            OnPropertyChanged(nameof(CaloriesText));
            OnPropertyChanged(nameof(CaloriesPercent));
            OnPropertyChanged(nameof(SleepText));
            
            OnPropertyChanged(nameof(DistanceText));
            OnPropertyChanged(nameof(FloorsText));
            OnPropertyChanged(nameof(SpeedText));

            OnPropertyChanged(nameof(HeartRateText));
            OnPropertyChanged(nameof(WeightText));
            OnPropertyChanged(nameof(HrvText));
            OnPropertyChanged(nameof(BloodPressureText));

            OnPropertyChanged(nameof(RhrText));
            OnPropertyChanged(nameof(RespText));
            OnPropertyChanged(nameof(Spo2Text));
            OnPropertyChanged(nameof(GlucoseText));

            OnPropertyChanged(nameof(BodyFatText));
            OnPropertyChanged(nameof(BmiText));
            OnPropertyChanged(nameof(LeanMassText));

            OnPropertyChanged(nameof(DeepSleepText));
            OnPropertyChanged(nameof(LightSleepText));
            OnPropertyChanged(nameof(RemSleepText));
            OnPropertyChanged(nameof(AwakeSleepText));
            OnPropertyChanged(nameof(SleepStagesVisibility));

            OnPropertyChanged(nameof(MindText));
            OnPropertyChanged(nameof(TempText));
            OnPropertyChanged(nameof(H2oText));
        }

        public event PropertyChangedEventHandler PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    public class ChartData
    {
        public string Label { get; set; }
        public double Value { get; set; }
    }
}

