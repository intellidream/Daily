using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Daily_WinUI.Views;
using Daily_WinUI.Services;
using Daily_WinUI.Controls;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;

namespace Daily_WinUI;

public sealed partial class MainPage : Page
{
    public static MainPage? Current { get; private set; }

    private readonly Dictionary<System.Type, DetailWindow> _openWindows = new();
    private SettingsWindow? _settingsWindow;
    private readonly WinUIAuthService _authService;
    private readonly WinUIWidgetService _widgetService;
    private System.Collections.ObjectModel.ObservableCollection<Daily.Models.WidgetModel> _widgets;

    private readonly List<System.Threading.Tasks.Task> _loadingTasks = new();
    private readonly object _lock = new object();
    private bool _isTrackingLoads = false;

    public MainPage()
    {
        InitializeComponent();
        Current = this;
        _authService = App.Current.Services.GetRequiredService<WinUIAuthService>();
        _widgetService = App.Current.Services.GetRequiredService<WinUIWidgetService>();
        Loaded += MainPage_Loaded;
        Unloaded += (_, _) => 
        {
            WeatherBannerService.WeatherConditionChanged -= OnWeatherConditionChanged;
            if (Current == this) Current = null;
        };
        WeatherBannerService.WeatherConditionChanged += OnWeatherConditionChanged;
        // Replay last known condition if weather already loaded before this page
        if (WeatherBannerService.LastIconCode is { } code)
            OnWeatherConditionChanged(code);
    }

    public void RegisterLoadingTask(System.Threading.Tasks.Task task)
    {
        lock (_lock)
        {
            if (!_isTrackingLoads) return;
            _loadingTasks.Add(task);
        }
    }

