using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Daily.Services;
using Windows.UI;
using System.Linq;
using System.Collections.ObjectModel;
using Daily.Models;

namespace Daily_WinUI.Controls;

public class WidgetLogEntryViewModel
{
    public HabitLog Log { get; set; }
    public string Icon { get; set; }
    public string ColorHex { get; set; }
    public string Label { get; set; }
    public string Amount { get; set; }
    public string TimeText { get; set; }
}

public class WidgetChartData
{
    public string Label { get; set; }
    public double Value { get; set; }
    public double Goal { get; set; }
    public double BarHeight => Goal > 0 ? System.Math.Min(100, (Value / Goal) * 100) : (Value > 0 ? 100 : 8);
    public string DateLabel => Label;
    public string ColorHex { get; set; }
}

public sealed partial class HabitsWidgetControl : UserControl, INotifyPropertyChanged
{
    private readonly IHabitsService _habitsService;
    private readonly ISettingsService _settingsService;
    private readonly ISyncService _syncService;

    private double _goalValue;
    public double GoalValue
    {
        get => _goalValue;
        set { _goalValue = value; OnPropertyChanged(); }
    }

    private double _currentProgress;
    public double CurrentProgress
    {
        get => _currentProgress;
        set { _currentProgress = value; OnPropertyChanged(); }
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

    private SolidColorBrush _gaugeColor = new SolidColorBrush(Colors.DarkGreen);
    public SolidColorBrush GaugeColor
    {
        get => _gaugeColor;
        set { _gaugeColor = value; OnPropertyChanged(); }
    }

    private ObservableCollection<WidgetLogEntryViewModel> _logs = new();
    public ObservableCollection<WidgetLogEntryViewModel> Logs
    {
        get => _logs;
        set
        {
            _logs = value;
            OnPropertyChanged();
        }
    }

    private ObservableCollection<WidgetChartData> _history = new();
    public ObservableCollection<WidgetChartData> History
    {
        get => _history;
        set
        {
            _history = value;
            OnPropertyChanged();
        }
    }

    public bool HasLogs => _logs != null && _logs.Count > 0;
    public bool HasNoLogs => !HasLogs;

    public string CurrentViewLabel => HabitsFlipView?.SelectedIndex == 0 ? "Hydration" : "Smoking";

    public event EventHandler? WidgetTapped;

    public HabitsWidgetControl()
    {
        InitializeComponent();
        _habitsService = App.Current.Services.GetRequiredService<IHabitsService>();
        _settingsService = App.Current.Services.GetRequiredService<ISettingsService>();
        _syncService = App.Current.Services.GetRequiredService<ISyncService>();

        Loaded += HabitsWidgetControl_Loaded;
        Unloaded += HabitsWidgetControl_Unloaded;
        SizeChanged += HabitsWidgetControl_SizeChanged;
    }

    private void HabitsWidgetControl_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (e.NewSize.Width < 250)
        {
            if (e.NewSize.Height >= 250)
            {
                VisualStateManager.GoToState(this, "TallState", true);
            }
            else
            {
                VisualStateManager.GoToState(this, "SmallState", true);
            }
        }
        else if (e.NewSize.Width < 500)
        {
            VisualStateManager.GoToState(this, "NormalState", true);
        }
        else
        {
            VisualStateManager.GoToState(this, "LargeState", true);
        }
    }

    private async void HabitsWidgetControl_Loaded(object sender, RoutedEventArgs e)
    {
        _habitsService.OnHabitsUpdated += HabitsService_OnHabitsUpdated;
        await LoadDataAsync();
    }

