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

namespace Daily_WinUI.Views;

public sealed partial class HabitsDetailPage : Page, INotifyPropertyChanged
{
    private readonly IHabitsService _habitsService;
    private readonly ISettingsService _settingsService;
    private string _currentType = "water";

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
        }
    }

    public double ProgressPercentage => GoalValue > 0 ? (CurrentProgress / GoalValue) * 100 : 0;
    public string ProgressPercentageText => $"{ProgressPercentage:F0}%";

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
        set { _todaysLogs = value; OnPropertyChanged(); }
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
        set { _smokesBaseline = value; OnPropertyChanged(); }
    }
    
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
        DispatcherQueue.TryEnqueue(async () =>
        {
            await LoadDataAsync();
        });
    }

    private void HabitTypeSelector_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox comboBox && comboBox.SelectedItem is ComboBoxItem selectedItem)
        {
            _currentType = selectedItem.Tag?.ToString() ?? "water";
            
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
        
        if (_currentType == "water")
        {
            var goal = await _habitsService.GetGoalAsync("water");
            GoalValue = goal.TargetValue > 0 ? goal.TargetValue : 2000;
            GoalDisplay = $"/ {GoalValue}";
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
        }

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

    private async void AddWaterSmall_Click(object sender, RoutedEventArgs e)
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

    private async void AddVape_Click(object sender, RoutedEventArgs e)
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
        if (sender is Button btn && btn.DataContext is HabitLog log)
        {
            await _habitsService.DeleteLogAsync(log.Id);
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

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
