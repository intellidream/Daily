using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using System;
using System.Threading.Tasks;
using System.Linq;
using Daily_WinUI.Services;
using Daily_WinUI.Models;

namespace Daily_WinUI.Controls;

public sealed partial class WeatherWidgetControl : UserControl
{
    private readonly WeatherClient _weatherClient = new();
    private readonly LocationService _locationService = new();
    private readonly AppSettings _settings;

    public WeatherWidgetControl()
    {
        InitializeComponent();
        _settings = SettingsService.Load();
        Loaded += WeatherWidgetControl_Loaded;
    }

    private async void WeatherWidgetControl_Loaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        await RefreshWeatherAsync();
    }

    public async Task RefreshWeatherAsync()
    {
        try
        {
            LoadingOverlay.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
            LocationText.Text = "Detecting location...";
            var coords = await _locationService.GetCurrentCoordinatesAsync();
            if (coords.HasValue)
            {
                var snapshot = await _weatherClient.GetCurrentWeatherAsync(
                    coords.Value.Latitude, 
                    coords.Value.Longitude, 
                    _settings.UnitSystem);
                
                if (snapshot != null)
                {
                    LocationText.Text = snapshot.LocationName;
                    
                    var unitStr = _settings.UnitSystem == "imperial" ? "F" : "C";
                    TempText.Text = $"{snapshot.Temperature:0.#}°";
                    FeelsLikeText.Text = $"{snapshot.FeelsLike:0.#}°";
                    DescText.Text = ToTitleCase(snapshot.Description);
                    HighLowText.Text = $"H: {snapshot.TempMax:0.#}° · L: {snapshot.TempMin:0.#}°";

                    try
                    {
                        ConditionIcon.Source = new BitmapImage(new Uri($"https://openweathermap.org/img/wn/{snapshot.IconCode}@4x.png"));
                    }
                    catch { }
                }
                else
                {
                    LocationText.Text = "Weather unavailable";
                }
            }
            else
            {
                LocationText.Text = "Location unavailable";
            }
        }
        catch
        {
            LocationText.Text = "Offline";
        }
        finally
        {
            LoadingOverlay.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        }
    }

    private static string ToTitleCase(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        return string.Join(' ', value.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(word => char.ToUpperInvariant(word[0]) + word.Substring(1)));
    }
}
