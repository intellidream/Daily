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

                try
                {
                    var behaviorService = App.Current.Services.GetService<Daily_WinUI.Services.IBehaviorService>();
                    if (behaviorService != null)
                    {
                        var stepsMetric = GetMetric(VitalType.Steps);
                        var hrMetric = GetMetric(VitalType.HeartRate);
                        var sleepMetric = GetMetric(VitalType.SleepDuration);
                        double steps = stepsMetric?.Value ?? 0;
                        double hr = hrMetric?.Value ?? 0;
                        double sleepHours = sleepMetric != null ? Daily_WinUI.Services.SettingsService.ConvertSleepToHours(sleepMetric.Value, sleepMetric.Unit) : 0;
                        
                        string metadata = $"{{\"steps\":{steps},\"heartRate\":{hr},\"sleepHours\":{sleepHours:F1}}}";
                        _ = behaviorService.TrackEventAsync("Health", "ViewVitals", metadata);
                    }
                }
                catch { }
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
                var caloriesData = await _healthService.GetHistoryAsync(VitalType.ActiveEnergy, 7);
                var weightData = await _healthService.GetHistoryAsync(VitalType.Weight, 7);
                var hrvData = await _healthService.GetHistoryAsync(VitalType.HeartRateVariabilitySDNN, 7);
                if (!hrvData.Any())
                {
                    hrvData = await _healthService.GetHistoryAsync(VitalType.HeartRateVariabilityRMSSD, 7);
                }

                StepsHistory.Clear();
                HrHistory.Clear();
                SleepHistory.Clear();
                CaloriesHistory.Clear();
                WeightHistory.Clear();
                HrvHistory.Clear();

                var stepsRawList = new List<double>();
                var hrRawList = new List<double>();
                var sleepRawList = new List<double>();
                var caloriesRawList = new List<double>();
                var weightRawList = new List<double>();
                var hrvRawList = new List<double>();
                var daysLabels = new List<string>();

                for (int i = 6; i >= 0; i--)
                {
                    var day = DateTime.Today.AddDays(-i);
                    daysLabels.Add(day.ToString("ddd"));

                    var stepValue = stepsData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    stepsRawList.Add(stepValue);

                    var hrValue = hrData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    hrRawList.Add(hrValue);

                    var sleepMetricObj = sleepData.FirstOrDefault(m => m.Date.Date == day);
                    var sleepHours = sleepMetricObj != null ? Daily_WinUI.Services.SettingsService.ConvertSleepToHours(sleepMetricObj.Value, sleepMetricObj.Unit) : 0;
                    sleepRawList.Add(Math.Round(sleepHours, 1));

                    var calValue = caloriesData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    caloriesRawList.Add(calValue);

                    var weightValue = weightData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    weightRawList.Add(weightValue);

                    var hrvValue = hrvData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    hrvRawList.Add(hrvValue);
                }

                // Steps calculations
                var nonZeroSteps = stepsRawList.Where(v => v > 0).ToList();
                _stepsMax = stepsRawList.Any() ? stepsRawList.Max() : 0;
                _stepsMin = nonZeroSteps.Any() ? nonZeroSteps.Min() : 0;
                _stepsAvg = nonZeroSteps.Any() ? nonZeroSteps.Average() : 0;
                _stepsTotal = stepsRawList.Sum();

                // HR calculations
                var nonZeroHr = hrRawList.Where(v => v > 0).ToList();
                _hrMax = hrRawList.Any() ? hrRawList.Max() : 0;
                _hrMin = nonZeroHr.Any() ? nonZeroHr.Min() : 0;
                _hrAvg = nonZeroHr.Any() ? nonZeroHr.Average() : 0;
                double hrRange = _hrMax - _hrMin;

                // Sleep calculations
                var nonZeroSleep = sleepRawList.Where(v => v > 0).ToList();
                _sleepMax = sleepRawList.Any() ? sleepRawList.Max() : 0;
                _sleepMin = nonZeroSleep.Any() ? nonZeroSleep.Min() : 0;
                _sleepAvg = nonZeroSleep.Any() ? nonZeroSleep.Average() : 0;

                // Calories calculations
                var nonZeroCal = caloriesRawList.Where(v => v > 0).ToList();
                _caloriesMax = caloriesRawList.Any() ? caloriesRawList.Max() : 0;
                _caloriesMin = nonZeroCal.Any() ? nonZeroCal.Min() : 0;
                _caloriesAvg = nonZeroCal.Any() ? nonZeroCal.Average() : 0;
                _caloriesTotal = caloriesRawList.Sum();

                // Weight calculations
                var nonZeroWeight = weightRawList.Where(v => v > 0).ToList();
                _weightMax = weightRawList.Any() ? weightRawList.Max() : 0;
                _weightMin = nonZeroWeight.Any() ? nonZeroWeight.Min() : 0;
                _weightAvg = nonZeroWeight.Any() ? nonZeroWeight.Average() : 0;
                double weightRange = _weightMax - _weightMin;

                // HRV calculations
                var nonZeroHrv = hrvRawList.Where(v => v > 0).ToList();
                _hrvMax = hrvRawList.Any() ? hrvRawList.Max() : 0;
                _hrvMin = nonZeroHrv.Any() ? nonZeroHrv.Min() : 0;
                _hrvAvg = nonZeroHrv.Any() ? nonZeroHrv.Average() : 0;
                double hrvRange = _hrvMax - _hrvMin;

                // Populate History Lists
                for (int i = 0; i < 7; i++)
                {
                    var label = daysLabels[i];

                    // Steps
                    double sVal = stepsRawList[i];
                    double sPct = 0;
                    if (sVal > 0 && _stepsMax > 0)
                    {
                        sPct = (sVal / _stepsMax) * 100.0;
                        sPct = Math.Max(10, sPct);
                    }
                    StepsHistory.Add(new ChartData
                    {
                        Label = label,
                        Value = sVal,
                        Percentage = sPct,
                        BarHeight = (sPct / 100.0) * 50.0,
                        FormattedValue = FormatNumber(sVal)
                    });

                    // Heart Rate
                    double hrVal = hrRawList[i];
                    double hrPct = 0;
                    if (hrVal > 0)
                    {
                        if (hrRange > 0)
                        {
                            hrPct = ((hrVal - _hrMin) / hrRange) * 100.0;
                            hrPct = Math.Max(15, Math.Min(hrPct, 100));
                        }
                        else
                        {
                            hrPct = 50;
                        }
                    }
                    HrHistory.Add(new ChartData
                    {
                        Label = label,
                        Value = hrVal,
                        Percentage = hrPct,
                        BarHeight = (hrPct / 100.0) * 50.0,
                        FormattedValue = hrVal > 0 ? hrVal.ToString("N0") : "--"
                    });

                    // Sleep
                    double slVal = sleepRawList[i];
                    double slPct = 0;
                    if (slVal > 0 && _sleepMax > 0)
                    {
                        slPct = (slVal / _sleepMax) * 100.0;
                        slPct = Math.Max(10, slPct);
                    }
                    SleepHistory.Add(new ChartData
                    {
                        Label = label,
                        Value = slVal,
                        Percentage = slPct,
                        BarHeight = (slPct / 100.0) * 50.0,
                        FormattedValue = slVal > 0 ? slVal.ToString("N1") + "h" : "--"
                    });

                    // Calories
                    double calVal = caloriesRawList[i];
                    double calPct = 0;
                    if (calVal > 0 && _caloriesMax > 0)
                    {
                        calPct = (calVal / _caloriesMax) * 100.0;
                        calPct = Math.Max(10, calPct);
                    }
                    CaloriesHistory.Add(new ChartData
                    {
                        Label = label,
                        Value = calVal,
                        Percentage = calPct,
                        BarHeight = (calPct / 100.0) * 50.0,
                        FormattedValue = FormatNumber(calVal)
                    });

                    // Weight
                    double wVal = weightRawList[i];
                    double wPct = 0;
                    if (wVal > 0)
                    {
                        if (weightRange > 0)
                        {
                            wPct = ((wVal - _weightMin) / weightRange) * 100.0;
                            wPct = Math.Max(15, Math.Min(wPct, 100));
                        }
                        else
                        {
                            wPct = 50;
                        }
                    }
                    WeightHistory.Add(new ChartData
                    {
                        Label = label,
                        Value = wVal,
                        Percentage = wPct,
                        BarHeight = (wPct / 100.0) * 50.0,
                        FormattedValue = wVal > 0 ? wVal.ToString("N1") : "--"
                    });

                    // HRV
                    double hrvVal = hrvRawList[i];
                    double hrvPct = 0;
                    if (hrvVal > 0)
                    {
                        if (hrvRange > 0)
                        {
                            hrvPct = ((hrvVal - _hrvMin) / hrvRange) * 100.0;
                            hrvPct = Math.Max(15, Math.Min(hrvPct, 100));
                        }
                        else
                        {
                            hrvPct = 50;
                        }
                    }
                    HrvHistory.Add(new ChartData
                    {
                        Label = label,
                        Value = hrvVal,
                        Percentage = hrvPct,
                        BarHeight = (hrvPct / 100.0) * 50.0,
                        FormattedValue = hrvVal > 0 ? hrvVal.ToString("N0") : "--"
                    });
                }

                // Notify UI of stats updates
                NotifyAllProperties();
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
        public ObservableCollection<ChartData> CaloriesHistory { get; set; } = new();
        public ObservableCollection<ChartData> WeightHistory { get; set; } = new();
        public ObservableCollection<ChartData> HrvHistory { get; set; } = new();

        // --- Stats Grid Bindings ---
        // Steps stats
        private double _stepsAvg;
        private double _stepsMax;
        private double _stepsMin;
        private double _stepsTotal;
        public string StepsAvgText => FormatNumber(_stepsAvg);
        public string StepsMaxText => FormatNumber(_stepsMax);
        public string StepsMinText => FormatNumber(_stepsMin);
        public string StepsTotalText => FormatNumber(_stepsTotal);

        // Heart rate stats
        private double _hrAvg;
        private double _hrMax;
        private double _hrMin;
        public string HrAvgText => _hrAvg > 0 ? _hrAvg.ToString("N0") : "--";
        public string HrMaxText => _hrMax > 0 ? _hrMax.ToString("N0") : "--";
        public string HrMinText => _hrMin > 0 ? _hrMin.ToString("N0") : "--";
        public string HrTodayText => HrHistory.Count > 0 && HrHistory[HrHistory.Count - 1].Value > 0 ? HrHistory[HrHistory.Count - 1].Value.ToString("N0") : "--";

        // Sleep stats
        private double _sleepAvg;
        private double _sleepMax;
        private double _sleepMin;
        public string SleepAvgText => _sleepAvg > 0 ? _sleepAvg.ToString("N1") + "h" : "--";
        public string SleepMaxText => _sleepMax > 0 ? _sleepMax.ToString("N1") + "h" : "--";
        public string SleepMinText => _sleepMin > 0 ? _sleepMin.ToString("N1") + "h" : "--";
        public string SleepTodayText => SleepHistory.Count > 0 && SleepHistory[SleepHistory.Count - 1].Value > 0 ? SleepHistory[SleepHistory.Count - 1].Value.ToString("N1") + "h" : "--";

        // Calories stats
        private double _caloriesAvg;
        private double _caloriesMax;
        private double _caloriesMin;
        private double _caloriesTotal;
        public string CaloriesAvgText => FormatNumber(_caloriesAvg);
        public string CaloriesMaxText => FormatNumber(_caloriesMax);
        public string CaloriesMinText => FormatNumber(_caloriesMin);
        public string CaloriesTotalText => FormatNumber(_caloriesTotal);
        public string CaloriesTodayText => CaloriesHistory.Count > 0 && CaloriesHistory[CaloriesHistory.Count - 1].Value > 0 ? FormatNumber(CaloriesHistory[CaloriesHistory.Count - 1].Value) : "--";

        // Weight stats
        private double _weightAvg;
        private double _weightMax;
        private double _weightMin;
        public string WeightAvgText => _weightAvg > 0 ? _weightAvg.ToString("N1") + " kg" : "--";
        public string WeightMaxText => _weightMax > 0 ? _weightMax.ToString("N1") + " kg" : "--";
        public string WeightMinText => _weightMin > 0 ? _weightMin.ToString("N1") + " kg" : "--";
        public string WeightTodayText => WeightHistory.Count > 0 && WeightHistory[WeightHistory.Count - 1].Value > 0 ? WeightHistory[WeightHistory.Count - 1].Value.ToString("N1") + " kg" : "--";

        // HRV stats
        private double _hrvAvg;
        private double _hrvMax;
        private double _hrvMin;
        public string HrvAvgText => _hrvAvg > 0 ? _hrvAvg.ToString("N0") + " ms" : "--";
        public string HrvMaxText => _hrvMax > 0 ? _hrvMax.ToString("N0") + " ms" : "--";
        public string HrvMinText => _hrvMin > 0 ? _hrvMin.ToString("N0") + " ms" : "--";
        public string HrvTodayText => HrvHistory.Count > 0 && HrvHistory[HrvHistory.Count - 1].Value > 0 ? HrvHistory[HrvHistory.Count - 1].Value.ToString("N0") : "--";

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
        public string SleepText
        {
            get
            {
                var m = GetMetric(VitalType.SleepDuration);
                return FormatSleep(m?.Value ?? 0, m?.Unit);
            }
        }
        
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
        public string DeepSleepText
        {
            get
            {
                var m = GetMetric(VitalType.SleepDeep);
                return FormatSleep(m?.Value ?? 0, m?.Unit);
            }
        }
        public string LightSleepText
        {
            get
            {
                var m = GetMetric(VitalType.SleepLight);
                return FormatSleep(m?.Value ?? 0, m?.Unit);
            }
        }
        public string RemSleepText
        {
            get
            {
                var m = GetMetric(VitalType.SleepREM);
                return FormatSleep(m?.Value ?? 0, m?.Unit);
            }
        }
        public string AwakeSleepText
        {
            get
            {
                var m = GetMetric(VitalType.SleepAwake);
                return FormatSleep(m?.Value ?? 0, m?.Unit);
            }
        }
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
        
        private string FormatSleep(double rawValue, string? unit = null)
        {
            if (rawValue <= 0) return "--";
            double minutes = Daily_WinUI.Services.SettingsService.ConvertSleepToMinutes(rawValue, unit);
            var ts = TimeSpan.FromMinutes(minutes);
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
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

            // Stats grid notifications
            OnPropertyChanged(nameof(StepsAvgText));
            OnPropertyChanged(nameof(StepsMaxText));
            OnPropertyChanged(nameof(StepsMinText));
            OnPropertyChanged(nameof(StepsTotalText));

            OnPropertyChanged(nameof(HrAvgText));
            OnPropertyChanged(nameof(HrMaxText));
            OnPropertyChanged(nameof(HrMinText));

            OnPropertyChanged(nameof(SleepAvgText));
            OnPropertyChanged(nameof(SleepMaxText));
            OnPropertyChanged(nameof(SleepMinText));

            OnPropertyChanged(nameof(CaloriesAvgText));
            OnPropertyChanged(nameof(CaloriesMaxText));
            OnPropertyChanged(nameof(CaloriesMinText));
            OnPropertyChanged(nameof(CaloriesTotalText));

            OnPropertyChanged(nameof(WeightAvgText));
            OnPropertyChanged(nameof(WeightMaxText));
            OnPropertyChanged(nameof(WeightMinText));

            OnPropertyChanged(nameof(HrvAvgText));
            OnPropertyChanged(nameof(HrvMaxText));
            OnPropertyChanged(nameof(HrvMinText));

            // Today properties notifications
            OnPropertyChanged(nameof(HrTodayText));
            OnPropertyChanged(nameof(SleepTodayText));
            OnPropertyChanged(nameof(CaloriesTodayText));
            OnPropertyChanged(nameof(WeightTodayText));
            OnPropertyChanged(nameof(HrvTodayText));
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
        public double Percentage { get; set; }
        public double BarHeight { get; set; }
        public string FormattedValue { get; set; }
    }
}

