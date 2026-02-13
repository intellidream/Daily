using System.Collections.ObjectModel;
using System.Globalization;
using System.Linq;
using System.Windows.Input;
using Daily.Models;
using Daily.Services;
using Microsoft.Maui.ApplicationModel;

namespace Daily.ViewModels
{
    public class WeatherViewModel : ViewModelBase
    {
        private readonly IWeatherService _weatherService;
        private readonly ISettingsService _settingsService;
        private readonly IRefreshService _refreshService;

        private bool _isBusy;
        private string _locationName = "";
        private string _temperatureText = "--";
        private double _temperatureValue;
        private string _conditionText = "--";
        private string _conditionTitle = "--";
        private string _iconUrl = "";
        private string _highLowText = "--";
        private string _humidityText = "--";
        private string _windText = "--";
        private string _feelsLikeText = "--";
        private string _pressureText = "--";
        private string _visibilityText = "--";
        private string _sunriseText = "--";
        private string _sunsetText = "--";
        private string _unitSymbol = "°C";
        private double _gaugeMinimum;
        private double _gaugeMaximum = 40;
        private DateTime _lastUpdated;
        private bool _isInitialized;

        public WeatherViewModel(IWeatherService weatherService, ISettingsService settingsService, IRefreshService refreshService)
        {
            _weatherService = weatherService;
            _settingsService = settingsService;
            _refreshService = refreshService;

            ForecastPoints = new ObservableCollection<ForecastPoint>();
            DailyForecasts = new ObservableCollection<DailyForecastPoint>();
            RefreshCommand = new Command(async () => await RefreshAsync(true));

            _refreshService.RefreshRequested += OnRefreshRequestedAsync;
            _refreshService.DetailRefreshRequested += OnRefreshRequestedAsync;

            _weatherService.OnWeatherUpdated += OnWeatherUpdated;
            _weatherService.OnLocationChanged += OnLocationChanged;
        }

        public ObservableCollection<ForecastPoint> ForecastPoints { get; }
        public ObservableCollection<DailyForecastPoint> DailyForecasts { get; }

        public ICommand RefreshCommand { get; }

        public bool IsBusy
        {
            get => _isBusy;
            private set => SetProperty(ref _isBusy, value);
        }

        public string LocationName
        {
            get => _locationName;
            private set => SetProperty(ref _locationName, value);
        }

        public string TemperatureText
        {
            get => _temperatureText;
            private set => SetProperty(ref _temperatureText, value);
        }

        public double TemperatureValue
        {
            get => _temperatureValue;
            private set => SetProperty(ref _temperatureValue, value);
        }

        public string ConditionText
        {
            get => _conditionText;
            private set => SetProperty(ref _conditionText, value);
        }

        public string ConditionTitle
        {
            get => _conditionTitle;
            private set => SetProperty(ref _conditionTitle, value);
        }

        public string IconUrl
        {
            get => _iconUrl;
            private set => SetProperty(ref _iconUrl, value);
        }

        public string HighLowText
        {
            get => _highLowText;
            private set => SetProperty(ref _highLowText, value);
        }

        public string HumidityText
        {
            get => _humidityText;
            private set => SetProperty(ref _humidityText, value);
        }

        public string WindText
        {
            get => _windText;
            private set => SetProperty(ref _windText, value);
        }

        public string FeelsLikeText
        {
            get => _feelsLikeText;
            private set => SetProperty(ref _feelsLikeText, value);
        }

        public string PressureText
        {
            get => _pressureText;
            private set => SetProperty(ref _pressureText, value);
        }

        public string VisibilityText
        {
            get => _visibilityText;
            private set => SetProperty(ref _visibilityText, value);
        }

        public string SunriseText
        {
            get => _sunriseText;
            private set => SetProperty(ref _sunriseText, value);
        }

        public string SunsetText
        {
            get => _sunsetText;
            private set => SetProperty(ref _sunsetText, value);
        }

        public string UnitSymbol
        {
            get => _unitSymbol;
            private set => SetProperty(ref _unitSymbol, value);
        }

        public double GaugeMinimum
        {
            get => _gaugeMinimum;
            private set => SetProperty(ref _gaugeMinimum, value);
        }

        public double GaugeMaximum
        {
            get => _gaugeMaximum;
            private set => SetProperty(ref _gaugeMaximum, value);
        }

        public string LastUpdatedText => _lastUpdated == default ? "" : _lastUpdated.ToString("t");

