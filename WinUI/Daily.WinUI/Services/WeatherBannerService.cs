namespace Daily_WinUI.Services;

/// <summary>
/// Lightweight static event bus that broadcasts the current weather icon code.
/// Also caches the last known code so late subscribers can apply it immediately.
/// </summary>
public static class WeatherBannerService
{
    /// <summary>The most recently received icon code, or null if weather hasn't loaded yet.</summary>
    public static string? LastIconCode { get; private set; }

    /// <summary>Fired with the OpenWeatherMap icon code after a successful weather fetch.</summary>
    public static event Action<string>? WeatherConditionChanged;

    public static void NotifyConditionChanged(string iconCode)
    {
        if (!string.IsNullOrWhiteSpace(iconCode))
        {
            LastIconCode = iconCode;
            WeatherConditionChanged?.Invoke(iconCode);
        }
    }
}
