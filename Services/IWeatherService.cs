using Daily.Models;

namespace Daily.Services
{
    public interface IWeatherService
    {
        Task<WeatherResponse> GetCurrentWeatherAsync(double latitude, double longitude);
        Task<ForecastResponse> GetForecastAsync(double latitude, double longitude);
    }
}
