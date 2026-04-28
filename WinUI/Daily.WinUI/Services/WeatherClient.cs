using System.Net.Http.Json;
using Daily.Models;
using Daily_WinUI.Models;

namespace Daily_WinUI.Services;

public sealed class WeatherClient
{
    private const string BaseUrl = "https://api.openweathermap.org/data/2.5";
    private const string GeoUrl = "https://api.openweathermap.org/geo/1.0";
    private readonly HttpClient _httpClient = new();

    public async Task<IReadOnlyList<LocationSuggestion>> SearchLocationsAsync(string query, int limit = 8, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return Array.Empty<LocationSuggestion>();
        }

        var url = $"{GeoUrl}/direct?q={Uri.EscapeDataString(query)}&limit={limit}&appid={Daily.Configuration.Secrets.OpenWeatherMapApiKey}";
        var response = await _httpClient.GetFromJsonAsync<List<GeoDirectItem>>(url, cancellationToken);
        if (response is null || response.Count == 0)
        {
            return Array.Empty<LocationSuggestion>();
        }

        return response
            .Select(item => new LocationSuggestion
            {
                Name = item.Name ?? "Unknown",
                State = item.State,
                Country = item.Country ?? "-",
                Latitude = item.Lat,
                Longitude = item.Lon,
                DisplayName = FormatDisplayName(item.Name, item.State, item.Country)
            })
            .ToList();
    }

    public async Task<WeatherSnapshot?> GetCurrentWeatherAsync(double latitude, double longitude, string unitSystem = "metric", CancellationToken cancellationToken = default)
    {
        var normalizedUnitSystem = NormalizeUnitSystem(unitSystem);
        var url = $"{BaseUrl}/weather?lat={latitude}&lon={longitude}&appid={Daily.Configuration.Secrets.OpenWeatherMapApiKey}&units={normalizedUnitSystem}";
        var response = await _httpClient.GetFromJsonAsync<WeatherResponse>(url, cancellationToken);

        if (response?.Main is null || response.Weather is null || response.Weather.Count == 0)
        {
            return null;
        }

        return new WeatherSnapshot
        {
            LocationName = string.IsNullOrWhiteSpace(response.Name) ? "Unknown location" : response.Name,
            Description = response.Weather[0].Description,
            IconCode = string.IsNullOrWhiteSpace(response.Weather[0].Icon) ? "01d" : response.Weather[0].Icon,
            Temperature = response.Main.Temp,
            FeelsLike = response.Main.FeelsLike,
            TempMin = response.Main.TempMin,
            TempMax = response.Main.TempMax,
            Humidity = response.Main.Humidity,
            WindSpeed = response.Wind?.Speed ?? 0,
            Visibility = response.Visibility,
            Pressure = response.Main.Pressure,
            Sunrise = response.Sys?.Sunrise ?? 0,
            Sunset = response.Sys?.Sunset ?? 0,
            RetrievedAtUtc = DateTime.UtcNow
        };
    }

    public async Task<ForecastResponse?> GetForecastResponseAsync(double latitude, double longitude, string unitSystem = "metric", CancellationToken cancellationToken = default)
    {
        var normalizedUnitSystem = NormalizeUnitSystem(unitSystem);
        var url = $"{BaseUrl}/forecast?lat={latitude}&lon={longitude}&appid={Daily.Configuration.Secrets.OpenWeatherMapApiKey}&units={normalizedUnitSystem}";
        return await _httpClient.GetFromJsonAsync<ForecastResponse>(url, cancellationToken);
    }

    public async Task<IReadOnlyList<ForecastDaySnapshot>> GetFiveDayForecastAsync(double latitude, double longitude, string unitSystem = "metric", CancellationToken cancellationToken = default)
    {
        var response = await GetForecastResponseAsync(latitude, longitude, unitSystem, cancellationToken);

        if (response?.List is null || response.List.Count == 0)
        {
            return Array.Empty<ForecastDaySnapshot>();
        }

        var nowDate = DateTimeOffset.UtcNow.Date;
        var items = response.List
            .Select(item =>
            {
                var at = DateTimeOffset.FromUnixTimeSeconds(item.Dt).ToLocalTime().DateTime;
                var iconCode = item.Weather?.FirstOrDefault()?.Icon;
                return new
                {
                    At = at,
                    Temp = item.Main?.Temp ?? 0,
                    Description = item.Weather?.FirstOrDefault()?.Description ?? "-",
                    IconCode = string.IsNullOrWhiteSpace(iconCode) ? "01d" : iconCode,
                    Pop = item.Pop < 0 ? 0 : item.Pop
                };
            })
            .Where(x => x.At.Date > nowDate)
            .GroupBy(x => x.At.Date)
            .OrderBy(g => g.Key)
            .Take(5)
            .Select(g => new ForecastDaySnapshot
            {
                DayLabel = g.Key.ToString("ddd"),
                Description = ToTitleCase(g.OrderBy(x => Math.Abs(x.At.Hour - 12)).First().Description),
                IconCode = g.OrderBy(x => Math.Abs(x.At.Hour - 12)).First().IconCode,
                PrecipitationChance = (int)Math.Round(g.Max(x => x.Pop) * 100),
                MinTemp = g.Min(x => x.Temp),
                MaxTemp = g.Max(x => x.Temp)
            })
            .ToList();

        return items;
    }

    public async Task<IReadOnlyList<HourlyForecastSnapshot>> GetHourlyForecastAsync(double latitude, double longitude, string unitSystem = "metric", int hours = 8, CancellationToken cancellationToken = default)
    {
        var response = await GetForecastResponseAsync(latitude, longitude, unitSystem, cancellationToken);
        if (response?.List is null || response.List.Count == 0)
        {
            return Array.Empty<HourlyForecastSnapshot>();
        }

        return response.List
            .Take(Math.Max(1, hours))
            .Select(item =>
            {
                var at = DateTimeOffset.FromUnixTimeSeconds(item.Dt).ToLocalTime();
                var iconCode = item.Weather?.FirstOrDefault()?.Icon;
                return new HourlyForecastSnapshot
                {
                    HourLabel = at.ToString("HH:mm"),
                    IconCode = string.IsNullOrWhiteSpace(iconCode) ? "01d" : iconCode,
                    Temperature = (int)Math.Round(item.Main?.Temp ?? 0),
                    PrecipitationChance = (int)Math.Round((item.Pop < 0 ? 0 : item.Pop) * 100)
                };
            })
            .ToList();
    }

    private static string NormalizeUnitSystem(string? unitSystem)
    {
        var value = (unitSystem ?? "metric").Trim().ToLowerInvariant();
        return value == "imperial" ? "imperial" : "metric";
    }

    private static string ToTitleCase(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "-";
        }

        return string.Join(' ', value.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(word => char.ToUpperInvariant(word[0]) + word.Substring(1)));
    }

    private static string FormatDisplayName(string? name, string? state, string? country)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(name))
        {
            parts.Add(name);
        }
        if (!string.IsNullOrWhiteSpace(state))
        {
            parts.Add(state);
        }
        if (!string.IsNullOrWhiteSpace(country))
        {
            parts.Add(country);
        }

        return parts.Count == 0 ? "Unknown" : string.Join(", ", parts);
    }

    private sealed class GeoDirectItem
    {
        public string? Name { get; set; }
        public double Lat { get; set; }
        public double Lon { get; set; }
        public string? Country { get; set; }
        public string? State { get; set; }
    }

}
