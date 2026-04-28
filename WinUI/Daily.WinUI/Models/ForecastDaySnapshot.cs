namespace Daily_WinUI.Models;

public sealed class ForecastDaySnapshot
{
    public required string DayLabel { get; init; }
    public required string Description { get; init; }
    public string IconCode { get; init; } = "01d";
    public int PrecipitationChance { get; init; }
    public double MinTemp { get; init; }
    public double MaxTemp { get; init; }
    public string PrecipitationText => $"Rain {PrecipitationChance}%";
    public string MaxTempText => $"{MaxTemp:0.#}°";
    public string MinTempText => $"{MinTemp:0.#}°";
}