        public async Task InitializeAsync()
        {
            if (_isInitialized)
            {
                return;
            }

            _isInitialized = true;

            await RefreshAsync(false);
        }

        private async Task OnRefreshRequestedAsync()
        {
            await RefreshAsync(true);
        }

        private async Task RefreshAsync(bool forceRefresh)
        {
            if (IsBusy)
            {
                return;
            }

            IsBusy = true;

            try
            {
                var location = await _weatherService.GetResilientLocationAsync();
                if (location == null)
                {
                    UpdateFallbackState("Location unavailable");
                    return;
                }

                var weatherTask = _weatherService.GetCurrentWeatherAsync(location.Latitude, location.Longitude, forceRefresh);
                var forecastTask = _weatherService.GetForecastAsync(location.Latitude, location.Longitude, forceRefresh);

                await Task.WhenAll(weatherTask, forecastTask);

                UpdateFromResponses(weatherTask.Result, forecastTask.Result);
            }
            catch
            {
                UpdateFallbackState("Weather unavailable");
            }
            finally
            {
                IsBusy = false;
                OnPropertyChanged(nameof(LastUpdatedText));
            }
        }

        private void UpdateFallbackState(string status)
        {
            LocationName = status;
            TemperatureText = "--";
            TemperatureValue = 0;
            ConditionText = "";
            ConditionTitle = "";
            IconUrl = "";
            HighLowText = "";
            HumidityText = "";
            WindText = "";
            FeelsLikeText = "";
            PressureText = "";
            VisibilityText = "";
            SunriseText = "";
            SunsetText = "";
            ForecastPoints.Clear();
            DailyForecasts.Clear();
        }

        private void UpdateFromResponses(WeatherResponse? weather, ForecastResponse? forecast)
        {
            if (weather == null)
            {
                UpdateFallbackState("Weather unavailable");
                return;
            }

            UpdateUnits();

            LocationName = string.IsNullOrWhiteSpace(weather.Name) ? "Current location" : weather.Name;
            _weatherService.SetCurrentLocation(LocationName, true);

            TemperatureValue = weather.Main.Temp;
            TemperatureText = $"{Math.Round(weather.Main.Temp)}{UnitSymbol}";
            var description = weather.Weather?.FirstOrDefault()?.Description ?? "";
            ConditionText = description;
            ConditionTitle = CultureInfo.CurrentCulture.TextInfo.ToTitleCase(description);
            IconUrl = BuildIconUrl(weather.Weather?.FirstOrDefault()?.Icon);
            HighLowText = $"H {Math.Round(weather.Main.TempMax)}{UnitSymbol} • L {Math.Round(weather.Main.TempMin)}{UnitSymbol}";
            HumidityText = $"{weather.Main.Humidity}%";
            WindText = FormatWind(weather.Wind.Speed);
            FeelsLikeText = $"{Math.Round(weather.Main.FeelsLike)}{UnitSymbol}";
            PressureText = FormatPressure(weather.Main.Pressure);
            VisibilityText = FormatVisibility(weather.Visibility);
            SunriseText = FormatSunTime(weather.Sys?.Sunrise ?? 0, weather.Timezone);
            SunsetText = FormatSunTime(weather.Sys?.Sunset ?? 0, weather.Timezone);
            _lastUpdated = DateTime.Now;

            UpdateForecast(forecast);
        }

        private static string BuildIconUrl(string? iconCode)
        {
            if (string.IsNullOrWhiteSpace(iconCode))
            {
                return string.Empty;
            }

            return $"https://openweathermap.org/img/wn/{iconCode}@4x.png";
        }

        private void UpdateUnits()
        {
            var unitSystem = _settingsService.Settings.UnitSystem?.ToLowerInvariant();
            UnitSymbol = unitSystem == "imperial" ? "°F" : "°C";

            if (unitSystem == "imperial")
            {
                GaugeMinimum = 0;
                GaugeMaximum = 110;
            }
            else
            {
                GaugeMinimum = -10;
                GaugeMaximum = 45;
            }
        }

        private string FormatWind(double speed)
        {
            var unit = _settingsService.Settings.WindUnit ?? "km/h";
            var unitSystem = _settingsService.Settings.UnitSystem?.ToLowerInvariant() ?? "metric";
            var value = speed;

            if (unit == "km/h" && unitSystem != "imperial")
            {
                value = speed * 3.6;
            }
            else if (unit == "mph" && unitSystem != "imperial")
            {
                value = speed * 2.23694;
            }

            return unit switch
            {
                "mph" => $"{value:0.#} mph",
                "m/s" => $"{value:0.#} m/s",
                _ => $"{value:0.#} km/h"
            };
        }

