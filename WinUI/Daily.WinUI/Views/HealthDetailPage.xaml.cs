using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Daily.Models.Health;
using Daily.Services;
using Daily.Services.Health;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace Daily_WinUI.Views
{
    public sealed partial class HealthDetailPage : Page, INotifyPropertyChanged
    {
        private IHealthService? _healthService;
        private IHealthHubService? _healthHubService;
        private IRefreshService? _refreshService;

        private DateTime _selectedDate = DateTime.Today;
        private HealthDailySummaryRecord? _currentSummary;
        private List<VitalMetric> _metrics = new();
        private List<HealthTelemetry> _telemetryData = new();
        private SleepSession? _primarySleepSession;
        private List<SleepSession> _allSleepSessions = new();

        private bool _isSyncing = false;
        public bool IsSyncing => _isSyncing;
        public bool IsNotSyncing => !_isSyncing;
        public Visibility SyncRingVisibility => _isSyncing ? Visibility.Visible : Visibility.Collapsed;
        public Visibility SyncIconVisibility => !_isSyncing ? Visibility.Visible : Visibility.Collapsed;

        // Multi-Device Filter State
        private string? _selectedDeviceFilter = null; // null = All Devices
        public ObservableCollection<DeviceFilterItem> AvailableDevices { get; } = new();

        // Selected Stage Pill State for Hypnogram
        private HealthTelemetry? _selectedStage = null;

        // Chart Data Collections
        public ObservableCollection<HealthChartData> HourlyStepsCollection { get; } = new();
        public ObservableCollection<HealthTelemetry> HeartRateCollection { get; } = new();
        public ObservableCollection<HealthChartData> StepsHistory { get; } = new();
        public ObservableCollection<HealthChartData> HrHistory { get; } = new();
        public ObservableCollection<HealthChartData> SleepHistory { get; } = new();
        public ObservableCollection<HealthChartData> CaloriesHistory { get; } = new();
        public ObservableCollection<HealthChartData> WeightHistory { get; } = new();
        public ObservableCollection<HealthChartData> HrvHistory { get; } = new();
        public ObservableCollection<NapDisplayItem> DaytimeNapsList { get; } = new();

        // Box Breathing State
        private DispatcherTimer? _breathingTimer;
        private int _breathingPhase = 0; // 0=Inhale, 1=Hold, 2=Exhale, 3=Hold
        private int _breathingSecondsLeft = 4;
        private bool _isBreathingActive = false;

        public HealthDetailPage()
        {
            this.InitializeComponent();

            try { _healthHubService = App.Current.Services.GetService<IHealthHubService>(); } catch { }
            try { _healthService = App.Current.Services.GetService<IHealthService>(); } catch { }
            try { _refreshService = App.Current.Services.GetService<IRefreshService>(); } catch { }

            if (_healthService != null)
            {
                _selectedDate = _healthService.SelectedDate.Date;
            }
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            base.OnNavigatedTo(e);

            if (e.Parameter is string tabName)
            {
                switch (tabName.ToLowerInvariant())
                {
                    case "sleep":
                    case "sleepstudio":
                        HealthPivot.SelectedIndex = 1;
                        break;
                    case "stress":
                    case "stressstudio":
                        HealthPivot.SelectedIndex = 2;
                        break;
                    case "heart":
                    case "vitals":
                    case "sensors":
                        HealthPivot.SelectedIndex = 3;
                        break;
                    case "trends":
                        HealthPivot.SelectedIndex = 4;
                        break;
                    default:
                        HealthPivot.SelectedIndex = 0;
                        break;
                }
            }
            else if (e.Parameter is int tabIdx && tabIdx >= 0 && tabIdx < 5)
            {
                HealthPivot.SelectedIndex = tabIdx;
            }
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
            }

            if (_healthHubService != null)
            {
                _healthHubService.OnDailySummaryChanged += OnDailySummaryChanged;
            }

            UpdateDayNavigatorUi();
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
                _healthService.OnSelectedDateChanged -= OnSelectedDateChanged;
            }

            if (_healthHubService != null)
            {
                _healthHubService.OnDailySummaryChanged -= OnDailySummaryChanged;
            }

            StopBreathingExercise();
        }

        private void OnDailySummaryChanged(HealthDailySummaryRecord? record)
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                _currentSummary = record;
                await RefreshDerivedDataAsync();
            });
        }

        private void OnSelectedDateChanged()
        {
            if (_healthService == null) return;
            DispatcherQueue.TryEnqueue(async () =>
            {
                _selectedDate = _healthService.SelectedDate.Date;
                UpdateDayNavigatorUi();
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
                    System.Diagnostics.Debug.WriteLine($"[HealthDetailPage] Refresh error: {ex.Message}");
                }
            });
            return Task.CompletedTask;
        }

        // ==========================================
        // DATA LOADING & DERIVATIONS
        // ==========================================

        public async Task LoadDataAsync()
        {
            try
            {
                // 1. Load canonical daily summary record from HealthHubService
                if (_healthHubService != null)
                {
                    _currentSummary = await _healthHubService.GetDailySummaryAsync(_selectedDate);
                }

                // 2. Load metrics list
                if (_healthService != null)
                {
                    _metrics = await _healthService.FetchMetricsForDateAsync(_selectedDate);
                }

                // 3. Load sleep session & hypnogram
                if (_healthService != null)
                {
                    var (primary, all) = await _healthService.GetSleepSessionsAsync(_selectedDate);
                    _primarySleepSession = primary;
                    _allSleepSessions = all;
                }

                // 4. Load intraday telemetry for continuous HR and steps
                if (_healthService != null)
                {
                    var startOfDay = _selectedDate.Date;
                    var endOfDay = startOfDay.AddDays(1).AddTicks(-1);
                    _telemetryData = await _healthService.GetHealthTelemetryAsync(startOfDay, endOfDay);
                }

                PopulateHourlySteps();
                PopulateHeartRate();
                PopulateDaytimeNaps();
                PopulateAvailableDevices();
                await LoadTrendsHistoryAsync();

                await RefreshDerivedDataAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[HealthDetailPage] LoadDataAsync error: {ex.Message}");
            }
        }

        public async Task RefreshFromTitleBarAsync()
        {
            await LoadDataAsync();
        }

        private static SolidColorBrush GetDeviceColorBrush(string? dev)
        {
            return new SolidColorBrush(DeviceColorPalette.ParseColor(DeviceColorPalette.GetColor(dev)));
        }

        private Task RefreshDerivedDataAsync()
        {
            NotifyAllProperties();

            // Re-render visual canvas graphs
            DrawSleepHypnogram();
            DrawSleepXAxis();
            DrawStageProportions();

            return Task.CompletedTask;
        }

        private void PopulateHourlySteps()
        {
            HourlyStepsCollection.Clear();

            var hourlyBuckets = _currentSummary?.Summary?.Activity?.HourlySteps;
            if (hourlyBuckets != null && hourlyBuckets.Any())
            {
                for (int h = 0; h < 24; h++)
                {
                    var bucket = hourlyBuckets.FirstOrDefault(b => b.Hour == h);
                    double steps = bucket?.Steps ?? 0;
                    HourlyStepsCollection.Add(new HealthChartData
                    {
                        Label = $"{h:D2}",
                        Value = steps,
                        FormattedValue = steps > 0 ? steps.ToString("N0") : ""
                    });
                }
            }
            else
            {
                var stepsTelemetry = _telemetryData
                    .Where(x => x.IsSteps && x.LocalStartTime.Date == _selectedDate.Date)
                    .GroupBy(x => x.LocalStartTime.Hour)
                    .ToDictionary(g => g.Key, g => g.Sum(x => x.Value ?? 0));

                for (int h = 0; h < 24; h++)
                {
                    double steps = stepsTelemetry.TryGetValue(h, out var s) ? s : 0;
                    HourlyStepsCollection.Add(new HealthChartData
                    {
                        Label = $"{h:D2}",
                        Value = steps,
                        FormattedValue = steps > 0 ? steps.ToString("N0") : ""
                    });
                }
            }
        }

        private void PopulateHeartRate()
        {
            HeartRateCollection.Clear();

            var intradayHr = _currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate;
            if (intradayHr != null && intradayHr.Any())
            {
                foreach (var pt in intradayHr)
                {
                    if (DateTime.TryParse(pt.Timestamp, out var ts) && pt.Bpm > 0)
                    {
                        HeartRateCollection.Add(new HealthTelemetry
                        {
                            TypeString = "heart_rate",
                            Value = pt.Bpm,
                            Unit = "bpm",
                            StartTime = ts,
                            EndTime = ts,
                            SourceDevice = "Canonical"
                        });
                    }
                }
            }
            else
            {
                var hrPoints = _telemetryData
                    .Where(x => x.IsHeartRate && x.LocalStartTime.Date == _selectedDate.Date && x.Value.HasValue && x.Value > 0)
                    .OrderBy(x => x.LocalStartTime)
                    .ToList();

                foreach (var item in hrPoints)
                {
                    HeartRateCollection.Add(item);
                }
            }
        }

        private void PopulateDaytimeNaps()
        {
            DaytimeNapsList.Clear();
            var naps = _currentSummary?.Summary?.Sleep?.Naps;
            if (naps != null && naps.Any())
            {
                foreach (var nap in naps)
                {
                    DateTimeOffset.TryParse(nap.StartTime, out var sDto);
                    DateTimeOffset.TryParse(nap.EndTime, out var eDto);
                    int mins = nap.DurationSeconds > 0 ? (int)Math.Round(nap.DurationSeconds / 60.0) : 0;
                    string timeRange = sDto != default && eDto != default
                        ? $"{sDto.LocalDateTime:HH:mm} - {eDto.LocalDateTime:HH:mm}"
                        : "--:--";

                    DaytimeNapsList.Add(new NapDisplayItem
                    {
                        TimeRange = timeRange,
                        DurationText = $"{mins} minutes restorative nap",
                        NapMinutesText = $"{mins} min",
                        DeviceName = nap.SourceDevice ?? nap.Tracker ?? "Device"
                    });
                }
            }
        }

        private void PopulateAvailableDevices()
        {
            AvailableDevices.Clear();

            // First entry: All Devices (Consolidated)
            AvailableDevices.Add(new DeviceFilterItem
            {
                DeviceName = "",
                DisplayName = "All Devices (Consolidated)",
                SegoeGlyph = "\xEB51",
                ColorBrush = new SolidColorBrush(Color.FromArgb(255, 255, 45, 85)),
                IsSelected = string.IsNullOrEmpty(_selectedDeviceFilter)
            });

            var discovered = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // From sleep session
            if (!string.IsNullOrEmpty(_primarySleepSession?.SourceDevice) && !DeviceSource.IsVirtual(_primarySleepSession.SourceDevice))
            {
                discovered.Add(_primarySleepSession.SourceDevice);
            }

            // From all sleep sessions
            foreach (var s in _allSleepSessions)
            {
                if (!string.IsNullOrEmpty(s.SourceDevice) && !DeviceSource.IsVirtual(s.SourceDevice))
                {
                    discovered.Add(s.SourceDevice);
                }
            }

            // From vitals
            if (_currentSummary?.Summary?.Vitals != null)
            {
                foreach (var v in _currentSummary.Summary.Vitals.Values)
                {
                    if (!string.IsNullOrEmpty(v.SourceDevice) && !DeviceSource.IsVirtual(v.SourceDevice))
                    {
                        discovered.Add(v.SourceDevice);
                    }
                }
            }

            // From metrics
            foreach (var m in _metrics)
            {
                if (!string.IsNullOrEmpty(m.SourceDevice) && !DeviceSource.IsVirtual(m.SourceDevice))
                {
                    discovered.Add(m.SourceDevice);
                }
            }

            foreach (var dev in discovered)
            {
                var src = DeviceSource.From(dev);
                AvailableDevices.Add(new DeviceFilterItem
                {
                    DeviceName = dev,
                    DisplayName = src.DisplayName,
                    SegoeGlyph = src.SegoeGlyph,
                    ColorBrush = GetDeviceColorBrush(dev),
                    IsSelected = string.Equals(_selectedDeviceFilter, dev, StringComparison.OrdinalIgnoreCase)
                });
            }

            RebuildDeviceMenuFlyout();
        }

        private void RebuildDeviceMenuFlyout()
        {
            if (DeviceMenuFlyout == null) return;
            DeviceMenuFlyout.Items.Clear();

            foreach (var item in AvailableDevices)
            {
                var menuItem = new MenuFlyoutItem
                {
                    Text = item.DisplayName,
                    Icon = new FontIcon { Glyph = item.SegoeGlyph, FontFamily = new FontFamily("Segoe Fluent Icons"), Foreground = item.ColorBrush },
                    Tag = item.DeviceName
                };

                menuItem.Click += (s, e) =>
                {
                    if (s is MenuFlyoutItem mi)
                    {
                        string? target = mi.Tag as string;
                        _selectedDeviceFilter = string.IsNullOrEmpty(target) ? null : target;
                        PopulateAvailableDevices();
                        OnPropertyChanged(nameof(SelectedDeviceLabel));
                        OnPropertyChanged(nameof(SelectedDeviceDotBrush));
                        OnPropertyChanged(nameof(SelectedDeviceGlyph));
                    }
                };

                DeviceMenuFlyout.Items.Add(menuItem);
            }
        }

        private async Task LoadTrendsHistoryAsync()
        {
            StepsHistory.Clear();
            HrHistory.Clear();
            SleepHistory.Clear();
            CaloriesHistory.Clear();
            WeightHistory.Clear();
            HrvHistory.Clear();

            var endDate = _selectedDate.Date;
            var startDate = endDate.AddDays(-6);

            List<HealthDailySummaryRecord> rangeSummaries = new();
            if (_healthHubService != null)
            {
                rangeSummaries = await _healthHubService.GetDailySummariesRangeAsync(startDate, endDate);
            }

            for (int i = 6; i >= 0; i--)
            {
                var day = endDate.AddDays(-i);
                var dayStr = day.ToString("yyyy-MM-dd");
                var dayLabel = day.ToString("ddd");

                var summary = rangeSummaries.FirstOrDefault(s => s.LocalDate == dayStr);

                // Steps
                double steps = summary?.Steps ?? 0;
                StepsHistory.Add(new HealthChartData { Label = dayLabel, Value = steps, FormattedValue = steps > 0 ? steps.ToString("N0") : "--" });

                // HR
                double rhr = summary?.Rhr ?? 0;
                HrHistory.Add(new HealthChartData { Label = dayLabel, Value = rhr, FormattedValue = rhr > 0 ? $"{rhr:F0}" : "--" });

                // Sleep (hours)
                double sleepHours = summary?.SleepAsleepS.HasValue == true ? Math.Round(summary.SleepAsleepS.Value / 3600.0, 1) : 0;
                SleepHistory.Add(new HealthChartData { Label = dayLabel, Value = sleepHours, FormattedValue = sleepHours > 0 ? $"{sleepHours:F1}h" : "--" });

                // Calories
                double cal = summary?.ActiveKcal ?? 0;
                CaloriesHistory.Add(new HealthChartData { Label = dayLabel, Value = cal, FormattedValue = cal > 0 ? $"{cal:F0}" : "--" });

                // Weight
                double wt = summary?.Weight ?? 0;
                WeightHistory.Add(new HealthChartData { Label = dayLabel, Value = wt, FormattedValue = wt > 0 ? $"{wt:F1}" : "--" });

                // HRV
                double hrv = summary?.HrvSdnn ?? summary?.HrvRmssd ?? 0;
                HrvHistory.Add(new HealthChartData { Label = dayLabel, Value = hrv, FormattedValue = hrv > 0 ? $"{hrv:F0}" : "--" });
            }
        }

        // ==========================================
        // TOPBAR PROPERTIES & COMMANDS
        // ==========================================

        public Visibility JumpTodayVisibility => _selectedDate.Date != DateTime.Today ? Visibility.Visible : Visibility.Collapsed;

        public string SelectedDeviceLabel
        {
            get
            {
                if (string.IsNullOrEmpty(_selectedDeviceFilter)) return "All Devices";
                return DeviceSource.From(_selectedDeviceFilter).DisplayName;
            }
        }

        public SolidColorBrush SelectedDeviceDotBrush
        {
            get
            {
                if (string.IsNullOrEmpty(_selectedDeviceFilter)) return new SolidColorBrush(Color.FromArgb(255, 255, 45, 85));
                return GetDeviceColorBrush(_selectedDeviceFilter);
            }
        }

        public string SelectedDeviceGlyph
        {
            get
            {
                if (string.IsNullOrEmpty(_selectedDeviceFilter)) return "\xEB51";
                return DeviceSource.From(_selectedDeviceFilter).SegoeGlyph;
            }
        }

        public string DominantDeviceName
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter)) return _selectedDeviceFilter;
                if (!string.IsNullOrEmpty(_primarySleepSession?.SourceDevice) && !DeviceSource.IsVirtual(_primarySleepSession.SourceDevice))
                {
                    return _primarySleepSession.SourceDevice;
                }
                var firstDev = AvailableDevices.FirstOrDefault(d => !string.IsNullOrEmpty(d.DeviceName));
                return firstDev?.DeviceName ?? "";
            }
        }

        public bool HasDominantDevice => !string.IsNullOrWhiteSpace(DominantDeviceName);

        private void UpdateDayNavigatorUi()
        {
            if (SelectedDateTextBlock != null)
            {
                if (_selectedDate.Date == DateTime.Today)
                {
                    SelectedDateTextBlock.Text = "Today";
                }
                else if (_selectedDate.Date == DateTime.Today.AddDays(-1))
                {
                    SelectedDateTextBlock.Text = "Yesterday";
                }
                else
                {
                    SelectedDateTextBlock.Text = _selectedDate.ToString("ddd, MMM d");
                }
            }

            OnPropertyChanged(nameof(JumpTodayVisibility));
        }

        private async void PrevDayButton_Click(object sender, RoutedEventArgs e)
        {
            _selectedDate = _selectedDate.AddDays(-1);
            if (_healthService != null) _healthService.SelectedDate = _selectedDate;
            UpdateDayNavigatorUi();
            await LoadDataAsync();
        }

        private async void NextDayButton_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedDate.Date >= DateTime.Today) return;
            _selectedDate = _selectedDate.AddDays(1);
            if (_healthService != null) _healthService.SelectedDate = _selectedDate;
            UpdateDayNavigatorUi();
            await LoadDataAsync();
        }

        private async void JumpTodayButton_Click(object sender, RoutedEventArgs e)
        {
            _selectedDate = DateTime.Today;
            if (_healthService != null) _healthService.SelectedDate = _selectedDate;
            UpdateDayNavigatorUi();
            await LoadDataAsync();
        }

        private async void SyncButton_Click(object sender, RoutedEventArgs e)
        {
            if (_isSyncing) return;
            _isSyncing = true;
            OnPropertyChanged(nameof(IsSyncing));
            OnPropertyChanged(nameof(IsNotSyncing));
            OnPropertyChanged(nameof(SyncRingVisibility));
            OnPropertyChanged(nameof(SyncIconVisibility));

            try
            {
                if (_healthHubService != null)
                {
                    await _healthHubService.PullDeltasAsync();
                }
                await LoadDataAsync();
            }
            finally
            {
                _isSyncing = false;
                OnPropertyChanged(nameof(IsSyncing));
                OnPropertyChanged(nameof(IsNotSyncing));
                OnPropertyChanged(nameof(SyncRingVisibility));
                OnPropertyChanged(nameof(SyncIconVisibility));
            }
        }

        // ==========================================
        // TAB 0: OVERVIEW PROPERTIES
        // ==========================================

        public string StepsText
        {
            get
            {
                double steps = _currentSummary?.Steps ?? GetMetric(VitalType.Steps)?.Value ?? 0;
                return steps > 0 ? steps.ToString("N0") : "--";
            }
        }

        public double StepsProgressValue
        {
            get
            {
                double steps = _currentSummary?.Steps ?? GetMetric(VitalType.Steps)?.Value ?? 0;
                return Math.Min(100.0, Math.Max(0.0, (steps / 10000.0) * 100.0));
            }
        }

        public string CaloriesText
        {
            get
            {
                double kcal = _currentSummary?.ActiveKcal ?? GetMetric(VitalType.ActiveEnergy)?.Value ?? 0;
                return kcal > 0 ? $"{kcal:N0}" : "--";
            }
        }

        public string SleepText
        {
            get
            {
                if (_currentSummary?.SleepAsleepS.HasValue == true && _currentSummary.SleepAsleepS.Value > 0)
                {
                    var ts = TimeSpan.FromSeconds(_currentSummary.SleepAsleepS.Value);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }
                var m = GetMetric(VitalType.SleepDuration);
                if (m != null && m.Value > 0)
                {
                    double mins = Daily_WinUI.Services.SettingsService.ConvertSleepToMinutes(m.Value, m.Unit);
                    var ts = TimeSpan.FromMinutes(mins);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }
                return "--";
            }
        }

        public string DistanceText
        {
            get
            {
                var m = GetMetric(VitalType.Distance);
                if (m?.Value > 0) return $"{m.Value / 1000.0:F1} km";
                double steps = _currentSummary?.Steps ?? 0;
                if (steps > 0) return $"{steps * 0.00075:F1} km";
                return "-- km";
            }
        }

        public string FloorsText
        {
            get
            {
                var m = GetMetric(VitalType.FloorsClimbed);
                return m?.Value > 0 ? $"{m.Value:F0} floors" : "-- floors";
            }
        }

        public string SpeedText => "-- km/h";

        public string HourlyStepsMaxText
        {
            get
            {
                if (!HourlyStepsCollection.Any()) return "";
                var max = HourlyStepsCollection.Max(x => x.Value);
                return max > 0 ? $"Peak: {max:N0} steps/hr" : "";
            }
        }

        // ==========================================
        // TAB 1: SLEEP STUDIO PROPERTIES
        // ==========================================

        public string SleepSourceDevice => _primarySleepSession?.SourceDevice ?? DominantDeviceName;

        public string TotalSleepText => SleepText;

        public string SleepScheduleAndEfficiencyText
        {
            get
            {
                string inBed = TimeInBedText;
                string eff = SleepEfficiencySummaryText;
                return $"{inBed} in bed • {eff}";
            }
        }

        public string SleepScoreText
        {
            get
            {
                int score = _primarySleepSession?.SleepScore ?? _currentSummary?.SleepScore ?? 0;
                return score > 0 ? score.ToString() : "--";
            }
        }

        public string SleepQualityRatingText
        {
            get
            {
                var rating = _currentSummary?.Summary?.Sleep?.PrimarySession?.QualityRating;
                if (!string.IsNullOrEmpty(rating)) return rating.ToUpperInvariant();

                int score = _primarySleepSession?.SleepScore ?? _currentSummary?.SleepScore ?? 0;
                if (score >= 85) return "EXCELLENT";
                if (score >= 70) return "GOOD";
                if (score >= 50) return "FAIR";
                if (score > 0) return "NEEDS ATTENTION";
                return "NO DATA";
            }
        }

        public string BedtimeText
        {
            get
            {
                if (_primarySleepSession != null && _primarySleepSession.StartTime != default)
                {
                    return _primarySleepSession.StartTime.ToString("HH:mm");
                }
                return "--:--";
            }
        }

        public string WakeTimeText
        {
            get
            {
                if (_primarySleepSession != null && _primarySleepSession.EndTime != default)
                {
                    return _primarySleepSession.EndTime.ToString("HH:mm");
                }
                return "--:--";
            }
        }

        public string SleepScheduleText => $"{BedtimeText} - {WakeTimeText}";

        public string TimeInBedText
        {
            get
            {
                if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0)
                {
                    var ts = TimeSpan.FromSeconds(_primarySleepSession.DurationSeconds);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }
                return "--";
            }
        }

        public string SleepEfficiencySummaryText
        {
            get
            {
                int eff = _currentSummary?.Summary?.Sleep?.PrimarySession?.EfficiencyPercent ?? 0;
                if (eff > 0) return $"{eff}% eff";
                return "--%";
            }
        }

        public string RestorativePctText
        {
            get
            {
                int rest = _currentSummary?.Summary?.Sleep?.PrimarySession?.RestorativePercent ?? 0;
                if (rest > 0) return $"{rest}%";

                double deep = _primarySleepSession?.DeepSeconds ?? 0;
                double rem = _primarySleepSession?.RemSeconds ?? 0;
                double asleep = _primarySleepSession?.AsleepSeconds ?? 0;
                if (asleep > 0)
                {
                    return $"{((deep + rem) / asleep) * 100:F0}%";
                }
                return "--%";
            }
        }

        public string SleepVerdictQualityText => SleepQualityRatingText;

        public string SleepVerdictSummaryText
        {
            get
            {
                var narrative = _currentSummary?.Summary?.Sleep?.Guidance?.Verdict?.Narrative;
                if (!string.IsNullOrEmpty(narrative)) return narrative;
                var headline = _currentSummary?.Summary?.Sleep?.Guidance?.Verdict?.Headline;
                if (!string.IsNullOrEmpty(headline)) return headline;

                int score = _primarySleepSession?.SleepScore ?? _currentSummary?.SleepScore ?? 0;
                if (score >= 85) return "Optimal restorative sleep cycle with balanced REM and Deep architecture.";
                if (score >= 70) return "Sufficient overall sleep duration with normal sleep stage continuity.";
                if (score > 0) return "Mild fragmentation or reduced restorative stages detected. Consider an earlier bedtime.";
                return "No sleep telemetry recorded for this night.";
            }
        }

        public string HypnogramHeaderTitle => _primarySleepSession?.HasGranularHypnogram == true && _primarySleepSession?.Stages?.Any() == true
            ? "Clinical Sleep Hypnogram"
            : "Sleep Stage Proportions";

        public Visibility GranularHypnogramVisibility => _primarySleepSession?.HasGranularHypnogram == true && _primarySleepSession?.Stages?.Any() == true
            ? Visibility.Visible
            : Visibility.Collapsed;

        public Visibility StageProportionVisibility => _primarySleepSession?.HasGranularHypnogram != true || _primarySleepSession?.Stages?.Any() != true
            ? Visibility.Visible
            : Visibility.Collapsed;

        public Visibility HasNapsVisibility => DaytimeNapsList.Any() ? Visibility.Visible : Visibility.Collapsed;

        // Selected Stage Inspection Pill Properties
        public Visibility SelectedStagePillVisibility => _selectedStage != null ? Visibility.Visible : Visibility.Collapsed;

        public SolidColorBrush SelectedStageColorBrush
        {
            get
            {
                if (_selectedStage == null) return new SolidColorBrush(Microsoft.UI.Colors.Transparent);
                return _selectedStage.SleepCategory switch
                {
                    "Deep" => new SolidColorBrush(Color.FromArgb(255, 57, 73, 171)),
                    "REM" => new SolidColorBrush(Color.FromArgb(255, 38, 198, 218)),
                    "Awake" => new SolidColorBrush(Color.FromArgb(255, 255, 112, 67)),
                    _ => new SolidColorBrush(Color.FromArgb(255, 66, 165, 245))
                };
            }
        }

        public string SelectedStageName => _selectedStage != null ? $"{_selectedStage.SleepCategory} Sleep" : "";

        public string SelectedStageTimeRange => _selectedStage != null ? $"{_selectedStage.LocalStartTime:HH:mm} - {_selectedStage.LocalEndTime:HH:mm}" : "";

        public string SelectedStageDurationText => _selectedStage != null ? $"{(int)(_selectedStage.DurationSeconds / 60)} min" : "";

        private void ClearStageSelection_Click(object sender, RoutedEventArgs e)
        {
            _selectedStage = null;
            OnPropertyChanged(nameof(SelectedStagePillVisibility));
            OnPropertyChanged(nameof(SelectedStageColorBrush));
            OnPropertyChanged(nameof(SelectedStageName));
            OnPropertyChanged(nameof(SelectedStageTimeRange));
            OnPropertyChanged(nameof(SelectedStageDurationText));
        }

        // Stage Breakdown Card Formats
        public string DeepDurationText => FormatSecondsToHoursMins(_primarySleepSession?.DeepSeconds ?? 0);
        public string DeepPercentText => CalculateStagePercent(_primarySleepSession?.DeepSeconds ?? 0);

        public string RemDurationText => FormatSecondsToHoursMins(_primarySleepSession?.RemSeconds ?? 0);
        public string RemPercentText => CalculateStagePercent(_primarySleepSession?.RemSeconds ?? 0);

        public string LightDurationText => FormatSecondsToHoursMins(_primarySleepSession?.LightSeconds ?? 0);
        public string LightPercentText => CalculateStagePercent(_primarySleepSession?.LightSeconds ?? 0);

        public string AwakeDurationText => FormatSecondsToHoursMins(_primarySleepSession?.AwakeSeconds ?? 0);
        public string AwakePercentText => CalculateStagePercent(_primarySleepSession?.AwakeSeconds ?? 0);

        private string FormatSecondsToHoursMins(double seconds)
        {
            if (seconds <= 0) return "--";
            var ts = TimeSpan.FromSeconds(seconds);
            if (ts.TotalMinutes < 60) return $"{(int)ts.TotalMinutes}m";
            return $"{(int)ts.TotalHours}h {ts.Minutes}m";
        }

        private string CalculateStagePercent(double stageSec)
        {
            double total = _primarySleepSession?.TotalStagesSeconds ?? 0;
            if (total <= 0) total = _primarySleepSession?.DurationSeconds ?? 0;
            if (total <= 0) return "--%";
            return $"{(stageSec / total) * 100:F0}%";
        }

        // AI Sleep Hygiene Tips
        public string TipCircadianText => "Maintain a consistent sleep window within ±30 minutes to synchronize cortisol and melatonin output.";
        public string TipClimateText => "Keep your bedroom temperature between 18-20°C (65-68°F) with optimal cross-ventilation for deep sleep.";
        public string TipNutritionText => "Avoid caffeine within 8 hours and heavy meals within 2.5 hours of bedtime to prevent elevated resting HR.";
        public string TipWindDownText => "Dim overhead lights and shift to warm lighting 60 minutes before bedtime to support natural melatonin.";

        // ==========================================
        // HYPNOGRAM & PROPORTIONS CANVAS RENDERING
        // ==========================================

        private void SleepHypnogramCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            DrawSleepHypnogram();
            DrawSleepXAxis();
        }

        private void StageProportionCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            DrawStageProportions();
        }

        private void DrawSleepHypnogram()
        {
            if (SleepHypnogramCanvas == null) return;
            SleepHypnogramCanvas.Children.Clear();

            var stages = _primarySleepSession?.Stages;
            if (stages == null || !stages.Any()) return;

            double canvasWidth = SleepHypnogramCanvas.ActualWidth;
            double canvasHeight = SleepHypnogramCanvas.ActualHeight;
            if (canvasWidth <= 0 || canvasHeight <= 0) return;

            var minTime = _primarySleepSession!.StartTime;
            var maxTime = _primarySleepSession.EndTime;
            double totalSeconds = (maxTime - minTime).TotalSeconds;
            if (totalSeconds <= 0) return;

            double rowHeight = 30;
            double[] rowTops = new double[] { 6, 42, 78, 114 };

            // Horizontal lane guide lines
            for (int r = 0; r < 4; r++)
            {
                var guide = new Rectangle
                {
                    Width = canvasWidth,
                    Height = 1,
                    Fill = new SolidColorBrush(Color.FromArgb(16, 255, 255, 255))
                };
                Canvas.SetLeft(guide, 0);
                Canvas.SetTop(guide, rowTops[r] + rowHeight + 2);
                SleepHypnogramCanvas.Children.Add(guide);
            }

            // Sleep stage blocks
            foreach (var item in stages)
            {
                double elapsed = (item.LocalStartTime - minTime).TotalSeconds;
                double left = Math.Max(0, (elapsed / totalSeconds) * canvasWidth);
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
                    CornerRadius = new CornerRadius(4),
                    Tag = item
                };

                block.PointerPressed += (s, e) =>
                {
                    if (s is Border b && b.Tag is HealthTelemetry st)
                    {
                        if (_selectedStage == st)
                        {
                            _selectedStage = null;
                        }
                        else
                        {
                            _selectedStage = st;
                        }

                        OnPropertyChanged(nameof(SelectedStagePillVisibility));
                        OnPropertyChanged(nameof(SelectedStageColorBrush));
                        OnPropertyChanged(nameof(SelectedStageName));
                        OnPropertyChanged(nameof(SelectedStageTimeRange));
                        OnPropertyChanged(nameof(SelectedStageDurationText));
                    }
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

            var stages = _primarySleepSession?.Stages;
            if (stages == null || !stages.Any()) return;

            double canvasWidth = SleepXAxisCanvas.ActualWidth;
            if (canvasWidth <= 0) return;

            var minTime = _primarySleepSession!.StartTime;
            var maxTime = _primarySleepSession.EndTime;
            double totalSeconds = (maxTime - minTime).TotalSeconds;
            if (totalSeconds <= 0) return;

            var startHour = new DateTime(minTime.Year, minTime.Month, minTime.Day, minTime.Hour, 0, 0);
            var endHour = maxTime.AddHours(1);

            for (var cur = startHour; cur <= endHour; cur = cur.AddHours(1))
            {
                if (cur >= minTime && cur <= maxTime)
                {
                    double left = ((cur - minTime).TotalSeconds / totalSeconds) * canvasWidth;
                    var tb = new TextBlock
                    {
                        Text = cur.ToString("HH:mm"),
                        FontSize = 9.5,
                        Foreground = (Brush)Application.Current.Resources["AppFgMutedColorBrush"]
                    };
                    Canvas.SetLeft(tb, Math.Max(0, left - 12));
                    Canvas.SetTop(tb, 2);
                    SleepXAxisCanvas.Children.Add(tb);
                }
            }
        }

        private void DrawStageProportions()
        {
            if (StageProportionCanvas == null) return;
            StageProportionCanvas.Children.Clear();

            double width = StageProportionCanvas.ActualWidth;
            double height = StageProportionCanvas.ActualHeight;
            if (width <= 0 || height <= 0) return;

            double deep = _primarySleepSession?.DeepSeconds ?? 0;
            double rem = _primarySleepSession?.RemSeconds ?? 0;
            double light = _primarySleepSession?.LightSeconds ?? 0;
            double awake = _primarySleepSession?.AwakeSeconds ?? 0;
            double total = deep + rem + light + awake;
            if (total <= 0) return;

            double currentX = 0;

            void AddSegment(double sec, Color col)
            {
                if (sec <= 0) return;
                double segWidth = Math.Max(4, (sec / total) * width);
                var rect = new Rectangle
                {
                    Width = segWidth,
                    Height = height,
                    Fill = new SolidColorBrush(col),
                    RadiusX = 3,
                    RadiusY = 3
                };
                Canvas.SetLeft(rect, currentX);
                Canvas.SetTop(rect, 0);
                StageProportionCanvas.Children.Add(rect);
                currentX += segWidth + 2;
            }

            AddSegment(deep, Color.FromArgb(255, 57, 73, 171));
            AddSegment(rem, Color.FromArgb(255, 38, 198, 218));
            AddSegment(light, Color.FromArgb(255, 66, 165, 245));
            AddSegment(awake, Color.FromArgb(255, 255, 112, 67));
        }

        // ==========================================
        // TAB 2: STRESS STUDIO PROPERTIES
        // ==========================================

        public string StressScoreText
        {
            get
            {
                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                return score > 0 ? score.ToString() : "--";
            }
        }

        public SolidColorBrush StressScoreBrush
        {
            get
            {
                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 0) return new SolidColorBrush(Color.FromArgb(180, 255, 255, 255));
                if (score <= 25) return new SolidColorBrush(Color.FromArgb(255, 52, 199, 89));
                if (score <= 50) return new SolidColorBrush(Color.FromArgb(255, 56, 151, 240));
                if (score <= 75) return new SolidColorBrush(Color.FromArgb(255, 255, 149, 0));
                return new SolidColorBrush(Color.FromArgb(255, 255, 45, 85));
            }
        }

        public string StressLevelLabelText
        {
            get
            {
                var lvl = _currentSummary?.Summary?.Stress?.CurrentLevel;
                if (!string.IsNullOrEmpty(lvl)) return lvl;

                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 0) return "No Data";
                if (score <= 25) return "Calm";
                if (score <= 50) return "Low";
                if (score <= 75) return "Moderate";
                return "High";
            }
        }

        public string MonkeyMoodEmoji
        {
            get
            {
                var mood = _currentSummary?.Summary?.Stress?.MonkeyMood;
                if (!string.IsNullOrEmpty(mood))
                {
                    return mood.ToLowerInvariant() switch
                    {
                        "zen" => "🧘",
                        "happy" => "🐵",
                        "curious" => "🐒",
                        "alert" => "👀",
                        "wired" => "⚡",
                        "exhausted" => "💤",
                        _ => "🐵"
                    };
                }

                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 0) return "🐵";
                if (score <= 25) return "🧘";
                if (score <= 50) return "🐵";
                if (score <= 75) return "⚡";
                return "💤";
            }
        }

        public SolidColorBrush MonkeyMoodBorderBrush => StressScoreBrush;

        public SolidColorBrush MonkeyMoodBackgroundBrush
        {
            get
            {
                var solid = StressScoreBrush.Color;
                return new SolidColorBrush(Color.FromArgb(30, solid.R, solid.G, solid.B));
            }
        }

        public string MonkeyMoodLabelText => StressLevelLabelText;

        public string MonkeyMoodDescriptionText
        {
            get
            {
                int score = _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
                if (score <= 25) return "Zen mode. Autonomic parasympathetic dominance indicates excellent recovery.";
                if (score <= 50) return "Balanced homeostasis. Physiological strain remains within normal limits.";
                if (score <= 75) return "Elevated sympathetic activation. Recommended: 5 minutes of box breathing.";
                if (score > 75) return "High autonomic strain. Consider resting, hydrating, and avoiding intensive stimuli.";
                return "No real-time stress data recorded for this period.";
            }
        }

        public string AutonomicDominantText
        {
            get
            {
                int para = _currentSummary?.Summary?.Stress?.AutonomicBalance?.ParasympatheticPercent ?? 50;
                return para >= 50 ? "Parasympathetic Dominant" : "Sympathetic Dominant";
            }
        }

        public double ParasympatheticRatioPct
        {
            get
            {
                var balance = _currentSummary?.Summary?.Stress?.AutonomicBalance;
                if (balance != null) return balance.ParasympatheticPercent;
                int score = _currentSummary?.StressAvg ?? 0;
                return Math.Max(10, Math.Min(90, 100 - score));
            }
        }

        public string SympatheticLabelText => $"Sympathetic {100 - (int)ParasympatheticRatioPct}%";
        public string ParasympatheticLabelText => $"Parasympathetic {(int)ParasympatheticRatioPct}%";

        // 4 Stress Drivers
        public string DriverActivityText => $"{DriverActivityPct:F0}%";
        public double DriverActivityPct
        {
            get
            {
                double steps = _currentSummary?.Steps ?? 0;
                return Math.Min(100.0, Math.Max(10.0, (steps / 10000.0) * 100.0));
            }
        }

        public string DriverSleepText => $"{DriverSleepPct:F0}%";
        public double DriverSleepPct
        {
            get
            {
                int score = _primarySleepSession?.SleepScore ?? _currentSummary?.SleepScore ?? 0;
                return score > 0 ? Math.Max(5.0, 100.0 - score) : 25.0;
            }
        }

        public string DriverHrvText => $"{DriverHrvPct:F0}%";
        public double DriverHrvPct
        {
            get
            {
                var drivers = _currentSummary?.Summary?.Stress?.BiometricDrivers;
                if (drivers?.CurrentHrvMs.HasValue == true && drivers.BaselineHrvMs > 0)
                {
                    double ratio = drivers.CurrentHrvMs.Value / drivers.BaselineHrvMs;
                    return Math.Min(100.0, Math.Max(0.0, (1.0 - ratio) * 100.0));
                }
                return 20.0;
            }
        }

        public string DriverSpikesText => $"{DriverSpikesPct:F0}%";
        public double DriverSpikesPct => Math.Min(100.0, Math.Max(5.0, (_currentSummary?.StressAvg ?? 25) * 0.4));

        // Box Breathing Player
        public string BreathingButtonText => _isBreathingActive ? "Stop" : "Start Exercise";

        private void BreathingButton_Click(object sender, RoutedEventArgs e)
        {
            if (_isBreathingActive)
            {
                StopBreathingExercise();
            }
            else
            {
                StartBreathingExercise();
            }
        }

        private void StartBreathingExercise()
        {
            _isBreathingActive = true;
            _breathingPhase = 0;
            _breathingSecondsLeft = 4;
            OnPropertyChanged(nameof(BreathingButtonText));

            if (_breathingTimer == null)
            {
                _breathingTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
                _breathingTimer.Tick += BreathingTimer_Tick;
            }

            UpdateBreathingDisplay();
            _breathingTimer.Start();
        }

        private void StopBreathingExercise()
        {
            _isBreathingActive = false;
            _breathingTimer?.Stop();
            OnPropertyChanged(nameof(BreathingButtonText));

            if (BreathingPhaseText != null) BreathingPhaseText.Text = "Ready";
            if (BreathingTimerText != null) BreathingTimerText.Text = "4s";
            if (BreathingCircle != null)
            {
                BreathingCircle.Width = 90;
                BreathingCircle.Height = 90;
            }
        }

        private void BreathingTimer_Tick(object? sender, object e)
        {
            _breathingSecondsLeft--;
            if (_breathingSecondsLeft <= 0)
            {
                _breathingPhase = (_breathingPhase + 1) % 4;
                _breathingSecondsLeft = 4;
            }
            UpdateBreathingDisplay();
        }

        private void UpdateBreathingDisplay()
        {
            if (BreathingPhaseText == null || BreathingTimerText == null || BreathingCircle == null) return;

            string[] phases = new[] { "Inhale", "Hold", "Exhale", "Hold" };
            BreathingPhaseText.Text = phases[_breathingPhase];
            BreathingTimerText.Text = $"{_breathingSecondsLeft}s";

            // Circle animation width
            if (_breathingPhase == 0) // Inhale expanding
            {
                BreathingCircle.Width = 70 + (4 - _breathingSecondsLeft) * 10;
                BreathingCircle.Height = BreathingCircle.Width;
            }
            else if (_breathingPhase == 2) // Exhale shrinking
            {
                BreathingCircle.Width = 110 - (4 - _breathingSecondsLeft) * 10;
                BreathingCircle.Height = BreathingCircle.Width;
            }
        }

        // ==========================================
        // TAB 3: HEART & VITALS PROPERTIES
        // ==========================================

        public string HeartRateText
        {
            get
            {
                var intraday = _currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate;
                if (intraday != null && intraday.Any())
                {
                    var lastPt = intraday.LastOrDefault(p => p.Bpm > 0);
                    if (lastPt != null) return $"{lastPt.Bpm:N0} bpm";
                }
                var m = GetMetric(VitalType.HeartRate);
                if (m?.Value > 0) return $"{m.Value:N0} bpm";
                double rhr = _currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                return rhr > 0 ? $"{rhr:N0} bpm" : "-- bpm";
            }
        }

        public string AvgHeartRateText
        {
            get
            {
                double? avg = _currentSummary?.Summary?.Cardiovascular?.AverageHeartRateBpm;
                if (avg.HasValue && avg.Value > 0) return $"{avg.Value:F0} bpm avg";
                if (HeartRateCollection.Any()) return $"{HeartRateCollection.Average(x => x.Value ?? 0):F0} bpm avg";
                return "-- bpm avg";
            }
        }

        public string RhrText
        {
            get
            {
                double rhr = _currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                return rhr > 0 ? $"{rhr:F0} bpm" : "-- bpm";
            }
        }

        public string HrvText
        {
            get
            {
                double hrv = _currentSummary?.HrvSdnn ?? _currentSummary?.HrvRmssd ?? GetMetric(VitalType.HeartRateVariabilitySDNN)?.Value ?? 0;
                return hrv > 0 ? $"{hrv:F0} ms" : "-- ms";
            }
        }

        public string Spo2Text
        {
            get
            {
                double spo2 = _currentSummary?.Spo2 ?? GetMetric(VitalType.OxygenSaturation)?.Value ?? 0;
                return spo2 > 0 ? $"{spo2:F0}%" : "--%";
            }
        }

        public string BloodPressureText
        {
            get
            {
                var sys = GetMetric(VitalType.BloodPressureSystolic)?.Value;
                var dia = GetMetric(VitalType.BloodPressureDiastolic)?.Value;
                if (sys.HasValue && dia.HasValue) return $"{sys:F0}/{dia:F0} mmHg";
                return "--/-- mmHg";
            }
        }

        public string RespText
        {
            get
            {
                var m = GetMetric(VitalType.RespiratoryRate);
                return m?.Value > 0 ? $"{m.Value:F0} br/m" : "-- br/m";
            }
        }

        public string GlucoseText
        {
            get
            {
                var m = GetMetric(VitalType.BloodGlucose);
                return m?.Value > 0 ? $"{m.Value:F0} mg/dL" : "-- mg/dL";
            }
        }

        public string WeightText
        {
            get
            {
                double wt = _currentSummary?.Weight ?? GetMetric(VitalType.Weight)?.Value ?? 0;
                return wt > 0 ? $"{wt:F1} kg" : "-- kg";
            }
        }

        public string BodyFatText => GetMetricValueWithUnit(VitalType.BodyFatPercentage, "%", 1);
        public string BmiText => GetMetricValueString(VitalType.BodyMassIndex, "F1");
        public string LeanMassText => GetMetricValueWithUnit(VitalType.LeanBodyMass, "kg", 1);

        public string HrRestingPctText => CalculateHrZonePercent(0, 100);
        public string HrFatBurnPctText => CalculateHrZonePercent(100, 120);
        public string HrCardioPctText => CalculateHrZonePercent(120, 150);
        public string HrPeakPctText => CalculateHrZonePercent(150, 250);

        private string CalculateHrZonePercent(double min, double max)
        {
            if (!HeartRateCollection.Any()) return "--%";
            int total = HeartRateCollection.Count;
            int count = HeartRateCollection.Count(x => (x.Value ?? 0) >= min && (x.Value ?? 0) < max);
            return total > 0 ? $"{((double)count / total) * 100:F0}%" : "0%";
        }

        // ==========================================
        // TAB 4: TRENDS PROPERTIES
        // ==========================================

        public string StepsAvgText => CalculateTrendAvg(StepsHistory, "N0");
        public string StepsMaxText => CalculateTrendMax(StepsHistory, "N0");
        public string StepsMinText => CalculateTrendMin(StepsHistory, "N0");
        public string StepsTotalText => StepsHistory.Any(x => x.Value > 0) ? StepsHistory.Sum(x => x.Value).ToString("N0") : "--";

        public string SleepAvgText => CalculateTrendAvg(SleepHistory, "F1", "h");
        public string SleepMaxText => CalculateTrendMax(SleepHistory, "F1", "h");
        public string SleepMinText => CalculateTrendMin(SleepHistory, "F1", "h");

        public string HrAvgText => CalculateTrendAvg(HrHistory, "F0", " bpm");
        public string HrMaxText => CalculateTrendMax(HrHistory, "F0", " bpm");
        public string HrMinText => CalculateTrendMin(HrHistory, "F0", " bpm");

        public string CaloriesAvgText => CalculateTrendAvg(CaloriesHistory, "N0");
        public string CaloriesMaxText => CalculateTrendMax(CaloriesHistory, "N0");
        public string CaloriesMinText => CalculateTrendMin(CaloriesHistory, "N0");
        public string CaloriesTotalText => CaloriesHistory.Any(x => x.Value > 0) ? CaloriesHistory.Sum(x => x.Value).ToString("N0") : "--";

        private string CalculateTrendAvg(ObservableCollection<HealthChartData> coll, string format, string suffix = "")
        {
            var nonZero = coll.Where(x => x.Value > 0).ToList();
            return nonZero.Any() ? $"{nonZero.Average(x => x.Value).ToString(format)}{suffix}" : "--";
        }

        private string CalculateTrendMax(ObservableCollection<HealthChartData> coll, string format, string suffix = "")
        {
            var nonZero = coll.Where(x => x.Value > 0).ToList();
            return nonZero.Any() ? $"{nonZero.Max(x => x.Value).ToString(format)}{suffix}" : "--";
        }

        private string CalculateTrendMin(ObservableCollection<HealthChartData> coll, string format, string suffix = "")
        {
            var nonZero = coll.Where(x => x.Value > 0).ToList();
            return nonZero.Any() ? $"{nonZero.Min(x => x.Value).ToString(format)}{suffix}" : "--";
        }

        // ==========================================
        // TAB SELECTION & NAVIGATION
        // ==========================================

        private void HealthPivot_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (HealthPivot.SelectedIndex == 1)
            {
                DrawSleepHypnogram();
                DrawSleepXAxis();
                DrawStageProportions();
            }
        }

        private void SleepPreview_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            HealthPivot.SelectedIndex = 1;
        }

        private void StressPreview_Tapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            HealthPivot.SelectedIndex = 2;
        }

        // ==========================================
        // HELPERS & PROPERTY CHANGED NOTIFICATIONS
        // ==========================================

        private VitalMetric? GetMetric(VitalType type)
        {
            return _metrics.FirstOrDefault(x => x.MatchesType(type) && x.Value > 0);
        }

        private string GetMetricValueString(VitalType type, string format)
        {
            var m = GetMetric(type);
            return m?.Value.ToString(format) ?? "--";
        }

        private string GetMetricValueWithUnit(VitalType type, string fallbackUnit, int decimals)
        {
            var m = GetMetric(type);
            if (m == null || m.Value <= 0) return "--";
            string format = decimals > 0 ? $"F{decimals}" : "F0";
            string unit = !string.IsNullOrEmpty(m.Unit) ? m.Unit : fallbackUnit;
            return string.IsNullOrEmpty(unit) ? m.Value.ToString(format) : $"{m.Value.ToString(format)} {unit}";
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

    public class HealthChartData
    {
        public string Label { get; set; } = string.Empty;
        public double Value { get; set; }
        public string FormattedValue { get; set; } = string.Empty;
    }

    public class NapDisplayItem
    {
        public string TimeRange { get; set; } = string.Empty;
        public string DurationText { get; set; } = string.Empty;
        public string NapMinutesText { get; set; } = string.Empty;
        public string DeviceName { get; set; } = string.Empty;
    }

    public class DeviceFilterItem
    {
        public string DeviceName { get; set; } = string.Empty;
        public string DisplayName { get; set; } = string.Empty;
        public string SegoeGlyph { get; set; } = "\xE95E";
        public SolidColorBrush ColorBrush { get; set; } = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        public bool IsSelected { get; set; }
    }
}
