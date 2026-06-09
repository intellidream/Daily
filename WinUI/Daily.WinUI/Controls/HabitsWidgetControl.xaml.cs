using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI;
using Microsoft.UI.Input;
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

public class WidgetBreakdownItem
{
    public string Label { get; set; }
    public string Amount { get; set; }
    public string Icon { get; set; }
    public string ColorHex { get; set; }
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

    private string _goalValueDisplay = "";
    public string GoalValueDisplay
    {
        get => _goalValueDisplay;
        set { _goalValueDisplay = value; OnPropertyChanged(); }
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

    private SolidColorBrush _waterProgressColor = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 33, 150, 243));
    public SolidColorBrush WaterProgressColor
    {
        get => _waterProgressColor;
        set { _waterProgressColor = value; OnPropertyChanged(); }
    }


    private string _daysSinceQuitShort = "-";
    public string DaysSinceQuitShort
    {
        get => _daysSinceQuitShort;
        set { _daysSinceQuitShort = value; OnPropertyChanged(); }
    }

    private string _smokesAvoidedShort = "-";
    public string SmokesAvoidedShort
    {
        get => _smokesAvoidedShort;
        set { _smokesAvoidedShort = value; OnPropertyChanged(); }
    }

    private string _moneySavedShort = "-";
    public string MoneySavedShort
    {
        get => _moneySavedShort;
        set { _moneySavedShort = value; OnPropertyChanged(); }
    }

    private string _remainingWaterText = "-";
    public string RemainingWaterText
    {
        get => _remainingWaterText;
        set { _remainingWaterText = value; OnPropertyChanged(); }
    }

    private string _progressPercentageText = "-";
    public string ProgressPercentageText
    {
        get => _progressPercentageText;
        set { _progressPercentageText = value; OnPropertyChanged(); }
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

    private ObservableCollection<WidgetBreakdownItem> _waterBreakdown = new();
    public ObservableCollection<WidgetBreakdownItem> WaterBreakdown
    {
        get => _waterBreakdown;
        set { _waterBreakdown = value; OnPropertyChanged(); }
    }

    private ObservableCollection<WidgetBreakdownItem> _smokesBreakdown = new();
    public ObservableCollection<WidgetBreakdownItem> SmokesBreakdown
    {
        get => _smokesBreakdown;
        set { _smokesBreakdown = value; OnPropertyChanged(); }
    }

    public string CurrentViewLabel => HabitsFlipView?.SelectedIndex == 0 ? "Bubbles" : "Smokes";



    public HabitsWidgetControl()
    {
        InitializeComponent();
        _habitsService = App.Current.Services.GetRequiredService<IHabitsService>();
        _settingsService = App.Current.Services.GetRequiredService<ISettingsService>();
        _syncService = App.Current.Services.GetRequiredService<ISyncService>();

        Loaded += HabitsWidgetControl_Loaded;
        Unloaded += HabitsWidgetControl_Unloaded;
        SizeChanged += HabitsWidgetControl_SizeChanged;
        DataContextChanged += HabitsWidgetControl_DataContextChanged;

        HabitsFlipView.Loaded += (s, e) =>
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                HideFlipViewNavigationButtons();
            });
        };

        this.PointerWheelChanged += HabitsWidgetControl_PointerWheelChanged;
    }

    private void HabitsWidgetControl_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        UpdateVisualState();
    }

    private void HabitsWidgetControl_DataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        UpdateVisualState();
    }

    private void UpdateVisualState()
    {
        if (!IsLoaded)
        {
            return;
        }

        string state = "NormalState";

        double width = ActualWidth;
        double height = ActualHeight;

        if (width == 0 || height == 0)
        {
            width = Width;
            height = Height;
        }

        if (DataContext is WidgetModel widget)
        {
            int colSpan = widget.ColumnSpan;
            int rowSpan = widget.RowSpan;

            if (width > 0 && width < 450)
            {
                colSpan = 1;
            }

            if (colSpan == 1 && rowSpan == 1)
            {
                state = "SmallState";
            }
            else if (colSpan == 2 && rowSpan == 1)
            {
                state = "NormalState";
            }
            else if (colSpan == 1 && rowSpan == 2)
            {
                state = "TallState";
            }
            else if (colSpan == 2 && rowSpan == 2)
            {
                state = "LargeState";
            }
        }
        else
        {
            if (width > 0 && height > 0)
            {
                if (width < 450 && height < 350)
                {
                    state = "SmallState";
                }
                else if (width < 450 && height >= 350)
                {
                    state = "TallState";
                }
                else if (width >= 450 && height < 350)
                {
                    state = "NormalState";
                }
                else
                {
                    state = "LargeState";
                }
            }
        }

        VisualStateManager.GoToState(this, state, true);
        ApplyGridDefinitions(state, width);

        bool isCompact = state == "SmallState" || state == "NormalState";
        if (WaterDetailedProgressText != null) WaterDetailedProgressText.FontSize = isCompact ? 16 : 24;
        if (WaterDetailedGoalStack != null) WaterDetailedGoalStack.Visibility = Visibility.Visible;
        if (WaterDetailedSeparator != null) WaterDetailedSeparator.Visibility = Visibility.Visible;
        if (WaterDetailedList != null)
        {
            WaterDetailedList.Margin = isCompact ? new Thickness(2, 0, 2, 2) : new Thickness(8, 0, 8, 8);
            WaterDetailedList.HorizontalAlignment = HorizontalAlignment.Stretch;
        }

        if (SmokesDetailedProgressText != null) SmokesDetailedProgressText.FontSize = isCompact ? 16 : 24;
        if (SmokesDetailedGoalStack != null) SmokesDetailedGoalStack.Visibility = Visibility.Visible;
        if (SmokesDetailedSeparator != null) SmokesDetailedSeparator.Visibility = Visibility.Visible;
        if (SmokesDetailedList != null)
        {
            SmokesDetailedList.Margin = isCompact ? new Thickness(2, 0, 2, 2) : new Thickness(8, 0, 8, 8);
            SmokesDetailedList.HorizontalAlignment = HorizontalAlignment.Stretch;
        }

        if (isCompact)
        {
            if (Resources.ContainsKey("DetailedListCompactTemplate"))
            {
                var ct = Resources["DetailedListCompactTemplate"] as DataTemplate;
                if (WaterDetailedList != null && WaterDetailedList.ItemTemplate != ct) WaterDetailedList.ItemTemplate = ct;
                if (SmokesDetailedList != null && SmokesDetailedList.ItemTemplate != ct) SmokesDetailedList.ItemTemplate = ct;
            }
        }
        else
        {
            if (Resources.ContainsKey("DetailedListDefaultTemplate"))
            {
                var dt = Resources["DetailedListDefaultTemplate"] as DataTemplate;
                if (WaterDetailedList != null && WaterDetailedList.ItemTemplate != dt) WaterDetailedList.ItemTemplate = dt;
                if (SmokesDetailedList != null && SmokesDetailedList.ItemTemplate != dt) SmokesDetailedList.ItemTemplate = dt;
            }
        }
    }

    private void SetGridPosition(FrameworkElement element, int row, int col, int rowSpan = 1, int colSpan = 1)
    {
        Grid.SetRow(element, row);
        Grid.SetColumn(element, col);
        Grid.SetRowSpan(element, rowSpan);
        Grid.SetColumnSpan(element, colSpan);
    }

    private void ApplyGridDefinitions(string state, double width)
    {
        if (RootGrid == null ||
            WaterMainCol0 == null || WaterMainCol1 == null || WaterMainRow0 == null || WaterMainRow1 == null ||
            SmokesMainCol0 == null || SmokesMainCol1 == null || SmokesMainRow0 == null || SmokesMainRow1 == null ||
            WaterExtCol0 == null || WaterExtCol1 == null || WaterExtRow0 == null || WaterExtRow1 == null || WaterExtRow2 == null ||
            SmokesExtCol0 == null || SmokesExtCol1 == null || SmokesExtRow0 == null || SmokesExtRow1 == null || SmokesExtRow2 == null ||
            WaterExtendedPanel == null || SmokesExtendedPanel == null ||
            WaterGraphBorder == null || SmokesGraphBorder == null ||
            WaterStatsGrid == null || SmokesStatsGrid == null ||
            WaterLogsList == null || SmokesLogsList == null ||
            WaterEmptyText == null || SmokesEmptyText == null ||
            WaterControlsStack == null || SmokesControlsStack == null)
        {
            return;
        }

        if (WaterLogsList != null) WaterLogsList.Width = double.NaN;
        if (WaterEmptyText != null) WaterEmptyText.Width = double.NaN;
        if (SmokesLogsList != null) SmokesLogsList.Width = double.NaN;
        if (SmokesEmptyText != null) SmokesEmptyText.Width = double.NaN;

        switch (state)
        {
            case "SmallState":
                if (width >= 380)
                {
                    RootGrid.Padding = new Thickness(16, 10, 16, 10);
                    WaterControlsStack.Spacing = 20;
                    SmokesControlsStack.Spacing = 20;
                }
                else if (width >= 340)
                {
                    RootGrid.Padding = new Thickness(12, 8, 12, 8);
                    WaterControlsStack.Spacing = 14;
                    SmokesControlsStack.Spacing = 14;
                }
                else
                {
                    RootGrid.Padding = new Thickness(8, 6, 8, 6);
                    WaterControlsStack.Spacing = 8;
                    SmokesControlsStack.Spacing = 8;
                }

                WaterExtendedPanel.Margin = new Thickness(0);
                SmokesExtendedPanel.Margin = new Thickness(0);

                // Outer layouts: left column only, top row only
                WaterMainCol0.Width = new GridLength(1, GridUnitType.Star);
                WaterMainCol1.Width = new GridLength(0, GridUnitType.Pixel);
                WaterMainRow0.Height = new GridLength(1, GridUnitType.Star);
                WaterMainRow1.Height = new GridLength(0, GridUnitType.Pixel);

                SmokesMainCol0.Width = new GridLength(1, GridUnitType.Star);
                SmokesMainCol1.Width = new GridLength(0, GridUnitType.Pixel);
                SmokesMainRow0.Height = new GridLength(1, GridUnitType.Star);
                SmokesMainRow1.Height = new GridLength(0, GridUnitType.Pixel);

                // Extended panels grid: Col 0 only, all 3 rows active
                WaterExtCol0.Width = new GridLength(1, GridUnitType.Star);
                WaterExtCol1.Width = new GridLength(0, GridUnitType.Pixel);
                WaterExtRow0.Height = GridLength.Auto;
                WaterExtRow1.Height = GridLength.Auto;
                WaterExtRow2.Height = new GridLength(1, GridUnitType.Star);

                SmokesExtCol0.Width = new GridLength(1, GridUnitType.Star);
                SmokesExtCol1.Width = new GridLength(0, GridUnitType.Pixel);
                SmokesExtRow0.Height = GridLength.Auto;
                SmokesExtRow1.Height = GridLength.Auto;
                SmokesExtRow2.Height = new GridLength(1, GridUnitType.Star);

                // Main grids position
                SetGridPosition(WaterExtendedPanel, 0, 0);
                SetGridPosition(SmokesExtendedPanel, 0, 0);

                // Inner grids position
                SetGridPosition(WaterGraphBorder, 0, 0, 1, 2);
                SetGridPosition(WaterStatsGrid, 1, 0, 1, 2);
                SetGridPosition(WaterLogsList, 2, 0, 1, 2);
                SetGridPosition(WaterEmptyText, 2, 0, 1, 2);

                SetGridPosition(SmokesGraphBorder, 0, 0, 1, 2);
                SetGridPosition(SmokesStatsGrid, 1, 0, 1, 2);
                SetGridPosition(SmokesLogsList, 2, 0, 1, 2);
                SetGridPosition(SmokesEmptyText, 2, 0, 1, 2);
                break;

            case "NormalState":
                // Outer layouts: left radial gauge, right extended panel
                // If width >= 650, there's enough space to show both chart and logs side-by-side
                bool hasSpace = width >= 650;

                WaterExtRow0.Height = new GridLength(1, GridUnitType.Star);
                WaterExtRow1.Height = new GridLength(0, GridUnitType.Pixel);
                WaterExtRow2.Height = new GridLength(0, GridUnitType.Pixel);

                SmokesExtRow0.Height = new GridLength(1, GridUnitType.Star);
                SmokesExtRow1.Height = new GridLength(0, GridUnitType.Pixel);
                SmokesExtRow2.Height = new GridLength(0, GridUnitType.Pixel);

                if (hasSpace)
                {
                    if (width >= 720)
                    {
                        RootGrid.Padding = new Thickness(36, 12, 36, 14);
                        WaterExtendedPanel.Margin = new Thickness(16, 0, 0, 0);
                        SmokesExtendedPanel.Margin = new Thickness(16, 0, 0, 0);

                        WaterExtCol0.Width = new GridLength(1.3, GridUnitType.Star);
                        WaterExtCol1.Width = new GridLength(1.0, GridUnitType.Star);

                        SmokesExtCol0.Width = new GridLength(1.3, GridUnitType.Star);
                        SmokesExtCol1.Width = new GridLength(1.0, GridUnitType.Star);

                        WaterControlsStack.Spacing = 24;
                        SmokesControlsStack.Spacing = 24;
                    }
                    else
                    {
                        RootGrid.Padding = new Thickness(24, 12, 24, 14);
                        WaterExtendedPanel.Margin = new Thickness(12, 0, 0, 0);
                        SmokesExtendedPanel.Margin = new Thickness(12, 0, 0, 0);

                        WaterExtCol0.Width = new GridLength(1.0, GridUnitType.Star);
                        WaterExtCol1.Width = new GridLength(1.2, GridUnitType.Star);

                        SmokesExtCol0.Width = new GridLength(1.0, GridUnitType.Star);
                        SmokesExtCol1.Width = new GridLength(1.2, GridUnitType.Star);

                        WaterControlsStack.Spacing = 16;
                        SmokesControlsStack.Spacing = 16;
                    }

                    WaterMainCol0.Width = GridLength.Auto;
                    WaterMainCol1.Width = new GridLength(1.0, GridUnitType.Star);

                    SmokesMainCol0.Width = GridLength.Auto;
                    SmokesMainCol1.Width = new GridLength(1.0, GridUnitType.Star);

                    if (WaterLogsList != null) WaterLogsList.Width = double.NaN;
                    if (WaterEmptyText != null) WaterEmptyText.Width = double.NaN;
                    if (SmokesLogsList != null) SmokesLogsList.Width = double.NaN;
                    if (SmokesEmptyText != null) SmokesEmptyText.Width = double.NaN;
                }
                else
                {
                    RootGrid.Padding = new Thickness(10, 8, 10, 8);
                    WaterExtendedPanel.Margin = new Thickness(12, 0, 0, 0);
                    SmokesExtendedPanel.Margin = new Thickness(12, 0, 0, 0);

                    WaterMainCol0.Width = new GridLength(1.5, GridUnitType.Star);
                    WaterMainCol1.Width = new GridLength(1, GridUnitType.Star);

                    SmokesMainCol0.Width = new GridLength(1.5, GridUnitType.Star);
                    SmokesMainCol1.Width = new GridLength(1, GridUnitType.Star);

                    WaterExtCol0.Width = new GridLength(1, GridUnitType.Star);
                    WaterExtCol1.Width = new GridLength(0, GridUnitType.Pixel);

                    SmokesExtCol0.Width = new GridLength(1, GridUnitType.Star);
                    SmokesExtCol1.Width = new GridLength(0, GridUnitType.Pixel);

                    WaterControlsStack.Spacing = 10;
                    SmokesControlsStack.Spacing = 10;

                    if (WaterLogsList != null) WaterLogsList.Width = 0;
                    if (WaterEmptyText != null) WaterEmptyText.Width = 0;
                    if (SmokesLogsList != null) SmokesLogsList.Width = 0;
                    if (SmokesEmptyText != null) SmokesEmptyText.Width = 0;
                }

                // Main grids position
                SetGridPosition(WaterExtendedPanel, 0, 1);
                SetGridPosition(SmokesExtendedPanel, 0, 1);

                // Inner grids position: Col 0 for Graph/Stats, Col 1 for Logs/EmptyText
                SetGridPosition(WaterGraphBorder, 0, 0, 1, 1);
                SetGridPosition(WaterStatsGrid, 0, 0, 1, 1);
                SetGridPosition(WaterLogsList, 0, 1, 1, 1);
                SetGridPosition(WaterEmptyText, 0, 1, 1, 1);

                SetGridPosition(SmokesGraphBorder, 0, 0, 1, 1);
                SetGridPosition(SmokesStatsGrid, 0, 0, 1, 1);
                SetGridPosition(SmokesLogsList, 0, 1, 1, 1);
                SetGridPosition(SmokesEmptyText, 0, 1, 1, 1);
                break;

            case "TallState":
                RootGrid.Padding = new Thickness(16, 12, 16, 14);
                WaterExtendedPanel.Margin = new Thickness(0);
                SmokesExtendedPanel.Margin = new Thickness(0);
                WaterControlsStack.Spacing = 12;
                SmokesControlsStack.Spacing = 12;

                // Outer layouts: left column only, top row only
                WaterMainCol0.Width = new GridLength(1, GridUnitType.Star);
                WaterMainCol1.Width = new GridLength(0, GridUnitType.Pixel);
                WaterMainRow0.Height = new GridLength(1, GridUnitType.Star);
                WaterMainRow1.Height = new GridLength(0, GridUnitType.Pixel);

                SmokesMainCol0.Width = new GridLength(1, GridUnitType.Star);
                SmokesMainCol1.Width = new GridLength(0, GridUnitType.Pixel);
                SmokesMainRow0.Height = new GridLength(1, GridUnitType.Star);
                SmokesMainRow1.Height = new GridLength(0, GridUnitType.Pixel);

                // Extended panels grid: Col 0 only, all 3 rows active
                WaterExtCol0.Width = new GridLength(1, GridUnitType.Star);
                WaterExtCol1.Width = new GridLength(0, GridUnitType.Pixel);
                WaterExtRow0.Height = GridLength.Auto;
                WaterExtRow1.Height = GridLength.Auto;
                WaterExtRow2.Height = new GridLength(1, GridUnitType.Star);

                SmokesExtCol0.Width = new GridLength(1, GridUnitType.Star);
                SmokesExtCol1.Width = new GridLength(0, GridUnitType.Pixel);
                SmokesExtRow0.Height = GridLength.Auto;
                SmokesExtRow1.Height = GridLength.Auto;
                SmokesExtRow2.Height = new GridLength(1, GridUnitType.Star);

                // Main grids position
                SetGridPosition(WaterExtendedPanel, 1, 0);
                SetGridPosition(SmokesExtendedPanel, 1, 0);

                // Inner grids position
                SetGridPosition(WaterGraphBorder, 0, 0, 1, 2);
                SetGridPosition(WaterStatsGrid, 1, 0, 1, 2);
                SetGridPosition(WaterLogsList, 2, 0, 1, 2);
                SetGridPosition(WaterEmptyText, 2, 0, 1, 2);

                SetGridPosition(SmokesGraphBorder, 0, 0, 1, 2);
                SetGridPosition(SmokesStatsGrid, 1, 0, 1, 2);
                SetGridPosition(SmokesLogsList, 2, 0, 1, 2);
                SetGridPosition(SmokesEmptyText, 2, 0, 1, 2);
                break;

            case "LargeState":
                RootGrid.Padding = new Thickness(16, 12, 16, 14);
                WaterExtendedPanel.Margin = new Thickness(16, 0, 0, 0);
                SmokesExtendedPanel.Margin = new Thickness(16, 0, 0, 0);
                WaterControlsStack.Spacing = 16;
                SmokesControlsStack.Spacing = 16;

                // Outer layouts: 2 columns side-by-side, top row only
                WaterMainCol0.Width = new GridLength(1, GridUnitType.Star);
                WaterMainCol1.Width = new GridLength(1.2, GridUnitType.Star);
                WaterMainRow0.Height = new GridLength(1, GridUnitType.Star);
                WaterMainRow1.Height = new GridLength(0, GridUnitType.Pixel);

                SmokesMainCol0.Width = new GridLength(1, GridUnitType.Star);
                SmokesMainCol1.Width = new GridLength(1.2, GridUnitType.Star);
                SmokesMainRow0.Height = new GridLength(1, GridUnitType.Star);
                SmokesMainRow1.Height = new GridLength(0, GridUnitType.Pixel);

                // Extended panels grid: Col 0 only, all 3 rows active
                WaterExtCol0.Width = new GridLength(1, GridUnitType.Star);
                WaterExtCol1.Width = new GridLength(0, GridUnitType.Pixel);
                WaterExtRow0.Height = GridLength.Auto;
                WaterExtRow1.Height = GridLength.Auto;
                WaterExtRow2.Height = new GridLength(1, GridUnitType.Star);

                SmokesExtCol0.Width = new GridLength(1, GridUnitType.Star);
                SmokesExtCol1.Width = new GridLength(0, GridUnitType.Pixel);
                SmokesExtRow0.Height = GridLength.Auto;
                SmokesExtRow1.Height = GridLength.Auto;
                SmokesExtRow2.Height = new GridLength(1, GridUnitType.Star);

                // Main grids position
                SetGridPosition(WaterExtendedPanel, 0, 1, 2, 1);
                SetGridPosition(SmokesExtendedPanel, 0, 1, 2, 1);

                // Inner grids position
                SetGridPosition(WaterGraphBorder, 0, 0, 1, 2);
                SetGridPosition(WaterStatsGrid, 1, 0, 1, 2);
                SetGridPosition(WaterLogsList, 2, 0, 1, 2);
                SetGridPosition(WaterEmptyText, 2, 0, 1, 2);

                SetGridPosition(SmokesGraphBorder, 0, 0, 1, 2);
                SetGridPosition(SmokesStatsGrid, 1, 0, 1, 2);
                SetGridPosition(SmokesLogsList, 2, 0, 1, 2);
                SetGridPosition(SmokesEmptyText, 2, 0, 1, 2);
                break;
        }
    }

    private void HideFlipViewNavigationButtons()
    {
        if (HabitsFlipView == null) return;

        var buttonsToHide = new[] { "PreviousButtonHorizontal", "NextButtonHorizontal", "PreviousButtonVertical", "NextButtonVertical" };
        foreach (var name in buttonsToHide)
        {
            var btn = FindVisualChildByName<Button>(HabitsFlipView, name);
            if (btn != null)
            {
                btn.Visibility = Visibility.Collapsed;
                btn.Opacity = 0;
                btn.Width = 0;
                btn.Height = 0;
                btn.IsEnabled = false;
            }
        }
    }

    private T? FindVisualChildByName<T>(DependencyObject parent, string name) where T : DependencyObject
    {
        int childCount = VisualTreeHelper.GetChildrenCount(parent);
        for (int i = 0; i < childCount; i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is T tChild && child is FrameworkElement fe && fe.Name == name)
            {
                return tChild;
            }

            var result = FindVisualChildByName<T>(child, name);
            if (result != null)
            {
                return result;
            }
        }
        return null;
    }

    private async void HabitsWidgetControl_Loaded(object sender, RoutedEventArgs e)
    {
        _habitsService.OnHabitsUpdated += HabitsService_OnHabitsUpdated;
        UpdateVisualState();
        var task = LoadDataAsync();
        MainPage.Current?.RegisterLoadingTask(task);
        await task;
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

    /// <summary>Called by the dashboard refresh button: runs full sync (push + pull), then reloads the UI.</summary>
    public async Task RefreshAsync()
    {
        try
        {
            await _syncService.SyncAsync(SyncScope.Habits);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[HabitsWidgetControl] Sync failed on refresh: {ex.Message}");
        }
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
            GoalValueDisplay = $"{GoalValue:0}";

            ProgressPercentageText = GoalValue > 0 ? $"{(CurrentProgress / GoalValue * 100):0}%" : "0%";
            RemainingWaterText = $"{(Math.Max(0, GoalValue - CurrentProgress)):0} ml";

            DaysSinceQuitShort = "-";
            SmokesAvoidedShort = "-";
            MoneySavedShort = "-";

            var breakdown = await _habitsService.GetDailyBreakdownAsync("water", DateTime.Now);
            UpdateGaugeSegments(WaterRadialAxis, breakdown);

            // Find the liquid with the highest amount to color the current total text
            string maxLiquidKey = null;
            double maxAmount = 0;
            foreach (var kvp in breakdown)
            {
                if (kvp.Value > maxAmount)
                {
                    maxAmount = kvp.Value;
                    maxLiquidKey = kvp.Key;
                }
            }

            string targetColorHex = "#FF2196F3"; // Default water color
            if (maxLiquidKey != null)
            {
                targetColorHex = GetColorForDrinkOrSmoke(maxLiquidKey);
            }
            WaterProgressColor = new SolidColorBrush(GetColorFromHex(targetColorHex));


            var waterItems = new List<WidgetBreakdownItem>();
            foreach (var kvp in breakdown)
            {
                if (kvp.Value <= 0) continue;
                string drinkKey = kvp.Key.ToLowerInvariant();
                
                string label = System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(drinkKey);
                string icon = "\xea97"; // Empty bubble as fallback/small
                string colorHex = GetColorForDrinkOrSmoke(drinkKey);

                if (drinkKey.Contains("large"))
                {
                    label = "Large";
                    icon = "\xfc12"; // Droplets
                }
                else if (drinkKey.Contains("small") || drinkKey == "water")
                {
                    label = "Small";
                    icon = "\xea97"; // Empty bubble
                }
                else if (drinkKey.Contains("coffee"))
                {
                    label = "Coffee";
                    icon = "\xef0e";
                }
                else if (drinkKey.Contains("tea"))
                {
                    label = "Tea";
                    icon = "\xf552";
                }
                else if (drinkKey.Contains("beer"))
                {
                    label = "Beer";
                    icon = "\xefa1";
                }
                else if (drinkKey.Contains("wine"))
                {
                    label = "Wine";
                    icon = "\xeab7";
                }
                else if (drinkKey.Contains("juice"))
                {
                    label = "Juice";
                    icon = "\xef28";
                }

                var existing = waterItems.FirstOrDefault(x => x.Label == label);
                if (existing != null)
                {
                    try
                    {
                        int existingVal = int.Parse(existing.Amount.Split(' ')[0]);
                        existing.Amount = $"{existingVal + (int)kvp.Value} ml";
                    }
                    catch { }
                }
                else
                {
                    waterItems.Add(new WidgetBreakdownItem
                    {
                        Label = label,
                        Amount = $"{(int)kvp.Value} ml",
                        Icon = icon,
                        ColorHex = colorHex
                    });
                }
            }
            WaterBreakdown = new ObservableCollection<WidgetBreakdownItem>(waterItems);

            MoneySavedDisplay = string.Empty;
        }
        else
        {
            GoalValue = _settingsService.Settings.SmokesBaselineDaily > 0 ? _settingsService.Settings.SmokesBaselineDaily : 20;
            CurrentProgress = await _habitsService.GetDailyProgressAsync("smokes", DateTime.Now);
            GoalDisplay = $"/ {GoalValue:0}";
            GoalValueDisplay = $"{GoalValue:0}";

            ProgressPercentageText = "-";
            RemainingWaterText = "-";

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

            var smokesBreakdown = await _habitsService.GetDailyBreakdownAsync("smokes", DateTime.Now);
            var smokesItems = new List<WidgetBreakdownItem>();
            foreach (var kvp in smokesBreakdown)
            {
                if (kvp.Value <= 0) continue;
                string label = System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(kvp.Key);
                if (label == "Large Water") label = "Large";
                else if (label == "Heated Tobacco") label = "Heated";
                string colorHex = GetColorForDrinkOrSmoke(kvp.Key);
                string icon = kvp.Key.ToLowerInvariant() switch
                {
                    var s when s.Contains("heated")     => "\xec2c",
                    var s when s.Contains("rolled")     => "\xec2b",
                    var s when s.Contains("cigarillo")  => "\xeed2",
                    _                                   => "\xecc4"
                };
                smokesItems.Add(new WidgetBreakdownItem
                {
                    Label = label,
                    Amount = $"{(int)kvp.Value}",
                    Icon = icon,
                    ColorHex = colorHex
                });
            }
            SmokesBreakdown = new ObservableCollection<WidgetBreakdownItem>(smokesItems);

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

                    DaysSinceQuitShort = $"{days:0}d";
                    SmokesAvoidedShort = $"{avoided:0}";
                    MoneySavedShort = $"{currency} {saved:F0}";
                }
                else
                {
                    MoneySavedDisplay = "-";
                    DaysSinceQuitShort = "-";
                    SmokesAvoidedShort = "-";
                    MoneySavedShort = "-";
                }
            }
            else
            {
                MoneySavedDisplay = "Not started";
                DaysSinceQuitShort = "-";
                SmokesAvoidedShort = "-";
                MoneySavedShort = "Not started";
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
            
            // Icon glyphs & labels
            string icon = "\xea97"; // Empty bubble as fallback/small
            string label = "";
            
            if (viewType == "smokes")
            {
                icon = drinkOrType switch
                {
                    var s when s.Contains("heated")     => "\xec2c",  // heated
                    var s when s.Contains("rolled")     => "\xec2b",  // rolled
                    var s when s.Contains("cigarillo")  => "\xeed2",  // cigarillo
                    _                                   => "\xecc4"   // cigarette
                };
                label = System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(drinkOrType) switch
                {
                    "Heated Tobacco" => "Heated",
                    var other => other
                };
            }
            else
            {
                if (drinkOrType.Contains("coffee"))
                {
                    icon = "\xef0e";
                    label = "Coffee";
                }
                else if (drinkOrType.Contains("tea"))
                {
                    icon = "\xf552";
                    label = "Tea";
                }
                else if (drinkOrType.Contains("juice"))
                {
                    icon = "\xef28";
                    label = "Juice";
                }
                else if (drinkOrType.Contains("beer"))
                {
                    icon = "\xefa1";
                    label = "Beer";
                }
                else if (drinkOrType.Contains("wine"))
                {
                    icon = "\xeab7";
                    label = "Wine";
                }
                else
                {
                    // Water Large vs Small
                    bool isLarge = false;
                    string sizeProp = "";
                    if (!string.IsNullOrWhiteSpace(log.Metadata))
                    {
                        try
                        {
                            using var doc = System.Text.Json.JsonDocument.Parse(log.Metadata);
                            if (doc.RootElement.TryGetProperty("size", out var sProp))
                                sizeProp = sProp.GetString()?.ToLowerInvariant() ?? "";
                        }
                        catch {}
                    }

                    if (drinkOrType.Contains("large") || sizeProp.Contains("large") || log.Value >= 300)
                    {
                        isLarge = true;
                    }

                    if (isLarge)
                    {
                        icon = "\xfc12"; // Droplets
                        label = "Large";
                    }
                    else
                    {
                        icon = "\xea97"; // Empty bubble
                        label = "Small";
                    }
                }
            }

            widgetLogs.Add(new WidgetLogEntryViewModel
            {
                Log = log,
                Icon = icon,
                ColorHex = colorHex,
                Label = label,
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
        var normalized = (item ?? string.Empty).Trim().ToLowerInvariant();

        if (normalized.Contains("water") || normalized.Contains("large") || normalized.Contains("small")) return "#FF2196F3";
        if (normalized.Contains("coffee")) return "#FFF2994A";
        if (normalized.Contains("tea")) return "#FF27AE60";
        if (normalized.Contains("juice")) return "#FFE91E63";
        if (normalized.Contains("beer")) return "#FFFFA000";
        if (normalized.Contains("wine")) return "#FF9C27B0";

        if (normalized.Contains("heat")) return "#FF1976D2";      // Heated / Heated Tobacco
        if (normalized.Contains("roll")) return "#FFEF6C00";      // Rolled
        if (normalized.Contains("cigarillo")) return "#FF8E24AA"; // Cigarillo
        if (normalized.Contains("cigarette")) return "#FFF44336"; // Cigarette

        return "#FF808080";
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
        await _habitsService.AddLogAsync("water", 150, "ml", DateTime.Now, "{\"drink\":\"Small Water\"}");
    }

    private async void AddWaterLarge_Click(object sender, RoutedEventArgs e)
    {
        await _habitsService.AddLogAsync("water", 300, "ml", DateTime.Now, "{\"drink\":\"Large Water\"}");
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

    private void HabitsWidgetControl_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
    {
        if (e.Handled) return;

        var properties = e.GetCurrentPoint(this).Properties;
        int delta = properties.MouseWheelDelta;
        if (delta == 0) return;

        if (HabitsFlipView != null && HabitsFlipView.Items.Count > 1)
        {
            e.Handled = true;
            if (delta < 0) // Scroll down -> Next
            {
                if (HabitsFlipView.SelectedIndex < HabitsFlipView.Items.Count - 1)
                    HabitsFlipView.SelectedIndex++;
                else
                    HabitsFlipView.SelectedIndex = 0;
            }
            else // Scroll up -> Prev
            {
                if (HabitsFlipView.SelectedIndex > 0)
                    HabitsFlipView.SelectedIndex--;
                else
                    HabitsFlipView.SelectedIndex = HabitsFlipView.Items.Count - 1;
            }
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

