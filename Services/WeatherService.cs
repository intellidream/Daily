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
        
        private const double LocationTolerance = 0.01; // Roughly 1km
        private readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(15);

        public WeatherService()
        {
            _httpClient = new HttpClient();
        }

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
                var url = $"{BaseUrl}/weather?lat={latitude}&lon={longitude}&appid={ApiKey}&units=metric";
                var result = await _httpClient.GetFromJsonAsync<WeatherResponse>(url);
                
                if (result != null)
                {
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
                var url = $"{BaseUrl}/forecast?lat={latitude}&lon={longitude}&appid={ApiKey}&units=metric";
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
