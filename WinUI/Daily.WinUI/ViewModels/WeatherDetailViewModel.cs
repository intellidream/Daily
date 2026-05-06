using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using System.Globalization;
using Daily_WinUI.Models;
using Daily_WinUI.Services;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Daily_WinUI.ViewModels;

public sealed class WeatherDetailViewModel : INotifyPropertyChanged
{
    private readonly WeatherClient _weatherClient = new();

    private string _statusText = "Loading weather...";
    private string _locationName = "-";
    private string _description = "-";
    private string _temperature = "--";
    private string _details = string.Empty;
    private string _feelsLike = "--";
    private string _highLow = "H --  L --";
    private string _humidity = "--";
    private double _humidityValue;
    private double _windSpeedValue;
    private string _wind = "--";
    private string _visibility = "--";
    private string _pressure = "--";
    private string _sunrise = "--:--";
    private string _sunset = "--:--";
    private string _sunLabel = "Sunrise";
    private string _sunValue = "--:--";
    private string _moistureLabel = "Humidity";
    private string _moistureValue = "--";
    private bool _hasWeatherAlert;
    private string _weatherAlertText = string.Empty;
    private string _iconUrl = "https://openweathermap.org/img/wn/01d@4x.png";
    private bool _isBusy;
    private string _unitSystem = "metric";
    private string _windUnit = "m/s";
    private string _pressureUnit = "hpa";
    private bool _showSunrise = true;
    private bool _showHumidity = true;
    private WeatherSnapshot? _lastSnapshot;
    private long _sunriseUnix;
    private long _sunsetUnix;
    private double _sunriseAnnotationX = -1;
    private double _sunsetAnnotationX = -1;
    private bool _showSunriseAnnotation;
    private bool _showSunsetAnnotation;
    private double _currentAnnotationX = -1;
    private bool _showCurrentAnnotation;
    private string _currentAnnotationIcon = "01d";
    private string _currentAnnotationTemp = "--°";
    private Brush _hourlyChartFill = new SolidColorBrush(Color.FromArgb(0x80, 0x69, 0xB6, 0xFF));
    private Brush _hourlyChartStroke = new SolidColorBrush(Color.FromArgb(0xFF, 0x69, 0xB6, 0xFF));

    public ObservableCollection<ForecastDaySnapshot> ForecastDays { get; } = new();
    public ObservableCollection<HourlyForecastSnapshot> HourlyForecast { get; } = new();

    public Brush HourlyChartFill
    {
        get => _hourlyChartFill;
        private set => SetProperty(ref _hourlyChartFill, value);
    }

    public Brush HourlyChartStroke
    {
        get => _hourlyChartStroke;
        private set => SetProperty(ref _hourlyChartStroke, value);
    }

    public double SunriseAnnotationX
    {
        get => _sunriseAnnotationX;
        private set => SetProperty(ref _sunriseAnnotationX, value);
    }

    public double SunsetAnnotationX
    {
        get => _sunsetAnnotationX;
        private set => SetProperty(ref _sunsetAnnotationX, value);
    }

    public bool ShowSunriseAnnotation
    {
        get => _showSunriseAnnotation;
        private set => SetProperty(ref _showSunriseAnnotation, value);
    }

    public bool ShowSunsetAnnotation
    {
        get => _showSunsetAnnotation;
        private set => SetProperty(ref _showSunsetAnnotation, value);
    }

    public double CurrentAnnotationX
    {
        get => _currentAnnotationX;
        private set => SetProperty(ref _currentAnnotationX, value);
    }

    public bool ShowCurrentAnnotation
    {
        get => _showCurrentAnnotation;
        private set => SetProperty(ref _showCurrentAnnotation, value);
    }

    public string CurrentAnnotationIcon
    {
        get => _currentAnnotationIcon;
        private set => SetProperty(ref _currentAnnotationIcon, value);
    }

