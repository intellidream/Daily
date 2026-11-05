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
        private List<HealthSleepSessionRecord> _leanSleepSessions = new();
        private List<HealthDailyVitalsRecord> _leanDailyVitals = new();
        private List<HealthIntradayHeartRateRecord> _leanIntradayHr = new();
        private List<HealthSourceRecord> _healthSources = new();
        private List<VitalMetric> _metrics = new();
        private List<VitalMetric> _rawMetrics = new();
        private List<HealthTelemetry> _telemetryData = new();
        private SleepSession? _primarySleepSession;
        private SleepSession? _rawPrimarySleepSession;
        private List<SleepSession> _allSleepSessions = new();
        private List<SleepSession> _rawSleepSessions = new();

        // Live v2.1 3-Class Arbitrated Cache (evaluated for both All Devices & Filtered Device)
        private HealthHubService.ArbitratedLatestHeartRateResult? _arbitratedLatestHr = null;
        private HealthHubService.ArbitratedActivityResult? _arbitratedActivity = null;
        private HealthHubService.ArbitratedSpotVitalResult? _arbitratedSpo2 = null;
        private HealthHubService.ArbitratedSpotVitalResult? _arbitratedWeight = null;

        // Per-device derived biometric cache when _selectedDeviceFilter != null
        private int? _filteredStressScore = null;
        private double? _filteredHrvMs = null;
        private bool _filteredHrvIsRmssd = false;
        private double? _filteredRhrBpm = null;
        private int? _filteredSteps = null;
        private double? _filteredActiveKcal = null;
        private double? _filteredSpo2 = null;
        private double? _filteredRespRate = null;
        private double? _filteredWeightKg = null;
        private double? _filteredSleepEfficiency = null;

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

            if (this.Frame != App.Current?.MainWindow?.RootFrame)
            {
                if (BackButton != null) BackButton.Visibility = Visibility.Collapsed;
                if (PopOutButton != null) PopOutButton.Visibility = Visibility.Collapsed;
            }

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
                _healthHubService.OnHealthSourcesChanged += OnHealthSourcesChanged;
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
                _healthHubService.OnHealthSourcesChanged -= OnHealthSourcesChanged;
            }

            StopBreathingExercise();
        }

        private void OnHealthSourcesChanged()
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                await LoadDataAsync();
            });
        }

        private void OnDailySummaryChanged(HealthDailySummaryRecord? record)
        {
            DispatcherQueue.TryEnqueue(async () =>
            {
                var targetDateStr = _selectedDate.ToString("yyyy-MM-dd");
                if (record != null && !string.IsNullOrEmpty(record.LocalDate) && record.LocalDate != targetDateStr)
                {
                    return;
                }
                await LoadDataAsync();
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

        private bool MatchesSelectedDevice(string? sourceName)
        {
            if (string.IsNullOrEmpty(_selectedDeviceFilter) || string.IsNullOrEmpty(sourceName)) return false;
            var targetCanon = DeviceSource.From(_selectedDeviceFilter).DisplayName;
            var candidateCanon = DeviceSource.From(sourceName).DisplayName;
            return string.Equals(candidateCanon, targetCanon, StringComparison.OrdinalIgnoreCase);
        }

        public async Task LoadDataAsync()
        {
            try
            {
                // 1. Load canonical daily summary + lean per-device tables + health_sources from HealthHubService
                if (_healthHubService != null)
                {
                    var summaryTask = _healthHubService.GetDailySummaryAsync(_selectedDate);
                    var sleepTask = _healthHubService.GetLeanSleepSessionsAsync(_selectedDate);
                    var vitalsTask = _healthHubService.GetLeanDailyVitalsAsync(_selectedDate);
                    var hrTask = _healthHubService.GetLeanIntradayHeartRateAsync(_selectedDate);
                    var sourcesTask = _healthHubService.GetHealthSourcesAsync();
                    await Task.WhenAll(summaryTask, sleepTask, vitalsTask, hrTask, sourcesTask);

                    _currentSummary = summaryTask.Result;
                    _leanSleepSessions = sleepTask.Result ?? new();
                    _leanDailyVitals = vitalsTask.Result ?? new();
                    _leanIntradayHr = hrTask.Result ?? new();
                    _healthSources = sourcesTask.Result ?? new();
                }
                else
                {
                    _leanSleepSessions = new();
                    _leanDailyVitals = new();
                    _leanIntradayHr = new();
                    _healthSources = new();
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

                _rawMetrics = _metrics;
                _rawSleepSessions = _allSleepSessions;
                _rawPrimarySleepSession = _primarySleepSession;

                // PopulateAvailableDevices FIRST so stale device filter auto-resets to All Devices when switching dates
                PopulateAvailableDevices();
                ApplyDeviceFilter();
                await LoadTrendsHistoryAsync();

                await RefreshDerivedDataAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[HealthDetailPage] LoadDataAsync error: {ex.Message}");
            }
        }

        private void ApplyDeviceFilter()
        {
            _selectedStage = null;
            _filteredStressScore = null;
            _filteredHrvMs = null;
            _filteredHrvIsRmssd = false;
            _filteredRhrBpm = null;
            _filteredSteps = null;
            _filteredActiveKcal = null;
            _filteredSpo2 = null;
            _filteredRespRate = null;
            _filteredWeightKg = null;
            _filteredSleepEfficiency = null;

            if (!string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var matchedLeanSleep = _leanSleepSessions
                    .Where(s => MatchesSelectedDevice(s.SourceDeviceKey) && s.DurationSeconds > 0)
                    .ToList();

                List<SleepSession> matchedSleep;
                if (matchedLeanSleep.Any())
                {
                    matchedSleep = matchedLeanSleep
                        .Select(s => s.ToDomainSleepSession(_selectedDate))
                        .ToList();

                    var primaryLean = matchedLeanSleep
                        .OrderByDescending(s => !string.Equals(s.SessionType, "nap", StringComparison.OrdinalIgnoreCase))
                        .ThenByDescending(s => s.DurationSeconds)
                        .FirstOrDefault();
                    _filteredSleepEfficiency = primaryLean?.EfficiencyPercent;
                }
                else
                {
                    matchedSleep = _rawSleepSessions
                        .Where(s => MatchesSelectedDevice(s.SourceDevice))
                        .ToList();
                }

                _allSleepSessions = matchedSleep;
                _primarySleepSession = matchedSleep
                    .OrderByDescending(s => !s.IsNap)
                    .ThenByDescending(s => s.AsleepSeconds > 0 ? s.AsleepSeconds : s.DurationSeconds)
                    .FirstOrDefault();

                _metrics = _rawMetrics
                    .Where(m => MatchesSelectedDevice(m.SourceDevice))
                    .ToList();

                var matchedVitals = _leanDailyVitals
                    .Where(v => MatchesSelectedDevice(v.SourceDeviceKey))
                    .ToList();

                if (matchedVitals.Any())
                {
                    _filteredSteps = matchedVitals.Max(v => v.Steps);
                    _filteredActiveKcal = matchedVitals.Max(v => v.ActiveKcal);
                    _filteredRhrBpm = matchedVitals.Where(v => (v.RestingHeartRate ?? 0) > 0).Select(v => (double?)v.RestingHeartRate).FirstOrDefault();
                    var sdnn = matchedVitals.Where(v => (v.HrvSdnnNightly ?? 0) > 0).Select(v => v.HrvSdnnNightly).FirstOrDefault();
                    var rmssd = matchedVitals.Where(v => (v.HrvRmssdNightly ?? 0) > 0).Select(v => v.HrvRmssdNightly).FirstOrDefault();
                    _filteredHrvIsRmssd = (!sdnn.HasValue || sdnn.Value <= 0) && rmssd.HasValue && rmssd.Value > 0;
                    _filteredHrvMs = (sdnn.HasValue && sdnn.Value > 0) ? sdnn : rmssd;
                    _filteredSpo2 = matchedVitals.Where(v => (v.Spo2 ?? 0) > 0).Select(v => v.Spo2).FirstOrDefault();
                    _filteredRespRate = matchedVitals.Where(v => (v.RespiratoryRate ?? 0) > 0).Select(v => v.RespiratoryRate).FirstOrDefault();
                    _filteredWeightKg = matchedVitals.Where(v => (v.WeightKg ?? 0) > 0).Select(v => v.WeightKg).FirstOrDefault();
                }

                ComputeFilteredDeviceStress();
            }
            else
            {
                _allSleepSessions = _rawSleepSessions;
                _primarySleepSession = _rawPrimarySleepSession;
                _metrics = _rawMetrics;
            }

            // Evaluate live v2.1 3-Class Arbitration across _leanDailyVitals + _leanIntradayHr
            _arbitratedLatestHr = HealthHubService.ArbitrateLatestHeartRate(
                _leanDailyVitals,
                _leanIntradayHr,
                _selectedDate,
                _healthSources,
                _selectedDeviceFilter);

            if (string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var cardio = _currentSummary?.Summary?.Cardiovascular;
                if (cardio?.LatestBpm is double srvBpm && srvBpm >= 30 && !string.IsNullOrEmpty(cardio.LatestSourceDevice))
                {
                    DateTimeOffset srvDto = default;
                    var rawIso = !string.IsNullOrEmpty(cardio.LatestBpmAt) ? cardio.LatestBpmAt : _currentSummary?.ComputedAt;
                    if (!string.IsNullOrEmpty(rawIso))
                    {
                        DateTimeOffset.TryParse(rawIso, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out srvDto);
                    }
                    if (_arbitratedLatestHr == null || (srvDto != default && srvDto > _arbitratedLatestHr.Timestamp.AddMinutes(1)))
                    {
                        _arbitratedLatestHr = new HealthHubService.ArbitratedLatestHeartRateResult(
                            srvBpm,
                            srvDto,
                            DeviceSource.From(cardio.LatestSourceDevice).DisplayName);
                    }
                }
            }

            _arbitratedActivity = _leanDailyVitals.Count > 0
                ? HealthHubService.ArbitrateHourlyActivity(_leanDailyVitals, _healthSources, _selectedDeviceFilter)
                : null;

            if (string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                _arbitratedSpo2 = HealthHubService.ArbitrateSpotVital(_leanDailyVitals, "spo2", v => v.Spo2, _healthSources);
                _arbitratedWeight = HealthHubService.ArbitrateSpotVital(_leanDailyVitals, "weight", v => v.WeightKg, _healthSources);
            }
            else
            {
                _arbitratedSpo2 = null;
                _arbitratedWeight = null;
            }

            PopulateHourlySteps();
            PopulateHeartRate();
            PopulateDaytimeNaps();
        }

        private static double ScoreFromHrvV2(double hrv, double baseline)
        {
            if (baseline <= 0) return 50.0;
            double scale = Math.Max(14.0, baseline * 0.35);
            double z = (hrv - baseline) / scale;
            return Math.Clamp(50.0 - Math.Tanh(z) * 45.0, 0.0, 100.0);
        }

        private static double ScoreFromSedentaryHrV2(double avgHr, double baselineRhr)
        {
            double delta = avgHr - baselineRhr;
            double z = (delta - 22.0) / 16.0;
            return Math.Clamp(46.0 + Math.Tanh(z) * 44.0, 6.0, 95.0);
        }

        private static double? DeriveNocturnalRhrV2(List<HealthIntradayHeartRateRecord> buckets)
        {
            var nocturnal = buckets
                .Where(b => b.BpmAvg > 35 && b.BpmAvg <= 95 && (b.BucketMinute / 60) < 8)
                .Select(b => (double)b.BpmAvg)
                .OrderBy(v => v)
                .ToList();
            if (nocturnal.Count >= 3)
            {
                int mid = nocturnal.Count / 2;
                double med = (nocturnal.Count % 2 == 1)
                    ? nocturnal[mid]
                    : (nocturnal[mid - 1] + nocturnal[mid]) / 2.0;
                return Math.Round(Math.Clamp(med + 5.5, 45.0, 85.0));
            }
            var daytime = buckets
                .Where(b => b.BpmAvg > 35 && b.BpmAvg < 220 && (b.BucketMinute / 60) >= 8)
                .Select(b => (double)b.BpmAvg)
                .ToList();
            if (daytime.Count >= 3)
            {
                return Math.Round(Math.Clamp(daytime.Min() - 2.0, 48.0, 72.0));
            }
            return null;
        }

        private void ComputeFilteredDeviceStress()
        {
            var canonFilter = !string.IsNullOrEmpty(_selectedDeviceFilter)
                ? DeviceSource.From(_selectedDeviceFilter).DisplayName
                : null;

            Dictionary<string, double>? srvBreakdown = null;
            if (!string.IsNullOrEmpty(canonFilter) && _currentSummary?.Summary?.SourcesBreakdown != null)
            {
                foreach (var kv in _currentSummary.Summary.SourcesBreakdown)
                {
                    if (string.Equals(DeviceSource.From(kv.Key).DisplayName, canonFilter, StringComparison.OrdinalIgnoreCase))
                    {
                        srvBreakdown = kv.Value;
                        break;
                    }
                }
            }

            if (!_filteredRhrBpm.HasValue && srvBreakdown != null)
            {
                if (srvBreakdown.TryGetValue("resting_heart_rate", out var srvRhr) && srvRhr > 0)
                    _filteredRhrBpm = srvRhr;
                else if (srvBreakdown.TryGetValue("derived_rhr", out var srvDerivedRhr) && srvDerivedRhr > 0)
                    _filteredRhrBpm = srvDerivedRhr;
            }

            var matchedHr = _leanIntradayHr
                .Where(h => MatchesSelectedDevice(h.SourceDeviceKey) && h.BpmAvg > 30 && h.BpmAvg < 240)
                .OrderBy(h => h.BucketMinute)
                .ToList();

            if (!_filteredRhrBpm.HasValue && matchedHr.Count > 0)
            {
                _filteredRhrBpm = DeriveNocturnalRhrV2(matchedHr);
            }

            // Prefer server-precomputed canonical per-device stress_score when present
            if (srvBreakdown != null && srvBreakdown.TryGetValue("stress_score", out var precomputedScore) && precomputedScore > 0)
            {
                _filteredStressScore = (int)Math.Round(precomputedScore);
                return;
            }

            // Strictly use filtered device biometrics — NEVER leak unfiltered SQLite vitals across devices!
            double? hrv = (_filteredHrvMs.HasValue && _filteredHrvMs.Value > 0) ? _filteredHrvMs : null;

            if (!hrv.HasValue && matchedHr.Count == 0)
            {
                _filteredStressScore = null;
                return;
            }

            double defaultHrvBase = _filteredHrvIsRmssd ? 62.0 : 45.0;
            bool summaryUsedRmssd = (_currentSummary?.HrvSdnn == null || _currentSummary.HrvSdnn <= 0)
                                 && (_currentSummary?.HrvRmssd != null && _currentSummary.HrvRmssd > 0);
            double? srvBaseHrv = _currentSummary?.Summary?.Stress?.BiometricDrivers?.BaselineHrvMs;
            double baselineHrv = defaultHrvBase;
            if (srvBaseHrv.HasValue && srvBaseHrv.Value > 0)
            {
                if ((_filteredHrvIsRmssd && summaryUsedRmssd && srvBaseHrv.Value >= 35.0) ||
                    (!_filteredHrvIsRmssd && !summaryUsedRmssd && srvBaseHrv.Value <= 120.0))
                {
                    baselineHrv = srvBaseHrv.Value;
                }
            }

            double baselineRhr = (_filteredRhrBpm.HasValue && _filteredRhrBpm.Value > 0)
                ? _filteredRhrBpm.Value
                : 60.0;

            int sleepScore = (_primarySleepSession?.SleepScore ?? 0) > 0 ? _primarySleepSession!.SleepScore : 80;
            double sleepPenalty = Math.Clamp(100.0 - sleepScore, 0.0, 100.0);
            double? dayHrvScore = hrv.HasValue ? ScoreFromHrvV2(hrv.Value, baselineHrv) : null;

            var matchedVitals = _leanDailyVitals.Where(v => MatchesSelectedDevice(v.SourceDeviceKey)).FirstOrDefault();
            var stepsByHour = new Dictionary<int, int>();
            if (matchedVitals?.HourlySteps != null)
            {
                foreach (var hb in matchedVitals.HourlySteps)
                    stepsByHour[hb.Hour] = hb.Steps;
            }

            var hrByHour = matchedHr
                .GroupBy(h => h.BucketMinute / 60)
                .ToDictionary(g => g.Key, g => g.Average(x => (double)x.BpmAvg));

            int maxHour = (_selectedDate.Date == DateTime.Today) ? DateTime.Now.Hour : 23;
            double? lastSedHrScore = null;
            var sedScores = new List<int>();
            var allScores = new List<int>();

            for (int hour = 0; hour <= maxHour; hour++)
            {
                int st = stepsByHour.TryGetValue(hour, out var sv) ? sv : 0;
                bool isSed = st < 300;
                bool hasHr = hrByHour.TryGetValue(hour, out var avgHr);
                if (!hasHr && (!hrv.HasValue || st == 0)) continue;

                double hrScore;
                if (hasHr && isSed)
                {
                    hrScore = ScoreFromSedentaryHrV2(avgHr, baselineRhr);
                    lastSedHrScore = hrScore;
                }
                else if (lastSedHrScore.HasValue)
                {
                    hrScore = 0.85 * lastSedHrScore.Value + 0.15 * 32.0;
                }
                else if (dayHrvScore.HasValue)
                {
                    hrScore = 0.70 * dayHrvScore.Value + 0.30 * 32.0;
                }
                else
                {
                    hrScore = 32.0;
                }

                double rawHourly = dayHrvScore.HasValue
                    ? (0.45 * dayHrvScore.Value + 0.35 * hrScore + 0.20 * sleepPenalty)
                    : (0.70 * hrScore + 0.30 * sleepPenalty);

                int hrFinal = (int)Math.Round(Math.Clamp(rawHourly, 5.0, 98.0));
                allScores.Add(hrFinal);
                if (isSed && hasHr) sedScores.Add(hrFinal);
            }

            if (sedScores.Count >= 2)
            {
                _filteredStressScore = (int)Math.Round(0.70 * sedScores[^1] + 0.30 * sedScores[^2]);
            }
            else if (sedScores.Count == 1)
            {
                _filteredStressScore = sedScores[0];
            }
            else if (allScores.Count > 0)
            {
                _filteredStressScore = allScores[^1];
            }
            else if (dayHrvScore.HasValue)
            {
                double fallbackHr = 0.70 * dayHrvScore.Value + 0.30 * 32.0;
                _filteredStressScore = (int)Math.Round(Math.Clamp(0.45 * dayHrvScore.Value + 0.35 * fallbackHr + 0.20 * sleepPenalty, 8.0, 95.0));
            }
            else
            {
                _filteredStressScore = null;
            }
        }

        public async Task RefreshFromTitleBarAsync()
        {
            if (_healthHubService != null)
            {
                await _healthHubService.PullDeltasAsync();
            }
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

            if (!string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var matchedVitalsWithHourly = _leanDailyVitals
                    .Where(v => MatchesSelectedDevice(v.SourceDeviceKey) && v.HourlySteps != null && v.HourlySteps.Any())
                    .ToList();

                if (matchedVitalsWithHourly.Any())
                {
                    var byHour = new Dictionary<int, double>();
                    foreach (var v in matchedVitalsWithHourly)
                    {
                        foreach (var b in v.HourlySteps!)
                        {
                            if (b.Hour >= 0 && b.Hour < 24)
                            {
                                byHour[b.Hour] = byHour.TryGetValue(b.Hour, out var prev) ? Math.Max(prev, b.Steps) : b.Steps;
                            }
                        }
                    }

                    for (int h = 0; h < 24; h++)
                    {
                        double steps = byHour.TryGetValue(h, out var s) ? s : 0;
                        HourlyStepsCollection.Add(new HealthChartData
                        {
                            Label = $"{h:D2}",
                            Value = steps,
                            FormattedValue = steps > 0 ? steps.ToString("N0") : ""
                        });
                    }
                    return;
                }

                var stepsTelemetry = _telemetryData
                    .Where(x => x.IsSteps && x.LocalStartTime.Date == _selectedDate.Date && MatchesSelectedDevice(x.SourceDevice))
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
                return;
            }

            if (_arbitratedActivity != null && _arbitratedActivity.HourlySteps.Any(b => b.Steps > 0))
            {
                for (int h = 0; h < 24; h++)
                {
                    double steps = _arbitratedActivity.HourlySteps.FirstOrDefault(b => b.Hour == h)?.Steps ?? 0;
                    HourlyStepsCollection.Add(new HealthChartData
                    {
                        Label = $"{h:D2}",
                        Value = steps,
                        FormattedValue = steps > 0 ? steps.ToString("N0") : ""
                    });
                }
                return;
            }

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

            if (!string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var matchedLeanHr = _leanIntradayHr
                    .Where(h => MatchesSelectedDevice(h.SourceDeviceKey) && h.BpmAvg > 0)
                    .OrderBy(h => h.BucketMinute)
                    .ToList();

                if (matchedLeanHr.Any())
                {
                    var canonDev = DeviceSource.From(_selectedDeviceFilter).DisplayName;
                    foreach (var pt in matchedLeanHr)
                    {
                        var ts = _selectedDate.Date.AddMinutes(Math.Clamp(pt.BucketMinute, 0, 1439));
                        HeartRateCollection.Add(new HealthTelemetry
                        {
                            TypeString = "heart_rate",
                            Value = pt.BpmAvg,
                            Unit = "bpm",
                            StartTime = ts,
                            EndTime = ts,
                            SourceDevice = canonDev
                        });
                    }
                    return;
                }

                var hrPoints = _telemetryData
                    .Where(x => x.IsHeartRate && x.LocalStartTime.Date == _selectedDate.Date && x.Value.HasValue && x.Value > 0 &&
                                MatchesSelectedDevice(x.SourceDevice))
                    .OrderBy(x => x.LocalStartTime)
                    .ToList();

                foreach (var item in hrPoints)
                {
                    HeartRateCollection.Add(item);
                }
                return;
            }

            if (_leanIntradayHr.Any(h => h.BpmAvg > 0))
            {
                var groupedByMinute = _leanIntradayHr
                    .Where(h => h.BpmAvg > 0)
                    .GroupBy(h => h.BucketMinute)
                    .OrderBy(g => g.Key);

                foreach (var grp in groupedByMinute)
                {
                    var best = grp.OrderBy(x => HealthHubService.ResolveEffectivePriorityRank(x.SourceDeviceKey, _healthSources)).First();
                    var ts = _selectedDate.Date.AddMinutes(Math.Clamp(best.BucketMinute, 0, 1439));
                    HeartRateCollection.Add(new HealthTelemetry
                    {
                        TypeString = "heart_rate",
                        Value = best.BpmAvg,
                        Unit = "bpm",
                        StartTime = ts,
                        EndTime = ts,
                        SourceDevice = DeviceSource.From(best.SourceDeviceKey).DisplayName
                    });
                }
                return;
            }

            var intradayHr = _currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate;
            if (intradayHr != null && intradayHr.Any())
            {
                foreach (var pt in intradayHr)
                {
                    if (DateTime.TryParse(pt.Timestamp, out var ts) && pt.Bpm > 0)
                    {
                        var srcName = !string.IsNullOrEmpty(pt.SourceDevice) && !DeviceSource.IsVirtual(pt.SourceDevice)
                            ? DeviceSource.From(pt.SourceDevice).DisplayName
                            : DominantDeviceName;

                        HeartRateCollection.Add(new HealthTelemetry
                        {
                            TypeString = "heart_rate",
                            Value = pt.Bpm,
                            Unit = "bpm",
                            StartTime = ts,
                            EndTime = ts,
                            SourceDevice = srcName
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

            if (!string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var naps = _allSleepSessions.Where(s => s.IsNap).ToList();
                foreach (var nap in naps)
                {
                    int mins = nap.DurationSeconds > 0 ? (int)Math.Round(nap.DurationSeconds / 60.0) : 0;
                    string timeRange = nap.StartTime != default && nap.EndTime != default
                        ? $"{nap.StartTime:HH:mm} - {nap.EndTime:HH:mm}"
                        : "--:--";

                    DaytimeNapsList.Add(new NapDisplayItem
                    {
                        TimeRange = timeRange,
                        DurationText = $"{mins} minutes restorative nap",
                        NapMinutesText = $"{mins} min",
                        DeviceName = DeviceSource.From(nap.SourceDevice ?? _selectedDeviceFilter).DisplayName
                    });
                }
                return;
            }

            var canonicalNaps = _currentSummary?.Summary?.Sleep?.Naps;
            if (canonicalNaps != null && canonicalNaps.Any())
            {
                foreach (var nap in canonicalNaps)
                {
                    DateTimeOffset.TryParse(nap.StartTime, out var sDto);
                    DateTimeOffset.TryParse(nap.EndTime, out var eDto);
                    int mins = nap.DurationSeconds > 0 ? (int)Math.Round(nap.DurationSeconds / 60.0) : 0;
                    string timeRange = sDto != default && eDto != default
                        ? $"{sDto.LocalDateTime:HH:mm} - {eDto.LocalDateTime:HH:mm}"
                        : "--:--";
                    var rawDev = nap.SourceDevice ?? nap.Tracker;
                    var cleanDev = !string.IsNullOrEmpty(rawDev) && !DeviceSource.IsVirtual(rawDev)
                        ? DeviceSource.From(rawDev).DisplayName
                        : "Wearable";

                    DaytimeNapsList.Add(new NapDisplayItem
                    {
                        TimeRange = timeRange,
                        DurationText = $"{mins} minutes restorative nap",
                        NapMinutesText = $"{mins} min",
                        DeviceName = cleanDev
                    });
                }
            }
        }

        private void PopulateAvailableDevices()
        {
            AvailableDevices.Clear();

            var discoveredCanon = new Dictionary<string, DeviceSource>(StringComparer.OrdinalIgnoreCase);

            void AddCandidate(string? rawName)
            {
                if (string.IsNullOrWhiteSpace(rawName)) return;
                var src = DeviceSource.From(rawName);
                if (src.IsVirtualEngine) return;
                if (!discoveredCanon.ContainsKey(src.DisplayName))
                {
                    discoveredCanon[src.DisplayName] = src;
                }
            }

            bool hasAnyLeanSignal = false;

            foreach (var s in _leanSleepSessions)
            {
                if (s.DurationSeconds > 0)
                {
                    AddCandidate(s.SourceDeviceKey);
                    hasAnyLeanSignal = true;
                }
            }

            foreach (var v in _leanDailyVitals)
            {
                if (v.HasSignal)
                {
                    AddCandidate(v.SourceDeviceKey);
                    hasAnyLeanSignal = true;
                }
            }

            foreach (var h in _leanIntradayHr)
            {
                if (h.BpmAvg > 0)
                {
                    AddCandidate(h.SourceDeviceKey);
                    hasAnyLeanSignal = true;
                }
            }

            // Fallback to summary / domain records ONLY if lean tables returned nothing (e.g. offline cache)
            if (!hasAnyLeanSignal)
            {
                if (!string.IsNullOrEmpty(_rawPrimarySleepSession?.SourceDevice))
                {
                    AddCandidate(_rawPrimarySleepSession.SourceDevice);
                }

                foreach (var s in _rawSleepSessions)
                {
                    if (s.DurationSeconds > 0) AddCandidate(s.SourceDevice);
                }

                if (_currentSummary?.Summary?.Vitals != null)
                {
                    foreach (var v in _currentSummary.Summary.Vitals.Values)
                    {
                        if (v.Value > 0) AddCandidate(v.SourceDevice);
                    }
                }

                if (_currentSummary?.Summary?.Sources != null)
                {
                    foreach (var srcName in _currentSummary.Summary.Sources)
                    {
                        AddCandidate(srcName);
                    }
                }

                foreach (var m in _rawMetrics)
                {
                    if (m.Value > 0) AddCandidate(m.SourceDevice);
                }
            }

            // Auto-reset device filter to All Devices if previously selected device has no data on _selectedDate
            if (!string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var selectedCanon = DeviceSource.From(_selectedDeviceFilter).DisplayName;
                if (!discoveredCanon.ContainsKey(selectedCanon))
                {
                    _selectedDeviceFilter = null;
                }
                else
                {
                    _selectedDeviceFilter = selectedCanon;
                }
            }

            // First entry: All Devices (Consolidated)
            AvailableDevices.Add(new DeviceFilterItem
            {
                DeviceName = "",
                DisplayName = "All Devices (Consolidated)",
                SegoeGlyph = "\xEB51",
                ColorBrush = new SolidColorBrush(Color.FromArgb(255, 255, 45, 85)),
                IsSelected = string.IsNullOrEmpty(_selectedDeviceFilter)
            });

            var sortedDevices = discoveredCanon.Values
                .OrderBy(d => HealthHubService.ResolveEffectivePriorityRank(d.DisplayName, _healthSources))
                .ThenBy(d => d.DisplayName)
                .ToList();

            foreach (var src in sortedDevices)
            {
                AvailableDevices.Add(new DeviceFilterItem
                {
                    DeviceName = src.DisplayName,
                    DisplayName = src.DisplayName,
                    SegoeGlyph = src.SegoeGlyph,
                    ColorBrush = GetDeviceColorBrush(src.DisplayName),
                    IsSelected = string.Equals(_selectedDeviceFilter, src.DisplayName, StringComparison.OrdinalIgnoreCase)
                });
            }

            RebuildDeviceMenuFlyout();
            OnPropertyChanged(nameof(SelectedDeviceLabel));
            OnPropertyChanged(nameof(SelectedDeviceDotBrush));
            OnPropertyChanged(nameof(SelectedDeviceGlyph));
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

                menuItem.Click += async (s, e) =>
                {
                    if (s is MenuFlyoutItem mi)
                    {
                        string? target = mi.Tag as string;
                        _selectedDeviceFilter = string.IsNullOrEmpty(target) ? null : target;
                        PopulateAvailableDevices();

                        ApplyDeviceFilter();
                        await LoadTrendsHistoryAsync();
                        await RefreshDerivedDataAsync();
                    }
                };

                DeviceMenuFlyout.Items.Add(menuItem);
            }

            if (_healthHubService != null && _healthSources.Count > 0)
            {
                DeviceMenuFlyout.Items.Add(new MenuFlyoutSeparator());
                var priorityItem = new MenuFlyoutItem
                {
                    Text = "Device Priority...",
                    Icon = new FontIcon
                    {
                        Glyph = "\xE713",
                        FontFamily = new FontFamily("Segoe Fluent Icons"),
                        Foreground = new SolidColorBrush(Color.FromArgb(255, 56, 151, 240))
                    }
                };
                priorityItem.Click += async (s, e) => await ShowDevicePriorityDialogAsync();
                DeviceMenuFlyout.Items.Add(priorityItem);
            }
        }

        private async Task ShowDevicePriorityDialogAsync()
        {
            if (_healthHubService == null || this.XamlRoot == null) return;

            var working = (await _healthHubService.GetHealthSourcesAsync(forceRefresh: true)).ToList();
            if (working.Count == 0) return;

            var listPanel = new StackPanel { Spacing = 8 };
            var statusText = new TextBlock
            {
                FontSize = 11,
                Opacity = 0.7,
                TextWrapping = TextWrapping.Wrap,
                Text = "Live heart rate and stress always use the newest reading from the device you are currently wearing. Priority order governs primary sleep, resting baselines, and simultaneous wear."
            };

            void RebuildRows()
            {
                listPanel.Children.Clear();
                for (int i = 0; i < working.Count; i++)
                {
                    int idx = i;
                    var src = working[idx];
                    var rowGrid = new Grid { Padding = new Thickness(10, 6, 10, 6) };
                    rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                    var leftStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
                    leftStack.Children.Add(new TextBlock
                    {
                        Text = $"#{idx + 1}",
                        FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                        Foreground = new SolidColorBrush(Color.FromArgb(255, 56, 151, 240)),
                        VerticalAlignment = VerticalAlignment.Center
                    });
                    leftStack.Children.Add(new Ellipse
                    {
                        Width = 8,
                        Height = 8,
                        Fill = GetDeviceColorBrush(src.DisplayName),
                        VerticalAlignment = VerticalAlignment.Center
                    });
                    leftStack.Children.Add(new TextBlock
                    {
                        Text = src.DisplayName,
                        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                        VerticalAlignment = VerticalAlignment.Center
                    });

                    var btnStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
                    var upBtn = new Button
                    {
                        Content = "▲",
                        FontSize = 11,
                        Padding = new Thickness(8, 3, 8, 3),
                        IsEnabled = idx > 0
                    };
                    upBtn.Click += (s, e) =>
                    {
                        if (idx <= 0) return;
                        (working[idx - 1], working[idx]) = (working[idx], working[idx - 1]);
                        RebuildRows();
                    };

                    var downBtn = new Button
                    {
                        Content = "▼",
                        FontSize = 11,
                        Padding = new Thickness(8, 3, 8, 3),
                        IsEnabled = idx < working.Count - 1
                    };
                    downBtn.Click += (s, e) =>
                    {
                        if (idx >= working.Count - 1) return;
                        (working[idx + 1], working[idx]) = (working[idx], working[idx + 1]);
                        RebuildRows();
                    };

                    btnStack.Children.Add(upBtn);
                    btnStack.Children.Add(downBtn);

                    Grid.SetColumn(leftStack, 0);
                    Grid.SetColumn(btnStack, 1);
                    rowGrid.Children.Add(leftStack);
                    rowGrid.Children.Add(btnStack);

                    listPanel.Children.Add(new Border
                    {
                        CornerRadius = new CornerRadius(8),
                        Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)),
                        Child = rowGrid
                    });
                }
            }

            RebuildRows();

            var contentStack = new StackPanel { Spacing = 12, MinWidth = 360 };
            contentStack.Children.Add(statusText);
            contentStack.Children.Add(listPanel);

            var dialog = new ContentDialog
            {
                XamlRoot = this.XamlRoot,
                Title = "Device Priority Order",
                Content = contentStack,
                PrimaryButtonText = "Save Priority",
                SecondaryButtonText = "Reset Default",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary
            };

            var res = await dialog.ShowAsync();
            if (res == ContentDialogResult.Primary)
            {
                await _healthHubService.SaveDevicePriorityOrderAsync(working.Select(x => x.Id).ToList());
                await LoadDataAsync();
            }
            else if (res == ContentDialogResult.Secondary)
            {
                await _healthHubService.ResetDevicePriorityOrderAsync();
                await LoadDataAsync();
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
            List<HealthDailyVitalsRecord> rangeVitals = new();
            List<HealthSleepSessionRecord> rangeSleeps = new();

            if (_healthHubService != null)
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    var sTask = _healthHubService.GetDailySummariesRangeAsync(startDate, endDate);
                    var vTask = _healthHubService.GetLeanDailyVitalsRangeAsync(startDate, endDate);
                    var slTask = _healthHubService.GetLeanSleepSessionsRangeAsync(startDate, endDate);
                    await Task.WhenAll(sTask, vTask, slTask);
                    rangeSummaries = sTask.Result ?? new();
                    rangeVitals = vTask.Result ?? new();
                    rangeSleeps = slTask.Result ?? new();
                }
                else
                {
                    rangeSummaries = await _healthHubService.GetDailySummariesRangeAsync(startDate, endDate);
                }
            }

            for (int i = 6; i >= 0; i--)
            {
                var day = endDate.AddDays(-i);
                var dayStr = day.ToString("yyyy-MM-dd");
                var dayLabel = day.ToString("ddd");

                var summary = rangeSummaries.FirstOrDefault(s => s.LocalDate == dayStr);

                double steps = 0;
                double rhr = 0;
                double sleepHours = 0;
                double cal = 0;
                double wt = 0;
                double hrv = 0;

                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    var dayVitals = rangeVitals
                        .Where(v => v.LocalDate == dayStr && MatchesSelectedDevice(v.SourceDeviceKey))
                        .ToList();

                    if (dayVitals.Any())
                    {
                        steps = dayVitals.Max(v => v.Steps);
                        cal = dayVitals.Max(v => v.ActiveKcal);
                        rhr = dayVitals.Where(v => (v.RestingHeartRate ?? 0) > 0).Select(v => (double)v.RestingHeartRate!.Value).FirstOrDefault();
                        wt = dayVitals.Where(v => (v.WeightKg ?? 0) > 0).Select(v => v.WeightKg!.Value).FirstOrDefault();
                        hrv = dayVitals.Where(v => (v.HrvSdnnNightly ?? 0) > 0).Select(v => v.HrvSdnnNightly!.Value).FirstOrDefault();
                        if (hrv <= 0)
                        {
                            hrv = dayVitals.Where(v => (v.HrvRmssdNightly ?? 0) > 0).Select(v => v.HrvRmssdNightly!.Value).FirstOrDefault();
                        }
                    }
                    else
                    {
                        var vitals = summary?.Summary?.Vitals;
                        if (vitals != null)
                        {
                            if (vitals.TryGetValue("steps", out var st) && MatchesSelectedDevice(st.SourceDevice)) steps = st.Value;
                            if (vitals.TryGetValue("resting_heart_rate", out var rh) && MatchesSelectedDevice(rh.SourceDevice)) rhr = rh.Value;
                            if (vitals.TryGetValue("active_energy", out var ae) && MatchesSelectedDevice(ae.SourceDevice)) cal = ae.Value;
                            if (vitals.TryGetValue("weight", out var we) && MatchesSelectedDevice(we.SourceDevice)) wt = we.Value;
                            if (vitals.TryGetValue("hrv_sdnn", out var hs) && MatchesSelectedDevice(hs.SourceDevice)) hrv = hs.Value;
                            else if (vitals.TryGetValue("hrv_rmssd", out var hr) && MatchesSelectedDevice(hr.SourceDevice)) hrv = hr.Value;
                        }
                    }

                    var daySleep = rangeSleeps
                        .Where(s => s.LocalDate == dayStr && MatchesSelectedDevice(s.SourceDeviceKey) &&
                                    !string.Equals(s.SessionType, "nap", StringComparison.OrdinalIgnoreCase))
                        .OrderByDescending(s => s.DurationSeconds)
                        .FirstOrDefault();

                    if (daySleep != null && daySleep.DurationSeconds > 0)
                    {
                        sleepHours = Math.Round(daySleep.DurationSeconds / 3600.0, 1);
                    }
                    else
                    {
                        var matchedSleep = summary?.Summary?.Sleep?.AllSessions?.FirstOrDefault(ss => MatchesSelectedDevice(ss.EffectiveSourceDevice));
                        if (matchedSleep != null)
                        {
                            sleepHours = matchedSleep.AsleepSeconds > 0 ? Math.Round(matchedSleep.AsleepSeconds / 3600.0, 1) : Math.Round(matchedSleep.DurationSeconds / 3600.0, 1);
                        }
                    }
                }
                else
                {
                    steps = summary?.Steps ?? 0;
                    rhr = summary?.Rhr ?? 0;
                    sleepHours = summary?.SleepAsleepS.HasValue == true ? Math.Round(summary.SleepAsleepS.Value / 3600.0, 1) : 0;
                    cal = summary?.ActiveKcal ?? 0;
                    wt = summary?.Weight ?? 0;
                    hrv = summary?.HrvSdnn ?? summary?.HrvRmssd ?? 0;
                }

                // Steps
                StepsHistory.Add(new HealthChartData { Label = dayLabel, Value = steps, FormattedValue = steps > 0 ? steps.ToString("N0") : "--" });

                // HR
                HrHistory.Add(new HealthChartData { Label = dayLabel, Value = rhr, FormattedValue = rhr > 0 ? $"{rhr:F0}" : "--" });

                // Sleep (hours)
                SleepHistory.Add(new HealthChartData { Label = dayLabel, Value = sleepHours, FormattedValue = sleepHours > 0 ? $"{sleepHours:F1}h" : "--" });

                // Calories
                CaloriesHistory.Add(new HealthChartData { Label = dayLabel, Value = cal, FormattedValue = cal > 0 ? $"{cal:F0}" : "--" });

                // Weight
                WeightHistory.Add(new HealthChartData { Label = dayLabel, Value = wt, FormattedValue = wt > 0 ? $"{wt:F1}" : "--" });

                // HRV
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

        // ==========================================
        // TAB 0: OVERVIEW PROPERTIES
        // ==========================================

        public string StepsText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    double s = _filteredSteps ?? GetMetric(VitalType.Steps)?.Value ?? 0;
                    return s > 0 ? s.ToString("N0") : "--";
                }
                double steps = Math.Max(_arbitratedActivity?.TotalSteps ?? 0, _currentSummary?.Steps ?? (int)(GetMetric(VitalType.Steps)?.Value ?? 0));
                return steps > 0 ? steps.ToString("N0") : "--";
            }
        }

        public double StepsProgressValue
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    double s = _filteredSteps ?? GetMetric(VitalType.Steps)?.Value ?? 0;
                    return Math.Min(100.0, Math.Max(0.0, (s / 10000.0) * 100.0));
                }
                double steps = Math.Max(_arbitratedActivity?.TotalSteps ?? 0, _currentSummary?.Steps ?? (int)(GetMetric(VitalType.Steps)?.Value ?? 0));
                return Math.Min(100.0, Math.Max(0.0, (steps / 10000.0) * 100.0));
            }
        }

        public string CaloriesText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    double cal = _filteredActiveKcal ?? GetMetric(VitalType.ActiveEnergy)?.Value ?? 0;
                    return cal > 0 ? $"{cal:N0}" : "--";
                }
                double kcal = Math.Max(_arbitratedActivity?.ActiveCalories ?? 0, _currentSummary?.ActiveKcal ?? GetMetric(VitalType.ActiveEnergy)?.Value ?? 0);
                return kcal > 0 ? $"{kcal:N0}" : "--";
            }
        }

        public string SleepText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0)
                    {
                        var ts = TimeSpan.FromSeconds(_primarySleepSession.AsleepSeconds > 0 ? _primarySleepSession.AsleepSeconds : _primarySleepSession.DurationSeconds);
                        return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                    }
                    return "--";
                }
                if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0)
                {
                    var ts = TimeSpan.FromSeconds(_primarySleepSession.AsleepSeconds > 0 ? _primarySleepSession.AsleepSeconds : _primarySleepSession.DurationSeconds);
                    return $"{(int)ts.TotalHours}h {ts.Minutes}m";
                }
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
                double steps = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredSteps ?? GetMetric(VitalType.Steps)?.Value ?? 0)
                    : (_currentSummary?.Steps ?? GetMetric(VitalType.Steps)?.Value ?? 0);
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
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    int s = _primarySleepSession?.SleepScore ?? 0;
                    return s > 0 ? s.ToString() : "--";
                }
                int score = _primarySleepSession?.SleepScore ?? _currentSummary?.SleepScore ?? 0;
                return score > 0 ? score.ToString() : "--";
            }
        }

        public string SleepQualityRatingText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    if (_primarySleepSession == null) return "NO DATA";
                    int s = _primarySleepSession.SleepScore;
                    if (s >= 85) return "EXCELLENT";
                    if (s >= 70) return "GOOD";
                    if (s >= 50) return "FAIR";
                    if (s > 0) return "NEEDS ATTENTION";
                    return "RECORDED";
                }
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
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    if (_primarySleepSession == null || _primarySleepSession.DurationSeconds <= 0)
                    {
                        return "--%";
                    }
                    if (_filteredSleepEfficiency.HasValue && _filteredSleepEfficiency.Value > 0)
                    {
                        return $"{_filteredSleepEfficiency.Value:F0}% eff";
                    }
                    double asleep = _primarySleepSession.AsleepSeconds > 0 ? _primarySleepSession.AsleepSeconds : _primarySleepSession.DurationSeconds;
                    double inBed = Math.Max(asleep, _primarySleepSession.DurationSeconds);
                    int computedEff = (int)Math.Round(Math.Clamp((asleep / inBed) * 100.0, 1.0, 100.0));
                    return $"{computedEff}% eff";
                }

                int eff = _currentSummary?.Summary?.Sleep?.PrimarySession?.EfficiencyPercent ?? 0;
                if (eff > 0) return $"{eff}% eff";

                if (_primarySleepSession != null && _primarySleepSession.DurationSeconds > 0 && _primarySleepSession.AsleepSeconds > 0)
                {
                    int computedEff = (int)Math.Round(Math.Clamp((_primarySleepSession.AsleepSeconds / _primarySleepSession.DurationSeconds) * 100.0, 1.0, 100.0));
                    return $"{computedEff}% eff";
                }
                return "--%";
            }
        }

        public string RestorativePctText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    if (_primarySleepSession == null) return "--%";
                    double d = _primarySleepSession.DeepSeconds;
                    double r = _primarySleepSession.RemSeconds;
                    double a = _primarySleepSession.AsleepSeconds > 0 ? _primarySleepSession.AsleepSeconds : _primarySleepSession.DurationSeconds;
                    if (a > 0 && (d + r) > 0)
                    {
                        return $"{((d + r) / a) * 100:F0}%";
                    }
                    return "--%";
                }

                int rest = _currentSummary?.Summary?.Sleep?.PrimarySession?.RestorativePercent ?? 0;
                if (rest > 0) return $"{rest}%";

                double deep = _primarySleepSession?.DeepSeconds ?? 0;
                double rem = _primarySleepSession?.RemSeconds ?? 0;
                double asleep = _primarySleepSession?.AsleepSeconds ?? 0;
                if (asleep > 0 && (deep + rem) > 0)
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
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    var devLabel = DeviceSource.From(_selectedDeviceFilter).DisplayName;
                    if (_primarySleepSession == null || _primarySleepSession.DurationSeconds <= 0)
                    {
                        return $"No sleep session recorded by {devLabel} for this date.";
                    }

                    double asleepSec = _primarySleepSession.AsleepSeconds > 0 ? _primarySleepSession.AsleepSeconds : _primarySleepSession.DurationSeconds;
                    var ts = TimeSpan.FromSeconds(asleepSec);
                    double restPct = asleepSec > 0 ? ((_primarySleepSession.DeepSeconds + _primarySleepSession.RemSeconds) / asleepSec) * 100.0 : 0;
                    int s = _primarySleepSession.SleepScore;

                    if (s >= 85)
                        return $"{devLabel} recorded {(int)ts.TotalHours}h {ts.Minutes}m of optimal restorative sleep ({restPct:F0}% Deep + REM architecture).";
                    if (s >= 70)
                        return $"{devLabel} recorded {(int)ts.TotalHours}h {ts.Minutes}m of solid sleep with {restPct:F0}% restorative Deep + REM stages.";
                    if (s > 0)
                        return $"{devLabel} recorded {(int)ts.TotalHours}h {ts.Minutes}m of sleep ({restPct:F0}% restorative). Mild fragmentation or shorter recovery detected.";
                    return $"{devLabel} recorded {(int)ts.TotalHours}h {ts.Minutes}m of sleep.";
                }

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

        private int EffectiveStressScore
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    return _filteredStressScore ?? 0;
                }
                int canonicalCurrent = _currentSummary?.Summary?.Stress?.CurrentScore ?? 0;
                if (canonicalCurrent > 0) return canonicalCurrent;
                return _currentSummary?.StressAvg ?? (int)(GetMetric(VitalType.Stress)?.Value ?? 0);
            }
        }

        public string StressScoreText
        {
            get
            {
                int score = EffectiveStressScore;
                return score > 0 ? score.ToString() : "--";
            }
        }

        public SolidColorBrush StressScoreBrush
        {
            get
            {
                int score = EffectiveStressScore;
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
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    int s = EffectiveStressScore;
                    if (s <= 0) return "No Data";
                    if (s <= 25) return "Restful";
                    if (s <= 50) return "Calm";
                    if (s <= 75) return "Moderate";
                    return "High";
                }
                var lvl = _currentSummary?.Summary?.Stress?.CurrentLevel;
                if (!string.IsNullOrEmpty(lvl)) return lvl;

                int score = EffectiveStressScore;
                if (score <= 0) return "No Data";
                if (score <= 25) return "Restful";
                if (score <= 50) return "Calm";
                if (score <= 75) return "Moderate";
                return "High";
            }
        }

        public string MonkeyMoodEmoji
        {
            get
            {
                if (string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    var mood = _currentSummary?.Summary?.Stress?.MonkeyMood;
                    if (!string.IsNullOrEmpty(mood))
                    {
                        return mood.ToLowerInvariant() switch
                        {
                            "zen" or "zen monkey" => "🧘",
                            "happy" => "🐵",
                            "curious" or "curious monkey" => "🐒",
                            "alert" => "👀",
                            "wired" or "busy" or "busy monkey" => "⚡",
                            "overheated" or "overheated monkey" or "exhausted" => "💤",
                            _ => "🐵"
                        };
                    }
                }

                int score = EffectiveStressScore;
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
                int score = EffectiveStressScore;
                if (score <= 0)
                {
                    return !string.IsNullOrEmpty(_selectedDeviceFilter)
                        ? $"No HRV or heart rate telemetry recorded by {DeviceSource.From(_selectedDeviceFilter).DisplayName} for this date."
                        : "No real-time stress data recorded for this period.";
                }
                if (score <= 25) return "Zen mode. Autonomic parasympathetic dominance indicates excellent recovery.";
                if (score <= 50) return "Balanced homeostasis. Physiological strain remains within normal limits.";
                if (score <= 75) return "Elevated sympathetic activation. Recommended: 5 minutes of box breathing.";
                return "High autonomic strain. Consider resting, hydrating, and avoiding intensive stimuli.";
            }
        }

        public string AutonomicDominantText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter) && EffectiveStressScore <= 0)
                {
                    return "No Autonomic Telemetry";
                }
                double para = ParasympatheticRatioPct;
                return para >= 50 ? "Parasympathetic Dominant" : "Sympathetic Dominant";
            }
        }

        public double ParasympatheticRatioPct
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    int s = EffectiveStressScore;
                    if (s <= 0) return 50.0;
                    return Math.Max(10.0, Math.Min(90.0, 100.0 - s));
                }
                var balance = _currentSummary?.Summary?.Stress?.AutonomicBalance;
                if (balance != null) return balance.ParasympatheticPercent;
                int score = EffectiveStressScore;
                return score > 0 ? Math.Max(10, Math.Min(90, 100 - score)) : 50;
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
                double steps = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredSteps ?? GetMetric(VitalType.Steps)?.Value ?? 0)
                    : (_currentSummary?.Steps ?? 0);
                return Math.Min(100.0, Math.Max(5.0, (steps / 10000.0) * 100.0));
            }
        }

        public string DriverSleepText => $"{DriverSleepPct:F0}%";
        public double DriverSleepPct
        {
            get
            {
                int score = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_primarySleepSession?.SleepScore ?? 0)
                    : (_primarySleepSession?.SleepScore ?? _currentSummary?.SleepScore ?? 0);
                return score > 0 ? Math.Max(5.0, 100.0 - score) : 25.0;
            }
        }

        public string DriverHrvText => $"{DriverHrvPct:F0}%";
        public double DriverHrvPct
        {
            get
            {
                double baseline = _currentSummary?.Summary?.Stress?.BiometricDrivers?.BaselineHrvMs ?? 45.0;
                if (baseline <= 0) baseline = 45.0;

                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    if (_filteredHrvMs.HasValue && _filteredHrvMs.Value > 0)
                    {
                        double devBase = _filteredHrvIsRmssd ? 62.0 : 45.0;
                        return Math.Round(ScoreFromHrvV2(_filteredHrvMs.Value, devBase), 0);
                    }
                    return 20.0;
                }

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
        public double DriverSpikesPct => Math.Min(100.0, Math.Max(5.0, (EffectiveStressScore > 0 ? EffectiveStressScore : 25) * 0.4));

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
                if (_arbitratedLatestHr != null && _arbitratedLatestHr.Bpm >= 30)
                {
                    return $"{_arbitratedLatestHr.Bpm:N0} bpm";
                }

                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    var lastFilteredPt = HeartRateCollection.LastOrDefault(p => (p.Value ?? 0) > 0);
                    if (lastFilteredPt != null) return $"{lastFilteredPt.Value:N0} bpm";

                    var mf = GetMetric(VitalType.HeartRate);
                    if (mf?.Value > 0) return $"{mf.Value:N0} bpm";

                    double rhrF = _filteredRhrBpm ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                    return rhrF > 0 ? $"{rhrF:N0} bpm" : "-- bpm";
                }

                var srvLatest = _currentSummary?.Summary?.Cardiovascular?.LatestBpm;
                if (srvLatest.HasValue && srvLatest.Value >= 30)
                {
                    return $"{srvLatest.Value:N0} bpm";
                }

                var intraday = _currentSummary?.Summary?.Cardiovascular?.IntradayHeartRate;
                if (intraday != null && intraday.Any())
                {
                    var lastPt = intraday.LastOrDefault(p => p.Bpm > 0);
                    if (lastPt != null) return $"{lastPt.Bpm:N0} bpm";
                }
                if (HeartRateCollection.Any())
                {
                    var lastColl = HeartRateCollection.LastOrDefault(p => (p.Value ?? 0) > 0);
                    if (lastColl != null) return $"{lastColl.Value:N0} bpm";
                }
                var m = GetMetric(VitalType.HeartRate);
                if (m?.Value > 0) return $"{m.Value:N0} bpm";
                double rhr = _currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0;
                return rhr > 0 ? $"{rhr:N0} bpm" : "-- bpm";
            }
        }

        public string LatestHeartRateHeroText => HeartRateText;

        public string LatestHeartRateMetaText
        {
            get
            {
                if (_arbitratedLatestHr == null || _arbitratedLatestHr.Bpm < 30) return string.Empty;
                var parts = new List<string>();
                if (_arbitratedLatestHr.Timestamp != default)
                {
                    parts.Add($"at {_arbitratedLatestHr.Timestamp.LocalDateTime:HH:mm}");
                }
                if (!string.IsNullOrEmpty(_arbitratedLatestHr.SourceDevice))
                {
                    parts.Add(_arbitratedLatestHr.SourceDevice);
                }
                return string.Join(" • ", parts);
            }
        }

        public Visibility HasLatestHeartRateMeta => !string.IsNullOrWhiteSpace(LatestHeartRateMetaText)
            ? Visibility.Visible
            : Visibility.Collapsed;

        public string HeroRestingHrSubText => $"Rest: {RhrText}";

        public string AvgHeartRateText
        {
            get
            {
                if (!string.IsNullOrEmpty(_selectedDeviceFilter))
                {
                    if (HeartRateCollection.Any())
                    {
                        return $"{HeartRateCollection.Average(x => x.Value ?? 0):F0} bpm avg";
                    }
                    return "-- bpm avg";
                }

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
                double rhr = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredRhrBpm ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0)
                    : (_currentSummary?.Rhr ?? GetMetric(VitalType.RestingHeartRate)?.Value ?? 0);
                return rhr > 0 ? $"{rhr:F0} bpm" : "-- bpm";
            }
        }

        public string HrvText
        {
            get
            {
                double hrv = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredHrvMs ?? GetMetric(VitalType.HeartRateVariabilitySDNN)?.Value ?? GetMetric(VitalType.HeartRateVariabilityRMSSD)?.Value ?? 0)
                    : (_currentSummary?.HrvSdnn ?? _currentSummary?.HrvRmssd ?? GetMetric(VitalType.HeartRateVariabilitySDNN)?.Value ?? 0);
                return hrv > 0 ? $"{hrv:F0} ms" : "-- ms";
            }
        }

        public string Spo2Text
        {
            get
            {
                double spo2 = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredSpo2 ?? GetMetric(VitalType.OxygenSaturation)?.Value ?? 0)
                    : (_arbitratedSpo2?.Value ?? _currentSummary?.Spo2 ?? GetMetric(VitalType.OxygenSaturation)?.Value ?? 0);
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
                double resp = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredRespRate ?? GetMetric(VitalType.RespiratoryRate)?.Value ?? 0)
                    : (GetMetric(VitalType.RespiratoryRate)?.Value ?? 0);
                return resp > 0 ? $"{resp:F0} br/m" : "-- br/m";
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
                double wt = !string.IsNullOrEmpty(_selectedDeviceFilter)
                    ? (_filteredWeightKg ?? GetMetric(VitalType.Weight)?.Value ?? 0)
                    : (_arbitratedWeight?.Value ?? _currentSummary?.Weight ?? GetMetric(VitalType.Weight)?.Value ?? 0);
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
            if (HeartRateCollection.Any())
            {
                int total = HeartRateCollection.Count;
                int count = HeartRateCollection.Count(x => (x.Value ?? 0) >= min && (x.Value ?? 0) < max);
                return total > 0 ? $"{((double)count / total) * 100:F0}%" : "0%";
            }

            if (string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                var z = _currentSummary?.Summary?.Cardiovascular?.HeartRateZones;
                if (z != null)
                {
                    int r = z.Resting > 0 ? z.Resting : z.RestingMinutes;
                    int fb = z.FatBurn > 0 ? z.FatBurn : z.FatBurnMinutes;
                    int c = z.Cardio > 0 ? z.Cardio : z.CardioMinutes;
                    int p = z.Peak > 0 ? z.Peak : z.PeakMinutes;
                    int sum = r + fb + c + p;
                    if (sum > 0)
                    {
                        int bucket = min < 100 ? r : (min < 120 ? fb : (min < 150 ? c : p));
                        return $"{((double)bucket / sum) * 100:F0}%";
                    }
                }
            }

            return "--%";
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
            if (!string.IsNullOrEmpty(_selectedDeviceFilter))
            {
                return _metrics.FirstOrDefault(x => x.MatchesType(type) && x.Value > 0 &&
                    MatchesSelectedDevice(x.SourceDevice));
            }
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

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (this.Frame?.CanGoBack == true)
            {
                this.Frame.GoBack();
            }
            else
            {
                if (App.Current?.MainWindow is MainWindow mw)
                {
                    mw.NavigateToTab(1);
                }
                else
                {
                    this.Frame?.Navigate(typeof(MainPage));
                }
            }
        }

        private void PopOutButton_Click(object sender, RoutedEventArgs e)
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.OpenDetailWindow(typeof(HealthDetailPage));
                mw.NavigateToTab(1);
            }
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
