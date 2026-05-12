using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.Extensions.DependencyInjection;
using Daily.Services;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI;

namespace Daily_WinUI.Controls;

public sealed partial class HabitsWidgetControl : UserControl, INotifyPropertyChanged
{
    private readonly IHabitsService _habitsService;
    private readonly ISettingsService _settingsService;

    // View Model Properties
    private double _currentProgress;
    public double CurrentProgress
    {
        get => _currentProgress;
        set { _currentProgress = value; OnPropertyChanged(); }
    }

    private double _goalValue = 2000;
    public double GoalValue
    {
        get => _goalValue;
        set { _goalValue = value; OnPropertyChanged(); }
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

    private SolidColorBrush _gaugeColor = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 2, 136, 209)); // Default Blue
    public SolidColorBrush GaugeColor
    {
        get => _gaugeColor;
        set { _gaugeColor = value; OnPropertyChanged(); }
    }

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
        DispatcherQueue.TryEnqueue(async () =>
        {
            await LoadDataAsync();
        });
    }

    private async Task LoadDataAsync()
    {
        if (_habitsService == null || _settingsService == null) return;
        
        bool isWater = HabitsFlipView.SelectedIndex == 0;
        
        if (isWater)
        {
            var waterGoal = await _habitsService.GetGoalAsync("water");
            GoalValue = waterGoal?.TargetValue > 0 ? waterGoal.TargetValue : 2000;
            CurrentProgress = await _habitsService.GetDailyProgressAsync("water", DateTime.Now);
            GoalDisplay = $"/ {GoalValue}";
            GaugeColor = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 2, 136, 209)); // Blue for water
        }
        else
        {
            GoalValue = _settingsService.Settings.SmokesBaselineDaily > 0 ? _settingsService.Settings.SmokesBaselineDaily : 20;
            CurrentProgress = await _habitsService.GetDailyProgressAsync("smokes", DateTime.Now);
            GoalDisplay = $"/ {GoalValue}";
            
            // Red for bad (more than 90%), Orange for warning (more than 50%), Green for good (less than 50%)
            if (GoalValue > 0)
            {
                double ratio = CurrentProgress / GoalValue;
                if (ratio < 0.5) GaugeColor = new SolidColorBrush(Microsoft.UI.Colors.DarkGreen);
                else if (ratio < 0.9) GaugeColor = new SolidColorBrush(Microsoft.UI.Colors.DarkOrange);
                else GaugeColor = new SolidColorBrush(Microsoft.UI.Colors.DarkRed);
            }
            else
            {
                GaugeColor = new SolidColorBrush(Microsoft.UI.Colors.DarkRed);
            }

            // Calculate financials via server-side RPC
            var quitDate = _settingsService.Settings.SmokesQuitDate;
            if (quitDate.HasValue)
            {
                var days = (DateTime.Today - quitDate.Value.Date).TotalDays + 1;
                if (days > 0)
                {
                    var (totalSmoked, daysTracked) = await _habitsService.GetSmokesFinancialsAsync(quitDate.Value);
                    var expected = days * GoalValue;
                    var avoided = Math.Max(0, expected - totalSmoked);
                    var costPerCig = _settingsService.Settings.SmokesPackCost / Math.Max(1, _settingsService.Settings.SmokesPackSize);
                    var saved = avoided * costPerCig;
                    var curr = string.IsNullOrEmpty(_settingsService.Settings.SmokesCurrency) ? "USD" : _settingsService.Settings.SmokesCurrency;
                    MoneySavedDisplay = $"{curr} {saved:F0}";
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
    }

    private async void HabitsFlipView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_habitsService != null)
        {
            _habitsService.CurrentViewType = HabitsFlipView.SelectedIndex == 0 ? "water" : "smokes";
        }
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

    private async void AddWater_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 250, "ml", DateTime.Now, "{\"drink\":\"Water\"}");
    }

    private async void AddCoffee_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 150, "ml", DateTime.Now, "{\"drink\":\"Coffee\"}");
    }

    private async void AddCigarette_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("smokes", 1, "unit", DateTime.Now, "{\"type\":\"Cigarette\"}");
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
