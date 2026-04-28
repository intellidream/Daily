namespace Daily_WinUI.Models;

public sealed class WeatherSnapshot
{
    public required string LocationName { get; init; }
    public required string Description { get; init; }
    public string IconCode { get; init; } = "01d";
    public double Temperature { get; init; }
    public double FeelsLike { get; init; }
    public double TempMin { get; init; }
    public double TempMax { get; init; }
    public int Humidity { get; init; }
    public double WindSpeed { get; init; }
    public int Visibility { get; init; }
    public int Pressure { get; init; }
    public long Sunrise { get; init; }
    public long Sunset { get; init; }
    public DateTime RetrievedAtUtc { get; init; }
}
