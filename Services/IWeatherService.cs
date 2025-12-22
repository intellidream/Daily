using Daily.Models;

namespace Daily.Services
{
    public interface IWeatherService
    {
        Task<WeatherResponse> GetCurrentWeatherAsync(double latitude, double longitude, bool forceRefresh = false);
        Task<ForecastResponse> GetForecastAsync(double latitude, double longitude, bool forceRefresh = false);
        string GetApiKey();
        
        string CurrentLocationName { get; }
        bool IsAutoLocation { get; }
        event Action OnLocationChanged;
        event Action OnWeatherUpdated;
        void SetCurrentLocation(string name, bool isAuto);
        Task<Location?> GetResilientLocationAsync();
    }
}
