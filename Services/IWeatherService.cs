using Daily.Models;

namespace Daily.Services
{
    public interface IWeatherService
    {
        Task<WeatherResponse> GetCurrentWeatherAsync(double latitude, double longitude);
        Task<ForecastResponse> GetForecastAsync(double latitude, double longitude);
        string GetApiKey();
        
        string CurrentLocationName { get; }
        bool IsAutoLocation { get; }
        event Action OnLocationChanged;
        void SetCurrentLocation(string name, bool isAuto);
    }
}
