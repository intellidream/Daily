namespace Daily_WinUI.Models;

public sealed class HourlyForecastSnapshot
{
    public required string HourLabel { get; init; }
    public string IconCode { get; init; } = "01d";
    public int Temperature { get; init; }
    public int PrecipitationChance { get; init; }
    public Uri IconUri => new($"https://openweathermap.org/img/wn/{IconCode}@2x.png");
    public string TemperatureText => $"{Temperature}°";
    public string PrecipitationText => $"{PrecipitationChance}%";
}