    private void OnWeatherConditionChanged(string iconCode)
    {
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Normal, () =>
        {
            // TopBarBanner removed - using solid background instead
        });
    }

    private async void MainPage_Loaded(object sender, RoutedEventArgs e)
    {
        UpdateUserUI();
        await RunLoadingSequenceAsync();
    }

    private async System.Threading.Tasks.Task RunLoadingSequenceAsync()
    {
        // Initialize transition targets to starting state
        ContentGrid.Opacity = 0.0;
        ContentScale.ScaleX = 0.94;
        ContentScale.ScaleY = 0.94;

        var mainWindow = App.Current.MainWindow as MainWindow;
        bool isInitialBoot = mainWindow != null && mainWindow.IsLoadingOverlayVisible;

        // 1. Track loads
        lock (_lock)
        {
            _isTrackingLoads = true;
            _loadingTasks.Clear();
        }

        // 2. Load widgets configuration and bind
        await LoadWidgetsAsync();

        // 3. Yield/delay to let widgets instantiate, trigger Loaded, and register their loading tasks
        await System.Threading.Tasks.Task.Delay(200);
        
        List<System.Threading.Tasks.Task> tasksToAwait;
        lock (_lock)
        {
            _isTrackingLoads = false;
            tasksToAwait = _loadingTasks.ToList();
        }

        // 4. Wait for all registered widget data loads to finish
        if (tasksToAwait.Count > 0)
        {
            try
            {
                await System.Threading.Tasks.Task.WhenAll(tasksToAwait);
            }
            catch (System.Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MainPage] Error loading widgets: {ex}");
            }
        }

        if (isInitialBoot && mainWindow != null)
        {
            // 5. Ensure minimum boot time has elapsed
            await mainWindow.WaitForMinBootTimeAsync();

            // 6. Fade out the window-level loading overlay
            await mainWindow.FadeOutLoadingOverlayAsync();
        }

        // 7. Trigger local widgets entrance animation
        FadeInContentStoryboard.Begin();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await LoadWidgetsAsync();
    }

    public void TriggerRefresh() => RefreshLiveWidgets();

    /// <summary>
    /// Refreshes all live widget controls in-place without rebuilding the grid.
    /// Walking the visual tree avoids the recreate-on-rebind issue where Loaded
    /// never re-fires on recycled GridView containers.
    /// </summary>
    private void RefreshLiveWidgets()
    {
        foreach (var item in _widgets ?? Enumerable.Empty<Daily.Models.WidgetModel>())
        {
            var container = WidgetGridView.ContainerFromItem(item) as GridViewItem;
            if (container == null) continue;

            var border = container.ContentTemplateRoot as Border;
            if (border?.Child is WeatherWidgetControl weather)
                _ = weather.RefreshAsync();
            else if (border?.Child is HabitsWidgetControl habits)
                _ = habits.RefreshAsync();
            else if (border?.Child is RssFeedWidgetControl rss)
                _ = rss.RefreshAsync();
            else if (border?.Child is HealthWidgetControl health)
                _ = health.LoadDataAsync();
            else if (border?.Child is FinancesWidgetControl finances)
                _ = finances.LoadDataAsync();
        }
    }

    private async System.Threading.Tasks.Task LoadWidgetsAsync()
    {
        var widgetList = await _widgetService.GetWidgetsAsync();
        _widgets = new System.Collections.ObjectModel.ObservableCollection<Daily.Models.WidgetModel>(widgetList);
        WidgetGridView.ItemsSource = _widgets;
    }

    private void UpdateUserUI()
    {
        var email       = _authService.CurrentUserEmail;
        var displayName = email?.Split('@').FirstOrDefault() ?? "U";
        var avatarUrl   = _authService.CurrentUserAvatarUrl;
        var isAuth      = _authService.IsAuthenticated;

        // Push state to the OS title bar controls hosted in MainWindow
        if (XamlRoot?.Content is FrameworkElement root &&
            root.XamlRoot != null &&
            App.Current.MainWindow is MainWindow mw)
        {
            mw.UpdateTitleBarUser(email ?? string.Empty, displayName, avatarUrl, isAuth);
        }
    }

    private void ThemeToggleButton_Click(object sender, RoutedEventArgs e)
        => ApplyThemeToggle();

    public void ApplyThemeToggle()
    {
        App.Current.MainWindow?.ToggleAppTheme();
    }

    public void ApplyTheme(ElementTheme newTheme)
    {
        if (App.Current.MainWindow is MainWindow mw && mw.Content is FrameworkElement root)
        {
            root.RequestedTheme = newTheme;
            mw.UpdateThemeIcon(isDark: newTheme == ElementTheme.Dark);
        }
        PropagateThemeToSubWindows(newTheme);
    }

    public void PropagateThemeToSubWindows(ElementTheme newTheme)
    {
        foreach (var win in _openWindows.Values)
            win.ApplyTheme(newTheme);

        _settingsWindow?.ApplyTheme(newTheme);
    }

    private async void SignOut_Click(object sender, RoutedEventArgs e)
        => await HandleSignOutAsync();

    public async Task HandleSignOutAsync()
    {
        if (_authService.IsAuthenticated)
            await _authService.SignOutAsync();

        // Reset the title-bar avatar/email/flyout text before leaving this page
        UpdateUserUI();

        Frame?.Navigate(typeof(LoginPage));
    }

    private void WidgetGridView_ContainerContentChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.Item is Daily.Models.WidgetModel widget && args.ItemContainer is GridViewItem itemContainer)
        {
            int clampedSpan = System.Math.Min(widget.ColumnSpan, _currentColumns);
            VariableSizedWrapGrid.SetColumnSpan(itemContainer, clampedSpan);
            VariableSizedWrapGrid.SetRowSpan(itemContainer, widget.RowSpan);

            itemContainer.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            itemContainer.VerticalContentAlignment = VerticalAlignment.Stretch;
        }
    }

    private Daily.Models.WidgetModel _draggedWidget;
    private int _currentColumns = 2; // tracks last computed column count

    private void WidgetGridView_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        var availableWidth = WidgetGridView.ActualWidth;
        if (availableWidth <= 0) return;

        var panel = WidgetGridView.ItemsPanelRoot as VariableSizedWrapGrid;
        if (panel == null) return;

        // One column per ~340 logical px; minimum 1 column.
        const double MinCellWidth = 340.0;
        int columns = System.Math.Max(1, (int)(availableWidth / MinCellWidth));

        if (columns != _currentColumns || e.NewSize.Width != e.PreviousSize.Width)
        {
            _currentColumns = columns;
            panel.MaximumRowsOrColumns = columns;
            panel.ItemWidth = System.Math.Floor(availableWidth / columns);

            // Re-clamp spans on all live containers so no widget overflows the new column count
            ReapplySpans();
        }
        else
        {
            // Width changed within same column count — keep ItemWidth pixel-perfect
            panel.ItemWidth = System.Math.Floor(availableWidth / columns);
        }
    }

    /// <summary>Re-applies ColumnSpan (clamped to current column count) and RowSpan to every visible container.</summary>
    private void ReapplySpans()
    {
        if (_widgets == null) return;

        var panel = WidgetGridView.ItemsPanelRoot as VariableSizedWrapGrid;

        foreach (var item in _widgets)
        {
            var container = WidgetGridView.ContainerFromItem(item) as GridViewItem;
            if (container == null) continue;

            int clampedSpan = System.Math.Min(item.ColumnSpan, _currentColumns);
            VariableSizedWrapGrid.SetColumnSpan(container, clampedSpan);
            VariableSizedWrapGrid.SetRowSpan(container, item.RowSpan);
        }

        panel?.InvalidateMeasure();
    }

    private void WidgetGridView_DragItemsStarting(object sender, DragItemsStartingEventArgs e)
    {
        if (e.Items != null && e.Items.Count > 0 && e.Items[0] is Daily.Models.WidgetModel widget)
        {
            _draggedWidget = widget;
        }
    }

    private void WidgetGridView_DragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Move;
    }

    private async void WidgetGridView_Drop(object sender, DragEventArgs e)
    {
        if (_draggedWidget == null) return;

        DependencyObject current = e.OriginalSource as DependencyObject;
        Daily.Models.WidgetModel targetWidget = null;
        
        while (current != null)
        {
            if (current is FrameworkElement fe && fe.DataContext is Daily.Models.WidgetModel w)
            {
                targetWidget = w;
                break;
            }
            current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current);
        }

        if (targetWidget == null)
        {
            var pos = e.GetPosition(WidgetGridView);
            foreach (var w in _widgets)
            {
                if (WidgetGridView.ContainerFromItem(w) is UIElement container)
                {
                    var transform = container.TransformToVisual(WidgetGridView);
                    var bounds = transform.TransformBounds(new Windows.Foundation.Rect(0, 0, container.RenderSize.Width, container.RenderSize.Height));
                    bounds.X -= 20;
                    bounds.Y -= 20;
                    bounds.Width += 40;
                    bounds.Height += 40;
                    if (bounds.Contains(pos))
                    {
                        targetWidget = w;
                        break;
                    }
                }
            }
        }

        if (targetWidget != null && targetWidget != _draggedWidget)
        {
            int draggedIndex = _widgets.IndexOf(_draggedWidget);
            int targetIndex = _widgets.IndexOf(targetWidget);

            if (draggedIndex >= 0 && targetIndex >= 0)
            {
                _widgets.RemoveAt(draggedIndex);
                _widgets.Insert(targetIndex, _draggedWidget);

                // UpdateLayout is no longer strictly needed for spans because DashboardGridView handles it,
                // but we call it to ensure visual refresh.
                WidgetGridView.UpdateLayout();
                await _widgetService.SaveWidgetsAsync(_widgets.ToList());
            }
        }
        
        _draggedWidget = null;
    }

    private async void WidgetResize_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem menuItem && menuItem.DataContext is Daily.Models.WidgetModel widget)
        {
            var tag = menuItem.Tag?.ToString();
            if (tag == "1x1") { widget.ColumnSpan = 1; widget.RowSpan = 1; }
            else if (tag == "2x1") { widget.ColumnSpan = 2; widget.RowSpan = 1; }
            else if (tag == "1x2") { widget.ColumnSpan = 1; widget.RowSpan = 2; }
            else if (tag == "2x2") { widget.ColumnSpan = 2; widget.RowSpan = 2; }

            // Re-insert to force DashboardGridView to prepare the container again
            int index = _widgets.IndexOf(widget);
            if (index >= 0)
            {
                _widgets.RemoveAt(index);
                _widgets.Insert(index, widget);
                
                // Save the new layout sizes
                _ = _widgetService.SaveWidgetsAsync(_widgets.ToList());
            }
            
            await _widgetService.SaveWidgetsAsync(_widgets.ToList());
        }
    }

    
    private void Widget_Tapped(object sender, TappedRoutedEventArgs e)
    {
        // Ignore taps if they originated inside a ListView or Button (like the RSS news items)
        DependencyObject current = e.OriginalSource as DependencyObject;
        while (current != null)
        {
            if (current is ListViewItem || current is Button) return;
            current = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(current);
        }

        if (sender is FrameworkElement fe && fe.DataContext is Daily.Models.WidgetModel widget)
        {
            switch (widget.ComponentType)
            {
                case "WeatherWidget":
                    OpenDetailWindow(typeof(WeatherDetailPage));
                    break;
                case "RssFeedWidget":
                    OpenDetailWindow(typeof(RssFeedDetailPage));
                    break;
                case "FinancesWidget":
                    OpenDetailWindow(typeof(FinancesDetailPage));
                    break;
                case "HabitsWidget":
                    OpenDetailWindow(typeof(HabitsDetailPage));
                    break;
                case "HealthWidget":
                    OpenDetailWindow(typeof(HealthDetailPage));
                    break;
            }
        }
    }

    private void RssFeedWidget_ArticleTapped(object sender, Daily.Models.RssItem e)
    {
        OpenDetailWindow(typeof(RssFeedDetailPage), e);
    }
    private void OpenDetailWindow(System.Type pageType, object parameter = null)
    {
        if (_openWindows.TryGetValue(pageType, out var existingWindow))
        {
            if (parameter != null) existingWindow.NavigateTo(pageType, parameter);
            existingWindow.Activate();
            return;
        }

        var window = new DetailWindow();
        window.RestorePosition(pageType.Name);
        window.Closed += (s, ev) => { _openWindows.Remove(pageType); };
        _openWindows[pageType] = window;
        window.NavigateTo(pageType, parameter);
        // Inherit current theme
        var root = this.XamlRoot?.Content as FrameworkElement;
        var activeTheme = root?.RequestedTheme ?? ElementTheme.Default;
        if (activeTheme == ElementTheme.Default)
        {
            activeTheme = root?.ActualTheme ?? ElementTheme.Light;
        }
        window.ApplyTheme(activeTheme);
        window.Activate();
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool EnableWindow(IntPtr hWnd, bool bEnable);

    public void OpenSettings()
    {
        if (_settingsWindow != null)
        {
            _settingsWindow.Activate();
            return;
        }

        // Disable the main window so Settings behaves modally
        var mainHwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.Current.MainWindow!);
        EnableWindow(mainHwnd, false);

        _settingsWindow = new SettingsWindow();

        _settingsWindow.Closed += (s, ev) =>
        {
            _settingsWindow = null;
            // Re-enable and bring main window back to front
            EnableWindow(mainHwnd, true);
            App.Current.MainWindow!.Activate();
        };

        // Inherit current theme
        var rootSettings = this.XamlRoot?.Content as FrameworkElement;
        var activeThemeSettings = rootSettings?.RequestedTheme ?? ElementTheme.Default;
        if (activeThemeSettings == ElementTheme.Default)
        {
            activeThemeSettings = rootSettings?.ActualTheme ?? ElementTheme.Light;
        }
        _settingsWindow.ApplyTheme(activeThemeSettings);

        _settingsWindow.Activate();
    }
}

