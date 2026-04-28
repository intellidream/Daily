using System.Text.Json;

namespace Daily_WinUI.Services;

public sealed class AppSettings
{
    public double? LastLatitude { get; set; }
    public double? LastLongitude { get; set; }
    public string? LastLocationName { get; set; }
    public string GlassIntensity { get; set; } = "Medium";
    public string UnitSystem { get; set; } = "metric";
    public string WindUnit { get; set; } = "m/s";
    public string PressureUnit { get; set; } = "hpa";
    public bool ShowSunrise { get; set; } = true;
    public bool ShowHumidity { get; set; } = true;
    public List<SavedLocation> FavoriteLocations { get; set; } = new();
    public List<SavedLocation> RecentLocations { get; set; } = new();
    public int WindowX { get; set; }
    public int WindowY { get; set; }
    public int WindowWidth { get; set; }
    public int WindowHeight { get; set; }
    public bool HasWindowPosition { get; set; }
}

public sealed class SavedLocation
{
    public string DisplayName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Country { get; set; } = string.Empty;
    public string? State { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public string FavoriteCategory { get; set; } = "Travel";
    public bool IsPinned { get; set; }
}

public static class SettingsService
{
    private static readonly string _dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Daily.WinUI");

    private static readonly string _path = Path.Combine(_dir, "settings.json");

    private static readonly JsonSerializerOptions _jsonOptions = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(_path))
            {
                var json = File.ReadAllText(_path);
                return JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
            }
        }
        catch { }
        return new AppSettings();
    }

    public static void Save(AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(_dir);
            File.WriteAllText(_path, JsonSerializer.Serialize(settings, _jsonOptions));
        }
        catch { }
    }
}
