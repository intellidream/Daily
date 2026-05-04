using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using System.Globalization;
using Daily_WinUI.Models;
using Daily_WinUI.Services;

namespace Daily_WinUI.ViewModels;

public sealed class MainPageViewModel : INotifyPropertyChanged
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

    public ObservableCollection<ForecastDaySnapshot> ForecastDays { get; } = new();
    public ObservableCollection<HourlyForecastSnapshot> HourlyForecast { get; } = new();

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
