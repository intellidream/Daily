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
using Microsoft.Extensions.DependencyInjection;

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
    private string? _loadedAvatarUrl;

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

        RootFrame.CacheSize = 10;
        RootFrame.Navigated += RootFrame_Navigated;

        LoadingOverlay.Visibility = Visibility.Visible;
        _minBootTimeTask = System.Threading.Tasks.Task.CompletedTask;
        LoadingStoryboard.Begin();
        App.LogDiagnostic("MainWindow ctor: calling NavigateAfterHydrationAsync");
        _ = NavigateAfterHydrationAsync();

        AppWindow.Changed += AppWindow_Changed;
        Closed += MainWindow_Closed;
        AppWindow.Closing += AppWindow_Closing;

        InitializeTaskbarIcon();
        SetupThemeWatcher();

        if (this.Content is UIElement rootContent)
        {
            rootContent.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler(OnPointerPressed), true);
        }

        UpdateTitleBarElementsVisibility();
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
    public void UpdateTitleBarUser(string userFirstName, string displayName, string? avatarUrl, bool isAuthenticated)
    {
        DispatcherQueue.TryEnqueue(async () =>
        {
            TitleBarUserAvatar.DisplayName = isAuthenticated ? (displayName ?? "U") : "?";
            TitleBarAuthItem.Text = isAuthenticated ? "Sign Out" : "Sign In";
            TitleBarAuthIcon.Glyph = isAuthenticated ? "\uF3B1" : "\uE77B"; // sign-out : person
            TitleBarUserEmailText.Text = isAuthenticated ? $"Hi, {userFirstName}!" : "Not signed in";

            if (!isAuthenticated || string.IsNullOrEmpty(avatarUrl))
            {
                TitleBarUserAvatar.ProfilePicture = null;
                _loadedAvatarUrl = null;
                return;
            }

            if (_loadedAvatarUrl == avatarUrl)
            {
                // Already loading or loaded this avatar URL, do not reload
                return;
            }

            _loadedAvatarUrl = avatarUrl;

            // Set to null first to clear previous picture while we load the new one
            TitleBarUserAvatar.ProfilePicture = null;

            try
            {
                // 1. Check if we have a locally cached file of this avatar URL
                var cacheFolder = Path.Combine(Windows.Storage.ApplicationData.Current.LocalFolder.Path, "AvatarCache");
                if (!Directory.Exists(cacheFolder))
                {
                    Directory.CreateDirectory(cacheFolder);
                }

                // Create a deterministic filename based on the hash of the URL
                var safeFileName = GetMd5Hash(avatarUrl) + ".png";
                var localFilePath = Path.Combine(cacheFolder, safeFileName);

                if (File.Exists(localFilePath))
                {
                    // Load from local file
                    await SetAvatarFromFileAsync(localFilePath);
                    return;
                }

                // 2. Download from web and save to local file
                var downloadedPath = await DownloadAvatarAsync(avatarUrl, localFilePath);
                if (downloadedPath != null)
                {
                    await SetAvatarFromFileAsync(downloadedPath);
                }
                else
                {
                    // Fallback to web URI if download failed but we can still try to let WinUI load it
                    TitleBarUserAvatar.ProfilePicture = new BitmapImage(new System.Uri(avatarUrl));
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MainWindow] Error loading/caching avatar: {ex.Message}");
                // Fallback
                try
                {
                    TitleBarUserAvatar.ProfilePicture = new BitmapImage(new System.Uri(avatarUrl));
                }
                catch
                {
                    // Ignore
                }
            }
        });
    }

    private async System.Threading.Tasks.Task<string?> DownloadAvatarAsync(string url, string destinationPath)
    {
        try
        {
            using (var httpClient = new System.Net.Http.HttpClient())
            {
                // Add user agent so Google doesn't block the request
                httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
                
                var bytes = await httpClient.GetByteArrayAsync(url);
                await File.WriteAllBytesAsync(destinationPath, bytes);
                return destinationPath;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[MainWindow] Failed to download avatar from {url}: {ex.Message}");
            return null;
        }
    }

    private async System.Threading.Tasks.Task SetAvatarFromFileAsync(string localPath)
    {
        try
        {
            var storageFile = await Windows.Storage.StorageFile.GetFileFromPathAsync(localPath);
            using (var randomAccessStream = await storageFile.OpenAsync(Windows.Storage.FileAccessMode.Read))
            {
                var bitmapImage = new BitmapImage();
                await bitmapImage.SetSourceAsync(randomAccessStream);
                TitleBarUserAvatar.ProfilePicture = bitmapImage;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[MainWindow] Failed to set avatar from file: {ex.Message}");
            // Delete corrupt file if any
            try { File.Delete(localPath); } catch {}
            throw;
        }
    }

    private string GetMd5Hash(string input)
    {
        using (var md5 = System.Security.Cryptography.MD5.Create())
        {
            var inputBytes = System.Text.Encoding.ASCII.GetBytes(input);
            var hashBytes = md5.ComputeHash(inputBytes);
            return Convert.ToHexString(hashBytes);
        }
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

    private async void TitleBarRefresh_Click(object sender, RoutedEventArgs e)
    {
        await TriggerCurrentViewRefreshAsync();
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

    public void Navigate(Type pageType)
    {
        RootFrame.Navigate(pageType);
    }

    public bool IsLoadingOverlayVisible => LoadingOverlay.Visibility == Visibility.Visible;

    public async System.Threading.Tasks.Task WaitForMinBootTimeAsync()
    {
        await _minBootTimeTask;
    }

    public void DismissLoadingOverlay()
    {
        App.LogDiagnostic($"DismissLoadingOverlay called. Currently visible={LoadingOverlay.Visibility}");
        try
        {
            LoadingStoryboard.Stop();
            FadeOutStoryboard.Stop();
        }
        catch { }

        LoadingOverlay.Visibility = Visibility.Collapsed;
        LoadingOverlay.Opacity = 0.0;

        bool isLoginPage = (RootFrame.Content is Views.LoginPage);

        if (!isLoginPage)
        {
            AppTitleBar.Opacity = 1.0;
            AppTitleBar.IsHitTestVisible = true;
            NavCapsule.Visibility = (AppSidebar.Visibility == Visibility.Visible || _currentTabIndex == 9) ? Visibility.Collapsed : Visibility.Visible;
        }
        else
        {
            AppTitleBar.Opacity = 0.0;
            AppTitleBar.IsHitTestVisible = false;
            NavCapsule.Visibility = Visibility.Collapsed;
            AppSidebar.Visibility = Visibility.Collapsed;
        }
        App.LogDiagnostic($"DismissLoadingOverlay completed. Visibility now={LoadingOverlay.Visibility}");
    }

    public async System.Threading.Tasks.Task FadeOutLoadingOverlayAsync()
    {
        App.LogDiagnostic("FadeOutLoadingOverlayAsync entered");
        bool shouldShowTitleBar = !(RootFrame.Content is Views.LoginPage);

        try
        {
            // Stop the bouncing loading storyboard first so it doesn't contend composition
            LoadingStoryboard.Stop();

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

            FadeOutStoryboard.Begin();

            // Bounded wait matching the 0.7s storyboard duration
            await System.Threading.Tasks.Task.Delay(750);
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"FadeOutLoadingOverlayAsync error: {ex}");
            System.Diagnostics.Debug.WriteLine($"[MainWindow] FadeOutLoadingOverlayAsync error: {ex.Message}");
        }
        finally
        {
            DismissLoadingOverlay();
        }
    }

    private async Task NavigateAfterHydrationAsync()
    {
        App.LogDiagnostic("NavigateAfterHydrationAsync started");
        try
        {
            // Wait for session and user preferences hydration to finish (bounded to 6 seconds) so saved session and dashboard layout are respected
            await Task.WhenAny(
                Task.WhenAll(App.Current.SessionRestoredTask, App.Current.PreferencesHydratedTask),
                Task.Delay(6000));
            App.LogDiagnostic("NavigateAfterHydrationAsync: task wait complete");
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"NavigateAfterHydrationAsync wait error: {ex}");
        }

        try
        {
            var authService = Microsoft.Extensions.DependencyInjection.ServiceProviderServiceExtensions
                .GetRequiredService<WinUIAuthService>(App.Current.Services);
            bool isAuth = authService.IsAuthenticated;
            App.LogDiagnostic($"NavigateAfterHydrationAsync: authService.IsAuthenticated={isAuth}");

            bool enqueued = DispatcherQueue.TryEnqueue(async () =>
            {
                App.LogDiagnostic($"NavigateAfterHydrationAsync dispatcher callback running. isAuth={isAuth}");
                try
                {
                    UpdateAppThemeFromSystem();

                    if (isAuth)
                    {
                        App.LogDiagnostic("NavigateAfterHydrationAsync: Navigating to MainPage");
                        RootFrame.Navigate(typeof(MainPage));
                    }
                    else
                    {
                        App.LogDiagnostic("NavigateAfterHydrationAsync: Not authenticated, navigating to LoginPage");
                        RootFrame.Opacity = 1.0;
                        RootFrame.Navigate(typeof(Views.LoginPage));
                        await FadeOutLoadingOverlayAsync();
                    }
                }
                catch (Exception ex)
                {
                    App.LogDiagnostic($"NavigateAfterHydrationAsync dispatcher callback error: {ex}");
                    DismissLoadingOverlay();
                }
            });
            App.LogDiagnostic($"NavigateAfterHydrationAsync: DispatcherQueue.TryEnqueue returned {enqueued}");
        }
        catch (Exception ex)
        {
            App.LogDiagnostic($"NavigateAfterHydrationAsync outer error: {ex}");
            DismissLoadingOverlay();
        }
    }

    private int _currentTabIndex = 1;
    private readonly Dictionary<Type, DetailWindow> _openWindows = new();

    public int CurrentTabIndex => _currentTabIndex;

    private void RootFrame_Navigated(object sender, Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        RootFrame.Opacity = 1.0;
        bool isLoginPage = (e.SourcePageType == typeof(Views.LoginPage));
        
        if (isLoginPage)
        {
            AppTitleBar.Opacity = 0.0;
            AppTitleBar.IsHitTestVisible = false;
            NavCapsule.Visibility = Visibility.Collapsed;
            AppSidebar.Visibility = Visibility.Collapsed;
        }
        else
        {
            if (LoadingOverlay.Visibility != Visibility.Visible)
            {
                AppTitleBar.Opacity = 1.0;
                AppTitleBar.IsHitTestVisible = true;
            }

            int tab = e.SourcePageType switch
            {
                var t when t == typeof(MainPage) => 1,
                var t when t == typeof(Views.FinancesDetailPage) => 2,
                var t when t == typeof(Views.TagdosNotesDetailPage) => 3,
                var t when t == typeof(Views.HealthDetailPage) => 4,
                var t when t == typeof(Views.HabitsDetailPage) => 5,
                var t when t == typeof(Views.WeatherDetailPage) => 6,
                var t when t == typeof(Views.RssFeedDetailPage) => 7,
                var t when t == typeof(Views.CalendarDetailPage) => 8,
                var t when t == typeof(Views.CosmosDetailPage) => 9,
                _ => 1
            };

            _currentTabIndex = tab;
            NavCapsule.SetSelectedTab(tab);
            AppSidebar.SetSelectedTab(tab);

            // Capsule is visible when sidebar is collapsed (except on Cosmos page where HUD has full screen)
            NavCapsule.Visibility = (AppSidebar.Visibility == Visibility.Visible || tab == 9) ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    // ── Navigation & In-Place Windowing ──────────────────────────────────────────

    public void NavigateToTab(int tabIndex, object? parameter = null)
    {
        if (tabIndex < 1 || tabIndex > 9) return;
        _currentTabIndex = tabIndex;
        NavCapsule.SetSelectedTab(tabIndex);
        AppSidebar.SetSelectedTab(tabIndex);

        Type targetPageType = tabIndex switch
        {
            1 => typeof(MainPage),
            2 => typeof(Views.FinancesDetailPage),
            3 => typeof(Views.TagdosNotesDetailPage),
            4 => typeof(Views.HealthDetailPage),
            5 => typeof(Views.HabitsDetailPage),
            6 => typeof(Views.WeatherDetailPage),
            7 => typeof(Views.RssFeedDetailPage),
            8 => typeof(Views.CalendarDetailPage),
            9 => typeof(Views.CosmosDetailPage),
            _ => typeof(MainPage)
        };

        if (RootFrame.Content?.GetType() == targetPageType && parameter == null)
        {
            return;
        }

        RootFrame.Navigate(targetPageType, parameter);
        if (tabIndex == 1 && RootFrame.BackStack.Count > 0)
        {
            RootFrame.BackStack.Clear();
        }
    }

    public void ToggleSidebar()
    {
        if (AppSidebar.Visibility == Visibility.Visible)
        {
            AppSidebar.Visibility = Visibility.Collapsed;
            NavCapsule.Visibility = (_currentTabIndex == 9) ? Visibility.Collapsed : Visibility.Visible;
        }
        else
        {
            AppSidebar.Visibility = Visibility.Visible;
            NavCapsule.Visibility = Visibility.Collapsed;
        }
    }

    public async Task TriggerCurrentViewRefreshAsync()
    {
        try
        {
            if (RootFrame.Content is MainPage mainPage)
            {
                mainPage.TriggerRefresh();
            }
            else if (RootFrame.Content is Views.HabitsDetailPage habitsPage)
            {
                await habitsPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.WeatherDetailPage weatherPage)
            {
                await weatherPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.HealthDetailPage healthPage)
            {
                await healthPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.FinancesDetailPage financesPage)
            {
                await financesPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.RssFeedDetailPage newsPage)
            {
                await newsPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.CalendarDetailPage calendarPage)
            {
                await calendarPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.TagdosNotesDetailPage tagdosPage)
            {
                await tagdosPage.RefreshFromTitleBarAsync();
            }
            else if (RootFrame.Content is Views.CosmosDetailPage cosmosPage)
            {
                await cosmosPage.RefreshFromTitleBarAsync();
            }
            else
            {
                var sync = App.Current?.Services?.GetService<Daily.Services.ISyncService>();
                if (sync != null) await sync.SyncAsync();
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[MainWindow] TriggerCurrentViewRefreshAsync failed: {ex}");
        }
    }

    public void TriggerGlobalSync()
    {
        _ = TriggerCurrentViewRefreshAsync();
    }

    public void OpenSettings()
    {
        if (RootFrame.Content is MainPage mp)
        {
            mp.OpenSettings();
        }
        else
        {
            var settingsWindow = new SettingsWindow();
            settingsWindow.Activate();
        }
    }

    public void OpenDetailWindow(Type pageType, object? parameter = null)
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

        var root = this.Content as FrameworkElement;
        var activeTheme = root?.RequestedTheme ?? ElementTheme.Default;
        if (activeTheme == ElementTheme.Default)
        {
            activeTheme = root?.ActualTheme ?? ElementTheme.Light;
        }
        window.ApplyTheme(activeTheme);
        window.Activate();
    }

    private void TitleBarSidebarToggle_Click(object sender, RoutedEventArgs e) => ToggleSidebar();
    private void OnSidebarTabSelected(object sender, int tabIndex) => NavigateToTab(tabIndex);
    private void OnSidebarCollapseRequested(object sender, EventArgs e) => ToggleSidebar();
    private void OnSidebarSettingsRequested(object sender, EventArgs e) => OpenSettings();
    private void OnCapsuleTabSelected(object sender, int tabIndex) => NavigateToTab(tabIndex);
    private void TaskbarGlanceControl_RequestCloseFlyout(object sender, EventArgs e) { }
    public Frame MainFrame => RootFrame;

    // ── Keyboard Accelerators ──────────────────────────────────────────────────
    private void OnAcceleratorCtrl1(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(1); }
    private void OnAcceleratorCtrl2(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(2); }
    private void OnAcceleratorCtrl3(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(3); }
    private void OnAcceleratorCtrl4(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(4); }
    private void OnAcceleratorCtrl5(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(5); }
    private void OnAcceleratorCtrl6(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(6); }
    private void OnAcceleratorCtrl7(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(7); }
    private void OnAcceleratorCtrl8(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(8); }
    private void OnAcceleratorCtrl9(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(9); }
    private void OnAcceleratorCtrlS(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; ToggleSidebar(); }
    private void OnAcceleratorCtrlR(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; TriggerGlobalSync(); }
    private void OnAcceleratorCtrlN(Microsoft.UI.Xaml.Input.KeyboardAccelerator sender, Microsoft.UI.Xaml.Input.KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; NavigateToTab(3); }

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

    private double GetDpiScale()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        uint dpi = GetDpiForWindow(hwnd);
        return dpi > 0 ? (double)dpi / 96.0 : 1.0;
    }

    private void UpdateTitleBarElementsVisibility()
    {
        double scale = GetDpiScale();
        double logicalWidth = AppWindow.Size.Width / scale;

        if (logicalWidth < 640)
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
        double scale = GetDpiScale();
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

        UpdateTitleBarElementsVisibility();
    }

    private void AppTitleBar_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        double scale = GetDpiScale();
        if (scale > 0 && AppWindow.TitleBar != null)
        {
            // Snap our grid height to exactly match the OS caption-button height
            double captionHeight = AppWindow.TitleBar.Height / scale;
            AppTitleBar.Height = captionHeight;

            // Keep the spacer column wide enough to clear the system buttons
            if (RightPaddingColumn != null)
                RightPaddingColumn.Width = new GridLength(AppWindow.TitleBar.RightInset / scale);
        }

        UpdateTitleBarElementsVisibility();
    }

    private void DockNormal_Click(object sender, RoutedEventArgs e)
    {
        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        double scale = GetDpiScale();

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

        double scale = GetDpiScale();

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

        double scale = GetDpiScale();

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

        _companionWindow?.Close();
        App.Current.CloseAllSecondaryWindows();
    }

    private TaskbarCompanionWindow? _companionWindow;

    public void ToggleTaskbarCompanion()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (_companionWindow == null)
            {
                _companionWindow = new TaskbarCompanionWindow();
            }

            if (_companionWindow.IsVisible)
            {
                _companionWindow.Hide();
            }
            else
            {
                _companionWindow.ShowNearTray();
            }
        });
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
                TrayIcon.NoLeftClickDelay = true;
                TrayIcon.ContextMenuMode = H.NotifyIcon.ContextMenuMode.SecondWindow;
                TrayIcon.MenuActivation = H.NotifyIcon.Core.PopupActivationMode.RightClick;
                TrayIcon.LeftClickCommand = new RelayCommand(() =>
                {
                    LogTray("[TrayIcon] LeftClickCommand invoked: toggling taskbar companion.");
                    ToggleTaskbarCompanion();
                });
                TrayIcon.DoubleClickCommand = new RelayCommand(() =>
                {
                    LogTray("[TrayIcon] DoubleClickCommand invoked: restoring main window.");
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
                return;
            }
            
            // Fallback 1: AppIcon.ico
            string appIconPath = System.IO.Path.Combine(System.AppContext.BaseDirectory, "Assets", "AppIcon.ico");
            if (System.IO.File.Exists(appIconPath))
            {
                var oldIcon = TrayIcon.Icon;
                TrayIcon.Icon = new System.Drawing.Icon(appIconPath);
                oldIcon?.Dispose();
                LogTray("[TrayIcon] Loaded fallback AppIcon.ico.");
                return;
            }

            // Fallback 2: Extract from executable process
            var exePath = System.Environment.ProcessPath;
            if (!string.IsNullOrEmpty(exePath))
            {
                var exeIcon = System.Drawing.Icon.ExtractAssociatedIcon(exePath);
                if (exeIcon != null)
                {
                    var oldIcon = TrayIcon.Icon;
                    TrayIcon.Icon = exeIcon;
                    oldIcon?.Dispose();
                    LogTray("[TrayIcon] Loaded fallback from process executable.");
                }
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

        // Run background session refresh and catch-up pulls on restoration
        System.Threading.Tasks.Task.Run(async () =>
        {
            try
            {
                var supabase = App.Current.Services.GetService<Supabase.Client>();
                if (supabase != null)
                {
                    var auth = supabase.Auth;
                    if (auth?.CurrentSession != null && auth.CurrentSession.Expired())
                    {
                        System.Diagnostics.Debug.WriteLine("[MainWindow] Restore: Session expired. Refreshing session...");
                        try { await auth.RefreshSession(); } catch { }
                    }
                }

                var habitsService = App.Current.Services.GetService<Daily.Services.IHabitsService>();
                if (habitsService != null)
                {
                    await habitsService.InitializeAsync();
                }

                var healthService = App.Current.Services.GetService<Daily.Services.Health.IHealthService>();
                if (healthService != null)
                {
                    await healthService.InitializeAsync();
                }

                DispatcherQueue.TryEnqueue(() =>
                {
                    if (RootFrame.Content is MainPage mainPage)
                    {
                        mainPage.TriggerRefresh();
                    }
                });
            }
            catch (System.Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[MainWindow] Restore background sync failed: {ex.Message}");
            }
        });
    }

    public void ExitApp()
    {
        _isExiting = true;
        _companionWindow?.Close();
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

