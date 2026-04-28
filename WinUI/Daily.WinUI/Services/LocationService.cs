using System.Net.Http.Json;
using Windows.Devices.Geolocation;

namespace Daily_WinUI.Services;

public sealed class LocationService
{
    private readonly HttpClient _httpClient = new();

    public async Task<(double Latitude, double Longitude)?> GetCurrentCoordinatesAsync(CancellationToken cancellationToken = default)
    {
        var windowsLocation = await TryWindowsLocationAsync(cancellationToken);
        if (windowsLocation.HasValue)
        {
            return windowsLocation;
        }

        return await TryIpLocationAsync(cancellationToken);
    }

    private static async Task<(double Latitude, double Longitude)?> TryWindowsLocationAsync(CancellationToken cancellationToken)
    {
        try
        {
            var access = await Geolocator.RequestAccessAsync().AsTask(cancellationToken);
            if (access != GeolocationAccessStatus.Allowed)
            {
                return null;
            }

            var locator = new Geolocator
            {
                DesiredAccuracyInMeters = 150
            };

            var position = await locator.GetGeopositionAsync(
                TimeSpan.FromSeconds(8),
                TimeSpan.FromSeconds(1)).AsTask(cancellationToken);

            return (position.Coordinate.Point.Position.Latitude, position.Coordinate.Point.Position.Longitude);
        }
        catch
        {
            return null;
        }
    }

    private async Task<(double Latitude, double Longitude)?> TryIpLocationAsync(CancellationToken cancellationToken)
    {
        try
        {
            var response = await _httpClient.GetFromJsonAsync<IpLocationResponse>("http://ip-api.com/json/", cancellationToken);
            if (response?.Status?.Equals("success", StringComparison.OrdinalIgnoreCase) == true)
            {
                return (response.Lat, response.Lon);
            }
        }
        catch
        {
            return null;
        }

        return null;
    }

    private sealed class IpLocationResponse
    {
        public string? Status { get; set; }
        public double Lat { get; set; }
        public double Lon { get; set; }
    }
}