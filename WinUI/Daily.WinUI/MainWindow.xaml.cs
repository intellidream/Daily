using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Daily_WinUI.Services;
using Windows.Graphics;
using System.Runtime.InteropServices;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Daily_WinUI;

public sealed partial class MainWindow : Window
{
    private readonly AppSettings _settings;
    private DispatcherTimer? _dateTimer;

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

        _ = NavigateAfterHydrationAsync();

        AppWindow.Changed += AppWindow_Changed;
        Closed += MainWindow_Closed;
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
                TitleBarUserAvatar.ProfilePicture = new BitmapImage(new System.Uri(avatarUrl));

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

    private void TitleBarTheme_Click(object sender, RoutedEventArgs e)
    {
        if (RootFrame.Content is MainPage mainPage)
            mainPage.ApplyThemeToggle();
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

    private async Task NavigateAfterHydrationAsync()
    {
        await App.Current.InitializationTask;

        var authService = Microsoft.Extensions.DependencyInjection.ServiceProviderServiceExtensions
            .GetRequiredService<WinUIAuthService>(App.Current.Services);

        DispatcherQueue.TryEnqueue(() =>
        {
            if (authService.IsAuthenticated)
                RootFrame.Navigate(typeof(MainPage));
            else
                RootFrame.Navigate(typeof(Views.LoginPage));
        });
    }

    // ── Window management ─────────────────────────────────────────────────────

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);

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

        // Enforce minimum window size (500×500 logical px, converted to physical)
        double scale = this.Content?.XamlRoot?.RasterizationScale ?? 1.0;
        int minPx = (int)(500 * scale);
        var size = sender.Size;
        if (size.Width < minPx || size.Height < minPx)
        {
            sender.ResizeClient(new SizeInt32(
                Math.Max(size.Width,  minPx),
                Math.Max(size.Height, minPx)));
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
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _dateTimer?.Stop();
        SettingsService.Save(_settings);
    }
}
