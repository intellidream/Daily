using System;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading;
using System.Threading.Tasks;
using Windows.Devices.Geolocation;

namespace Daily_WinUI.Services;

public sealed class LocationService : IDisposable
{
    private readonly HttpClient _httpClient = new();
    private Geolocator? _watcher;

    /// <summary>Raised when the device position changes significantly (≥500 m).</summary>
    public event EventHandler<(double Latitude, double Longitude)>? PositionChanged;

    private static (double Latitude, double Longitude)? _cachedCoordinates;
    private static DateTime? _cachedCoordinatesTimeUtc;
    private static readonly TimeSpan CoordinatesCacheTtl = TimeSpan.FromMinutes(15);
    private static readonly SemaphoreSlim _locationLock = new(1, 1);

    /// <summary>
    /// Seeds the coordinates cache (e.g. from persisted settings on startup) so location is available with 0ms delay.
    /// </summary>
    public static void SeedCache(double latitude, double longitude)
    {
        if (!_cachedCoordinates.HasValue)
        {
            _cachedCoordinates = (latitude, longitude);
            _cachedCoordinatesTimeUtc = DateTime.UtcNow;
        }
    }

    /// <summary>
    /// Returns the currently cached coordinates immediately if valid within the 15-minute TTL,
    /// or fetches fresh coordinates via Windows Geolocator / IP geolocation.
    /// </summary>
    public async Task<(double Latitude, double Longitude)?> GetCurrentCoordinatesAsync(bool forceRefresh = false, CancellationToken cancellationToken = default)
    {
        if (!forceRefresh && _cachedCoordinates.HasValue && _cachedCoordinatesTimeUtc.HasValue &&
            DateTime.UtcNow - _cachedCoordinatesTimeUtc.Value < CoordinatesCacheTtl)
        {
            return _cachedCoordinates.Value;
        }

        await _locationLock.WaitAsync(cancellationToken);
        try
        {
            if (!forceRefresh && _cachedCoordinates.HasValue && _cachedCoordinatesTimeUtc.HasValue &&
                DateTime.UtcNow - _cachedCoordinatesTimeUtc.Value < CoordinatesCacheTtl)
            {
                return _cachedCoordinates.Value;
            }

            // Try Windows location with a strict timeout of 1500 milliseconds
            using (var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
            {
                cts.CancelAfter(1500);
                try
                {
                    var windowsLocation = await TryWindowsLocationAsync(cts.Token);
                    if (windowsLocation.HasValue)
                    {
                        _cachedCoordinates = windowsLocation;
                        _cachedCoordinatesTimeUtc = DateTime.UtcNow;
                        return windowsLocation;
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[LocationService] Windows location failed/timed out: {ex.Message}");
                }
            }

            // Fallback to IP location with a strict timeout of 1500 milliseconds
            using (var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
            {
                cts.CancelAfter(1500);
                try
                {
                    var ipLocation = await TryIpLocationAsync(cts.Token);
                    if (ipLocation.HasValue)
                    {
                        _cachedCoordinates = ipLocation;
                        _cachedCoordinatesTimeUtc = DateTime.UtcNow;
                        return ipLocation;
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[LocationService] IP location failed/timed out: {ex.Message}");
                }
            }

            // If refresh failed or timed out, but we have a prior coordinate, return it as graceful fallback
            if (_cachedCoordinates.HasValue)
            {
                return _cachedCoordinates.Value;
            }

            return null;
        }
        finally
        {
            _locationLock.Release();
        }
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
        _cachedCoordinates = (pos.Latitude, pos.Longitude);
        _cachedCoordinatesTimeUtc = DateTime.UtcNow;
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
