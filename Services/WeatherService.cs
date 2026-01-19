using System.Net.Http.Json;
using Daily.Models;

namespace Daily.Services
{
    public class WeatherService : IWeatherService
    {
        private readonly HttpClient _httpClient;
        // API Key moved to Configuration/Secrets.cs
        private const string ApiKey = Daily.Configuration.Secrets.OpenWeatherMapApiKey;
        private const string BaseUrl = "https://api.openweathermap.org/data/2.5";
        
        // Caching
        private WeatherResponse? _cachedCurrentWeather;
        private ForecastResponse? _cachedForecast;
        private DateTime _lastCurrentFetchTime;
        private DateTime _lastForecastFetchTime;
        private (double Lat, double Lon)? _lastCurrentLocation;
        private (double Lat, double Lon)? _lastForecastLocation;
        
        public WeatherResponse? CachedWeather => _cachedCurrentWeather;
        public ForecastResponse? CachedForecast => _cachedForecast;

        private const double LocationTolerance = 0.01; // Roughly 1km
        private readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(15);

        private readonly ISettingsService _settingsService;
        private readonly ISyncService _syncService;
        private readonly IGeolocation _geolocation;

        public WeatherService(ISettingsService settingsService, IGeolocation geolocation, ISyncService syncService)
        {
            _httpClient = new HttpClient();
            _settingsService = settingsService;
            _geolocation = geolocation;
            _syncService = syncService;
            
            // Re-fetch weather if units change
            _settingsService.OnSettingsChanged += async () => 
            {
                if (_lastCurrentLocation.HasValue)
                {
                    await GetCurrentWeatherAsync(_lastCurrentLocation.Value.Lat, _lastCurrentLocation.Value.Lon, forceRefresh: true);
                }
                
                // Also trigger forecast refresh if we have a location
                if (_lastForecastLocation.HasValue)
                {
                    await GetForecastAsync(_lastForecastLocation.Value.Lat, _lastForecastLocation.Value.Lon, forceRefresh: true);
                }
            };
        }

        private Location? _cachedUserLocation;
        private DateTime _lastUserLocationTime;

        public async Task<Location?> GetResilientLocationAsync()
        {
            // Check cache
            if (_cachedUserLocation != null && DateTime.Now - _lastUserLocationTime < CacheDuration)
            {
                return _cachedUserLocation;
            }

            try
            {
                _syncService.Log("[WeatherService] Checking Permissions...");
                var status = await Permissions.CheckStatusAsync<Permissions.LocationWhenInUse>();
                
                if (status != PermissionStatus.Granted)
                {
                    _syncService.Log("[WeatherService] Requesting Permission (MainThread)...");
                    status = await MainThread.InvokeOnMainThreadAsync(async () => 
                        await Permissions.RequestAsync<Permissions.LocationWhenInUse>());
                }

                _syncService.Log($"[WeatherService] Permission Status: {status}");

                if (status == PermissionStatus.Granted)
                {
                    // 2. Try Last Known (Very Fast)
                    var location = await _geolocation.GetLastKnownLocationAsync();
                    if (location != null) 
                    {
                        _syncService.Log("[WeatherService] cache hit (LastKnown).");
                        _cachedUserLocation = location;
                        _lastUserLocationTime = DateTime.Now;
                        return location;
                    }

                    // 3. Single Robust Attempt (Fast Timeout)
                    _syncService.Log("[WeatherService] Requesting GPS Location (Timeout: 10s)...");
                    location = await MainThread.InvokeOnMainThreadAsync(async () => await AttemptGetLocation(GeolocationAccuracy.Default, 10));
                    
                    if (location != null) 
                    {
                        _syncService.Log($"[WeatherService] GPS Location found: {location.Latitude}, {location.Longitude}");
                        _cachedUserLocation = location;
                        _lastUserLocationTime = DateTime.Now;
                        return location;
                    }
                    _syncService.Log("[WeatherService] GPS Location returned null.");
                }
            }
            catch (Exception ex)
            {
                _syncService.Log($"[WeatherService] Location Exception: {ex}");
                // Ignore errors to fall through to IP
            }

            // 4. Fallback to IP
            var ipLocation = await GetLocationFromIpAsync();
            if (ipLocation != null)
            {
                _cachedUserLocation = ipLocation;
                _lastUserLocationTime = DateTime.Now;
                return ipLocation;
            }

            return null;
        }

        private async Task<Location?> AttemptGetLocation(GeolocationAccuracy accuracy, int timeoutSeconds)
        {
            try
            {
                var request = new GeolocationRequest
                {
                    DesiredAccuracy = accuracy,
                    Timeout = TimeSpan.FromSeconds(timeoutSeconds)
                };
                return await _geolocation.GetLocationAsync(request);
            }
            catch (Exception ex)
            {
                _syncService.Log($"[WeatherService] GetLocation Error: {ex.Message}");
                return null;
            }
        }

