using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services;
using Daily.Models;
using System.Linq;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI;
using Windows.UI;

namespace Daily_WinUI.Views;

public sealed partial class HabitsDetailPage : Page, INotifyPropertyChanged
{
    private readonly IHabitsService _habitsService;
    private readonly ISettingsService _settingsService;
    private string _currentType = "water";
    private bool _isReconciling;
    private bool _isSyncingPointer;  // blocks ValueChanged snap during programmatic set
    private double _pointerPrevValue = -1; // tracks last confirmed snap for direction detection

    private double _currentProgress;
    public double CurrentProgress
    {
        get => _currentProgress;
        set 
        { 
            _currentProgress = value; 
            OnPropertyChanged(); 
            OnPropertyChanged(nameof(ProgressPercentage));
            OnPropertyChanged(nameof(ProgressPercentageText));
            OnPropertyChanged(nameof(HeroMainText));
            WaterMlText = $"{value:0} ml";
        }
    }

    private double _goalValue = 2000;
    public double GoalValue
    {
        get => _goalValue;
        set 
        { 
            _goalValue = value; 
            OnPropertyChanged(); 
            OnPropertyChanged(nameof(ProgressPercentage));
            OnPropertyChanged(nameof(ProgressPercentageText));
            OnPropertyChanged(nameof(HeroMainText));
        }
    }

    public double ProgressPercentage => GoalValue > 0 ? (CurrentProgress / GoalValue) * 100 : 0;
    public string ProgressPercentageText => $"{ProgressPercentage:F0}%";
    public string HeroMainText => _currentType == "water" ? ProgressPercentageText : CurrentProgress.ToString();

    private string _waterMlText = "0 ml";
    public string WaterMlText
    {
        get => _waterMlText;
        private set { if (_waterMlText == value) return; _waterMlText = value; OnPropertyChanged(); }
    }

