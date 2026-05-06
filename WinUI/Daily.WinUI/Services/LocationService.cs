using System.Net.Http.Json;
using Windows.Devices.Geolocation;

namespace Daily_WinUI.Services;

public sealed class LocationService : IDisposable
{
    private readonly HttpClient _httpClient = new();
    private Geolocator? _watcher;

    /// <summary>Raised when the device position changes significantly (≥500 m).</summary>
    public event EventHandler<(double Latitude, double Longitude)>? PositionChanged;

    public async Task<(double Latitude, double Longitude)?> GetCurrentCoordinatesAsync(CancellationToken cancellationToken = default)
    {
        var windowsLocation = await TryWindowsLocationAsync(cancellationToken);
        if (windowsLocation.HasValue)
        {
            return windowsLocation;
        }

        return await TryIpLocationAsync(cancellationToken);
    }

    /// <summary>
    /// Requests location access and starts watching for position changes.
    /// Raises <see cref="PositionChanged"/> whenever the device moves ≥500 m.
    /// </summary>
    public async Task StartWatchingAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var access = await Geolocator.RequestAccessAsync().AsTask(cancellationToken);
            if (access != GeolocationAccessStatus.Allowed)
                return;

            _watcher = new Geolocator
            {
                DesiredAccuracyInMeters = 150,
                MovementThreshold = 500   // metres before firing PositionChanged
            };
            _watcher.PositionChanged += OnPositionChanged;
        }
        catch { /* location unavailable or cancelled */ }
    }

    public void StopWatching()
    {
        if (_watcher is not null)
        {
            _watcher.PositionChanged -= OnPositionChanged;
            _watcher = null;
        }
    }

    private void OnPositionChanged(Geolocator sender, PositionChangedEventArgs args)
    {
        var pos = args.Position.Coordinate.Point.Position;
        PositionChanged?.Invoke(this, (pos.Latitude, pos.Longitude));
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

    public void Dispose()
    {
        StopWatching();
        _httpClient.Dispose();
    }
}
