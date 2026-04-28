using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Daily_WinUI.Services;
using Windows.Graphics;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Daily_WinUI;

/// <summary>
/// The application window. This hosts a Frame that displays pages. Add your
/// UI and logic to MainPage.xaml / MainPage.xaml.cs instead of here so you
/// can use Page features such as navigation events and the Loaded lifecycle.
/// </summary>
public sealed partial class MainWindow : Window
{
    private readonly AppSettings _settings;

    public MainWindow()
    {
        InitializeComponent();
        _settings = SettingsService.Load();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        AppWindow.SetIcon("Assets/AppIcon.ico");
        AppWindow.Title = "Daily for Windows";
        ConfigureStartupWindow();

        // Navigate the root frame to the main page on startup.
        RootFrame.Navigate(typeof(MainPage));

        AppWindow.Changed += AppWindow_Changed;
        Closed += MainWindow_Closed;
    }

    private void ConfigureStartupWindow()
    {
        if (AppWindow.Presenter is OverlappedPresenter overlappedPresenter)
        {
            overlappedPresenter.IsResizable = true;
            overlappedPresenter.IsMaximizable = true;
            overlappedPresenter.IsMinimizable = true;
        }

        if (_settings.HasWindowPosition && _settings.WindowWidth > 0 && _settings.WindowHeight > 0)
        {
            AppWindow.MoveAndResize(new RectInt32(_settings.WindowX, _settings.WindowY, _settings.WindowWidth, _settings.WindowHeight));
            return;
        }

        var displayArea = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        var workArea = displayArea.WorkArea;

        var width = Math.Min(600, workArea.Width);
        var height = Math.Min(800, workArea.Height);
        var x = workArea.X + (workArea.Width - width) / 2;
        var y = workArea.Y + (workArea.Height - height) / 2;

        AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
    }

    private void AppWindow_Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (!args.DidPositionChange && !args.DidSizeChange)
        {
            return;
        }

        var bounds = sender.Position;
        var size = sender.Size;
        _settings.WindowX = bounds.X;
        _settings.WindowY = bounds.Y;
        _settings.WindowWidth = size.Width;
        _settings.WindowHeight = size.Height;
        _settings.HasWindowPosition = true;
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        SettingsService.Save(_settings);
    }
}