    // Last-log info used by the split drag handle
    private double  _lastLogValue = 150;
    private string  _lastLogMlText = "150 ml";
    private Microsoft.UI.Xaml.Media.Brush _lastLogColor =
        new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 94, 181, 255));

    public string LastLogMlText
    {
        get => _lastLogMlText;
        private set { if (_lastLogMlText == value) return; _lastLogMlText = value; OnPropertyChanged(); }
    }
    public Microsoft.UI.Xaml.Media.Brush LastLogColor
    {
        get => _lastLogColor;
        private set { _lastLogColor = value; OnPropertyChanged(); }
    }

    public Visibility WaterGaugeVisibility  => _currentType == "water"  ? Visibility.Visible : Visibility.Collapsed;
    public Visibility SmokesGaugeVisibility => Visibility.Collapsed;  // replaced by LungsControl
    public Visibility SmokesLungsVisibility => _currentType == "smokes" ? Visibility.Visible : Visibility.Collapsed;

    private DateTimeOffset? _viewDate = DateTimeOffset.Now;
    public DateTimeOffset? ViewDate
    {
        get => _viewDate;
        set 
        { 
            _viewDate = value; 
            OnPropertyChanged(); 
            OnPropertyChanged(nameof(ViewDateText));
            _ = LoadDataAsync();
        }
    }

    public string ViewDateText => ViewDate.GetValueOrDefault().Date == DateTime.Today ? "Today" : ViewDate.GetValueOrDefault().ToString("MMM dd, yyyy");

    private List<HabitLog> _todaysLogs = new();
    public List<HabitLog> TodaysLogs
    {
        get => _todaysLogs;
        set
        {
            _todaysLogs = value;
            OnPropertyChanged();
            BuildLogEntries();
        }
    }

    private List<LogEntryViewModel> _logEntries = new();
    public List<LogEntryViewModel> LogEntries
    {
        get => _logEntries;
        set { _logEntries = value; OnPropertyChanged(); }
    }

    private void BuildLogEntries()
    {
        var result = new List<LogEntryViewModel>();
        foreach (var log in _todaysLogs.OrderByDescending(l => l.LoggedAt))
        {
            string drinkOrType = "water";
            if (!string.IsNullOrWhiteSpace(log.Metadata))
            {
                try
                {
                    var doc = System.Text.Json.JsonDocument.Parse(log.Metadata);
                    if (doc.RootElement.TryGetProperty("drink", out var d))
                        drinkOrType = d.GetString()?.ToLowerInvariant() ?? "water";
                    else if (doc.RootElement.TryGetProperty("type", out var t))
                        drinkOrType = t.GetString()?.ToLowerInvariant() ?? "cigarette";
                }
                catch { }
            }
            else if (_currentType == "smokes")
            {
                drinkOrType = "cigarette";
            }

            string colorHex = GetColorForDrinkOrSmoke(drinkOrType.Contains("water") ? "water"
                            : drinkOrType.Contains("coffee") ? "coffee"
                            : drinkOrType.Contains("tea") ? "tea"
                            : drinkOrType.Contains("juice") ? "juice"
                            : drinkOrType.Contains("beer") ? "beer"
                            : drinkOrType.Contains("wine") ? "wine"
                            : drinkOrType.Contains("cigarillo") ? "cigarillo"
                            : drinkOrType.Contains("rolled") ? "rolled"
                            : drinkOrType.Contains("heated") ? "heated"
                            : drinkOrType.Contains("cigarette") ? "cigarette"
                            : _currentType == "smokes" ? "cigarette" : "water");

            // Icon glyphs (Tabler Icons)
            string icon = _currentType == "smokes"
                ? drinkOrType switch
                {
                    var s when s.Contains("heated")     => "\xec2c",  // heated
                    var s when s.Contains("rolled")     => "\x100bd",  // rolled
                    var s when s.Contains("cigarillo")  => "\xeed2",  // cigarillo
                    _                                   => "\xecc4"   // cigarette
                }
                : drinkOrType switch
                {
                    var s when s.Contains("coffee")     => "\xef0e",  // coffee
                    var s when s.Contains("tea")        => "\xf552",  // tea
                    var s when s.Contains("juice")      => "\xef28",  // juice
                    var s when s.Contains("beer")       => "\xefa1",  // beer
                    var s when s.Contains("wine")       => "\xeab7",  // wine
                    _                                   => "\xea97"   // water
                };

            string label = _currentType == "smokes"
                ? System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(drinkOrType)
                : System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(drinkOrType);

            string amount = _currentType == "smokes"
                ? $"{(int)log.Value} unit"
                : $"{(int)log.Value} ml";

            result.Add(new LogEntryViewModel
            {
                Log       = log,
                Icon      = icon,
                ColorHex  = colorHex,
                Label     = label,
                Amount    = amount,
                TimeText  = log.LoggedAt.ToLocalTime().ToString("HH:mm")
            });
        }
        LogEntries = result;
    }

    private Microsoft.UI.Xaml.Media.Brush _waterFillBrush =
        new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 41, 150, 204)); // #2996cc water blue
    public Microsoft.UI.Xaml.Media.Brush WaterFillBrush
    {
        get => _waterFillBrush;
        set { _waterFillBrush = value; OnPropertyChanged(); }
    }

    private string _goalDisplay = "";
    public string GoalDisplay
    {
        get => _goalDisplay;
        set { _goalDisplay = value; OnPropertyChanged(); }
    }

    private string _moneySavedDisplay = "";
    public string MoneySavedDisplay
    {
        get => _moneySavedDisplay;
        set { _moneySavedDisplay = value; OnPropertyChanged(); }
    }

    private string _daysSinceQuitDisplay = "";
    public string DaysSinceQuitDisplay
    {
        get => _daysSinceQuitDisplay;
        set { _daysSinceQuitDisplay = value; OnPropertyChanged(); }
    }

    private double _smokesBaseline;
    public double SmokesBaseline
    {
        get => _smokesBaseline;
        set { _smokesBaseline = value; OnPropertyChanged(); OnPropertyChanged(nameof(SmokesAxisInterval)); }
    }

    /// <summary>
    /// Ruler interval: 1 when baseline ≤ 10, 2 when ≤ 20, 5 when ≤ 50, else 10.
    /// </summary>
    public double SmokesAxisInterval => _smokesBaseline <= 10 ? 1
                                      : _smokesBaseline <= 20 ? 2
                                      : _smokesBaseline <= 50 ? 5
                                      : 10;

    // Smokes pointer state
    private bool   _isSyncingSmokesPointer;
    private double _smokesPointerPrevValue = -1;

    private string _smokesCountText = "0";
    public string SmokesCountText
    {
        get => _smokesCountText;
        private set { if (_smokesCountText == value) return; _smokesCountText = value; OnPropertyChanged(); }
    }

    // Last smokes log info (for the split handle bottom half)
    private double _lastSmokeLogValue  = 1;
    private string _lastSmokeTypeName  = "Cigarette";

    
    private double _smokesPackCost;
    public double SmokesPackCost
    {
        get => _smokesPackCost;
        set { _smokesPackCost = value; OnPropertyChanged(); }
    }
    
    private double _smokesPackSize;
    public double SmokesPackSize
    {
        get => _smokesPackSize;
        set { _smokesPackSize = value; OnPropertyChanged(); }
    }

    public class ChartData
    {
        public string DateLabel { get; set; } = "";
        public double Value { get; set; }
        public double BarHeight { get; set; } = 8;
    }

    public class HeatmapCell
    {
        public SolidColorBrush Color { get; set; } = new SolidColorBrush(Colors.Transparent);
        public string Tooltip { get; set; } = "";
    }

    private List<ChartData> _historyData = new();
    public List<ChartData> HistoryData
    {
        get => _historyData;
        set { _historyData = value; OnPropertyChanged(); }
    }

    private List<HeatmapCell> _heatmapData = new();
    public List<HeatmapCell> HeatmapData
    {
        get => _heatmapData;
        set { _heatmapData = value; OnPropertyChanged(); }
    }

    public HabitsDetailPage()
    {
        this.InitializeComponent();
        this.DataContext = this;
        _habitsService = App.Current.Services.GetRequiredService<IHabitsService>();
        _settingsService = App.Current.Services.GetRequiredService<ISettingsService>();
        
        Loaded += HabitsDetailPage_Loaded;
        Unloaded += HabitsDetailPage_Unloaded;
    }

    private async void HabitsDetailPage_Loaded(object sender, RoutedEventArgs e)
    {
        _habitsService.OnHabitsUpdated += HabitsService_OnHabitsUpdated;
        await LoadDataAsync();
    }

    private void HabitsDetailPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _habitsService.OnHabitsUpdated -= HabitsService_OnHabitsUpdated;
    }

    private void HabitsService_OnHabitsUpdated()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            _ = LoadDataSafeAsync();
        });
    }

    private async Task LoadDataSafeAsync()
    {
        try
        {
            await LoadDataAsync();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[HabitsDetailPage] LoadData failed: {ex}");
        }
    }

    private void HabitTypeSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox comboBox && comboBox.SelectedItem is ComboBoxItem selectedItem)
        {
            _currentType = selectedItem.Tag?.ToString() ?? "water";
            OnPropertyChanged(nameof(WaterGaugeVisibility));
            OnPropertyChanged(nameof(SmokesLungsVisibility));
            
            if (WaterSummaryPanel == null || SmokesSummaryPanel == null || SettingsGrid == null) return;
            
            if (_currentType == "water")
            {
                WaterSummaryPanel.Visibility = Visibility.Visible;
                SmokesSummaryPanel.Visibility = Visibility.Collapsed;
                SettingsGrid.Visibility = Visibility.Collapsed;
            }
            else
            {
                WaterSummaryPanel.Visibility = Visibility.Collapsed;
                SmokesSummaryPanel.Visibility = Visibility.Visible;
                SettingsGrid.Visibility = Visibility.Visible;
            }

            _ = LoadDataAsync();
        }
    }

    private void CalendarDatePicker_DateChanged(CalendarDatePicker sender, CalendarDatePickerDateChangedEventArgs args)
    {
        if (args.NewDate.HasValue)
        {
            ViewDate = args.NewDate.Value;
        }
        else
        {
            ViewDate = DateTimeOffset.Now;
        }
    }

    private async Task LoadDataAsync()
    {
        if (_habitsService == null || _settingsService == null) return;

        // Summary
        CurrentProgress = await _habitsService.GetDailyProgressAsync(_currentType, ViewDate.GetValueOrDefault().Date);
        TodaysLogs = await _habitsService.GetLogsAsync(_currentType, ViewDate.GetValueOrDefault().Date);
        
        var breakdown = await _habitsService.GetDailyBreakdownAsync(_currentType, ViewDate.GetValueOrDefault().Date);

        if (_currentType == "water")
        {
            var goal = await _habitsService.GetGoalAsync("water");
            GoalValue = goal.TargetValue > 0 ? goal.TargetValue : 2000;
            GoalDisplay = $"/ {GoalValue}";
            // Set pointer to real DB value — guard prevents ValueChanged from snapping it
            _isSyncingPointer = true;
            waterShapePointer.Value = CurrentProgress;
            _pointerPrevValue = CurrentProgress;
            WaterMlText = $"{CurrentProgress:0} ml";
            _isSyncingPointer = false;
            UpdateWaterFillColor(TodaysLogs);
            UpdateLastLogInfo(TodaysLogs);
        }
        else
        {
            SmokesBaseline = _settingsService.Settings.SmokesBaselineDaily > 0 ? _settingsService.Settings.SmokesBaselineDaily : 20;
            SmokesPackCost = _settingsService.Settings.SmokesPackCost;
            SmokesPackSize = _settingsService.Settings.SmokesPackSize > 0 ? _settingsService.Settings.SmokesPackSize : 20;
            
            GoalValue = SmokesBaseline;
            GoalDisplay = $"/ {GoalValue}";
            
            // Financials via server-side RPC
            double costPerCig = SmokesPackCost / Math.Max(1.0, SmokesPackSize);
            var currency = string.IsNullOrEmpty(_settingsService.Settings.SmokesCurrency) ? "USD" : _settingsService.Settings.SmokesCurrency;
            
            var quitDateNullable = _settingsService.Settings.SmokesQuitDate;
            if (quitDateNullable.HasValue)
            {
                var quitDate = quitDateNullable.Value;
                var days = (DateTime.Today - quitDate.Date).TotalDays;
                if (days < 0) days = 0;
                DaysSinceQuitDisplay = $"{days} days since quit date";
                
                // Use server-side financial aggregation
                var (totalSmoked, daysTracked) = await _habitsService.GetSmokesFinancialsAsync(quitDate);
                var totalExpected = (days + 1) * SmokesBaseline;
                var avoided = Math.Max(0, totalExpected - totalSmoked);
                var totalSaved = avoided * costPerCig;
                MoneySavedDisplay = $"Total Saved: {currency} {totalSaved:F0}";
            }
            else
            {
                DaysSinceQuitDisplay = "Quit date not set";
                double savedToday = Math.Max(0, SmokesBaseline - CurrentProgress) * costPerCig;
                MoneySavedDisplay = $"Saved Today: {currency} {savedToday:0.00}";
            }

            // Update lungs fill: fraction = cigarettes smoked / baseline (capped at 1)
            double lungsFraction = SmokesBaseline > 0 ? Math.Clamp(CurrentProgress / SmokesBaseline, 0.0, 1.0) : 0.0;
            SmokesLungsControl.FillFraction = lungsFraction;

            // Sync smokes pointer to real DB value
            _isSyncingSmokesPointer = true;
            smokesShapePointer.Value = CurrentProgress;
            _smokesPointerPrevValue  = CurrentProgress;
            SmokesCountText = $"{(int)CurrentProgress}";
            _isSyncingSmokesPointer = false;

            UpdateSmokesLastLogInfo(TodaysLogs);
        }

        UpdateHeroGauge(breakdown);

        // History Chart (Last 7 Days) - via server-side RPC
        var endDate = DateTime.Today;
        var startDate = endDate.AddDays(-6);
        var summaries = await _habitsService.GetConsistencyAsync(_currentType, startDate, endDate);
        
        var newChart = new List<ChartData>();
        for (int i = 0; i < 7; i++)
        {
            var date = startDate.AddDays(i);
            var sum = summaries.FirstOrDefault(s => s.Date.Date == date);
            newChart.Add(new ChartData 
            { 
                DateLabel = date.ToString("ddd"), 
                Value = sum != null ? sum.TotalValue : 0 
            });
        }

        var maxChartValue = Math.Max(1.0, newChart.Max(item => item.Value));
        foreach (var item in newChart)
        {
            item.BarHeight = item.Value <= 0 ? 8 : 24 + ((item.Value / maxChartValue) * 140);
        }

        HistoryData = newChart;

        // Heatmap (Last 16 weeks ~ 112 days) - via server-side RPC
        var heatStart = endDate.AddDays(-111);
        var heatSummaries = await _habitsService.GetConsistencyAsync(_currentType, heatStart, endDate);
        
        var newHeat = new List<HeatmapCell>();
        double maxGoal = _currentType == "water" ? 2000 : 20; // fallback goals
        if (_currentType == "water")
        {
            var g = await _habitsService.GetGoalAsync("water");
            if (g.TargetValue > 0) maxGoal = g.TargetValue;
        }
        else
        {
            if (_settingsService.Settings.SmokesBaselineDaily > 0) maxGoal = _settingsService.Settings.SmokesBaselineDaily;
        }

        for (int i = 0; i < 112; i++)
        {
            var date = heatStart.AddDays(i);
            var sum = heatSummaries.FirstOrDefault(s => s.Date.Date == date);
            double val = sum != null ? sum.TotalValue : 0;
            
            SolidColorBrush brush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 30, 30, 30)); // Empty dark gray
            if (val > 0)
            {
                double ratio = val / maxGoal;
                if (_currentType == "water")
                {
                    // Water: More is better, turns blue
                    byte intensity = (byte)(Math.Min(1.0, ratio) * 200 + 55);
                    brush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 100, intensity));
                }
                else
                {
                    // Smokes: More is worse, turns red. Less is green.
                    if (ratio < 0.5) brush = new SolidColorBrush(Microsoft.UI.Colors.DarkGreen);
                    else if (ratio < 0.9) brush = new SolidColorBrush(Microsoft.UI.Colors.DarkOrange);
                    else brush = new SolidColorBrush(Microsoft.UI.Colors.DarkRed);
                }
            }

            newHeat.Add(new HeatmapCell 
            { 
                Color = brush, 
                Tooltip = $"{date:MMM dd}: {val}" 
            });
        }
        HeatmapData = newHeat;
    }

    private void UpdateHeroGauge(Dictionary<string, double> breakdown)
    {
        if (HeroRadialAxis == null) return;

        HeroRadialAxis.Ranges.Clear();

        // Always add background range first
        var bgRange = new Syncfusion.UI.Xaml.Gauges.GaugeRange
        {
            StartValue = 0,
            EndValue = GoalValue > 0 ? GoalValue : 100,
            StartWidth = 0.265,
            EndWidth = 0.265,
            WidthUnit = Syncfusion.UI.Xaml.Gauges.SizeUnit.Factor,
            
            
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(26, 128, 128, 128)) // semi-transparent gray
        };
        HeroRadialAxis.Ranges.Add(bgRange);

        if (_currentType == "smokes")
        {
            var brush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Colors.DarkRed);
            if (GoalValue > 0)
            {
                var ratio = CurrentProgress / GoalValue;
                brush = ratio < 0.265 ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Colors.DarkGreen)
                      : ratio < 0.5 ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Colors.DarkOrange)
                      : new Microsoft.UI.Xaml.Media.SolidColorBrush(Colors.DarkRed);
            }
            
            var progressRange = new Syncfusion.UI.Xaml.Gauges.GaugeRange
            {
                StartValue = 0,
                EndValue = CurrentProgress,
                StartWidth = 0.265,
                EndWidth = 0.265,
                WidthUnit = Syncfusion.UI.Xaml.Gauges.SizeUnit.Factor,
                
                
                Background = brush
            };
            HeroRadialAxis.Ranges.Add(progressRange);
        }
        else
        {
            double currentStart = 0;
            foreach (var kvp in breakdown)
            {
                double amount = kvp.Value;
                if (amount <= 0) continue;

                string colorHex = GetColorForDrinkOrSmoke(kvp.Key);
                var color = GetColorFromHex(colorHex);

                var range = new Syncfusion.UI.Xaml.Gauges.GaugeRange
                {
                    StartValue = currentStart,
                    EndValue = currentStart + amount,
                    StartWidth = 0.265,
                    EndWidth = 0.265,
                    WidthUnit = Syncfusion.UI.Xaml.Gauges.SizeUnit.Factor,
                    
                    
                    Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(color)
                };

                HeroRadialAxis.Ranges.Add(range);
                currentStart += amount;
            }
        }
    }

    private string GetColorForDrinkOrSmoke(string item)
    {
        return item.ToLowerInvariant() switch
        {
            "water"     => "#FF2996CC",
            "coffee"    => "#FFF2994A",
            "tea"       => "#FF27AE60",
            "juice"     => "#FFE91E63",
            "beer"      => "#FFFFA000",
            "wine"      => "#FF9C27B0",
            "cigarette" => "#FFF44336",
            "heated"    => "#FF1976D2",
            "rolled"    => "#FFEF6C00",
            "cigarillo" => "#FF8E24AA",
            _           => "#FF808080"
        };
    }

    private string GetWaterColorForAmount(double amountMl)
    {
        // 150 ml -> clearly light blue, 300 ml+ -> clearly darker blue
        double ratio = Math.Clamp((amountMl - 150.0) / 150.0, 0.0, 1.0);

        byte startR = 94;
        byte startG = 181;
        byte startB = 255;

        byte endR = 36;
        byte endG = 122;
        byte endB = 212;

        byte r = (byte)Math.Round(startR + ((endR - startR) * ratio));
        byte g = (byte)Math.Round(startG + ((endG - startG) * ratio));
        byte b = (byte)Math.Round(startB + ((endB - startB) * ratio));

        return $"#FF{r:X2}{g:X2}{b:X2}";
    }

    private string GetHydrationColorForDrink(string drink, double amountMl)
    {
        var normalized = (drink ?? string.Empty).Trim().ToLowerInvariant();

        if (normalized.Contains("water")) return GetWaterColorForAmount(amountMl);
        if (normalized.Contains("coffee")) return GetColorForDrinkOrSmoke("coffee");
        if (normalized.Contains("tea")) return GetColorForDrinkOrSmoke("tea");
        if (normalized.Contains("juice")) return GetColorForDrinkOrSmoke("juice");
        if (normalized.Contains("beer")) return GetColorForDrinkOrSmoke("beer");
        if (normalized.Contains("wine")) return GetColorForDrinkOrSmoke("wine");

        // Unknown/legacy drinks keep the darker hydration blue tone.
        return GetWaterColorForAmount(300);
    }

    private Windows.UI.Color GetColorFromHex(string hex)
    {
        hex = hex.Replace("#", "");
        byte a = 255;
        byte r = 0, g = 0, b = 0;
        if (hex.Length == 8)
        {
            a = byte.Parse(hex.Substring(0, 2), System.Globalization.NumberStyles.HexNumber);
            r = byte.Parse(hex.Substring(2, 2), System.Globalization.NumberStyles.HexNumber);
            g = byte.Parse(hex.Substring(4, 2), System.Globalization.NumberStyles.HexNumber);
            b = byte.Parse(hex.Substring(6, 2), System.Globalization.NumberStyles.HexNumber);
        }
        else if (hex.Length == 6)
        {
            r = byte.Parse(hex.Substring(0, 2), System.Globalization.NumberStyles.HexNumber);
            g = byte.Parse(hex.Substring(2, 2), System.Globalization.NumberStyles.HexNumber);
            b = byte.Parse(hex.Substring(4, 2), System.Globalization.NumberStyles.HexNumber);
        }
        return Windows.UI.Color.FromArgb(a, r, g, b);
    }

    private async void AddWater_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 150, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Water\",\"size\":\"Small\"}");
    }

    private async void AddWaterLarge_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 300, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Water\",\"size\":\"Large\"}");
    }

    private async void AddCoffee_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 150, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Coffee\"}");
    }

    private async void AddTea_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 200, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Tea\"}");
    }

    private async void AddJuice_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 250, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Juice\"}");
    }

    private async void AddBeer_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 330, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Beer\"}");
    }

    private async void AddWine_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 150, "ml", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Wine\"}");
    }

    private async void AddCigarette_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"type\":\"Cigarette\"}");
    }

    private async void AddHeated_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"type\":\"Heated Tobacco\"}");
    }

    private async void AddRolled_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"type\":\"Rolled\"}");
    }

    private async void AddCigarillo_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", ViewDate.GetValueOrDefault().Date.Add(DateTime.Now.TimeOfDay), "{\"type\":\"Cigarillo\"}");
    }

    private async void DeleteLog_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.DataContext is LogEntryViewModel vm)
        {
            await _habitsService.DeleteLogAsync(vm.Log.Id);
            await LoadDataAsync();
        }
    }

    private async void SaveSettings_Click(object sender, RoutedEventArgs e)
    {
        _settingsService.Settings.SmokesBaselineDaily = (int)SmokesBaseline;
        _settingsService.Settings.SmokesPackCost = SmokesPackCost;
        _settingsService.Settings.SmokesPackSize = (int)SmokesPackSize;
        await _settingsService.SaveSettingsAsync();
        
        // Reload to update financials
        await LoadDataAsync();
    }

    private void WaterShapePointer_ValueChanged(object sender, Syncfusion.UI.Xaml.Gauges.ValueChangedEventArgs e)
    {
        if (_isReconciling || _isSyncingPointer) return;
        if (sender is not Syncfusion.UI.Xaml.Gauges.LinearShapePointer ptr) return;

        double snapped = SnapPointerValue(ptr.Value);
        snapped = Math.Clamp(snapped, 0, GoalValue);
        ptr.Value = snapped;
        WaterMlText = $"{snapped:0} ml";
    }

    private async void WaterShapePointer_ValueChangeCompleted(object sender, Syncfusion.UI.Xaml.Gauges.ValueChangedEventArgs e)
    {
        if (_isReconciling || _isSyncingPointer) return;
        if (sender is not Syncfusion.UI.Xaml.Gauges.LinearShapePointer ptr) return;

        double snapped = SnapPointerValue(ptr.Value);
        snapped = Math.Clamp(snapped, 0, GoalValue);
        ptr.Value = snapped;
        _pointerPrevValue = snapped;
        await ReconcileWaterToTargetAsync(snapped);
    }

    /// <summary>
    /// Determines the correct snapped value based on drag direction.
    /// Up  → nearest 150 ml step above previous value.
    /// Down → previous value minus the exact last-log amount.
    /// </summary>
    private double SnapPointerValue(double rawValue)
    {
        double prev = _pointerPrevValue >= 0 ? _pointerPrevValue : CurrentProgress;

        if (rawValue >= prev)
        {
            // Dragging up — add 150 ml step
            return Math.Round(rawValue / 150.0) * 150.0;
        }
        else
        {
            // Dragging down — remove exactly the last log's amount
            double step = _lastLogValue > 0 ? _lastLogValue : 150;
            return Math.Max(0, prev - step);
        }
    }

    private async Task ReconcileWaterToTargetAsync(double targetMl)
    {
        _isReconciling = true;
        try
        {
            var date = ViewDate.GetValueOrDefault().Date;
            double currentTotal = await _habitsService.GetDailyProgressAsync("water", date);
            double diff = targetMl - currentTotal;

            // Nothing meaningful to change
            if (Math.Abs(diff) < 1)
            {
                await LoadDataAsync();
                return;
            }

            if (diff > 0)
            {
                // Add exactly as many 150 ml logs as needed (round up)
                int stepsToAdd = (int)Math.Ceiling(diff / 150.0);
                for (int i = 0; i < stepsToAdd; i++)
                    await _habitsService.AddLogAsync("water", 150, "ml",
                        date.Add(DateTime.Now.TimeOfDay), "{\"drink\":\"Water\",\"source\":\"gauge\"}");
            }
            else
            {
                // Remove enough logs (newest first) to reach target
                double toRemove = -diff;
                var logs = await _habitsService.GetLogsAsync("water", date);
                var sorted = logs.OrderByDescending(l => l.LoggedAt).ToList();

                foreach (var log in sorted)
                {
                    if (toRemove < 1) break;

                    if (log.Value <= toRemove)
                    {
                        await _habitsService.DeleteLogAsync(log.Id);
                        toRemove -= log.Value;
                    }
                    else
                    {
                        // Split: keep the remainder, delete the original
                        double remainder = log.Value - toRemove;
                        await _habitsService.DeleteLogAsync(log.Id);
                        if (remainder >= 1)
                            await _habitsService.AddLogAsync("water", remainder, "ml",
                                log.LoggedAt, log.Metadata);
                        toRemove = 0;
                    }
                }
            }

            await LoadDataAsync();
        }
        finally
        {
            _isReconciling = false;
        }
    }

    // ── Smokes pointer handlers ──────────────────────────────────────────────────

    private void SmokesShapePointer_ValueChanged(object sender, Syncfusion.UI.Xaml.Gauges.ValueChangedEventArgs e)
    {
        if (_isReconciling || _isSyncingSmokesPointer) return;
        if (sender is not Syncfusion.UI.Xaml.Gauges.LinearShapePointer ptr) return;

        double snapped = SnapSmokesPointerValue(ptr.Value);
        snapped = Math.Clamp(snapped, 0, SmokesBaseline);
        ptr.Value = snapped;
        SmokesCountText = $"{(int)snapped}";
    }

    private async void SmokesShapePointer_ValueChangeCompleted(object sender, Syncfusion.UI.Xaml.Gauges.ValueChangedEventArgs e)
    {
        if (_isReconciling || _isSyncingSmokesPointer) return;
        if (sender is not Syncfusion.UI.Xaml.Gauges.LinearShapePointer ptr) return;

        double snapped = SnapSmokesPointerValue(ptr.Value);
        snapped = Math.Clamp(snapped, 0, SmokesBaseline);
        ptr.Value = snapped;
        _smokesPointerPrevValue = snapped;
        await ReconcileSmokesToTargetAsync(snapped);
    }

    /// <summary>
    /// Up → next integer step (+1); Down → prev value minus last-log amount.
    /// </summary>
    private double SnapSmokesPointerValue(double rawValue)
    {
        double prev = _smokesPointerPrevValue >= 0 ? _smokesPointerPrevValue : CurrentProgress;

        if (rawValue >= prev)
            return Math.Round(rawValue);   // snap to nearest whole number (up)
        else
            return Math.Max(0, prev - _lastSmokeLogValue);  // remove last-log amount
    }

    private async Task ReconcileSmokesToTargetAsync(double targetCount)
    {
        _isReconciling = true;
        try
        {
            var date = ViewDate.GetValueOrDefault().Date;
            double current = await _habitsService.GetDailyProgressAsync("smokes", date);
            double diff = targetCount - current;

            if (Math.Abs(diff) < 0.5)
            {
                await LoadDataAsync();
                return;
            }

            if (diff > 0)
            {
                // The handle top always reads "1 Cig" — always log a Cigarette on upward drag.
                int toAdd = (int)Math.Round(diff);
                const string meta = "{\"type\":\"Cigarette\"}";
                for (int i = 0; i < toAdd; i++)
                    await _habitsService.AddLogAsync("smokes", 1, "unit",
                        date.Add(DateTime.Now.TimeOfDay), meta);
            }
            else
            {
                // Delete newest logs until target is reached
                double toRemove = -diff;
                var logs   = await _habitsService.GetLogsAsync("smokes", date);
                var sorted = logs.OrderByDescending(l => l.LoggedAt).ToList();

                foreach (var log in sorted)
                {
                    if (toRemove < 0.5) break;
                    await _habitsService.DeleteLogAsync(log.Id);
                    toRemove -= log.Value;
                }
            }

            await LoadDataAsync();
        }
        finally
        {
            _isReconciling = false;
        }
    }

    private void UpdateLastLogInfo(List<HabitLog> logs)
    {
        var last = logs.OrderByDescending(l => l.LoggedAt).FirstOrDefault();
        if (last == null)
        {
            // No logs today — show neutral defaults
            _lastLogValue   = 150;
            LastLogMlText   = "150 ml";
            LastLogColor    = new Microsoft.UI.Xaml.Media.SolidColorBrush(
                                  GetColorFromHex("#FF808080"));
            ApplyLastLogColorBrush("#FF808080", "150 ml");
            return;
        }

        _lastLogValue = last.Value;
        LastLogMlText = $"{(int)last.Value} ml";

        // Determine colour from metadata drink name, falling back to plain water
        string drinkName = "water";
        if (!string.IsNullOrWhiteSpace(last.Metadata))
        {
            try
            {
                var doc = System.Text.Json.JsonDocument.Parse(last.Metadata);
                if (doc.RootElement.TryGetProperty("drink", out var d))
                    drinkName = d.GetString() ?? "water";
            }
            catch { /* malformed metadata → keep "water" */ }
        }

        string colorHex = GetHydrationColorForDrink(drinkName, last.Value);
        LastLogColor = new Microsoft.UI.Xaml.Media.SolidColorBrush(GetColorFromHex(colorHex));
        ApplyLastLogColorBrush(colorHex, LastLogMlText);
    }

    /// <summary>
    /// Updates the mutable resource brush so the DataTemplate's bottom half refreshes,
    /// and walks the pointer shape visual tree to update the ml label text.
    /// </summary>
    private void ApplyLastLogColorBrush(string colorHex, string mlText)
    {
        var color = GetColorFromHex(colorHex);

        // Update the named resource brush — existing template instances observe this change
        if (Resources.TryGetValue("LastLogColorBrush", out var obj) && obj is Microsoft.UI.Xaml.Media.SolidColorBrush brush)
        {
            brush.Color = color;
        }

        // Walk the visual tree of the LinearShapePointer to find and update the label
        UpdateLastLogLabelInTree(waterShapePointer, mlText);
    }

    private static void UpdateLastLogLabelInTree(DependencyObject root, string mlText)
    {
        if (root == null) return;
        int count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i);
            if (child is TextBlock tb && tb.Name == "LastLogMlLabel")
            {
                tb.Text = mlText;
                return;
            }
            UpdateLastLogLabelInTree(child, mlText);
        }
    }

    private void UpdateSmokesLastLogInfo(List<HabitLog> logs)
    {
        var last = logs.OrderByDescending(l => l.LoggedAt).FirstOrDefault();
        if (last == null)
        {
            _lastSmokeLogValue = 1;
            _lastSmokeTypeName = "Cigarette";
            ApplySmokesLastLogBrush(GetColorForDrinkOrSmoke("cigarette"), "Cig");
            return;
        }

        _lastSmokeLogValue = last.Value > 0 ? last.Value : 1;

        // Parse type from metadata  { "type": "Cigarette" }
        _lastSmokeTypeName = "Cigarette";
        if (!string.IsNullOrWhiteSpace(last.Metadata))
        {
            try
            {
                var doc = System.Text.Json.JsonDocument.Parse(last.Metadata);
                if (doc.RootElement.TryGetProperty("type", out var t))
                    _lastSmokeTypeName = t.GetString() ?? "Cigarette";
            }
            catch { /* keep default */ }
        }

        // Map type name to colour key used in GetColorForDrinkOrSmoke
        string colorKey = _lastSmokeTypeName.ToLowerInvariant() switch
        {
            var s when s.Contains("heat")                           => "heated",
            var s when s.Contains("roll")                           => "rolled",
            var s when s.Contains("cigarillo")                      => "cigarillo",
            _                                                       => "cigarette"
        };

        // Short label for the bottom half of the handle
        string shortLabel = _lastSmokeTypeName.Length > 8
            ? _lastSmokeTypeName[..7] + "…"
            : _lastSmokeTypeName;

        ApplySmokesLastLogBrush(GetColorForDrinkOrSmoke(colorKey), shortLabel);
    }

    private void ApplySmokesLastLogBrush(string colorHex, string label)
    {
        var color = GetColorFromHex(colorHex);

        if (Resources.TryGetValue("SmokesLastLogColorBrush", out var obj)
            && obj is Microsoft.UI.Xaml.Media.SolidColorBrush brush)
        {
            brush.Color = color;
        }

        UpdateSmokesLabelInTree(smokesShapePointer, label);
    }

    private static void UpdateSmokesLabelInTree(DependencyObject root, string label)
    {
        if (root == null) return;
        int count = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < count; i++)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(root, i);
            if (child is TextBlock tb && tb.Name == "SmokesLastLogLabel")
            {
                tb.Text = label;
                return;
            }
            UpdateSmokesLabelInTree(child, label);
        }
    }

    private void UpdateWaterFillColor(List<HabitLog> logs)
    {
        if (WaterFillControl == null) return;

        var selectedDate = ViewDate.GetValueOrDefault().Date;
        var dayLogs = logs.Where(l => l.LoggedAt.Date == selectedDate).ToList();

        double totalMl = dayLogs.Sum(l => l.Value);
        if (totalMl <= 0)
        {
            WaterFillControl.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(GetColorFromHex(GetWaterColorForAmount(150)));
            return;
        }

        // Build segments from selected-day history in chronological order:
        // oldest log = bottom of glass, newest = top.
        var segments = new List<(string ColorHex, double Ml)>();
        foreach (var log in dayLogs.OrderBy(l => l.LoggedAt))
        {
            string drink = "Water";
            if (!string.IsNullOrEmpty(log.Metadata))
            {
                try
                {
                    var doc = System.Text.Json.JsonDocument.Parse(log.Metadata);
                    if (doc.RootElement.TryGetProperty("drink", out var d))
                        drink = d.GetString() ?? "Water";
                }
                catch { }
            }

            string colorHex = GetHydrationColorForDrink(drink, log.Value);

            // Merge consecutive same-color logs into one segment
            if (segments.Count > 0 && segments[^1].ColorHex.Equals(colorHex, StringComparison.OrdinalIgnoreCase))
                segments[^1] = (colorHex, segments[^1].Ml + log.Value);
            else
                segments.Add((colorHex, log.Value));
        }

        // Single segment — use a plain solid brush
        if (segments.Count == 1)
        {
            WaterFillControl.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(
                GetColorFromHex(segments[0].ColorHex));
            return;
        }

        // Multiple types — build a hard-stop gradient:
        // StartPoint (0.5,1) = bottom of element = glass bottom = oldest drink (offset 0)
        // EndPoint   (0.5,0) = top    of element = water surface = newest drink (offset 1)
        var gradient = new Microsoft.UI.Xaml.Media.LinearGradientBrush
        {
            StartPoint = new Windows.Foundation.Point(0.5, 1),
            EndPoint   = new Windows.Foundation.Point(0.5, 0)
        };

        double cursor = 0.0;
        for (int i = 0; i < segments.Count; i++)
        {
            var (colorHex, ml) = segments[i];
            double fraction = ml / totalMl;
            var color = GetColorFromHex(colorHex);
            gradient.GradientStops.Add(new Microsoft.UI.Xaml.Media.GradientStop { Color = color, Offset = cursor });

            double next = i == segments.Count - 1
                ? 1.0
                : Math.Min(1.0, cursor + fraction);

            gradient.GradientStops.Add(new Microsoft.UI.Xaml.Media.GradientStop { Color = color, Offset = next });
            cursor = next;
        }

        WaterFillControl.Background = gradient;
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

/// <summary>Display model for a single habit log row.</summary>
public sealed class LogEntryViewModel
{
    public HabitLog Log      { get; set; } = null!;
    public string   Icon     { get; set; } = "\ueb7b";
    public string   ColorHex { get; set; } = "#FF808080";
    public string   Label    { get; set; } = "";
    public string   Amount   { get; set; } = "";
    public string   TimeText { get; set; } = "";

    /// <summary>Parsed accent color as a WinUI brush for direct binding.</summary>
    public Microsoft.UI.Xaml.Media.SolidColorBrush AccentBrush =>
        new(Windows.UI.Color.FromArgb(
            Convert.ToByte(ColorHex.Length >= 9 ? ColorHex.Substring(1, 2) : "FF", 16),
            Convert.ToByte(ColorHex.Length >= 9 ? ColorHex.Substring(3, 2) : ColorHex.Substring(1, 2), 16),
            Convert.ToByte(ColorHex.Length >= 9 ? ColorHex.Substring(5, 2) : ColorHex.Substring(3, 2), 16),
            Convert.ToByte(ColorHex.Length >= 9 ? ColorHex.Substring(7, 2) : ColorHex.Substring(5, 2), 16)));

    /// <summary>Faded version (30% alpha) for the left pill background.</summary>
    public Microsoft.UI.Xaml.Media.SolidColorBrush PillBrush
    {
        get
        {
            var c = AccentBrush.Color;
            return new Microsoft.UI.Xaml.Media.SolidColorBrush(
                Windows.UI.Color.FromArgb(60, c.R, c.G, c.B));
        }
    }
}