        private string FormatPressure(int pressureHpa)
        {
            var unit = _settingsService.Settings.PressureUnit ?? "hpa";
            return unit switch
            {
                "mmhg" => $"{pressureHpa * 0.75006:0} mmHg",
                "inhg" => $"{pressureHpa * 0.02953:0.00} inHg",
                _ => $"{pressureHpa} hPa"
            };
        }

        private string FormatVisibility(int visibilityMeters)
        {
            var unit = _settingsService.Settings.VisibilityUnit ?? "km";
            var km = visibilityMeters / 1000d;
            return unit == "mi"
                ? $"{km * 0.621371:0.#} mi"
                : $"{km:0.#} km";
        }

        private string FormatSunTime(long unixSeconds, int timezoneOffsetSeconds)
        {
            if (unixSeconds <= 0)
            {
                return "--";
            }

            var offset = TimeSpan.FromSeconds(timezoneOffsetSeconds);
            var time = DateTimeOffset.FromUnixTimeSeconds(unixSeconds).ToOffset(offset).DateTime;
            return time.ToString("t");
        }

        private void UpdateForecast(ForecastResponse? forecast)
        {
            ForecastPoints.Clear();
            DailyForecasts.Clear();

            if (forecast?.List == null || forecast.List.Count == 0)
            {
                return;
            }

            foreach (var item in forecast.List.Take(8))
            {
                var time = DateTimeOffset.FromUnixTimeSeconds(item.Dt).ToLocalTime().DateTime;
                var pop = Math.Round(item.Pop * 100);
                ForecastPoints.Add(new ForecastPoint
                {
                    Time = time,
                    Temperature = item.Main.Temp,
                    DisplayTime = time.ToString("HH:mm"),
                    IconUrl = BuildIconUrl(item.Weather?.FirstOrDefault()?.Icon),
                    PrecipitationText = pop > 0 ? $"{pop:0}%" : string.Empty
                });
            }

            var grouped = forecast.List
                .GroupBy(item => DateTimeOffset.FromUnixTimeSeconds(item.Dt).ToLocalTime().Date)
                .Take(5);

            foreach (var day in grouped)
            {
                var min = day.Min(x => x.Main.TempMin);
                var max = day.Max(x => x.Main.TempMax);
                var weather = day.SelectMany(x => x.Weather ?? new List<Weather>()).FirstOrDefault();
                var condition = weather?.Main ?? "";
                var icon = weather?.Icon;
                var maxPop = day.Max(x => x.Pop);
                var popText = maxPop > 0 ? $"{Math.Round(maxPop * 100):0}%" : string.Empty;

                DailyForecasts.Add(new DailyForecastPoint
                {
                    Date = day.Key,
                    DayName = day.Key.ToString("ddd"),
                    MinTemp = min,
                    MaxTemp = max,
                    Condition = condition,
                    IconUrl = BuildIconUrl(icon),
                    MaxPrecipitation = maxPop,
                    PrecipitationText = popText
                });
            }
        }

        private void OnWeatherUpdated()
        {
            if (_weatherService.CachedWeather == null)
            {
                return;
            }

            MainThread.BeginInvokeOnMainThread(() =>
            {
                UpdateFromResponses(_weatherService.CachedWeather, _weatherService.CachedForecast);
                OnPropertyChanged(nameof(LastUpdatedText));
            });
        }

        private void OnLocationChanged()
        {
            MainThread.BeginInvokeOnMainThread(() =>
            {
                LocationName = _weatherService.CurrentLocationName;
            });
        }
    }

    public class ForecastPoint
    {
        public DateTime Time { get; set; }
        public string DisplayTime { get; set; } = "";
        public double Temperature { get; set; }
            public string IconUrl { get; set; } = "";
            public string PrecipitationText { get; set; } = "";
    }

    public class DailyForecastPoint
    {
        public DateTime Date { get; set; }
        public string DayName { get; set; } = "";
        public double MinTemp { get; set; }
        public double MaxTemp { get; set; }
        public string Condition { get; set; } = "";
            public string IconUrl { get; set; } = "";
            public double MaxPrecipitation { get; set; }
            public string PrecipitationText { get; set; } = "";
    }
}
