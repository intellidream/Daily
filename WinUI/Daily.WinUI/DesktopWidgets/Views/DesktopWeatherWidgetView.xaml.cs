using System;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily_WinUI.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopWeatherWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;

        public DesktopWeatherWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            _model = model;
            _hostWindow = hostWindow;
            this.InitializeComponent();

            ApplySizeLayout();
        }

        private void ApplySizeLayout()
        {
            if (_model.Size == DesktopWidgetSize.Small)
            {
                SmallLayout.Visibility = Visibility.Visible;
                MediumLargeLayout.Visibility = Visibility.Collapsed;
            }
            else
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLargeLayout.Visibility = Visibility.Visible;
            }
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            RefreshData();
        }

        public void Detach()
        {
        }

        public async void RefreshData()
        {
            try
            {
                var settings = SettingsService.Load();
                var locationService = App.Current.Services?.GetService<LocationService>() ?? new LocationService();
                var coords = await locationService.GetCurrentCoordinatesAsync();

                double lat = coords?.Latitude ?? settings.LastLatitude ?? 44.4323;
                double lon = coords?.Longitude ?? settings.LastLongitude ?? 26.1063;
                string locName = settings.LastLocationName ?? "Bucharest";

                var client = new WeatherClient();
                var weather = await client.GetCurrentWeatherAsync(lat, lon, settings.UnitSystem ?? "metric");

                if (weather != null)
                {
                    if (!string.IsNullOrWhiteSpace(weather.LocationName))
                    {
                        locName = weather.LocationName;
                    }

                    int currentTemp = (int)Math.Round(weather.Temperature);
                    int highTemp = (int)Math.Round(weather.TempMax);
                    int lowTemp = (int)Math.Round(weather.TempMin);
                    string condition = weather.Description ?? "Partly Cloudy";

                    SmallLocationText.Text = locName;
                    SmallTempText.Text = $"{currentTemp}°";
                    SmallConditionText.Text = condition;
                    SmallHighLowText.Text = $"H: {highTemp}° · L: {lowTemp}°";

                    MediumLocationText.Text = locName;
                    MediumConditionSubtitle.Text = $"{condition} · Feels like {(int)Math.Round(weather.FeelsLike)}°";
                    MediumTempText.Text = $"{currentTemp}°C";
                    MediumHighLowDetail.Text = $"High: {highTemp}° · Low: {lowTemp}°";

                    int humidity = weather.Humidity;
                    double wind = weather.WindSpeed;
                    HumidityWindText.Text = $"💧 {humidity}% · 💨 {wind:F1} m/s";

                    // Hourly slots
                    Hour1Temp.Text = $"{currentTemp}°";
                    Hour2Temp.Text = $"{currentTemp + 1}°";
                    Hour3Temp.Text = $"{currentTemp + 2}°";
                    Hour4Temp.Text = $"{currentTemp + 1}°";
                    Hour5Temp.Text = $"{currentTemp}°";
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWeatherWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
