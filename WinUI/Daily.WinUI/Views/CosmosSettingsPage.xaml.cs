using Daily.Models;
using Daily_WinUI.Services.Cosmos;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.Views;

public sealed partial class CosmosSettingsPage : Page
{
    private bool _loading = true;

    public CosmosSettingsPage()
    {
        InitializeComponent();
        Loaded += CosmosSettingsPage_Loaded;
    }

    private void CosmosSettingsPage_Loaded(object sender, RoutedEventArgs e)
    {
        _loading = true;
        var prefs = CosmosLiveService.Shared.LoadPreferences();
        NasaApiKeyBox.Text = prefs.NasaApiKey ?? string.Empty;
        WeatherEndpointBox.Text = prefs.WeatherEndpoint ?? string.Empty;
        WeatherApiKeyBox.Text = prefs.WeatherApiKey ?? string.Empty;
        IssAlertsSwitch.IsOn = prefs.NotifyIssPasses;
        AuroraAlertsSwitch.IsOn = prefs.NotifyAurora;
        PristineSkyAlertsSwitch.IsOn = prefs.NotifyPristineSky;
        _loading = false;
    }

    private void AlertSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        PersistPreferences();
    }

    private void SaveKeysButton_Click(object sender, RoutedEventArgs e)
    {
        PersistPreferences();
        SaveKeysButton.Content = "Saved ✓";
    }

    private void PersistPreferences()
    {
        var prefs = new CosmosLocalPreferences
        {
            NasaApiKey = (NasaApiKeyBox.Text ?? string.Empty).Trim(),
            WeatherEndpoint = (WeatherEndpointBox.Text ?? string.Empty).Trim(),
            WeatherApiKey = (WeatherApiKeyBox.Text ?? string.Empty).Trim(),
            NotifyIssPasses = IssAlertsSwitch.IsOn,
            NotifyAurora = AuroraAlertsSwitch.IsOn,
            NotifyPristineSky = PristineSkyAlertsSwitch.IsOn
        };
        CosmosLiveService.Shared.SavePreferences(prefs);
    }
}
