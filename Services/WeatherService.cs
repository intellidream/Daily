using System.Net.Http.Json;
using Daily.Models;

namespace Daily.Services
{
    public class WeatherService : IWeatherService
    {
        private readonly HttpClient _httpClient;
        private const string ApiKey = "eebcefca9dbf33a96cb6d583481235d2";
        private const string BaseUrl = "https://api.openweathermap.org/data/2.5";

        public WeatherService()
        {
            _httpClient = new HttpClient();
        }

        public async Task<WeatherResponse> GetCurrentWeatherAsync(double latitude, double longitude)
        {
            try
            {
                var url = $"{BaseUrl}/weather?lat={latitude}&lon={longitude}&appid={ApiKey}&units=metric";
                return await _httpClient.GetFromJsonAsync<WeatherResponse>(url);
            }
            catch (Exception ex)
            {
                // Handle error (log it, return null, etc.)
                Console.WriteLine($"Error fetching weather: {ex.Message}");
                return null;
            }
        }

        public async Task<ForecastResponse> GetForecastAsync(double latitude, double longitude)
        {
            try
            {
                var url = $"{BaseUrl}/forecast?lat={latitude}&lon={longitude}&appid={ApiKey}&units=metric";
                return await _httpClient.GetFromJsonAsync<ForecastResponse>(url);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error fetching forecast: {ex.Message}");
                return null;
            }
        }
    }
}
