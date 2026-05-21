using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily_WinUI.Services;

namespace Daily_WinUI.Views;

public sealed partial class GeneralSettingsPage : Page
{
    private readonly AppSettings _settings;

    public GeneralSettingsPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        Loaded += GeneralSettingsPage_Loaded;
    }

    private void GeneralSettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        // Unregister event during initial load to prevent saving on load
        CloseToTraySwitch.Toggled -= CloseToTraySwitch_Toggled;
        CloseToTraySwitch.IsOn = _settings.CloseToTray;
        CloseToTraySwitch.Toggled += CloseToTraySwitch_Toggled;
    }

    private void CloseToTraySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        _settings.CloseToTray = CloseToTraySwitch.IsOn;
        SettingsService.Save(_settings);
    }

    private void ToggleThemeButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current.MainWindow is MainWindow mw)
        {
            mw.TitleBarTheme_Click(sender, e);
        }
    }
}
