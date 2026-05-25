using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily_WinUI.Services;

namespace Daily_WinUI.Views;

public sealed partial class AppearanceSettingsPage : Page
{
    private readonly AppSettings _settings;

    public AppearanceSettingsPage()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        Loaded += AppearanceSettingsPage_Loaded;
    }

    private void AppearanceSettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        CloseToTraySwitch.Toggled -= CloseToTraySwitch_Toggled;
        CloseToTraySwitch.IsOn = _settings.CloseToTray;
        CloseToTraySwitch.Toggled += CloseToTraySwitch_Toggled;
    }

    private void CloseToTraySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_settings == null || CloseToTraySwitch == null) return;
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
