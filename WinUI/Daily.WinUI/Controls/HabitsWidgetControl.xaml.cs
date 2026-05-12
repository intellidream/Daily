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

namespace Daily_WinUI.Controls;

public sealed partial class HabitsWidgetControl : UserControl, INotifyPropertyChanged
{
    private readonly IHabitsService _habitsService;
    private readonly ISettingsService _settingsService;

    private double _currentProgress;
    public double CurrentProgress
    {
        get => _currentProgress;
        set
        {
            if (Math.Abs(_currentProgress - value) < 0.01) return;
            _currentProgress = value;
            OnPropertyChanged();
        }
    }

    private double _goalValue = 2000;
    public double GoalValue
    {
        get => _goalValue;
        set
        {
            if (Math.Abs(_goalValue - value) < 0.01) return;
            _goalValue = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(GoalDisplay));
        }
    }

    private string _goalDisplay = "";
    public string GoalDisplay
    {
        get => _goalDisplay;
        set
        {
            if (_goalDisplay == value) return;
            _goalDisplay = value;
            OnPropertyChanged();
        }
    }

    private string _moneySavedDisplay = "";
    public string MoneySavedDisplay
    {
        get => _moneySavedDisplay;
        set
        {
            if (_moneySavedDisplay == value) return;
            _moneySavedDisplay = value;
            OnPropertyChanged();
        }
    }

    private SolidColorBrush _gaugeColor = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 2, 136, 209));
    public SolidColorBrush GaugeColor
    {
        get => _gaugeColor;
        set
        {
            if (ReferenceEquals(_gaugeColor, value)) return;
            _gaugeColor = value;
            OnPropertyChanged();
        }
    }

    private double _waterAmount;
    public double WaterAmount
    {
        get => _waterAmount;
        set
        {
            if (Math.Abs(_waterAmount - value) < 0.01) return;
            _waterAmount = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(WaterAndCoffeeAmount));
            OnPropertyChanged(nameof(TotalDrinkAmount));
        }
    }

    private double _coffeeAmount;
    public double CoffeeAmount
    {
        get => _coffeeAmount;
        set
        {
            if (Math.Abs(_coffeeAmount - value) < 0.01) return;
            _coffeeAmount = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(WaterAndCoffeeAmount));
            OnPropertyChanged(nameof(TotalDrinkAmount));
        }
    }

    private double _teaAmount;
    public double TeaAmount
    {
        get => _teaAmount;
        set
        {
            if (Math.Abs(_teaAmount - value) < 0.01) return;
            _teaAmount = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(TotalDrinkAmount));
        }
    }

    public double WaterAndCoffeeAmount => WaterAmount + CoffeeAmount;
    public double TotalDrinkAmount => WaterAmount + CoffeeAmount + TeaAmount;
    public string CurrentViewLabel => HabitsFlipView?.SelectedIndex == 0 ? "Hydration" : "Smoking";

    public event EventHandler? WidgetTapped;

    public HabitsWidgetControl()
    {
        InitializeComponent();
        _habitsService = App.Current.Services.GetRequiredService<IHabitsService>();
        _settingsService = App.Current.Services.GetRequiredService<ISettingsService>();

        Loaded += HabitsWidgetControl_Loaded;
        Unloaded += HabitsWidgetControl_Unloaded;
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
        DispatcherQueue.TryEnqueue(async () => await LoadDataAsync());
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
            GaugeColor = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 2, 136, 209));

            var breakdown = await _habitsService.GetDailyBreakdownAsync("water", DateTime.Now);
            WaterAmount = GetBreakdownValue(breakdown, "water", "Water");
            CoffeeAmount = GetBreakdownValue(breakdown, "coffee", "Coffee");
            TeaAmount = GetBreakdownValue(breakdown, "tea", "Tea");

            if (WaterAndCoffeeAmount + TeaAmount <= 0)
            {
                WaterAmount = CurrentProgress;
                CoffeeAmount = 0;
                TeaAmount = 0;
            }

            MoneySavedDisplay = string.Empty;
        }
        else
        {
            WaterAmount = 0;
            CoffeeAmount = 0;
            TeaAmount = 0;

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

        OnPropertyChanged(nameof(CurrentViewLabel));
    }

    private static double GetBreakdownValue(IReadOnlyDictionary<string, double>? breakdown, params string[] keys)
    {
        if (breakdown is null || breakdown.Count == 0)
        {
            return 0;
        }

        foreach (var pair in breakdown)
        {
            foreach (var key in keys)
            {
                if (string.Equals(pair.Key, key, StringComparison.OrdinalIgnoreCase))
                {
                    return pair.Value;
                }
            }
        }

        return 0;
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

    private async void AddWaterSmall_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 150, "ml", DateTime.Now, "{\"drink\":\"Water\",\"size\":\"Small\"}");
    }

    private async void AddWaterLarge_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 300, "ml", DateTime.Now, "{\"drink\":\"Water\",\"size\":\"Large\"}");
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

    private async void AddVape_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"Vape\"}");
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
