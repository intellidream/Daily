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
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace Daily_WinUI.Views
{
    public sealed partial class HealthDetailPage : Page, INotifyPropertyChanged
    {
        private IHealthService _healthService;
        private IRefreshService _refreshService;
        private List<VitalMetric> _metrics = new();
        private List<HealthTelemetry> _telemetryData = new();
        private List<HealthTelemetry> _sleepTelemetry = new();

        private bool _isSyncing = false;
        public bool IsNotSyncing => !_isSyncing;

        public ObservableCollection<ChartData> StepsHistory { get; set; } = new();
        public ObservableCollection<ChartData> HrHistory { get; set; } = new();
        public ObservableCollection<ChartData> SleepHistory { get; set; } = new();
        public ObservableCollection<ChartData> CaloriesHistory { get; set; } = new();
        public ObservableCollection<ChartData> WeightHistory { get; set; } = new();
        public ObservableCollection<ChartData> HrvHistory { get; set; } = new();

        public List<HealthTelemetry> HeartRateTelemetryData { get; private set; } = new();

        public HealthDetailPage()
        {
            this.InitializeComponent();
            _healthService = App.Current.Services.GetService<IHealthService>();
            _refreshService = App.Current.Services.GetService<IRefreshService>();
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
                _healthService.OnViewTypeChanged += OnViewTypeChanged;
                SyncTabFromService();
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

            if (_healthService != null)
            {
                _healthService.OnViewTypeChanged -= OnViewTypeChanged;
            }
        }

        private void OnViewTypeChanged()
        {
            DispatcherQueue.TryEnqueue(SyncTabFromService);
        }

        private void SyncTabFromService()
        {
            if (_healthService == null || HealthPivot == null) return;
            var target = _healthService.CurrentViewType switch
            {
                "Sleep" => 1,
                "Sensors" => 2,
                "Nutrition" => 3,
                _ => 0
            };
            if (HealthPivot.SelectedIndex != target)
            {
                HealthPivot.SelectedIndex = target;
            }
        }

        private void HealthPivot_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_healthService == null || HealthPivot == null) return;
            var newTab = HealthPivot.SelectedIndex switch
            {
                1 => "Sleep",
                2 => "Sensors",
                3 => "Nutrition",
                _ => "Overview"
            };
            if (_healthService.CurrentViewType != newTab)
            {
                _healthService.CurrentViewType = newTab;
            }
        }

        private Task OnRefreshRequested()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                try { await LoadDataAsync(); }
                catch (Exception ex) { Console.WriteLine($"[HealthDetailPage] Refresh failed: {ex.Message}"); }
            });
            return Task.CompletedTask;
        }

        private async void SyncButton_Click(object sender, RoutedEventArgs e)
        {
            await RefreshFromTitleBarAsync();
        }

        public async Task RefreshFromTitleBarAsync()
        {
            if (_isSyncing) return;
            _isSyncing = true;
            OnPropertyChanged(nameof(IsNotSyncing));

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
                _isSyncing = false;
                OnPropertyChanged(nameof(IsNotSyncing));
            }
        }

        private async Task LoadDataAsync()
        {
            try
            {
                _metrics = await _healthService.FetchMetricsAsync(DateTime.Now);

                var yesterdayEvening = DateTime.Today.AddDays(-1).AddHours(18);
                var endOfToday = DateTime.Today.AddDays(1).AddTicks(-1);
                _telemetryData = await _healthService.GetHealthTelemetryAsync(yesterdayEvening, endOfToday);

                ProcessSleepTelemetry();
                ProcessSensorsTelemetry();

                NotifyAllProperties();
                await LoadHistoryAsync();

                DrawSleepHypnogram();
                DrawSleepXAxis();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthDetail] Error loading data: {ex.Message}");
            }
        }

        // ==========================================
        // SLEEP ARCHITECTURE PROCESSING & HYPNOGRAM
        // ==========================================

        private int _sleepScore = 0;
        private int _sleepEfficiency = 0;
        private int _restorativePct = 0;
        private int _awakeCount = 0;
        private string _sleepAsleepFormatted = "--";
        private string _sleepInBedFormatted = "--";
        private string _deepDurationFormatted = "--";
        private string _remDurationFormatted = "--";
        private string _lightDurationFormatted = "--";
        private string _awakeDurationFormatted = "--";
        private int _deepPct = 0;
        private int _remPct = 0;
        private int _lightPct = 0;
        private int _awakePct = 0;
        private DateTime _sleepMinTime = DateTime.MinValue;
        private DateTime _sleepMaxTime = DateTime.MinValue;

        private void ProcessSleepTelemetry()
        {
            _sleepTelemetry = _telemetryData
                .Where(x => x.IsSleep)
                .OrderBy(x => x.LocalStartTime)
                .ToList();

            if (_sleepTelemetry.Any())
            {
                _sleepMinTime = _sleepTelemetry.Min(x => x.LocalStartTime);
                _sleepMaxTime = _sleepTelemetry.Max(x => x.LocalEndTime);

                var deepSec = _sleepTelemetry.Where(x => x.SleepCategory == "Deep").Sum(x => x.DurationSeconds);
                var remSec = _sleepTelemetry.Where(x => x.SleepCategory == "REM").Sum(x => x.DurationSeconds);
                var lightSec = _sleepTelemetry.Where(x => x.SleepCategory == "Core").Sum(x => x.DurationSeconds);
                var awakeSec = _sleepTelemetry.Where(x => x.SleepCategory == "Awake").Sum(x => x.DurationSeconds);

                var asleepSec = deepSec + remSec + lightSec;
                var totalSec = (_sleepMaxTime - _sleepMinTime).TotalSeconds;
                var inBedSec = Math.Max(asleepSec + awakeSec, totalSec > 0 ? totalSec : asleepSec);

                _sleepAsleepFormatted = FormatSeconds(asleepSec);
                _sleepInBedFormatted = FormatSeconds(inBedSec);
                _deepDurationFormatted = FormatSeconds(deepSec);
                _remDurationFormatted = FormatSeconds(remSec);
                _lightDurationFormatted = FormatSeconds(lightSec);
                _awakeDurationFormatted = FormatSeconds(awakeSec);

                _awakeCount = _sleepTelemetry.Count(x => x.SleepCategory == "Awake");

                if (asleepSec > 0)
                {
                    _deepPct = (int)((deepSec / asleepSec) * 100);
                    _remPct = (int)((remSec / asleepSec) * 100);
                    _lightPct = (int)((lightSec / asleepSec) * 100);
                    _restorativePct = _deepPct + _remPct;
                }

                if (inBedSec > 0)
                {
                    _awakePct = (int)((awakeSec / inBedSec) * 100);
                    _sleepEfficiency = Math.Min((int)((asleepSec / inBedSec) * 100), 100);
                }

                double durationScore = Math.Min((asleepSec / (8.0 * 3600.0)) * 50.0, 50.0);
                double efficiencyScore = (_sleepEfficiency / 100.0) * 30.0;
                double qualityScore = Math.Min((_restorativePct / 40.0) * 20.0, 20.0);
                _sleepScore = Math.Clamp((int)(durationScore + efficiencyScore + qualityScore), 0, 100);
            }
            else
            {
                // Fallback from aggregated vitals
                var dM = GetMetric(VitalType.SleepDeep)?.Value ?? 0;
                var rM = GetMetric(VitalType.SleepREM)?.Value ?? 0;
                var lM = GetMetric(VitalType.SleepLight)?.Value ?? 0;
                var aM = GetMetric(VitalType.SleepAwake)?.Value ?? 0;
                var totalM = dM + rM + lM;
                var inBedM = totalM + aM;

                _sleepAsleepFormatted = totalM > 0 ? FormatMinutes(totalM) : "--";
                _sleepInBedFormatted = inBedM > 0 ? FormatMinutes(inBedM) : "--";
                _deepDurationFormatted = FormatMinutes(dM);
                _remDurationFormatted = FormatMinutes(rM);
                _lightDurationFormatted = FormatMinutes(lM);
                _awakeDurationFormatted = FormatMinutes(aM);

                if (totalM > 0)
                {
                    _deepPct = (int)((dM / totalM) * 100);
                    _remPct = (int)((rM / totalM) * 100);
                    _lightPct = (int)((lM / totalM) * 100);
                    _restorativePct = _deepPct + _remPct;
                }
                if (inBedM > 0)
                {
                    _awakePct = (int)((aM / inBedM) * 100);
                    _sleepEfficiency = (int)((totalM / inBedM) * 100);
                }
                _sleepScore = totalM > 0 ? Math.Clamp((int)((totalM / 480.0) * 85.0 + 10), 40, 95) : 0;
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

            if (_sleepTelemetry == null || !_sleepTelemetry.Any()) return;

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
            foreach (var item in _sleepTelemetry)
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
                    "Awake" => Color.FromArgb(255, 255, 112, 67),   // #FF7043
                    "REM" => Color.FromArgb(255, 38, 198, 218),     // #26C6DA
                    "Deep" => Color.FromArgb(255, 57, 73, 171),     // #3949AB
                    _ => Color.FromArgb(255, 66, 165, 245)          // #42A5F5
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

            if (_sleepTelemetry == null || !_sleepTelemetry.Any()) return;

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

        // ==========================================
        // SENSORS & INTRADAY TELEMETRY PROCESSING
        // ==========================================

        private double _avgIntradayHr = 0;
        private int _hrRestingPct = 70;
        private int _hrFatBurnPct = 20;
        private int _hrCardioPct = 8;
        private int _hrPeakPct = 2;
        private int _stressLevel = 28;
        private int _paiScore = 82;

        private void ProcessSensorsTelemetry()
        {
            var today = DateTime.Today;

            HeartRateTelemetryData = _telemetryData
                .Where(x => x.IsHeartRate && x.LocalStartTime >= today && x.Value.HasValue)
                .OrderBy(x => x.LocalStartTime)
                .ToList();

            if (HeartRateTelemetryData.Any())
            {
                _avgIntradayHr = Math.Round(HeartRateTelemetryData.Average(x => x.Value!.Value), 0);
                var total = HeartRateTelemetryData.Count;
                _hrRestingPct = (int)((HeartRateTelemetryData.Count(x => x.Value < 100) / (double)total) * 100);
                _hrFatBurnPct = (int)((HeartRateTelemetryData.Count(x => x.Value >= 100 && x.Value < 120) / (double)total) * 100);
                _hrCardioPct = (int)((HeartRateTelemetryData.Count(x => x.Value >= 120 && x.Value < 150) / (double)total) * 100);
                _hrPeakPct = Math.Max(0, 100 - (_hrRestingPct + _hrFatBurnPct + _hrCardioPct));
            }
        }

        // ==========================================
        // 7-DAY TRENDS & HISTORY
        // ==========================================

        private async Task LoadHistoryAsync()
        {
            try
            {
                var stepsData = await _healthService.GetHistoryAsync(VitalType.Steps, 7);
                var hrData = await _healthService.GetHistoryAsync(VitalType.HeartRate, 7);
                var sleepData = await _healthService.GetHistoryAsync(VitalType.SleepDuration, 7);
                var caloriesData = await _healthService.GetHistoryAsync(VitalType.ActiveEnergy, 7);

                StepsHistory.Clear();
                HrHistory.Clear();
                SleepHistory.Clear();
                CaloriesHistory.Clear();

                for (int i = 6; i >= 0; i--)
                {
                    var day = DateTime.Today.AddDays(-i);
                    var label = day.ToString("ddd");

                    var sVal = stepsData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    StepsHistory.Add(new ChartData { Label = label, Value = sVal });

                    var hrVal = hrData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    HrHistory.Add(new ChartData { Label = label, Value = hrVal });

                    var slMetric = sleepData.FirstOrDefault(m => m.Date.Date == day);
                    var slHours = slMetric != null ? Daily_WinUI.Services.SettingsService.ConvertSleepToHours(slMetric.Value, slMetric.Unit) : 0;
                    SleepHistory.Add(new ChartData { Label = label, Value = Math.Round(slHours, 1) });

                    var calVal = caloriesData.FirstOrDefault(m => m.Date.Date == day)?.Value ?? 0;
                    CaloriesHistory.Add(new ChartData { Label = label, Value = calVal });
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HealthDetail] History load error: {ex.Message}");
            }
        }

        // ==========================================
        // BINDABLE PROPERTIES
        // ==========================================

        // Overview & Core Vitals
        public string StepsText => FormatNumber(GetMetric(VitalType.Steps)?.Value ?? 0);
        public string CaloriesText => FormatNumber(GetMetric(VitalType.ActiveEnergy)?.Value ?? 0);
        public string SleepText => FormatMinutes(GetMetric(VitalType.SleepDuration)?.Value ?? 0);
        public string DistanceText => (GetMetric(VitalType.Distance)?.Value > 0) ? $"{Math.Round(GetMetric(VitalType.Distance)!.Value / 1000.0, 2)} km" : "--";
        public string FloorsText => (GetMetric(VitalType.FloorsClimbed)?.Value > 0) ? GetMetric(VitalType.FloorsClimbed)!.Value.ToString("N0") : "--";
        public string SpeedText => (GetMetric(VitalType.WalkingSpeed)?.Value > 0) ? $"{GetMetric(VitalType.WalkingSpeed)!.Value:N1} m/s" : "--";
        public string BasalCaloriesText => (GetMetric(VitalType.BasalEnergyBurned)?.Value > 0) ? $"{GetMetric(VitalType.BasalEnergyBurned)!.Value:N0} kcal" : "--";

        public string HeartRateText => (GetMetric(VitalType.HeartRate)?.Value > 0) ? $"{GetMetric(VitalType.HeartRate)!.Value:N0} BPM" : "--";
        public string BloodPressureText
        {
            get
            {
                var sys = GetMetric(VitalType.BloodPressureSystolic)?.Value ?? 0;
                var dia = GetMetric(VitalType.BloodPressureDiastolic)?.Value ?? 0;
                return (sys > 0 && dia > 0) ? $"{sys:N0}/{dia:N0}" : "--";
            }
        }
        public string HrvText => (GetMetric(VitalType.HeartRateVariabilitySDNN)?.Value > 0) ? $"{GetMetric(VitalType.HeartRateVariabilitySDNN)!.Value:N0} ms" : "--";
        public string Spo2Text => (GetMetric(VitalType.OxygenSaturation)?.Value > 0) ? $"{GetMetric(VitalType.OxygenSaturation)!.Value:N0}%" : "--";
        public string RhrText => (GetMetric(VitalType.RestingHeartRate)?.Value > 0) ? $"{GetMetric(VitalType.RestingHeartRate)!.Value:N0} bpm" : "--";
        public string RespText => (GetMetric(VitalType.RespiratoryRate)?.Value > 0) ? $"{GetMetric(VitalType.RespiratoryRate)!.Value:N0} br/m" : "--";
        public string GlucoseText => (GetMetric(VitalType.BloodGlucose)?.Value > 0) ? $"{GetMetric(VitalType.BloodGlucose)!.Value:N0} mg/dL" : "--";
        public string TempText => (GetMetric(VitalType.BodyTemperature)?.Value > 0) ? $"{GetMetric(VitalType.BodyTemperature)!.Value:N1} °C" : "--";

        // Sleep Tab Properties
        public string SleepScoreText => _sleepScore > 0 ? _sleepScore.ToString() : "--";
        public string SleepQualityTitle => _sleepScore switch
        {
            >= 90 => "Excellent Sleep",
            >= 80 => "Good Sleep",
            >= 70 => "Fair Sleep",
            > 0 => "Needs Improvement",
            _ => "Analyzing Sleep"
        };
        public string SleepScheduleText => _sleepMinTime != DateTime.MinValue && _sleepMaxTime != DateTime.MinValue
            ? $"Bed: {_sleepMinTime:HH:mm} • Wake: {_sleepMaxTime:HH:mm}"
            : "Wearable sleep schedule not recorded";
        public string SleepEfficiencyText => $"Efficiency: {_sleepEfficiency}%";
        public string SleepAsleepText => _sleepAsleepFormatted;
        public string SleepInBedText => _sleepInBedFormatted;
        public string AwakeCountText => _awakeCount.ToString();
        public string RestorativePercentText => $"{_restorativePct}%";

        public string DeepDurationText => _deepDurationFormatted;
        public string RemDurationText => _remDurationFormatted;
        public string LightDurationText => _lightDurationFormatted;
        public string AwakeDurationText => _awakeDurationFormatted;
        public string DeepPercentText => $"{_deepPct}% of total sleep";
        public string RemPercentText => $"{_remPct}% of total sleep";
        public string LightPercentText => $"{_lightPct}% of total sleep";
        public string AwakePercentText => $"{_awakePct}% time in bed";

        // Sensors Tab Properties
        public string AvgIntradayHrText => _avgIntradayHr > 0 ? $"{_avgIntradayHr:N0} BPM AVG" : "--";
        public string HrRestingPctText => $"{_hrRestingPct}%";
        public string HrFatBurnPctText => $"{_hrFatBurnPct}%";
        public string HrCardioPctText => $"{_hrCardioPct}%";
        public string HrPeakPctText => $"{_hrPeakPct}%";
        public string StressLevelText => _stressLevel.ToString();
        public double StressLevelValue => _stressLevel;
        public string PaiScoreText => $"{_paiScore} PAI";
        public double PaiScoreValue => _paiScore;

        // Nutrition & Body Composition
        public string WaterIntakeText
        {
            get
            {
                var val = GetMetric(VitalType.Hydration)?.Value ?? 0;
                var liters = val > 20 ? val / 1000.0 : val;
                return liters > 0 ? liters.ToString("N1") : "--";
            }
        }
        public double WaterPercentValue
        {
            get
            {
                var val = GetMetric(VitalType.Hydration)?.Value ?? 0;
                var liters = val > 20 ? val / 1000.0 : val;
                return Math.Min((liters / 3.0) * 100.0, 100.0);
            }
        }
        public string WaterPercentText => $"{(int)WaterPercentValue}% of daily 3.0L goal";

        public string CarbsText => $"{GetMetric(VitalType.Carbs)?.Value ?? 0:N0}g";
        public string ProteinText => $"{GetMetric(VitalType.Protein)?.Value ?? 0:N0}g";
        public string FatText => $"{GetMetric(VitalType.Fat)?.Value ?? 0:N0}g";
        public string TotalMacrosText
        {
            get
            {
                var total = (GetMetric(VitalType.Carbs)?.Value ?? 0) + (GetMetric(VitalType.Protein)?.Value ?? 0) + (GetMetric(VitalType.Fat)?.Value ?? 0);
                return total > 0 ? $"{total:N0}g total logged" : "No nutrition logged";
            }
        }

        public string WeightText => (GetMetric(VitalType.Weight)?.Value > 0) ? $"{GetMetric(VitalType.Weight)!.Value:N1} kg" : "--";
        public string HeightText
        {
            get
            {
                var val = GetMetric(VitalType.Height)?.Value ?? 0;
                if (val <= 0) return "--";
                return val > 3 ? $"{val:N0} cm" : $"{val * 100:N0} cm";
            }
        }
        public string BmiText
        {
            get
            {
                var bmi = GetMetric(VitalType.BodyMassIndex)?.Value ?? 0;
                if (bmi > 0) return bmi.ToString("N1");
                var w = GetMetric(VitalType.Weight)?.Value ?? 0;
                var h = GetMetric(VitalType.Height)?.Value ?? 0;
                var hM = h > 3 ? h / 100.0 : h;
                if (w > 0 && hM > 0) return (w / (hM * hM)).ToString("N1");
                return "--";
            }
        }
        public string BmiCategoryText
        {
            get
            {
                if (!double.TryParse(BmiText, out var bmi) || bmi <= 0) return "--";
                if (bmi < 18.5) return "Underweight";
                if (bmi <= 24.9) return "Normal";
                if (bmi <= 29.9) return "Overweight";
                return "Obese";
            }
        }
        public string BodyFatText => (GetMetric(VitalType.BodyFatPercentage)?.Value > 0) ? $"{GetMetric(VitalType.BodyFatPercentage)!.Value:N1}%" : "--";
        public string LeanMassText => (GetMetric(VitalType.LeanBodyMass)?.Value > 0) ? $"{GetMetric(VitalType.LeanBodyMass)!.Value:N1} kg" : "--";
        public string BoneMassText => (GetMetric(VitalType.BoneMass)?.Value > 0) ? $"{GetMetric(VitalType.BoneMass)!.Value:N1} kg" : "--";

        public string CaffeineText => (GetMetric(VitalType.Caffeine)?.Value > 0) ? $"{GetMetric(VitalType.Caffeine)!.Value:N0} mg" : "--";
        public string SugarText => (GetMetric(VitalType.Sugar)?.Value > 0) ? $"{GetMetric(VitalType.Sugar)!.Value:N0} g" : "--";
        public string MagnesiumText => (GetMetric(VitalType.Magnesium)?.Value > 0) ? $"{GetMetric(VitalType.Magnesium)!.Value:N0} mg" : "--";
        public string ZincText => (GetMetric(VitalType.Zinc)?.Value > 0) ? $"{GetMetric(VitalType.Zinc)!.Value:N1} mg" : "--";
        public string CalciumText => (GetMetric(VitalType.Calcium)?.Value > 0) ? $"{GetMetric(VitalType.Calcium)!.Value:N0} mg" : "--";
        public string IronText => (GetMetric(VitalType.Iron)?.Value > 0) ? $"{GetMetric(VitalType.Iron)!.Value:N1} mg" : "--";
        public string VitaminCText => (GetMetric(VitalType.VitaminC)?.Value > 0) ? $"{GetMetric(VitalType.VitaminC)!.Value:N0} mg" : "--";
        public string VitaminAText => (GetMetric(VitalType.VitaminA)?.Value > 0) ? $"{GetMetric(VitalType.VitaminA)!.Value:N0} mcg" : "--";

        // Helpers
        private VitalMetric? GetMetric(VitalType type)
        {
            var m = _metrics.FirstOrDefault(x => x.TypeString == type.ToString());
            return m?.Value > 0 ? m : null;
        }

        private string FormatNumber(double val) => val >= 1000 ? (val / 1000.0).ToString("N1") + "k" : (val > 0 ? val.ToString("N0") : "--");

        private string FormatMinutes(double m)
        {
            if (m <= 0) return "--";
            var ts = TimeSpan.FromMinutes(m);
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
        }

        private string FormatSeconds(double s)
        {
            if (s <= 0) return "--";
            var ts = TimeSpan.FromSeconds(s);
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
        }

        private void NotifyAllProperties()
        {
            OnPropertyChanged(string.Empty);
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }

    public class ChartData
    {
        public string Label { get; set; } = string.Empty;
        public double Value { get; set; }
        public double Percentage { get; set; }
        public double BarHeight { get; set; }
        public string FormattedValue { get; set; } = string.Empty;
    }
}
