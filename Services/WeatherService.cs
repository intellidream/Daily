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
        private readonly DebugLogger _debugLogger;

        public WeatherService(ISettingsService settingsService, IGeolocation geolocation, ISyncService syncService, DebugLogger debugLogger)
        {
            _httpClient = new HttpClient();
            _settingsService = settingsService;
            _geolocation = geolocation;
            _syncService = syncService;
            _debugLogger = debugLogger;
            
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
                _debugLogger.Log("[WeatherService] Checking location permission...");
                var status = await Permissions.CheckStatusAsync<Permissions.LocationWhenInUse>();
                
                if (status != PermissionStatus.Granted)
                {
                    _syncService.Log("[WeatherService] Requesting Permission (MainThread)...");
                    _debugLogger.Log("[WeatherService] Requesting location permission...");
                    status = await MainThread.InvokeOnMainThreadAsync(async () => 
                        await Permissions.RequestAsync<Permissions.LocationWhenInUse>());
                }

                _syncService.Log($"[WeatherService] Permission Status: {status}");
                _debugLogger.Log($"[WeatherService] Permission Status: {status}");

                if (status == PermissionStatus.Granted)
                {
                    // 2. Try Last Known (Very Fast)
                    var location = await TryGetLastKnownLocationAsync(TimeSpan.FromSeconds(2));
                    if (location != null) 
                    {
                        _syncService.Log("[WeatherService] cache hit (LastKnown).");
                        _debugLogger.Log("[WeatherService] Location from last known.");
                        if (location.Accuracy.HasValue)
                        {
                            _debugLogger.Log($"[WeatherService] Last known accuracy: {location.Accuracy.Value:F0}m.");
                        }
                        _cachedUserLocation = location;
                        _lastUserLocationTime = DateTime.Now;
                        return location;
                    }
                    _debugLogger.Log("[WeatherService] Last known location unavailable.");

                    // 3. Single Robust Attempt (Fast Timeout)
                    _syncService.Log("[WeatherService] Requesting GPS Location (High, Timeout: 20s)...");
                    _debugLogger.Log("[WeatherService] Requesting GPS location (High, 20s timeout)...");
                    location = await MainThread.InvokeOnMainThreadAsync(async () => await AttemptGetLocation(GeolocationAccuracy.Best, 20));
                    if (location == null)
                    {
                        _syncService.Log("[WeatherService] Retrying GPS Location (Default, Timeout: 15s)...");
                        _debugLogger.Log("[WeatherService] Retrying GPS location (Default, 15s timeout)...");
                        location = await MainThread.InvokeOnMainThreadAsync(async () => await AttemptGetLocation(GeolocationAccuracy.Default, 15));
                    }
                    
                    if (location != null) 
                    {
                        _syncService.Log($"[WeatherService] GPS Location found: {location.Latitude}, {location.Longitude}");
                        _debugLogger.Log($"[WeatherService] GPS Location found: {location.Latitude}, {location.Longitude}");
                        if (location.Accuracy.HasValue)
                        {
                            _debugLogger.Log($"[WeatherService] GPS accuracy: {location.Accuracy.Value:F0}m.");
                        }
                        _cachedUserLocation = location;
                        _lastUserLocationTime = DateTime.Now;
                        return location;
                    }
                    _syncService.Log("[WeatherService] GPS Location returned null.");
                    _debugLogger.Log("[WeatherService] GPS Location returned null.");
                }
            }
            catch (Exception ex)
            {
                _syncService.Log($"[WeatherService] Location Exception: {ex}");
                _debugLogger.Log($"[WeatherService] Location Exception: {ex.Message}");
                // Ignore errors to fall through to IP
            }

            // 4. Fallback to IP
            var ipLocation = await GetLocationFromIpAsync();
            if (ipLocation != null)
            {
                _debugLogger.Log("[WeatherService] Location from IP fallback.");
                _cachedUserLocation = ipLocation;
                _lastUserLocationTime = DateTime.Now;
                return ipLocation;
            }

            _debugLogger.Log("[WeatherService] Location unavailable after all attempts.");
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
                var location = await _geolocation.GetLocationAsync(request);
                if (location == null)
                {
                    _debugLogger.Log($"[WeatherService] GPS location returned null (accuracy: {accuracy}).");
                }
                return location;
            }
            catch (Exception ex)
            {
                _syncService.Log($"[WeatherService] GetLocation Error: {ex.Message}");
                _debugLogger.Log($"[WeatherService] GetLocation Error: {ex.Message}");
                return null;
            }
        }

        private async Task<Location?> TryGetLastKnownLocationAsync(TimeSpan timeout)
        {
            try
            {
                var lastKnownTask = _geolocation.GetLastKnownLocationAsync();
                var completed = await Task.WhenAny(lastKnownTask, Task.Delay(timeout));
                if (completed != lastKnownTask)
                {
                    _debugLogger.Log($"[WeatherService] Last known location timed out after {timeout.TotalSeconds:F0}s.");
                    return null;
                }

                var location = await lastKnownTask;
                if (location == null)
                {
                    _debugLogger.Log("[WeatherService] Last known location returned null.");
                }
                return location;
            }
            catch (Exception ex)
            {
                _debugLogger.Log($"[WeatherService] Last known location error: {ex.Message}");
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
            catch (Exception ex)
            {
                _debugLogger.Log($"[WeatherService] IP location error: {ex.Message}");
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
                _debugLogger.Log("[WeatherService] Weather cache hit.");
                return _cachedCurrentWeather;
            }

            try
            {
                var startTime = DateTime.UtcNow;
                _debugLogger.Log($"[WeatherService] Weather fetch start: {latitude}, {longitude} (force={forceRefresh}).");
                // Sanitize units: Default to metric if missing, ensure lowercase
                var rawSetting = _settingsService.Settings.UnitSystem;
                var units = (rawSetting ?? "metric").ToLower();
                
                var url = $"{BaseUrl}/weather?lat={latitude}&lon={longitude}&appid={ApiKey}&units={units}";

                Console.WriteLine($"[WeatherService] Fetching Weather. RawSetting: '{rawSetting}' | UnitsParam: '{units}'");
                Console.WriteLine($"[WeatherService] URL: {url.Replace(ApiKey, "APIKEY")}");
                _debugLogger.Log($"[WeatherService] Weather URL: {url.Replace(ApiKey, "APIKEY")}");

                using var response = await _httpClient.GetAsync(url);
                if (!response.IsSuccessStatusCode)
                {
                    var body = await response.Content.ReadAsStringAsync();
                    _debugLogger.Log($"[WeatherService] Weather API error: {(int)response.StatusCode} {response.ReasonPhrase}. Body: {body}");
                    _debugLogger.Log($"[WeatherService] Weather fetch failed after {(DateTime.UtcNow - startTime).TotalSeconds:F1}s.");
                    return null;
                }

                var result = await response.Content.ReadFromJsonAsync<WeatherResponse>();
                
                if (result != null)
                {
                    Console.WriteLine($"[WeatherService] Result Temp: {result.Main.Temp}");
                    _debugLogger.Log($"[WeatherService] Weather result: {result.Name} {result.Main.Temp}");
                    _cachedCurrentWeather = result;
                    _lastCurrentLocation = (latitude, longitude);
                    _lastCurrentFetchTime = DateTime.Now;
                    _debugLogger.Log($"[WeatherService] Weather fetch completed in {(DateTime.UtcNow - startTime).TotalSeconds:F1}s.");
                    OnWeatherUpdated?.Invoke();
                }
                else
                {
                    _debugLogger.Log("[WeatherService] Weather API returned empty payload.");
                    _debugLogger.Log($"[WeatherService] Weather fetch completed in {(DateTime.UtcNow - startTime).TotalSeconds:F1}s.");
                }
                
                return result;
            }
            catch (Exception ex)
            {
                // Handle error (log it, return null, etc.)
                Console.WriteLine($"Error fetching weather: {ex.Message}");
                _debugLogger.Log($"[WeatherService] Weather fetch exception: {ex.Message}");
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
                _debugLogger.Log("[WeatherService] Forecast cache hit.");
                return _cachedForecast;
            }

            try
            {
                var startTime = DateTime.UtcNow;
                _debugLogger.Log($"[WeatherService] Forecast fetch start: {latitude}, {longitude} (force={forceRefresh}).");
                var units = (_settingsService.Settings.UnitSystem ?? "metric").ToLower();
                var url = $"{BaseUrl}/forecast?lat={latitude}&lon={longitude}&appid={ApiKey}&units={units}";
                _debugLogger.Log($"[WeatherService] Forecast URL: {url.Replace(ApiKey, "APIKEY")}");

                using var response = await _httpClient.GetAsync(url);
                if (!response.IsSuccessStatusCode)
                {
                    var body = await response.Content.ReadAsStringAsync();
                    _debugLogger.Log($"[WeatherService] Forecast API error: {(int)response.StatusCode} {response.ReasonPhrase}. Body: {body}");
                    _debugLogger.Log($"[WeatherService] Forecast fetch failed after {(DateTime.UtcNow - startTime).TotalSeconds:F1}s.");
                    return null;
                }

                var result = await response.Content.ReadFromJsonAsync<ForecastResponse>();

                if (result != null)
                {
                    _cachedForecast = result;
                    _lastForecastLocation = (latitude, longitude);
                    _lastForecastFetchTime = DateTime.Now;
                    // Note: We might want to invoke update here too, but usually CurrentWeather is the trigger. 
                    // Let's invoke it just in case Forecast updates independently.
                    _debugLogger.Log($"[WeatherService] Forecast fetch completed in {(DateTime.UtcNow - startTime).TotalSeconds:F1}s.");
                    OnWeatherUpdated?.Invoke(); 
                }
                else
                {
                    _debugLogger.Log("[WeatherService] Forecast API returned empty payload.");
                    _debugLogger.Log($"[WeatherService] Forecast fetch completed in {(DateTime.UtcNow - startTime).TotalSeconds:F1}s.");
                }

                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error fetching forecast: {ex.Message}");
                _debugLogger.Log($"[WeatherService] Forecast fetch exception: {ex.Message}");
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