        private async Task<Location?> GetLocationFromIpAsync()
        {
            try
            {
                // Using ip-api.com (free, no key required for non-commercial)
                // Note: HTTP only for free tier. iOS/Mac ATS might block this if not configured.
                var ipInfo = await _httpClient.GetFromJsonAsync<IpLocationInfo>("http://ip-api.com/json/");
                if (ipInfo != null && ipInfo.Status == "success")
                {
                    return new Location(ipInfo.Lat, ipInfo.Lon);
                }
            }
            catch
            {
                // Ignore
            }
            return null;
        }

        private class IpLocationInfo
        {
            public string Status { get; set; }
            public double Lat { get; set; }
            public double Lon { get; set; }
        }

        // ... Existing Methods ...
        public async Task<WeatherResponse> GetCurrentWeatherAsync(double latitude, double longitude, bool forceRefresh = false)
        {
            // Check cache
            if (!forceRefresh &&
                _cachedCurrentWeather != null && 
                _lastCurrentLocation.HasValue &&
                IsLocationClose(latitude, longitude, _lastCurrentLocation.Value.Lat, _lastCurrentLocation.Value.Lon) &&
                DateTime.Now - _lastCurrentFetchTime < CacheDuration)
            {
                return _cachedCurrentWeather;
            }

            try
            {
                // Sanitize units: Default to metric if missing, ensure lowercase
                var rawSetting = _settingsService.Settings.UnitSystem;
                var units = (rawSetting ?? "metric").ToLower();
                
                var url = $"{BaseUrl}/weather?lat={latitude}&lon={longitude}&appid={ApiKey}&units={units}";
                
                Console.WriteLine($"[WeatherService] Fetching Weather. RawSetting: '{rawSetting}' | UnitsParam: '{units}'");
                Console.WriteLine($"[WeatherService] URL: {url.Replace(ApiKey, "APIKEY")}");

                var result = await _httpClient.GetFromJsonAsync<WeatherResponse>(url);
                
                if (result != null)
                {
                    Console.WriteLine($"[WeatherService] Result Temp: {result.Main.Temp}");
                    _cachedCurrentWeather = result;
                    _lastCurrentLocation = (latitude, longitude);
                    _lastCurrentFetchTime = DateTime.Now;
                    OnWeatherUpdated?.Invoke();
                }
                
                return result;
            }
            catch (Exception ex)
            {
                // Handle error (log it, return null, etc.)
                Console.WriteLine($"Error fetching weather: {ex.Message}");
                return null;
            }
        }

        public async Task<ForecastResponse> GetForecastAsync(double latitude, double longitude, bool forceRefresh = false)
        {
            // Check cache
            if (!forceRefresh &&
                _cachedForecast != null && 
                _lastForecastLocation.HasValue &&
                IsLocationClose(latitude, longitude, _lastForecastLocation.Value.Lat, _lastForecastLocation.Value.Lon) &&
                DateTime.Now - _lastForecastFetchTime < CacheDuration)
            {
                return _cachedForecast;
            }

            try
            {
                var units = (_settingsService.Settings.UnitSystem ?? "metric").ToLower();
                var url = $"{BaseUrl}/forecast?lat={latitude}&lon={longitude}&appid={ApiKey}&units={units}";
                var result = await _httpClient.GetFromJsonAsync<ForecastResponse>(url);

                if (result != null)
                {
                    _cachedForecast = result;
                    _lastForecastLocation = (latitude, longitude);
                    _lastForecastFetchTime = DateTime.Now;
                    // Note: We might want to invoke update here too, but usually CurrentWeather is the trigger. 
                    // Let's invoke it just in case Forecast updates independently.
                    OnWeatherUpdated?.Invoke(); 
                }

                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error fetching forecast: {ex.Message}");
                return null;
            }
        }

        private bool IsLocationClose(double lat1, double lon1, double lat2, double lon2)
        {
            return Math.Abs(lat1 - lat2) < LocationTolerance && Math.Abs(lon1 - lon2) < LocationTolerance;
        }

        public string GetApiKey() => ApiKey;

        public string CurrentLocationName { get; private set; }
        public bool IsAutoLocation { get; private set; }
        public event Action OnLocationChanged;
        public event Action OnWeatherUpdated;

        public void SetCurrentLocation(string name, bool isAuto)
        {
            CurrentLocationName = name;
            IsAutoLocation = isAuto;
            OnLocationChanged?.Invoke();
        }
    }
}