    public string CurrentAnnotationTemp
    {
        get => _currentAnnotationTemp;
        private set => SetProperty(ref _currentAnnotationTemp, value);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    public string LocationName
    {
        get => _locationName;
        private set => SetProperty(ref _locationName, value);
    }

    public string Description
    {
        get => _description;
        private set => SetProperty(ref _description, value);
    }

    public string Temperature
    {
        get => _temperature;
        private set => SetProperty(ref _temperature, value);
    }

    public string Details
    {
        get => _details;
        private set => SetProperty(ref _details, value);
    }

    public string FeelsLike
    {
        get => _feelsLike;
        private set => SetProperty(ref _feelsLike, value);
    }

    public string HighLow
    {
        get => _highLow;
        private set => SetProperty(ref _highLow, value);
    }

    public string Humidity
    {
        get => _humidity;
        private set => SetProperty(ref _humidity, value);
    }

    public double HumidityValue
    {
        get => _humidityValue;
        private set => SetProperty(ref _humidityValue, value);
    }

    public double WindSpeedValue
    {
        get => _windSpeedValue;
        private set => SetProperty(ref _windSpeedValue, value);
    }

    public string Wind
    {
        get => _wind;
        private set => SetProperty(ref _wind, value);
    }

    public string Visibility
    {
        get => _visibility;
        private set => SetProperty(ref _visibility, value);
    }

    public string Pressure
    {
        get => _pressure;
        private set => SetProperty(ref _pressure, value);
    }

    public string Sunrise
    {
        get => _sunrise;
        private set => SetProperty(ref _sunrise, value);
    }

    public string Sunset
    {
        get => _sunset;
        private set => SetProperty(ref _sunset, value);
    }

    public string SunLabel
    {
        get => _sunLabel;
        private set => SetProperty(ref _sunLabel, value);
    }

    public string SunValue
    {
        get => _sunValue;
        private set => SetProperty(ref _sunValue, value);
    }

    public string MoistureLabel
    {
        get => _moistureLabel;
        private set => SetProperty(ref _moistureLabel, value);
    }

    public string MoistureValue
    {
        get => _moistureValue;
        private set => SetProperty(ref _moistureValue, value);
    }

    public string IconUrl
    {
        get => _iconUrl;
        private set => SetProperty(ref _iconUrl, value);
    }

    public bool HasWeatherAlert
    {
        get => _hasWeatherAlert;
        private set => SetProperty(ref _hasWeatherAlert, value);
    }

    public string WeatherAlertText
    {
        get => _weatherAlertText;
        private set => SetProperty(ref _weatherAlertText, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetProperty(ref _isBusy, value);
    }

    public async Task LoadWeatherAsync(
        double latitude,
        double longitude,
        string unitSystem,
        string windUnit,
        string pressureUnit,
        bool showSunrise,
        bool showHumidity,
        CancellationToken cancellationToken = default)
    {
        if (IsBusy)
        {
            return;
        }

        try
        {
            IsBusy = true;
            StatusText = "Fetching weather...";

            _unitSystem = unitSystem;
            _windUnit = windUnit;
            _pressureUnit = pressureUnit;
            _showSunrise = showSunrise;
            _showHumidity = showHumidity;

            var currentTask = _weatherClient.GetCurrentWeatherAsync(latitude, longitude, unitSystem, cancellationToken);
            var dailyTask = _weatherClient.GetFiveDayForecastAsync(latitude, longitude, unitSystem, cancellationToken);
            var hourlyTask = _weatherClient.GetHourlyForecastAsync(latitude, longitude, unitSystem, 8, cancellationToken);
            await Task.WhenAll(currentTask, dailyTask, hourlyTask);

            var snapshot = await currentTask;
            if (snapshot is null)
            {
                StatusText = "Could not load weather right now.";
                ForecastDays.Clear();
                HourlyForecast.Clear();
                return;
            }

            var forecast = await dailyTask;
            var hourly = await hourlyTask;
            _lastSnapshot = snapshot;

            LocationName = snapshot.LocationName;
            Description = ToTitleCase(snapshot.Description);
            Temperature = $"{snapshot.Temperature:0.#}°{(_unitSystem == "imperial" ? "F" : "C")}";
            FeelsLike = $"{snapshot.FeelsLike:0.#}°";
            HighLow = $"H {snapshot.TempMax:0.#}°  L {snapshot.TempMin:0.#}°";
            Humidity = $"{snapshot.Humidity}%";
            HumidityValue = snapshot.Humidity;
            WindSpeedValue = snapshot.WindSpeed;
            Wind = FormatWind(snapshot.WindSpeed, _unitSystem, _windUnit);
            Visibility = $"{Math.Round(snapshot.Visibility / 1000.0, 1):0.#} km";
            Pressure = FormatPressure(snapshot.Pressure, _pressureUnit);
            _sunriseUnix = snapshot.Sunrise;
            _sunsetUnix = snapshot.Sunset;
            Sunrise = snapshot.Sunrise > 0 ? DateTimeOffset.FromUnixTimeSeconds(snapshot.Sunrise).ToLocalTime().ToString("HH:mm") : "--:--";
            Sunset = snapshot.Sunset > 0 ? DateTimeOffset.FromUnixTimeSeconds(snapshot.Sunset).ToLocalTime().ToString("HH:mm") : "--:--";
            IconUrl = $"https://openweathermap.org/img/wn/{snapshot.IconCode}@4x.png";
            Details = $"Updated weather for {snapshot.LocationName}";

            var isStorm = (snapshot.IconCode ?? string.Empty).StartsWith("11", StringComparison.Ordinal);
            HasWeatherAlert = snapshot.WindSpeed >= 14.0 || isStorm;
            WeatherAlertText = HasWeatherAlert ? "!" : string.Empty;

            ForecastDays.Clear();
            foreach (var day in forecast)
            {
                ForecastDays.Add(day);
            }

            HourlyForecast.Clear();
            foreach (var hour in hourly)
            {
                HourlyForecast.Add(hour);
            }
            RebuildHourlyChartBrush();
            RebuildSunAnnotations();

            UpdateToggleDisplays();
            StatusText = $"Updated {snapshot.RetrievedAtUtc.ToLocalTime():HH:mm:ss}";
        }
        catch (OperationCanceledException)
        {
            StatusText = "Request canceled.";
        }
        catch (Exception)
        {
            StatusText = "Unable to fetch weather. Check internet/API key.";
        }
        finally
        {
            IsBusy = false;
        }
    }

    public void SetStatus(string status)
    {
        StatusText = status;
    }

    public void ToggleSunPhase()
    {
        _showSunrise = !_showSunrise;
        UpdateToggleDisplays();
    }

    public void ToggleMoisturePressure()
    {
        _showHumidity = !_showHumidity;
        UpdateToggleDisplays();
    }

    private void UpdateToggleDisplays()
    {
        SunLabel = _showSunrise ? "Sunrise" : "Sunset";
        SunValue = _showSunrise ? Sunrise : Sunset;

        if (_showHumidity)
        {
            MoistureLabel = "Humidity";
            MoistureValue = Humidity;
            return;
        }

        MoistureLabel = "Pressure";
        MoistureValue = _lastSnapshot is null ? "--" : FormatPressure(_lastSnapshot.Pressure, _pressureUnit);
    }

    private static string FormatPressure(int pressureHpa, string pressureUnit)
    {
        var unit = (pressureUnit ?? "hpa").Trim().ToLowerInvariant();
        return unit switch
        {
            "mmhg" => $"{Math.Round(pressureHpa * 0.750062)} mmHg",
            "inhg" => $"{Math.Round(pressureHpa * 0.02953, 2).ToString("0.##", CultureInfo.InvariantCulture)} inHg",
            _ => $"{pressureHpa} hPa"
        };
    }

    private static string FormatWind(double speedFromApi, string unitSystem, string targetWindUnit)
    {
        var isImperialBase = string.Equals(unitSystem, "imperial", StringComparison.OrdinalIgnoreCase);
        var speedMs = isImperialBase ? speedFromApi * 0.44704 : speedFromApi;
        var target = (targetWindUnit ?? "m/s").Trim().ToLowerInvariant();

        return target switch
        {
            "km/h" or "kmh" => $"{(speedMs * 3.6):0.#} km/h",
            "mph" => $"{(speedMs * 2.23694):0.#} mph",
            "kn" => $"{(speedMs * 1.94384):0.#} kn",
            _ => $"{speedMs:0.#} m/s"
        };
    }

    private void RebuildHourlyChartBrush()
    {
        var hours = HourlyForecast;
        if (hours.Count == 0)
        {
            return;
        }

        var fillGradient = new LinearGradientBrush { StartPoint = new(0, 0), EndPoint = new(1, 0) };
        var strokeGradient = new LinearGradientBrush { StartPoint = new(0, 0), EndPoint = new(1, 0) };

        for (int i = 0; i < hours.Count; i++)
        {
            double offset = i / (double)(hours.Count - 1);
            var (fill, stroke) = ConditionColors(hours[i].IconCode);
            fillGradient.GradientStops.Add(new GradientStop { Color = fill, Offset = offset });
            strokeGradient.GradientStops.Add(new GradientStop { Color = stroke, Offset = offset });
        }

        HourlyChartFill = fillGradient;
        HourlyChartStroke = strokeGradient;
    }

    private void RebuildSunAnnotations()
    {
        var hours = HourlyForecast;
        if (hours.Count == 0)
        {
            ShowSunriseAnnotation = false;
            ShowSunsetAnnotation = false;
            ShowCurrentAnnotation = false;
            return;
        }

        // Returns fractional 0-based index by interpolating between the two hourly slots
        // that bracket the given unix timestamp.
        // OWM sunrise/sunset are always for *today*, but the chart may start in the afternoon
        // and show tomorrow morning's hours (e.g. 15:00 → … → 06:00 next day).
        // If the raw unix falls before the first chart slot, advance it by 24 h so it lands
        // on tomorrow's equivalent time which IS inside the chart window.
        double FindAnnotationX(long unix)
        {
            if (unix <= 0) return -1;

            const long day = 86400;
            // Advance by 24 h increments until the timestamp is at or after the first slot,
            // but stop if we've gone past the last slot (it's outside the window entirely).
            while (unix < hours[0].UnixTime)
                unix += day;

            if (unix > hours[^1].UnixTime) return -1; // outside the chart window

            if (unix <= hours[0].UnixTime) return 0;

            for (int i = 1; i < hours.Count; i++)
            {
                if (unix <= hours[i].UnixTime)
                {
                    var span = hours[i].UnixTime - hours[i - 1].UnixTime;
                    var frac = span > 0 ? (double)(unix - hours[i - 1].UnixTime) / span : 0;
                    return (i - 1) + frac;
                }
            }

            return -1;
        }

        var rx = FindAnnotationX(_sunriseUnix);
        var sx = FindAnnotationX(_sunsetUnix);
        SunriseAnnotationX = rx;
        SunsetAnnotationX = sx;
        ShowSunriseAnnotation = rx >= 0;
        ShowSunsetAnnotation = sx >= 0;

        // Current time bubble
        var nowUnix = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var cx = FindAnnotationX(nowUnix);
        CurrentAnnotationX = cx;
        ShowCurrentAnnotation = cx >= 0;
        if (_lastSnapshot is not null)
        {
            CurrentAnnotationIcon = _lastSnapshot.IconCode ?? "01d";
            CurrentAnnotationTemp = $"{_lastSnapshot.Temperature:0.#}°";
        }
    }

    // Maps an OWM icon code to (fillColor, strokeColor) representing the weather condition.
    // Sunny=amber, few clouds=warm blue, overcast=steel, rain=deep blue, thunder=violet, snow=icy, mist=gray.
    private static (Color fill, Color stroke) ConditionColors(string iconCode)
    {
        var prefix = iconCode.Length >= 2 ? iconCode[..2] : "01";
        return prefix switch
        {
            "01" => (Color.FromArgb(0x80, 0xFF, 0xD1, 0x66), Color.FromArgb(0xFF, 0xFF, 0xC1, 0x3A)), // clear — amber
            "02" => (Color.FromArgb(0x80, 0xFF, 0xE0, 0x90), Color.FromArgb(0xFF, 0xFF, 0xD1, 0x66)), // few clouds — light amber
            "03" => (Color.FromArgb(0x80, 0x90, 0xB8, 0xD8), Color.FromArgb(0xFF, 0x70, 0xA8, 0xD0)), // scattered clouds — steel blue
            "04" => (Color.FromArgb(0x80, 0x70, 0x90, 0xB0), Color.FromArgb(0xFF, 0x50, 0x78, 0xA0)), // broken/overcast — darker steel
            "09" => (Color.FromArgb(0x80, 0x40, 0x80, 0xD0), Color.FromArgb(0xFF, 0x20, 0x60, 0xC0)), // drizzle — deep blue
            "10" => (Color.FromArgb(0x80, 0x30, 0x70, 0xD8), Color.FromArgb(0xFF, 0x10, 0x50, 0xC8)), // rain — deeper blue
            "11" => (Color.FromArgb(0x90, 0x80, 0x50, 0xD0), Color.FromArgb(0xFF, 0x70, 0x30, 0xC8)), // thunderstorm — purple
            "13" => (Color.FromArgb(0x80, 0xC8, 0xE8, 0xFF), Color.FromArgb(0xFF, 0xA8, 0xD8, 0xFF)), // snow — icy
            "50" => (Color.FromArgb(0x80, 0xA0, 0xB8, 0xC8), Color.FromArgb(0xFF, 0x80, 0xA0, 0xB8)), // mist — gray-blue
            _    => (Color.FromArgb(0x80, 0x69, 0xB6, 0xFF), Color.FromArgb(0xFF, 0x69, 0xB6, 0xFF)), // default
        };
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

    private void SetProperty<T>(ref T backingField, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(backingField, value))
        {
            return;
        }

        backingField = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
