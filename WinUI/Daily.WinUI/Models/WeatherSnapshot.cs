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
    public int WindDeg { get; init; }
    public int Clouds { get; init; }
    public int Visibility { get; init; }
    public int Pressure { get; init; }
    public long Sunrise { get; init; }
    public long Sunset { get; init; }
    public DateTime RetrievedAtUtc { get; init; }

    public string WindDirection => WindDirectionHelper.FromDegrees(WindDeg);
}

public static class WindDirectionHelper
{
    private static readonly string[] Directions = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" };

    public static string FromDegrees(int degrees)
    {
        var normalized = ((degrees % 360) + 360) % 360;
        var index = (int)Math.Floor((normalized + 11.25) / 22.5) % 16;
        return Directions[index];
    }
}

