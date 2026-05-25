using System.Text.Json;

namespace Daily_WinUI.Services;

public sealed class DetailWindowPosition
{
    public int X { get; set; }
    public int Y { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
}

public sealed class AppSettings
{
    public double? LastLatitude { get; set; }
    public double? LastLongitude { get; set; }
    public string? LastLocationName { get; set; }
    /// <summary>True when the last loaded location came from auto-detection, not a manual search.</summary>
    public bool LastLocationWasAuto { get; set; }
    /// <summary>When true, always attempt GPS/IP auto-detection at startup and on manual refresh, ignoring any saved location.</summary>
    public bool AlwaysAutoLocation { get; set; } = false;
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
    public bool CloseToTray { get; set; } = false;
    public bool EnableSmartBriefing { get; set; } = true;
    public bool LocalAiModelDownloaded { get; set; } = false;
    public string SelectedAiAccelerator { get; set; } = "Auto";
    /// <summary>Saved position per detail page type name (e.g. "WeatherDetailPage").</summary>
    public Dictionary<string, DetailWindowPosition> DetailWindowPositions { get; set; } = new();
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

    private static AppSettings? _cachedSettings;
    private static readonly object _lock = new();

    public static AppSettings Load()
    {
        lock (_lock)
        {
            if (_cachedSettings != null)
            {
                return _cachedSettings;
            }

            try
            {
                if (File.Exists(_path))
                {
                    var json = File.ReadAllText(_path);
                    _cachedSettings = JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
                    return _cachedSettings;
                }
            }
            catch { }

            _cachedSettings = new AppSettings();
            return _cachedSettings;
        }
    }

    public static void Save(AppSettings settings)
    {
        lock (_lock)
        {
            _cachedSettings = settings;
            try
            {
                Directory.CreateDirectory(_dir);
                File.WriteAllText(_path, JsonSerializer.Serialize(settings, _jsonOptions));
            }
            catch { }
        }
    }

    public static string GetProcessorName()
    {
        try
        {
            using (var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0"))
            {
                if (key != null)
                {
                    return key.GetValue("ProcessorNameString")?.ToString() ?? "Unknown Processor";
                }
            }
        }
        catch { }
        return "Unknown Processor";
    }

    public static string? GetDetectedNpuName()
    {
        try
        {
            string name = GetProcessorName();
            if (!string.IsNullOrEmpty(name))
            {
                if (name.Contains("Snapdragon") || name.Contains("Qualcomm") || name.Contains("SQ3") || name.Contains("SQ2"))
                {
                    return "Qualcomm Hexagon NPU (45 TOPS)";
                }
                if (name.Contains("Ultra") || name.Contains("Intel") && (name.Contains("Core(TM) Ultra") || name.Contains("Lunar Lake")))
                {
                    return "Intel(R) AI Boost NPU (48 TOPS)";
                }
                if (name.Contains("Ryzen") || name.Contains("AMD") && (name.Contains("AI") || name.Contains("Strix Point") || name.Contains("7840") || name.Contains("8840")))
                {
                    return "AMD Ryzen AI NPU (50 TOPS)";
                }
            }
        }
        catch { }
        return null;
    }

    public static double ConvertSleepToHours(double value, string? unit)
    {
        if (value <= 0) return 0;
        
        if (string.IsNullOrEmpty(unit))
        {
            // Auto-detect based on magnitude
            if (value > 2000)
            {
                // Likely seconds (e.g. 25000s = 6.94h)
                return value / 3600.0;
            }
            else if (value > 24)
            {
                // Likely minutes (e.g. 450m = 7.5h)
                return value / 60.0;
            }
            return value; // Likely hours
        }

        var normalizedUnit = unit.ToLowerInvariant();
        if (normalizedUnit.Contains("sec") || normalizedUnit == "s")
        {
            return value / 3600.0;
        }
        if (normalizedUnit.Contains("min") || normalizedUnit == "m")
        {
            return value / 60.0;
        }
        if (normalizedUnit.Contains("hour") || normalizedUnit == "h")
        {
            return value;
        }
        
        // Guess fallback
        if (value > 2000) return value / 3600.0;
        if (value > 24) return value / 60.0;
        return value;
    }

    public static double ConvertSleepToMinutes(double value, string? unit)
    {
        return ConvertSleepToHours(value, unit) * 60.0;
    }
}