    private void HabitsWidgetControl_Unloaded(object sender, RoutedEventArgs e)
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
            System.Diagnostics.Debug.WriteLine($"[HabitsWidgetControl] LoadData failed: {ex}");
        }
    }

    /// <summary>Called by the dashboard refresh button: pulls latest data from remote, then reloads the UI.</summary>
    public async Task RefreshAsync()
    {
        await _syncService.PullAsync();
        await LoadDataAsync();
    }

    private async Task LoadDataAsync()
    {
        if (_habitsService == null || _settingsService == null)
        {
            return;
        }

        var isWater = HabitsFlipView.SelectedIndex == 0;
        if (isWater)
        {
            var waterGoal = await _habitsService.GetGoalAsync("water");
            GoalValue = waterGoal?.TargetValue > 0 ? waterGoal.TargetValue : 2000;
            CurrentProgress = await _habitsService.GetDailyProgressAsync("water", DateTime.Now);
            GoalDisplay = $"/ {GoalValue:0}";

            var breakdown = await _habitsService.GetDailyBreakdownAsync("water", DateTime.Now);
            UpdateGaugeSegments(WaterRadialAxis, breakdown);

            MoneySavedDisplay = string.Empty;
        }
        else
        {
            GoalValue = _settingsService.Settings.SmokesBaselineDaily > 0 ? _settingsService.Settings.SmokesBaselineDaily : 20;
            CurrentProgress = await _habitsService.GetDailyProgressAsync("smokes", DateTime.Now);
            GoalDisplay = $"/ {GoalValue:0}";

            if (GoalValue > 0)
            {
                var ratio = CurrentProgress / GoalValue;
                GaugeColor = ratio < 0.5
                    ? new SolidColorBrush(Colors.DarkGreen)
                    : ratio < 0.9
                        ? new SolidColorBrush(Colors.DarkOrange)
                        : new SolidColorBrush(Colors.DarkRed);
            }
            else
            {
                GaugeColor = new SolidColorBrush(Colors.DarkRed);
            }

            SmokesRadialAxis.Ranges.Clear();
            var bgRange = new Syncfusion.UI.Xaml.Gauges.GaugeRange
            {
                StartValue = 0,
                EndValue = GoalValue > 0 ? GoalValue : 100,
                StartWidth = 0.265,
                EndWidth = 0.265,
                WidthUnit = Syncfusion.UI.Xaml.Gauges.SizeUnit.Factor,
                Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(26, 128, 128, 128))
            };
            SmokesRadialAxis.Ranges.Add(bgRange);

            var progressRange = new Syncfusion.UI.Xaml.Gauges.GaugeRange
            {
                StartValue = 0,
                EndValue = CurrentProgress,
                StartWidth = 0.265,
                EndWidth = 0.265,
                WidthUnit = Syncfusion.UI.Xaml.Gauges.SizeUnit.Factor,
                Background = GaugeColor
            };
            SmokesRadialAxis.Ranges.Add(progressRange);

            var quitDate = _settingsService.Settings.SmokesQuitDate;
            if (quitDate.HasValue)
            {
                var days = (DateTime.Today - quitDate.Value.Date).TotalDays + 1;
                if (days > 0)
                {
                    var (totalSmoked, _) = await _habitsService.GetSmokesFinancialsAsync(quitDate.Value);
                    var expected = days * GoalValue;
                    var avoided = Math.Max(0, expected - totalSmoked);
                    var costPerCig = _settingsService.Settings.SmokesPackCost / Math.Max(1, _settingsService.Settings.SmokesPackSize);
                    var saved = avoided * costPerCig;
                    var currency = string.IsNullOrEmpty(_settingsService.Settings.SmokesCurrency) ? "USD" : _settingsService.Settings.SmokesCurrency;
                    MoneySavedDisplay = $"{currency} {saved:F0}";
                }
                else
                {
                    MoneySavedDisplay = "-";
                }
            }
            else
            {
                MoneySavedDisplay = "Not started";
            }
        }

        // Fetch Logs and History
        string viewType = isWater ? "water" : "smokes";
        
        var todayLogs = await _habitsService.GetLogsAsync(viewType, DateTime.Today);
        var widgetLogs = new ObservableCollection<WidgetLogEntryViewModel>();
        foreach (var log in todayLogs.OrderByDescending(l => l.LoggedAt))
        {
            string drinkOrType = viewType;
            if (!string.IsNullOrWhiteSpace(log.Metadata))
            {
                try
                {
                    var doc = System.Text.Json.JsonDocument.Parse(log.Metadata);
                    if (doc.RootElement.TryGetProperty("drink", out var d))
                        drinkOrType = d.GetString()?.ToLowerInvariant() ?? viewType;
                    else if (doc.RootElement.TryGetProperty("type", out var t))
                        drinkOrType = t.GetString()?.ToLowerInvariant() ?? viewType;
                }
                catch { }
            }

            string colorHex = GetColorForDrinkOrSmoke(drinkOrType);
            
            // Icon glyphs (Tabler Icons)
            string icon = viewType == "smokes"
                ? drinkOrType switch
                {
                    var s when s.Contains("heated") => "\xec2c",  // heated
                    var s when s.Contains("rolled") => "\x100bd",  // rolled
                    var s when s.Contains("cigarillo") => "\xeed2",  // cigarillo
                    _ => "\xecc4"   // smoking icon (cigarette)
                }
                : drinkOrType switch
                {
                    var s when s.Contains("coffee") => "\ue96e",  // coffee
                    var s when s.Contains("tea") => "\uecfe",  // cup
                    var s when s.Contains("juice") => "\ued09",  // lemon
                    var s when s.Contains("beer") => "\uecf5",  // beer
                    var s when s.Contains("wine") => "\uecf6",  // bottle
                    _ => "\ueb7b"   // droplet
                };


            widgetLogs.Add(new WidgetLogEntryViewModel
            {
                Log = log,
                Icon = icon,
                ColorHex = colorHex,
                Label = System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(drinkOrType),
                Amount = isWater ? $"{(int)log.Value} ml" : $"{(int)log.Value} unit",
                TimeText = log.LoggedAt.ToLocalTime().ToString("HH:mm")
            });
        }
        Logs = widgetLogs;

        var historyData = await _habitsService.GetHistoryAsync(viewType, DateTime.Today.AddDays(-6), DateTime.Today);
        var widgetHistory = new ObservableCollection<WidgetChartData>();
        
        // Backfill 7 days
        for (int i = 6; i >= 0; i--)
        {
            var targetDate = DateTime.Today.AddDays(-i);
            var existing = historyData.FirstOrDefault(x => x.Date.Date == targetDate.Date);
            
            double val = existing != null ? existing.TotalValue : 0;
            
            widgetHistory.Add(new WidgetChartData
            {
                Label = targetDate.ToString("ddd"),
                Value = val,
                Goal = GoalValue,
                ColorHex = val >= GoalValue && GoalValue > 0 ? "#FF4CAF50" : (viewType == "smokes" ? "#FFF44336" : "#FF2196F3")
            });
        }
        History = widgetHistory;

        OnPropertyChanged(nameof(HasLogs));
        OnPropertyChanged(nameof(HasNoLogs));
        OnPropertyChanged(nameof(CurrentViewLabel));
    }

    private async void HabitsFlipView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_habitsService != null)
        {
            _habitsService.CurrentViewType = HabitsFlipView.SelectedIndex == 0 ? "water" : "smokes";
        }

        OnPropertyChanged(nameof(CurrentViewLabel));
        await LoadDataAsync();
    }

    private void UpdateGaugeSegments(Syncfusion.UI.Xaml.Gauges.RadialAxis axis, Dictionary<string, double> breakdown)
    {
        if (axis == null) return;

        axis.Ranges.Clear();

        var bgRange = new Syncfusion.UI.Xaml.Gauges.GaugeRange
        {
            StartValue = 0,
            EndValue = GoalValue > 0 ? GoalValue : 100,
            StartWidth = 0.265,
            EndWidth = 0.265,
            WidthUnit = Syncfusion.UI.Xaml.Gauges.SizeUnit.Factor,
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(26, 128, 128, 128))
        };
        axis.Ranges.Add(bgRange);

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

            axis.Ranges.Add(range);
            currentStart += amount;
        }
    }

    private string GetColorForDrinkOrSmoke(string item)
    {
        return item.ToLowerInvariant() switch
        {
            "water" => "#FF2196F3",
            "coffee" => "#FFF2994A",
            "tea" => "#FF27AE60",
            "juice" => "#FFE91E63",
            "cigarette" => "#FFF44336",
            "heated" => "#FF1976D2",
            "rolled" => "#FFEF6C00",
            "cigarillo" => "#FF8E24AA",
            _ => "#FF808080"
        };
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

    private void Header_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        HeaderGrid.Opacity = 0.8;
    }

    private void Header_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        HeaderGrid.Opacity = 1.0;
    }

    private void Header_Tapped(object sender, TappedRoutedEventArgs e)
    {
        e.Handled = true;
        WidgetTapped?.Invoke(this, EventArgs.Empty);
    }

    private void Widget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        e.Handled = true;
        WidgetTapped?.Invoke(this, EventArgs.Empty);
    }

    private void Prev_Click(object sender, RoutedEventArgs e)
    {
        if (HabitsFlipView.SelectedIndex > 0)
        {
            HabitsFlipView.SelectedIndex--;
        }
        else
        {
            HabitsFlipView.SelectedIndex = HabitsFlipView.Items.Count - 1;
        }
    }

    private void Next_Click(object sender, RoutedEventArgs e)
    {
        if (HabitsFlipView.SelectedIndex < HabitsFlipView.Items.Count - 1)
        {
            HabitsFlipView.SelectedIndex++;
        }
        else
        {
            HabitsFlipView.SelectedIndex = 0;
        }
    }

    private async void AddWater_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 250, "ml", DateTime.Now, "{\"drink\":\"Water\"}");
    }

    private async void AddJuice_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 250, "ml", DateTime.Now, "{\"drink\":\"Juice\"}");
    }

    private async void AddCoffee_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 150, "ml", DateTime.Now, "{\"drink\":\"Coffee\"}");
    }

    private async void AddTea_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 200, "ml", DateTime.Now, "{\"drink\":\"Tea\"}");
    }

    private async void AddCigarette_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"Cigarette\"}");
    }

    private async void AddHeated_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"Heated Tobacco\"}");
    }

    private async void AddRolled_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"Rolled\"}");
    }

    private async void AddCigarillo_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"Cigarillo\"}");
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