public class DashboardGridView : GridView
{
    protected override void PrepareContainerForItemOverride(DependencyObject element, object item)
    {
        base.PrepareContainerForItemOverride(element, item);
        if (item is Daily.Models.WidgetModel widget && element is GridViewItem itemContainer)
        {
            itemContainer.HorizontalContentAlignment = HorizontalAlignment.Stretch;
            itemContainer.VerticalContentAlignment = VerticalAlignment.Stretch;

            // Clamp span to the panel's current column count so widgets never overflow
            ApplySpans(itemContainer, widget);

            // Re-apply once fully in the visual tree (VariableSizedWrapGrid can drop spans on first pass)
            itemContainer.Loaded += (s, e) =>
            {
                ApplySpans(itemContainer, widget);
                (this.ItemsPanelRoot as VariableSizedWrapGrid)?.InvalidateMeasure();
            };
        }
    }

    private void ApplySpans(GridViewItem container, Daily.Models.WidgetModel widget)
    {
        int maxCols = (this.ItemsPanelRoot is VariableSizedWrapGrid p && p.MaximumRowsOrColumns > 0)
            ? p.MaximumRowsOrColumns
            : 2;
        VariableSizedWrapGrid.SetColumnSpan(container, System.Math.Min(widget.ColumnSpan, maxCols));
        VariableSizedWrapGrid.SetRowSpan(container, widget.RowSpan);
    }
}

