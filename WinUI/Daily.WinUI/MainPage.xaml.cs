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
    private Supabase.Gotrue.Interfaces.IGotrueClient<Supabase.Gotrue.User, Supabase.Gotrue.Session>.AuthEventHandler? _authStateChangedHandler;

    private readonly List<System.Threading.Tasks.Task> _loadingTasks = new();
    private readonly object _lock = new object();
    private bool _isTrackingLoads = false;
    private bool _isBriefingActive = false;

    // Smart Briefing backing states
    private DispatcherTimer? _typewriterTimer;
    private string _fullBriefingText = string.Empty;
    private int _typewriterIndex = 0;
    private string[] _briefingWords = System.Array.Empty<string>();
    private System.Threading.Tasks.Task<SmartBriefingData>? _pregeneratedBriefingTask;
    private string? _pregeneratedAccelerator;
    private string? _pregeneratedModelId;

    public MainPage()
    {
        InitializeComponent();
        Current = this;
        _authService = App.Current.Services.GetRequiredService<WinUIAuthService>();
        _widgetService = App.Current.Services.GetRequiredService<WinUIWidgetService>();
        Loaded += MainPage_Loaded;
        FadeOutBriefingStoryboard.Completed += FadeOutBriefingStoryboard_Completed;
        SizeChanged += MainPage_SizeChanged;
        Unloaded += (_, _) => 
        {
            WeatherBannerService.WeatherConditionChanged -= OnWeatherConditionChanged;
            if (_authStateChangedHandler != null)
            {
                _authService.RemoveStateChangedListener(_authStateChangedHandler);
                _authStateChangedHandler = null;
            }
            if (Current == this) Current = null;
        };
        WeatherBannerService.WeatherConditionChanged += OnWeatherConditionChanged;
        // Replay last known condition if weather already loaded before this page
        if (WeatherBannerService.LastIconCode is { } code)
            OnWeatherConditionChanged(code);

        // Listen for Auth changes so we update profile picture when session hydration completes
        _authStateChangedHandler = (sender, state) =>
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                UpdateUserUI();
            });
        };
        _authService.AddStateChangedListener(_authStateChangedHandler);
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

        // 4.1 Sync behavior events, briefing cache, and habits logs from remote (Supabase)
        try
        {
            var behaviorSvc = App.Current.Services.GetRequiredService<IBehaviorService>();
            var cacheManager = App.Current.Services.GetRequiredService<SmartBriefingCacheManager>();
            var syncService = App.Current.Services.GetRequiredService<Daily.Services.ISyncService>();
            
            // Run pulls concurrently (including Habits sync pull!)
            await Task.WhenAll(
                behaviorSvc.PullEventsAsync(),
                cacheManager.PullRemoteCacheAsync(),
                syncService.PullAsync(Daily.Services.SyncScope.Habits)
            );
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[MainPage] Remote pulls failed: {ex.Message}");
        }

        // Pre-generate Smart Briefing data in background as soon as data loading is complete
        var settingsForPreGen = SettingsService.Load();
        _pregeneratedAccelerator = settingsForPreGen.SelectedAiAccelerator ?? "Auto";
        _pregeneratedModelId = settingsForPreGen.SelectedLocalAiModel ?? "llama32_1b";
        string currentUserName = _authService.CurrentUserDisplayName ?? "Explorer";
        var cacheMgr = App.Current.Services.GetRequiredService<SmartBriefingCacheManager>();
        _pregeneratedBriefingTask = cacheMgr.GetOrGenerateBriefingAsync(currentUserName);

        if (isInitialBoot && mainWindow != null)
        {
            // 5. Ensure minimum boot time has elapsed
            await mainWindow.WaitForMinBootTimeAsync();

            // 6. Start the fade out of the window-level loading overlay concurrently with widgets entrance
            var fadeOutTask = mainWindow.FadeOutLoadingOverlayAsync();

            // 7. Trigger local widgets entrance animation concurrently
            FadeInContentStoryboard.Begin();

            // 8. Wait for the fade out to finish before collapsing the loading overlay entirely
            await fadeOutTask;
        }
        else
        {
            // 7. Trigger local widgets entrance animation
            FadeInContentStoryboard.Begin();
        }

        // 9. Show Smart Briefing if enabled on startup
        var settings = SettingsService.Load();
        if (settings.EnableSmartBriefing && isInitialBoot)
        {
            ShowSmartBriefing(isAutomatic: true);
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        _pregeneratedBriefingTask = null; // Reset cached task
        await LoadWidgetsAsync();

        // Re-trigger pre-generation in the background since data is refreshed
        var settingsForRefresh = SettingsService.Load();
        _pregeneratedAccelerator = settingsForRefresh.SelectedAiAccelerator ?? "Auto";
        _pregeneratedModelId = settingsForRefresh.SelectedLocalAiModel ?? "llama32_1b";
        string userName = _authService.CurrentUserDisplayName ?? "Explorer";
        var cacheMgr = App.Current.Services.GetRequiredService<SmartBriefingCacheManager>();
        _pregeneratedBriefingTask = cacheMgr.GetOrGenerateBriefingAsync(userName, forceRefresh: true);
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
        if (App.Current.MainWindow is MainWindow mw)
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
    public void OpenDetailWindow(System.Type pageType, object parameter = null)
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

    // ── Smart Briefing Overlay & Local AI Engine ──────────────────────────────

    public async void ShowSmartBriefing(bool isAutomatic = false)
    {
        var settings = SettingsService.Load();
        string userName = _authService.CurrentUserDisplayName ?? "Explorer";

        // If automatic startup presentation, check contextual time slot
        if (isAutomatic)
        {
            int hour = DateTime.Now.Hour;
            bool isImportantMoment = (hour >= 5 && hour < 12) ||  // Morning
                                     (hour >= 12 && hour < 15) || // Mid-Day
                                     (hour >= 17 && hour < 22);   // Evening / End of work day

            if (!isImportantMoment)
            {
                System.Diagnostics.Debug.WriteLine("[MainPage] Skipping automatic smart briefing: Not an important moment of the day.");
                return;
            }
        }

        SmartBriefingData? data = null;
        string currentAcc = settings.SelectedAiAccelerator ?? "Auto";
        string currentModelId = settings.SelectedLocalAiModel ?? "llama32_1b";
        
        if (_pregeneratedBriefingTask != null &&
            (_pregeneratedAccelerator != currentAcc || _pregeneratedModelId != currentModelId))
        {
            System.Diagnostics.Debug.WriteLine("[MainPage] Discarding pregenerated briefing because AI settings changed.");
            _pregeneratedBriefingTask = null;
        }

        var cacheManager = App.Current.Services.GetRequiredService<SmartBriefingCacheManager>();

        // For automatic show, load data first to check if cache was refreshed
        if (isAutomatic)
        {
            try
            {
                if (_pregeneratedBriefingTask != null)
                {
                    data = await _pregeneratedBriefingTask;
                    _pregeneratedBriefingTask = null;
                }
                else
                {
                    data = await cacheManager.GetOrGenerateBriefingAsync(userName);
                }
            }
            catch (System.Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MainPage] Automatic briefing load failed: {ex.Message}");
                return;
            }

            if (data == null || !data.WasRegenerated)
            {
                System.Diagnostics.Debug.WriteLine("[MainPage] Skipping automatic smart briefing: Cached narrative is unchanged.");
                return;
            }
        }

        _isBriefingActive = true;
        // Show overlay with fade-in animation
        SmartBriefingOverlay.Opacity = 0.0;
        SmartBriefingOverlay.Visibility = Visibility.Visible;
        FadeInBriefingStoryboard.Begin();

        // Update layout based on current actual width
        UpdateBriefingLayout(ActualWidth);

        // Cancel any active typewriter or download timers
        _typewriterTimer?.Stop();

        if (data == null)
        {
            BriefingLoadingPanel.Visibility = Visibility.Visible;
            RotatingLoadingIconStoryboard.Begin();
            BriefingGrid.Visibility = Visibility.Collapsed;

            try
            {
                if (_pregeneratedBriefingTask != null)
                {
                    data = await _pregeneratedBriefingTask;
                    _pregeneratedBriefingTask = null;
                }
                else
                {
                    data = await cacheManager.GetOrGenerateBriefingAsync(userName);
                }
            }
            catch (System.Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MainPage] Briefing generation failed: {ex.Message}");
                CloseBriefing_Click(this, new RoutedEventArgs());
                return;
            }
        }
        else
        {
            BriefingLoadingPanel.Visibility = Visibility.Collapsed;
            BriefingGrid.Visibility = Visibility.Visible;
        }

        if (!_isBriefingActive) return;

        // Bind Weather Card
        BriefingWeatherTempText.Text = $"{data.WeatherTemp:F0}°C";
        BriefingWeatherCondText.Text = data.WeatherCondition;
        
        // 5-day forecast columns
        if (data.WeatherForecast.Count >= 5)
        {
            ForecastDay1Text.Text = data.WeatherForecast[0].DayName.Length >= 3 ? data.WeatherForecast[0].DayName.Substring(0, 3) : data.WeatherForecast[0].DayName;
            ForecastDay1Temp.Text = $"{data.WeatherForecast[0].Temp:F0}°";
            ForecastDay1Icon.Glyph = data.WeatherForecast[0].Icon;
            ForecastDay1Icon.Foreground = GetBrushFromHex(data.WeatherForecast[0].ColorHex);

            ForecastDay2Text.Text = data.WeatherForecast[1].DayName.Length >= 3 ? data.WeatherForecast[1].DayName.Substring(0, 3) : data.WeatherForecast[1].DayName;
            ForecastDay2Temp.Text = $"{data.WeatherForecast[1].Temp:F0}°";
            ForecastDay2Icon.Glyph = data.WeatherForecast[1].Icon;
            ForecastDay2Icon.Foreground = GetBrushFromHex(data.WeatherForecast[1].ColorHex);

            ForecastDay3Text.Text = data.WeatherForecast[2].DayName.Length >= 3 ? data.WeatherForecast[2].DayName.Substring(0, 3) : data.WeatherForecast[2].DayName;
            ForecastDay3Temp.Text = $"{data.WeatherForecast[2].Temp:F0}°";
            ForecastDay3Icon.Glyph = data.WeatherForecast[2].Icon;
            ForecastDay3Icon.Foreground = GetBrushFromHex(data.WeatherForecast[2].ColorHex);

            ForecastDay4Text.Text = data.WeatherForecast[3].DayName.Length >= 3 ? data.WeatherForecast[3].DayName.Substring(0, 3) : data.WeatherForecast[3].DayName;
            ForecastDay4Temp.Text = $"{data.WeatherForecast[3].Temp:F0}°";
            ForecastDay4Icon.Glyph = data.WeatherForecast[3].Icon;
            ForecastDay4Icon.Foreground = GetBrushFromHex(data.WeatherForecast[3].ColorHex);

            ForecastDay5Text.Text = data.WeatherForecast[4].DayName.Length >= 3 ? data.WeatherForecast[4].DayName.Substring(0, 3) : data.WeatherForecast[4].DayName;
            ForecastDay5Temp.Text = $"{data.WeatherForecast[4].Temp:F0}°";
            ForecastDay5Icon.Glyph = data.WeatherForecast[4].Icon;
            ForecastDay5Icon.Foreground = GetBrushFromHex(data.WeatherForecast[4].ColorHex);
        }

        // Set advices
        WeatherAdviceText.Text = data.WeatherAdvice;
        HealthAdviceText.Text = data.HealthAdvice;
        FinancesAdviceText.Text = data.FinanceAdvice;
        HabitsAdviceText.Text = data.HabitsAdvice;

        // Bind Health Card
        BriefingStepsText.Text = data.HealthSteps.ToString("N0");
        BriefingStepsProgress.Value = data.HealthSteps;
        BriefingSleepText.Text = $"{data.HealthSleepHours:F1} hrs";
        BriefingSleepProgress.Value = data.HealthSleepHours;
        BriefingHeartRateText.Text = $"{data.HealthAvgHr} bpm";

        // Bind Finances Card
        BriefingNetWorthText.Text = data.NetWorth.ToString("C0");
        var greenBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 76, 175, 80));
        var redBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 244, 67, 54));
        var greenBgBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(51, 76, 175, 80));
        var redBgBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(51, 244, 67, 54));

        if (data.WatchlistStocks.Count >= 2)
        {
            Stock1Symbol.Text = data.WatchlistStocks[0].Symbol;
            Stock1Price.Text = data.WatchlistStocks[0].Price.ToString("F2");
            Stock1Change.Text = data.WatchlistStocks[0].FormattedChange;
            if (data.WatchlistStocks[0].IsPositive)
            {
                Stock1Badge.Background = greenBgBrush;
                Stock1Change.Foreground = greenBrush;
            }
            else
            {
                Stock1Badge.Background = redBgBrush;
                Stock1Change.Foreground = redBrush;
            }

            Stock2Symbol.Text = data.WatchlistStocks[1].Symbol;
            Stock2Price.Text = data.WatchlistStocks[1].Price.ToString("F2");
            Stock2Change.Text = data.WatchlistStocks[1].FormattedChange;
            if (data.WatchlistStocks[1].IsPositive)
            {
                Stock2Badge.Background = greenBgBrush;
                Stock2Change.Foreground = greenBrush;
            }
            else
            {
                Stock2Badge.Background = redBgBrush;
                Stock2Change.Foreground = redBrush;
            }
        }

        // Bind Habits Card
        BriefingHabitsProgress.Maximum = data.HabitsTotal;
        BriefingHabitsProgress.Value = data.HabitsCompleted;
        BriefingHabitsProgressText.Text = $"{data.HabitsCompleted}/{data.HabitsTotal}";

        // Habits dynamic checklist
        double waterProgress = data.HabitsWaterProgress;
        double waterGoal = data.HabitsWaterGoal;
        BriefingHabit1Text.Text = $"Water: {waterProgress:F0}/{waterGoal:F0} ml";
        if (waterProgress >= waterGoal && waterGoal > 0)
        {
            BriefingHabit1Icon.Glyph = "\uE73E"; // Checkmark
            BriefingHabit1Icon.Foreground = greenBrush;
            BriefingHabit1Panel.Opacity = 1.0;
        }
        else
        {
            BriefingHabit1Icon.Glyph = "\uE739"; // Circle
            BriefingHabit1Icon.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(128, 128, 128, 128));
            BriefingHabit1Panel.Opacity = 0.6;
        }

        double smokesProgress = data.HabitsSmokesProgress;
        double smokesGoal = data.HabitsSmokesGoal;
        if (smokesGoal > 0 || smokesProgress > 0)
        {
            BriefingHabit2Panel.Visibility = Visibility.Visible;
            BriefingHabit2Text.Text = $"Smokes: {smokesProgress:F0}/{smokesGoal:F0} today";
            if (smokesProgress > smokesGoal && smokesGoal > 0)
            {
                BriefingHabit2Icon.Glyph = "\uE711"; // Warning
                BriefingHabit2Icon.Foreground = redBrush;
                BriefingHabit2Panel.Opacity = 1.0;
            }
            else
            {
                BriefingHabit2Icon.Glyph = "\uE73E"; // Checkmark
                BriefingHabit2Icon.Foreground = greenBrush;
                BriefingHabit2Panel.Opacity = 1.0;
            }
        }
        else
        {
            BriefingHabit2Panel.Visibility = Visibility.Collapsed;
        }

        // Bind News recommendations control directly
        BriefingNewsWidget.Populate(data.NewsRecommendations);

        // Reset visual cards state for animation
        BriefingWeatherCard.Opacity = 0;
        WeatherCardTransform.Y = 30;
        BriefingHealthCard.Opacity = 0;
        HealthCardTransform.Y = 30;
        BriefingFinancesCard.Opacity = 0;
        FinancesCardTransform.Y = 30;
        BriefingHabitsCard.Opacity = 0;
        HabitsCardTransform.Y = 30;
        BriefingNewsCard.Opacity = 0;
        NewsCardTransform.Y = 30;

        // Hide loading panel and show briefing content grid
        BriefingLoadingPanel.Visibility = Visibility.Collapsed;
        RotatingLoadingIconStoryboard.Stop();
        BriefingGrid.Visibility = Visibility.Visible;

        // Typewriter Animation
        BriefingGreetingText.Text = data.Greeting;
        BriefingOutroText.Text = data.OutroText;
        BriefingOutroText.Opacity = 0.0; // Hide initially

        BriefingTypedText.Text = string.Empty;
        _fullBriefingText = data.BriefingText;
        _briefingWords = _fullBriefingText.Split(' ');
        _typewriterIndex = 0;

        // Speed up the typewriter animation (20ms interval instead of 50ms)
        _typewriterTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(20) };
        _typewriterTimer.Tick += (s, ev) =>
        {
            if (_typewriterIndex < _briefingWords.Length)
            {
                BriefingTypedText.Text += _briefingWords[_typewriterIndex] + " ";
                _typewriterIndex++;

                // Pulsate and glow effect for the AI Icon (slowed down for a "thinking" feel)
                try
                {
                    double sinVal = Math.Sin(_typewriterIndex * 0.12);
                    double scaleVal = 1.0 + 0.08 * sinVal;      // pulsates between 0.92 and 1.08
                    double glowScaleVal = 1.0 + 0.3 * sinVal;   // glow pulsates between 0.7 and 1.3
                    double opacityVal = 0.45 + 0.25 * sinVal;   // opacity pulsates between 0.2 and 0.7

                    IconScale.ScaleX = scaleVal;
                    IconScale.ScaleY = scaleVal;
                    GlowScale.ScaleX = glowScaleVal;
                    GlowScale.ScaleY = glowScaleVal;
                    AIIconGlow.Opacity = opacityVal;
                }
                catch { }

                double percent = (double)_typewriterIndex / _briefingWords.Length;

                // Animate visual cards in as typewriter milestones are reached
                if (percent >= 0.20 && BriefingWeatherCard.Opacity == 0)
                    FadeInWeatherStoryboard.Begin();
                if (percent >= 0.40 && BriefingHealthCard.Opacity == 0)
                    FadeInHealthStoryboard.Begin();
                if (percent >= 0.60 && BriefingFinancesCard.Opacity == 0)
                    FadeInFinancesStoryboard.Begin();
                if (percent >= 0.80 && BriefingHabitsCard.Opacity == 0)
                    FadeInHabitsStoryboard.Begin();
                if (percent >= 0.92 && BriefingNewsCard.Opacity == 0)
                    FadeInNewsStoryboard.Begin();
            }
            else
            {
                _typewriterTimer.Stop();

                // Reset AI Icon scale to resting state
                try
                {
                    IconScale.ScaleX = 1.0;
                    IconScale.ScaleY = 1.0;
                    GlowScale.ScaleX = 1.0;
                    GlowScale.ScaleY = 1.0;
                    AIIconGlow.Opacity = 0.4;
                }
                catch { }

                // Fade in sign-off text at the end
                try
                {
                    var fadeAnimation = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
                    {
                        From = 0.0,
                        To = 0.75, // Muted opacity
                        Duration = new Duration(TimeSpan.FromSeconds(0.8))
                    };
                    Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(fadeAnimation, BriefingOutroText);
                    Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(fadeAnimation, "Opacity");
                    var outroStoryboard = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
                    outroStoryboard.Children.Add(fadeAnimation);
                    outroStoryboard.Begin();
                }
                catch
                {
                    BriefingOutroText.Opacity = 0.75;
                }

                // Ensure all visual cards are shown
                if (BriefingWeatherCard.Opacity == 0) FadeInWeatherStoryboard.Begin();
                if (BriefingHealthCard.Opacity == 0) FadeInHealthStoryboard.Begin();
                if (BriefingFinancesCard.Opacity == 0) FadeInFinancesStoryboard.Begin();
                if (BriefingHabitsCard.Opacity == 0) FadeInHabitsStoryboard.Begin();
                if (BriefingNewsCard.Opacity == 0) FadeInNewsStoryboard.Begin();
            }
        };
        _typewriterTimer.Start();
    }

    private void CloseBriefing_Click(object sender, RoutedEventArgs e)
    {
        _isBriefingActive = false;
        _typewriterTimer?.Stop();
        FadeOutBriefingStoryboard.Begin();
    }

    private void FadeOutBriefingStoryboard_Completed(object? sender, object e)
    {
        SmartBriefingOverlay.Visibility = Visibility.Collapsed;
    }



    private void MainPage_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        UpdateBriefingLayout(e.NewSize.Width);
    }

    private void UpdateBriefingLayout(double width)
    {
        if (BriefingGrid == null || BriefingNarrativePanel == null || BriefingWidgetsPanel == null || 
            BriefingCardBorder == null || BriefingOuterScrollViewer == null || 
            BriefingWidgetsGrid == null || BriefingTextScrollViewer == null ||
            BriefingHeaderGrid == null || BriefingIconContainer == null || BriefingHeaderTextPanel == null ||
            BriefingGreetingText == null || BriefingIntroText == null ||
            AIIconGlow == null || SmartBriefAIIcon == null)
            return;

        if (width < 850)
        {
            // ─── Narrow / Docked Layout (Stacked Vertically) ───
            
            // 1. Enable outer ScrollViewer, disable inner ScrollViewers
            BriefingOuterScrollViewer.VerticalScrollBarVisibility = Microsoft.UI.Xaml.Controls.ScrollBarVisibility.Auto;
            BriefingOuterScrollViewer.VerticalScrollMode = Microsoft.UI.Xaml.Controls.ScrollMode.Enabled;
            
            BriefingTextScrollViewer.VerticalScrollBarVisibility = Microsoft.UI.Xaml.Controls.ScrollBarVisibility.Disabled;
            BriefingTextScrollViewer.VerticalScrollMode = Microsoft.UI.Xaml.Controls.ScrollMode.Disabled;
            
            BriefingWidgetsPanel.VerticalScrollBarVisibility = Microsoft.UI.Xaml.Controls.ScrollBarVisibility.Disabled;
            BriefingWidgetsPanel.VerticalScrollMode = Microsoft.UI.Xaml.Controls.ScrollMode.Disabled;

            // 2. Stack Narrative and Widgets Grid in BriefingGrid (using Auto height for both rows)
            if (BriefingGrid.ColumnDefinitions.Count > 1)
            {
                BriefingGrid.ColumnDefinitions.Clear();
                BriefingGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            }
            
            BriefingGrid.RowDefinitions.Clear();
            BriefingGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            BriefingGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            
            Grid.SetColumn(BriefingNarrativePanel, 0);
            Grid.SetRow(BriefingNarrativePanel, 0);
            BriefingNarrativePanel.Margin = new Thickness(0, 0, 0, 24);
            
            Grid.SetColumn(BriefingWidgetsPanel, 0);
            Grid.SetRow(BriefingWidgetsPanel, 1);

            // 3. Stack and Center the Greeting Header elements vertically to fit narrow sidebars
            if (BriefingHeaderGrid.ColumnDefinitions.Count > 1)
            {
                BriefingHeaderGrid.ColumnDefinitions.Clear();
                BriefingHeaderGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            }
            
            BriefingHeaderGrid.RowDefinitions.Clear();
            BriefingHeaderGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            BriefingHeaderGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Grid.SetColumn(BriefingIconContainer, 0);
            Grid.SetRow(BriefingIconContainer, 0);
            Grid.SetColumn(BriefingHeaderTextPanel, 0);
            Grid.SetRow(BriefingHeaderTextPanel, 1);

            BriefingIconContainer.Width = 64;
            BriefingIconContainer.Height = 64;
            BriefingIconContainer.Margin = new Thickness(0, 0, 0, 12);
            BriefingIconContainer.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Center;

            AIIconGlow.Width = 44;
            AIIconGlow.Height = 44;
            SmartBriefAIIcon.Width = 44;
            SmartBriefAIIcon.Height = 44;

            BriefingHeaderTextPanel.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Center;
            
            BriefingGreetingText.FontSize = 20;
            BriefingGreetingText.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Center;
            
            BriefingIntroText.FontSize = 12;
            BriefingIntroText.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Center;
            BriefingIntroText.TextAlignment = Microsoft.UI.Xaml.TextAlignment.Center;

            // 4. Re-layout widgets inside BriefingWidgetsGrid to stack in a single column
            BriefingWidgetsGrid.ColumnDefinitions.Clear();
            BriefingWidgetsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            BriefingWidgetsGrid.RowDefinitions.Clear();
            for (int i = 0; i < 5; i++)
            {
                BriefingWidgetsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            }

            Grid.SetRow(BriefingWeatherCard, 0);
            Grid.SetColumn(BriefingWeatherCard, 0);
            Grid.SetColumnSpan(BriefingWeatherCard, 1);

            Grid.SetRow(BriefingHealthCard, 1);
            Grid.SetColumn(BriefingHealthCard, 0);
            Grid.SetColumnSpan(BriefingHealthCard, 1);

            Grid.SetRow(BriefingFinancesCard, 2);
            Grid.SetColumn(BriefingFinancesCard, 0);
            Grid.SetColumnSpan(BriefingFinancesCard, 1);

            Grid.SetRow(BriefingHabitsCard, 3);
            Grid.SetColumn(BriefingHabitsCard, 0);
            Grid.SetColumnSpan(BriefingHabitsCard, 1);

            Grid.SetRow(BriefingNewsCard, 4);
            Grid.SetColumn(BriefingNewsCard, 0);
            Grid.SetColumnSpan(BriefingNewsCard, 1);

            // 5. Tighten outer margins and paddings for small viewport space efficiency
            BriefingCardBorder.Margin = new Thickness(24);
            BriefingCardBorder.Padding = new Thickness(16);
            BriefingCardBorder.MaxWidth = double.PositiveInfinity;
            BriefingCardBorder.MaxHeight = double.PositiveInfinity;
        }
        else
        {
            // ─── Wide Layout (Side-by-Side) ───
            
            // 1. Disable outer ScrollViewer, enable inner ScrollViewers for independent scroll areas
            BriefingOuterScrollViewer.VerticalScrollBarVisibility = Microsoft.UI.Xaml.Controls.ScrollBarVisibility.Disabled;
            BriefingOuterScrollViewer.VerticalScrollMode = Microsoft.UI.Xaml.Controls.ScrollMode.Disabled;
            
            BriefingTextScrollViewer.VerticalScrollBarVisibility = Microsoft.UI.Xaml.Controls.ScrollBarVisibility.Auto;
            BriefingTextScrollViewer.VerticalScrollMode = Microsoft.UI.Xaml.Controls.ScrollMode.Auto;
            
            BriefingWidgetsPanel.VerticalScrollBarVisibility = Microsoft.UI.Xaml.Controls.ScrollBarVisibility.Auto;
            BriefingWidgetsPanel.VerticalScrollMode = Microsoft.UI.Xaml.Controls.ScrollMode.Auto;

            // 2. Put Narrative (Col 0) and Widgets (Col 1) side-by-side
            if (BriefingGrid.ColumnDefinitions.Count < 2)
            {
                BriefingGrid.ColumnDefinitions.Clear();
                BriefingGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star) });
                BriefingGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
            }
            
            BriefingGrid.RowDefinitions.Clear();
            
            Grid.SetColumn(BriefingNarrativePanel, 0);
            Grid.SetRow(BriefingNarrativePanel, 0);
            BriefingNarrativePanel.Margin = new Thickness(0, 0, 24, 0);
            
            Grid.SetColumn(BriefingWidgetsPanel, 1);
            Grid.SetRow(BriefingWidgetsPanel, 0);

            // 3. Restore Wide Greeting Header Layout (Side-by-Side)
            if (BriefingHeaderGrid.ColumnDefinitions.Count < 2)
            {
                BriefingHeaderGrid.ColumnDefinitions.Clear();
                BriefingHeaderGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Auto) });
                BriefingHeaderGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            }
            
            BriefingHeaderGrid.RowDefinitions.Clear();

            Grid.SetColumn(BriefingIconContainer, 0);
            Grid.SetRow(BriefingIconContainer, 0);
            Grid.SetColumn(BriefingHeaderTextPanel, 1);
            Grid.SetRow(BriefingHeaderTextPanel, 0);

            BriefingIconContainer.Width = 96;
            BriefingIconContainer.Height = 96;
            BriefingIconContainer.Margin = new Thickness(0, 0, 16, 0);
            BriefingIconContainer.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Left;

            AIIconGlow.Width = 64;
            AIIconGlow.Height = 64;
            SmartBriefAIIcon.Width = 64;
            SmartBriefAIIcon.Height = 64;

            BriefingHeaderTextPanel.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Left;
            
            BriefingGreetingText.FontSize = 28;
            BriefingGreetingText.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Left;
            
            BriefingIntroText.FontSize = 14;
            BriefingIntroText.HorizontalAlignment = Microsoft.UI.Xaml.HorizontalAlignment.Left;
            BriefingIntroText.TextAlignment = Microsoft.UI.Xaml.TextAlignment.Left;

            // 4. Reset widgets inside BriefingWidgetsGrid to 2-column layout
            BriefingWidgetsGrid.ColumnDefinitions.Clear();
            BriefingWidgetsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            BriefingWidgetsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            BriefingWidgetsGrid.RowDefinitions.Clear();
            BriefingWidgetsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            BriefingWidgetsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            BriefingWidgetsGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            Grid.SetRow(BriefingWeatherCard, 0);
            Grid.SetColumn(BriefingWeatherCard, 0);
            Grid.SetColumnSpan(BriefingWeatherCard, 1);

            Grid.SetRow(BriefingHealthCard, 0);
            Grid.SetColumn(BriefingHealthCard, 1);
            Grid.SetColumnSpan(BriefingHealthCard, 1);

            Grid.SetRow(BriefingFinancesCard, 1);
            Grid.SetColumn(BriefingFinancesCard, 0);
            Grid.SetColumnSpan(BriefingFinancesCard, 1);

            Grid.SetRow(BriefingHabitsCard, 1);
            Grid.SetColumn(BriefingHabitsCard, 1);
            Grid.SetColumnSpan(BriefingHabitsCard, 1);

            Grid.SetRow(BriefingNewsCard, 2);
            Grid.SetColumn(BriefingNewsCard, 0);
            Grid.SetColumnSpan(BriefingNewsCard, 2);

            // 5. Restore spacious margins and paddings
            BriefingCardBorder.Margin = new Thickness(24);
            BriefingCardBorder.Padding = new Thickness(32);
            BriefingCardBorder.MaxWidth = 1400;
            BriefingCardBorder.MaxHeight = 900;
        }
    }

    private static Microsoft.UI.Xaml.Media.SolidColorBrush GetBrushFromHex(string hex)
    {
        if (string.IsNullOrEmpty(hex)) return new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.LightGray);
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
        return new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(a, r, g, b));
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

