using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Daily_WinUI.Services;
using Windows.Graphics;
using System.Runtime.InteropServices;
using System.IO;
using System.Diagnostics;
using H.NotifyIcon;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Daily_WinUI;

public sealed partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private DispatcherTimer? _dateTimer;
    private Windows.UI.ViewManagement.UISettings? _uiSettings;
    private bool _isExiting = false;
    private readonly System.Threading.Tasks.Task _minBootTimeTask;

    public MainWindow()
    {
        InitializeComponent();
        _settings = SettingsService.Load();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Title = "DayOne";
        ConfigureStartupWindow();

        StartDateClock();

        RootFrame.Navigated += RootFrame_Navigated;

        var persistence = new Daily_WinUI.Services.WinUISessionPersistence();
        bool hasSession = persistence.LoadSession() != null;

        if (hasSession)
        {
            LoadingOverlay.Visibility = Visibility.Visible;
            _minBootTimeTask = System.Threading.Tasks.Task.Delay(1200);
            LoadingStoryboard.Begin();
            _ = NavigateAfterHydrationAsync();
        }
        else
        {
            LoadingOverlay.Visibility = Visibility.Collapsed;
            RootFrame.Opacity = 1.0;
            _minBootTimeTask = System.Threading.Tasks.Task.CompletedTask;
            RootFrame.Navigate(typeof(Views.LoginPage));
        }

        AppWindow.Changed += AppWindow_Changed;
        Closed += MainWindow_Closed;
        AppWindow.Closing += AppWindow_Closing;

        InitializeTaskbarIcon();
        SetupThemeWatcher();

        if (this.Content is UIElement rootContent)
        {
            rootContent.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler(OnPointerPressed), true);
        }
    }

    private void OnPointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (this.Content is UIElement root)
        {
            Daily_WinUI.Helpers.NavigationHelper.HandleMouseNavigation(root, e);
        }
    }

    // ── Title bar user state ──────────────────────────────────────────────────

    /// <summary>Called by MainPage after auth state changes to update title bar profile.</summary>
    public void UpdateTitleBarUser(string email, string displayName, string? avatarUrl, bool isAuthenticated)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            TitleBarUserAvatar.DisplayName = isAuthenticated ? (displayName ?? "U") : "?";
            TitleBarUserAvatar.ProfilePicture = null;
            if (isAuthenticated && !string.IsNullOrEmpty(avatarUrl))
            {
                try
                {
                    TitleBarUserAvatar.ProfilePicture = new BitmapImage(new System.Uri(avatarUrl));
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[MainWindow] Failed to load avatar image: {ex.Message}");
                }
            }

            TitleBarAuthItem.Text = isAuthenticated ? "Sign Out" : "Sign In";
            TitleBarAuthIcon.Glyph = isAuthenticated ? "\uF3B1" : "\uE77B"; // sign-out : person
            TitleBarUserEmailText.Text = isAuthenticated ? (email ?? "Signed in") : "Not signed in";
        });
    }

    /// <summary>Called by MainPage after a theme toggle to sync the title bar button icon/text.</summary>
    public void UpdateThemeIcon(bool isDark)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            TitleBarThemeIcon.Glyph = isDark ? "\uE708" : "\uE706"; // moon : sun
        });
    }

    // ── Date clock ────────────────────────────────────────────────────────────

    private void StartDateClock()
    {
        UpdateDateText();
        _dateTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        _dateTimer.Tick += (_, _) => UpdateDateText();
        _dateTimer.Start();
    }

    private void UpdateDateText()
    {
        TitleBarDateText.Text = DateTime.Now.ToString("dddd, MMMM d");
    }

    // ── Theme toggle handler ──────────────────────────────────────────────────

    private void TitleBarRefresh_Click(object sender, RoutedEventArgs e)
    {
        if (RootFrame.Content is MainPage mainPage)
            mainPage.TriggerRefresh();
    }

    private void TitleBarBriefing_Click(object sender, RoutedEventArgs e)
    {
        if (RootFrame.Content is MainPage mainPage)
            mainPage.ShowSmartBriefing();
    }

    internal void TitleBarTheme_Click(object sender, RoutedEventArgs e)
    {
        ToggleAppTheme();
    }

    // ── Auth flyout handler (Sign In / Sign Out) ─────────────────────────────

    private async void TitleBarAuth_Click(object sender, RoutedEventArgs e)
    {
        if (RootFrame.Content is MainPage mainPage)
        {
            // Authenticated → sign out
            await mainPage.HandleSignOutAsync();
        }
        else
        {
            // Not authenticated → navigate to login
            RootFrame.Navigate(typeof(Views.LoginPage));
        }
    }

    // ── Settings button handler ───────────────────────────────────────────────

    internal void TitleBarSettings_Click(object sender, RoutedEventArgs e)
    {
        if (RootFrame.Content is MainPage mainPage)
            mainPage.OpenSettings();
    }

    // ── Navigation after auth hydration ──────────────────────────────────────

    public bool IsLoadingOverlayVisible => LoadingOverlay.Visibility == Visibility.Visible;

    public async System.Threading.Tasks.Task WaitForMinBootTimeAsync()
    {
        await _minBootTimeTask;
    }

    public System.Threading.Tasks.Task FadeOutLoadingOverlayAsync()
    {
        var tcs = new System.Threading.Tasks.TaskCompletionSource();
        bool shouldShowTitleBar = RootFrame.Content is MainPage;

        FadeOutStoryboard.Completed += (s, e) =>
        {
            LoadingOverlay.Visibility = Visibility.Collapsed;
            LoadingStoryboard.Stop();
            if (shouldShowTitleBar)
            {
                AppTitleBar.Opacity = 1.0;
                AppTitleBar.IsHitTestVisible = true;
            }
            else
            {
                AppTitleBar.Opacity = 0.0;
                AppTitleBar.IsHitTestVisible = false;
            }
            tcs.SetResult();
        };

        if (shouldShowTitleBar)
        {
            var titleBarAnimation = new Microsoft.UI.Xaml.Media.Animation.DoubleAnimation
            {
                From = 0.0,
                To = 1.0,
                Duration = new Duration(TimeSpan.FromSeconds(0.7)),
                EasingFunction = new Microsoft.UI.Xaml.Media.Animation.CubicEase { EasingMode = Microsoft.UI.Xaml.Media.Animation.EasingMode.EaseOut }
            };
            Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTarget(titleBarAnimation, AppTitleBar);
            Microsoft.UI.Xaml.Media.Animation.Storyboard.SetTargetProperty(titleBarAnimation, "Opacity");

            var tempStoryboard = new Microsoft.UI.Xaml.Media.Animation.Storyboard();
            tempStoryboard.Children.Add(titleBarAnimation);
            tempStoryboard.Begin();
        }
        else
        {
            AppTitleBar.Opacity = 0.0;
            AppTitleBar.IsHitTestVisible = false;
        }

        FadeOutStoryboard.Begin();
        return tcs.Task;
    }

    private async Task NavigateAfterHydrationAsync()
    {
        await App.Current.InitializationTask;

        var authService = Microsoft.Extensions.DependencyInjection.ServiceProviderServiceExtensions
            .GetRequiredService<WinUIAuthService>(App.Current.Services);

        DispatcherQueue.TryEnqueue(async () =>
        {
            UpdateAppThemeFromSystem();

            if (authService.IsAuthenticated)
            {
                RootFrame.Navigate(typeof(MainPage));
            }
            else
            {
                RootFrame.Navigate(typeof(Views.LoginPage));
                await FadeOutLoadingOverlayAsync();
            }
        });
    }

    private void RootFrame_Navigated(object sender, Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        if (e.SourcePageType == typeof(MainPage))
        {
            if (LoadingOverlay.Visibility != Visibility.Visible)
            {
                AppTitleBar.Opacity = 1.0;
                AppTitleBar.IsHitTestVisible = true;
            }
        }
        else if (e.SourcePageType == typeof(Views.LoginPage))
        {
            AppTitleBar.Opacity = 0.0;
            AppTitleBar.IsHitTestVisible = false;
        }
    }

    // ── Window management ─────────────────────────────────────────────────────

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    private const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    private (int left, int top, int right, int bottom) GetWindowMargins()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        if (GetWindowRect(hwnd, out RECT windowRect) &&
            DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT frameRect, Marshal.SizeOf(typeof(RECT))) == 0)
        {
            int left = frameRect.Left - windowRect.Left;
            int top = frameRect.Top - windowRect.Top;
            int right = windowRect.Right - frameRect.Right;
            int bottom = windowRect.Bottom - frameRect.Bottom;
            return (left, top, right, bottom);
        }
        return (7, 0, 7, 7); // Default fallback margins for Windows 10/11 standard borders
    }

    private void ConfigureStartupWindow()
    {
        if (AppWindow.Presenter is OverlappedPresenter overlappedPresenter)
        {
            overlappedPresenter.IsResizable = true;
            overlappedPresenter.IsMaximizable = true;
            overlappedPresenter.IsMinimizable = true;
        }

        // Restore saved position/size if available
        if (_settings.HasWindowPosition && _settings.WindowWidth > 0 && _settings.WindowHeight > 0)
        {
            AppWindow.MoveAndResize(new RectInt32(_settings.WindowX, _settings.WindowY, _settings.WindowWidth, _settings.WindowHeight));
            return;
        }

        // Default: Copilot-style — wide, lower-centre, floating above the taskbar.
        // Measured on this machine: 1380×790 logical px, centred horizontally, bottom-aligned to work area.
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        var hwnd2 = WinRT.Interop.WindowNative.GetWindowHandle(this);
        double scale2 = GetDpiForWindow(hwnd2) / 96.0;

        int width  = Math.Min((int)(1380 * scale2), workArea.Width);
        int height = Math.Min((int)(790  * scale2), workArea.Height);

        // Horizontally centred, vertically bottom-aligned (leaves taskbar gap via workArea)
        int x = workArea.X + (workArea.Width  - width)  / 2;
        int y = workArea.Y +  workArea.Height - height;

        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidPositionChange && !args.DidSizeChange) return;

        // Enforce minimum window size (400×400 logical px, converted to physical)
        double scale = this.Content?.XamlRoot?.RasterizationScale ?? 1.0;
        int minWidthPx = (int)(400 * scale);
        int minHeightPx = (int)(400 * scale);
        var size = sender.Size;
        if (size.Width < minWidthPx || size.Height < minHeightPx)
        {
            sender.ResizeClient(new SizeInt32(
                Math.Max(size.Width,  minWidthPx),
                Math.Max(size.Height, minHeightPx)));
            return; // ResizeClient fires another Changed — skip saving on the clamped event
        }

        var bounds = sender.Position;
        _settings.WindowX = bounds.X;
        _settings.WindowY = bounds.Y;
        _settings.WindowWidth = size.Width;
        _settings.WindowHeight = size.Height;
        _settings.HasWindowPosition = true;
    }

    private void AppTitleBar_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (AppWindow.TitleBar == null) return;
        double scale = this.Content?.XamlRoot?.RasterizationScale ?? 1.0;
        if (scale <= 0) return;

        // Snap our grid height to exactly match the OS caption-button height
        double captionHeight = AppWindow.TitleBar.Height / scale;
        AppTitleBar.Height = captionHeight;

        // Keep the spacer column wide enough to clear the system buttons
        if (RightPaddingColumn != null)
            RightPaddingColumn.Width = new GridLength(AppWindow.TitleBar.RightInset / scale);

        // Adjust title bar elements dynamically when resized below 640 logical pixels
        double width = e.NewSize.Width;
        if (width < 640)
        {
            if (TitleBarDateText != null)
                TitleBarDateText.Visibility = Visibility.Collapsed;
            if (TitleBarUserEmailText != null)
                TitleBarUserEmailText.Visibility = Visibility.Collapsed;
        }
        else
        {
            if (TitleBarDateText != null)
                TitleBarDateText.Visibility = Visibility.Visible;
            if (TitleBarUserEmailText != null)
                TitleBarUserEmailText.Visibility = Visibility.Visible;
        }
    }

    private void DockNormal_Click(object sender, RoutedEventArgs e)
    {
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        double scale = GetDpiForWindow(hwnd) / 96.0;

        int targetWidth = Math.Min((int)(1380 * scale), workArea.Width);
        int targetHeight = Math.Min((int)(790 * scale), workArea.Height);

        var margins = GetWindowMargins();

        int x = workArea.X + (workArea.Width - targetWidth) / 2 - margins.left;
        int y = workArea.Y + workArea.Height - targetHeight - margins.top;
        int width = targetWidth + margins.left + margins.right;
        int height = targetHeight + margins.top + margins.bottom;

        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private void DockLeft_Click(object sender, RoutedEventArgs e)
    {
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        double scale = GetDpiForWindow(hwnd) / 96.0;

        int targetWidth = Math.Min((int)(480 * scale), workArea.Width);
        int targetHeight = workArea.Height;

        var margins = GetWindowMargins();

        int x = workArea.X - margins.left;
        int y = workArea.Y - margins.top;
        int width = targetWidth + margins.left + margins.right;
        int height = targetHeight + margins.top + margins.bottom;

        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private void DockRight_Click(object sender, RoutedEventArgs e)
    {
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        double scale = GetDpiForWindow(hwnd) / 96.0;

        int targetWidth = Math.Min((int)(480 * scale), workArea.Width);
        int targetHeight = workArea.Height;

        var margins = GetWindowMargins();

        int x = workArea.X + workArea.Width - targetWidth - margins.left;
        int y = workArea.Y - margins.top;
        int width = targetWidth + margins.left + margins.right;
        int height = targetHeight + margins.top + margins.bottom;

        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private void AppWindow_Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_isExiting)
        {
            return;
        }

        var settings = SettingsService.Load();
        if (settings.CloseToTray)
        {
            args.Cancel = true;
            sender.Hide();
        }
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _dateTimer?.Stop();
        SettingsService.Save(_settings);
        TrayIcon?.Dispose();
    }

    private void LogTray(string message)
    {
        string logLine = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}{Environment.NewLine}";
        System.Diagnostics.Debug.WriteLine(message);
        try
        {
            string path = System.IO.Path.Combine(System.AppContext.BaseDirectory, "tray_icon_debug.log");
            System.IO.File.AppendAllText(path, logLine);
        }
        catch { }
    }

    private void InitializeTaskbarIcon()
    {
        LogTray("[TrayIcon] Initializing TaskbarIcon...");
        try
        {
            if (TrayIcon != null)
            {
                TrayIcon.ToolTipText = "DayOne";
                TrayIcon.ContextMenuMode = H.NotifyIcon.ContextMenuMode.SecondWindow;
                TrayIcon.MenuActivation = H.NotifyIcon.Core.PopupActivationMode.RightClick;
                TrayIcon.LeftClickCommand = new RelayCommand(() =>
                {
                    LogTray("[TrayIcon] LeftClickCommand invoked.");
                    ShowAndActivate();
                });
                TrayIcon.DoubleClickCommand = new RelayCommand(() =>
                {
                    LogTray("[TrayIcon] DoubleClickCommand invoked.");
                    ShowAndActivate();
                });
                UpdateTrayIcon();
                LogTray("[TrayIcon] TaskbarIcon properties set and initialized successfully.");
            }
            else
            {
                LogTray("[TrayIcon] ERROR: TrayIcon is null in InitializeTaskbarIcon.");
            }
        }
        catch (Exception ex)
        {
            LogTray($"[TrayIcon] ERROR initializing TaskbarIcon: {ex}");
        }
    }

    private void TrayShow_Click(object sender, RoutedEventArgs e)
    {
        LogTray("[TrayIcon] TrayShow_Click invoked.");
        ShowAndActivate();
    }

    private void TrayExit_Click(object sender, RoutedEventArgs e)
    {
        LogTray("[TrayIcon] TrayExit_Click invoked.");
        ExitApp();
    }

    private void SetupThemeWatcher()
    {
        try
        {
            _uiSettings = new Windows.UI.ViewManagement.UISettings();
            _uiSettings.ColorValuesChanged += (sender, args) =>
            {
                LogTray("[TrayIcon] System theme color values changed.");
                DispatcherQueue.TryEnqueue(() =>
                {
                    UpdateTrayIcon();
                    UpdateAppThemeFromSystem();
                });
            };
        }
        catch (Exception ex)
        {
            LogTray($"[TrayIcon] ERROR setting up theme watcher: {ex}");
        }
    }

    public void UpdateAppThemeFromSystem()
    {
        try
        {
            bool isLightTheme = IsAppsUseLightTheme();
            var targetTheme = isLightTheme ? ElementTheme.Light : ElementTheme.Dark;
            LogTray($"[TrayIcon] Updating App Theme from System: {targetTheme}");
            
            if (this.Content is FrameworkElement root)
            {
                root.RequestedTheme = targetTheme;
            }

            UpdateThemeIcon(isDark: !isLightTheme);

            if (RootFrame.Content is MainPage mainPage)
            {
                mainPage.PropagateThemeToSubWindows(targetTheme);
            }
        }
        catch (Exception ex)
        {
            LogTray($"[TrayIcon] ERROR updating App theme from system: {ex}");
        }
    }

    public void ToggleAppTheme()
    {
        try
        {
            if (this.Content is FrameworkElement root)
            {
                var currentTheme = root.RequestedTheme;
                if (currentTheme == ElementTheme.Default)
                {
                    currentTheme = root.ActualTheme;
                }

                var newTheme = currentTheme == ElementTheme.Dark ? ElementTheme.Light : ElementTheme.Dark;
                LogTray($"[TrayIcon] Toggling App Theme manually to: {newTheme}");
                root.RequestedTheme = newTheme;

                UpdateThemeIcon(isDark: newTheme == ElementTheme.Dark);

                if (RootFrame.Content is MainPage mainPage)
                {
                    mainPage.PropagateThemeToSubWindows(newTheme);
                }
            }
        }
        catch (Exception ex)
        {
            LogTray($"[TrayIcon] ERROR toggling App theme: {ex}");
        }
    }

    private void UpdateTrayIcon()
    {
        if (TrayIcon == null)
        {
            LogTray("[TrayIcon] UpdateTrayIcon called but TrayIcon is null.");
            return;
        }

        bool isLightTheme = IsSystemUsesLightTheme();
        string relativePath = isLightTheme 
            ? "Assets/TrayIconLightTheme.ico" 
            : "Assets/TrayIconDarkTheme.ico";
        
        try
        {
            string absolutePath = System.IO.Path.Combine(System.AppContext.BaseDirectory, relativePath);
            LogTray($"[TrayIcon] Setting Icon using path: {absolutePath}");
            if (System.IO.File.Exists(absolutePath))
            {
                var oldIcon = TrayIcon.Icon;
                TrayIcon.Icon = new System.Drawing.Icon(absolutePath);
                oldIcon?.Dispose();
                LogTray("[TrayIcon] Successfully loaded and set system tray Icon using System.Drawing.Icon.");
            }
            else
            {
                LogTray($"[TrayIcon] WARNING: File does not exist at {absolutePath}.");
            }
        }
        catch (Exception ex)
        {
            LogTray($"[TrayIcon] Exception setting Icon: {ex}");
        }
    }

    private bool IsSystemUsesLightTheme()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("SystemUsesLightTheme");
            return value is int i && i == 1;
        }
        catch
        {
            return false;
        }
    }

    private bool IsAppsUseLightTheme()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            return value is int i && i == 1;
        }
        catch
        {
            return true;
        }
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public void ShowAndActivate()
    {
        AppWindow.Show();
        this.Activate();

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        if (hwnd != IntPtr.Zero)
        {
            ShowWindow(hwnd, 9); // SW_RESTORE
            SetForegroundWindow(hwnd);
        }
    }

    private void ExitApp()
    {
        _isExiting = true;
        this.Close();
    }

    private class RelayCommand : System.Windows.Input.ICommand
    {
        private readonly Action _execute;

        public RelayCommand(Action execute)
        {
            _execute = execute ?? throw new ArgumentNullException(nameof(execute));
        }

        public bool CanExecute(object? parameter) => true;

        public void Execute(object? parameter) => _execute();

        public event EventHandler? CanExecuteChanged;
    }
}

