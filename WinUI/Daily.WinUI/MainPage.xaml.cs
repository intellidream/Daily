using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml;
using Syncfusion.UI.Xaml.Editors;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Input;
using Windows.UI;
using System.Collections.ObjectModel;
using Daily_WinUI.Models;
using Daily_WinUI.Services;
using Daily_WinUI.ViewModels;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace Daily_WinUI;

/// <summary>
/// The main content page displayed inside the application window.
/// Add your UI logic, event handlers, and data binding here.
/// </summary>
public sealed partial class MainPage : Page
{
    public MainPageViewModel ViewModel { get; } = new();
    public ObservableCollection<LocationSuggestion> FavoriteLocations { get; } = new();
    public ObservableCollection<LocationSuggestion> RecentLocations { get; } = new();
    public ObservableCollection<LocationSuggestion> HomeFavorites { get; } = new();
    public ObservableCollection<LocationSuggestion> WorkFavorites { get; } = new();
    public ObservableCollection<LocationSuggestion> TravelFavorites { get; } = new();

    private readonly WeatherClient _weatherClient = new();
    private readonly LocationService _locationService = new();
    private readonly AppSettings _settings = SettingsService.Load();
    private IReadOnlyList<LocationSuggestion> _lastSuggestions = Array.Empty<LocationSuggestion>();
    private LocationSuggestion? _selectedLocation;
    private CancellationTokenSource? _searchCts;
    private bool _suppressTextCallback;

    public MainPage()
    {
        InitializeComponent();
        Loaded += MainPage_Loaded;
    }

    private Microsoft.UI.Xaml.Visibility BoolToVisibility(bool value) =>
        value ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

    private async void MainPage_Loaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        LoadSavedLocations();
        ApplyGlassIntensity(_settings.GlassIntensity);
        GlassIntensityComboBox.SelectedItem = _settings.GlassIntensity;
        UnitSystemComboBox.SelectedItem = _settings.UnitSystem == "imperial" ? "Imperial (F)" : "Metric (C)";
        WindUnitComboBox.SelectedItem = _settings.WindUnit;
        PressureUnitComboBox.SelectedItem = _settings.PressureUnit;
        FavoriteCategoryComboBox.SelectedItem = "Travel";

        ViewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(ViewModel.ShowSunriseAnnotation) or
                nameof(ViewModel.ShowSunsetAnnotation) or
                nameof(ViewModel.SunriseAnnotationX) or
                nameof(ViewModel.SunsetAnnotationX) or
                nameof(ViewModel.Sunrise) or
                nameof(ViewModel.Sunset))
            {
                PositionSunAnnotations();
            }
        };

        await InitializeLocationAsync();
        await RefreshWeatherAsync();
    }

    /// <summary>Appends a degree symbol to every Y-axis label on the hourly chart.</summary>
    private void HourlyYAxis_LabelCreated(object sender, Syncfusion.UI.Xaml.Charts.ChartAxisLabelEventArgs e)
    {
        if (e.Label is { } label && !label.EndsWith("°", StringComparison.Ordinal))
        {
            e.Label = label + "°";
        }
    }

    // Actual plot-area bounds reported by Syncfusion after layout.
    private Windows.Foundation.Rect _chartPlotBounds;

    private void HourlyForecastChart_SeriesBoundsChanged(object sender, Syncfusion.UI.Xaml.Charts.ChartSeriesBoundsEventArgs e)
    {
        _chartPlotBounds = e.NewBounds;
        PositionSunAnnotations();
    }

    /// <summary>Positions the sunrise/sunset badge overlays on the chart canvas.</summary>
    private void PositionSunAnnotations()
    {
        var hourlyCount = ViewModel.HourlyForecast.Count;
        if (hourlyCount == 0) return;

        var plotBounds = _chartPlotBounds;
        if (plotBounds.Width <= 0 || plotBounds.Height <= 0) return;

        // CategoryAxis internal range is [-0.5 .. N-0.5].
        // Category i centre pixel = plotLeft + (i + 0.5) * slotWidth.
        // annotX from the ViewModel is a fractional slot index (e.g. 6.38 for 06:23
        // sitting 38 % of the way between the 06:00 and 09:00 slots), so the same
        // formula places the badge centred on exactly that fractional position.
        var slotWidth = plotBounds.Width / hourlyCount;

        const double bottomMargin = 4; // px above the x-axis line

        void PlaceBadge(Border badge, TextBlock timeText, double annotX, bool show, string time)
        {
            if (!show || annotX < 0)
            {
                badge.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
                return;
            }

            timeText.Text = time;
            badge.Visibility = Microsoft.UI.Xaml.Visibility.Visible;

            // Force a layout pass so ActualWidth reflects the new text.
            badge.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
            var badgeWidth  = badge.DesiredSize.Width  > 0 ? badge.DesiredSize.Width  : 70;
            var badgeHeight = badge.DesiredSize.Height > 0 ? badge.DesiredSize.Height : 24;

            // Centre badge on the fractional slot position.
            var xCenter = plotBounds.X + (annotX + 0.5) * slotWidth;
            var xLeft   = xCenter - badgeWidth / 2;

            // Sit just above the x-axis line.
            var yTop = plotBounds.Y + plotBounds.Height - badgeHeight - bottomMargin;

            Canvas.SetLeft(badge, xLeft);
            Canvas.SetTop(badge, yTop);
        }

        PlaceBadge(SunriseBadge, SunriseTimeText, ViewModel.SunriseAnnotationX, ViewModel.ShowSunriseAnnotation, ViewModel.Sunrise);
        PlaceBadge(SunsetBadge,  SunsetTimeText,  ViewModel.SunsetAnnotationX,  ViewModel.ShowSunsetAnnotation,  ViewModel.Sunset);

        CurrentWeatherBadge.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
    }

    private async void RefreshButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        await RefreshWeatherAsync();
    }

    private async Task RefreshWeatherAsync()
    {
        RefreshButton.IsEnabled = false;
        try
        {
            if (_selectedLocation is null)
            {
                ViewModel.SetStatus("Select a city from the search box.");
                return;
            }

            await ViewModel.LoadWeatherAsync(
                _selectedLocation.Latitude,
                _selectedLocation.Longitude,
                _settings.UnitSystem,
                _settings.WindUnit,
                _settings.PressureUnit,
                _settings.ShowSunrise,
                _settings.ShowHumidity);
            UpdateWeatherIcon();

            AddRecent(_selectedLocation);
            UpdateFavoriteButtonText();

            _settings.LastLatitude = _selectedLocation.Latitude;
            _settings.LastLongitude = _selectedLocation.Longitude;
            _settings.LastLocationName = _selectedLocation.DisplayName;
            SaveLocationsToSettings();
            SettingsService.Save(_settings);
        }
        finally
        {
            RefreshButton.IsEnabled = true;
        }
    }

    private async Task InitializeLocationAsync()
    {
        if (_settings.LastLatitude.HasValue && _settings.LastLongitude.HasValue)
        {
            _selectedLocation = new LocationSuggestion
            {
                Name = _settings.LastLocationName ?? "Saved Location",
                Country = "",
                State = null,
                Latitude = _settings.LastLatitude.Value,
                Longitude = _settings.LastLongitude.Value,
                DisplayName = _settings.LastLocationName ?? "Saved Location"
            };
            SetLocationText(_selectedLocation.DisplayName);
            ViewModel.SetStatus("Loaded last location.");
            UpdateFavoriteButtonText();
            UpdatePinButtonText();
            return;
        }

        var location = await _locationService.GetCurrentCoordinatesAsync();
        if (location.HasValue)
        {
            _selectedLocation = new LocationSuggestion
            {
                Name = "Auto Location",
                Country = "",
                State = null,
                Latitude = location.Value.Latitude,
                Longitude = location.Value.Longitude,
                DisplayName = "Auto location"
            };
            SetLocationText(_selectedLocation.DisplayName);
            ViewModel.SetStatus("Using auto location.");
            UpdateFavoriteButtonText();
            UpdatePinButtonText();
            return;
        }

        ViewModel.SetStatus("Auto-location unavailable; using default coordinates.");
        _selectedLocation = new LocationSuggestion
        {
            Name = "Bucharest",
            Country = "RO",
            State = null,
            Latitude = 44.4268,
            Longitude = 26.1025,
            DisplayName = "Bucharest, RO"
        };
        SetLocationText(_selectedLocation.DisplayName);
        UpdateFavoriteButtonText();
        UpdatePinButtonText();
    }

    private void SetLocationText(string text)
    {
        _suppressTextCallback = true;
        LocationSearchBox.Text = text;
        _suppressTextCallback = false;
    }

    private void UpdateWeatherIcon()
    {
        try
        {
            ConditionIcon.Source = new BitmapImage(new Uri(ViewModel.IconUrl));
        }
        catch
        {
            ConditionIcon.Source = null;
        }
    }

    private void LocationSearchBox_ComboBoxLoaded(object sender, RoutedEventArgs e)
    {
        LocationSearchBox.RegisterPropertyChangedCallback(
            DropDownListBase.TextProperty,
            LocationSearchBox_TextPropertyChanged);
    }

    private async void LocationSearchBox_TextPropertyChanged(DependencyObject d, DependencyProperty dp)
    {
        if (_suppressTextCallback) return;

        var text = LocationSearchBox.Text?.Trim();
        if (string.IsNullOrWhiteSpace(text) || text.Length < 2)
        {
            LocationSearchBox.ItemsSource = null;
            _lastSuggestions = Array.Empty<LocationSuggestion>();
            return;
        }

        _searchCts?.Cancel();
        _searchCts = new CancellationTokenSource();

        try
        {
            var suggestions = await _weatherClient.SearchLocationsAsync(text, cancellationToken: _searchCts.Token);
            _lastSuggestions = suggestions;
            if (!_suppressTextCallback)
                LocationSearchBox.ItemsSource = suggestions;
        }
        catch (OperationCanceledException)
        {
        }
        catch
        {
            LocationSearchBox.ItemsSource = null;
        }
    }

    private async void LocationSearchBox_SelectionChanged(object sender, ComboBoxSelectionChangedEventArgs args)
    {
        if (args.AddedItems?.Count > 0 && args.AddedItems[0] is LocationSuggestion suggestion)
        {
            _selectedLocation = suggestion;
            _suppressTextCallback = true;
            LocationSearchBox.Text = suggestion.DisplayName;
            _suppressTextCallback = false;
            UpdateFavoriteButtonText();
            UpdatePinButtonText();
            await RefreshWeatherAsync();
        }
    }

    private async void LocationSearchBox_InputSubmitted(object sender, ComboBoxInputSubmittedEventArgs args)
    {
        if (args.Item is LocationSuggestion selected)
        {
            _selectedLocation = selected;
        }
        else if (_lastSuggestions.Count > 0)
        {
            _selectedLocation = _lastSuggestions[0];
            SetLocationText(_selectedLocation.DisplayName);
        }

        await RefreshWeatherAsync();
    }

    private async void FavoriteChip_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: LocationSuggestion location })
        {
            _selectedLocation = location;
            SetLocationText(location.DisplayName);
            UpdateFavoriteButtonText();
            UpdatePinButtonText();
            await RefreshWeatherAsync();
        }
    }

    private async void RecentChip_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (sender is FrameworkElement { DataContext: LocationSuggestion location })
        {
            _selectedLocation = location;
            SetLocationText(location.DisplayName);
            UpdateFavoriteButtonText();
            UpdatePinButtonText();
            await RefreshWeatherAsync();
        }
    }

    private void FavoriteToggleButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_selectedLocation is null)
        {
            return;
        }

        var existing = FavoriteLocations.FirstOrDefault(IsSameLocationPredicate(_selectedLocation));
        if (existing is not null)
        {
            FavoriteLocations.Remove(existing);
            ViewModel.SetStatus($"Removed {_selectedLocation.DisplayName} from favorites.");
        }
        else
        {
            var clone = CloneLocation(_selectedLocation);
            clone.FavoriteCategory = FavoriteCategoryComboBox.SelectedItem as string ?? "Travel";
            FavoriteLocations.Insert(0, clone);
            ViewModel.SetStatus($"Added {_selectedLocation.DisplayName} to favorites.");
        }

        RebuildFavoriteGroups();
        SaveLocationsToSettings();
        SettingsService.Save(_settings);
        UpdateFavoriteButtonText();
        UpdatePinButtonText();
    }

    private void FavoritePinButton_Click(object sender, RoutedEventArgs e)
    {
        if (_selectedLocation is null)
        {
            return;
        }

        var existing = FavoriteLocations.FirstOrDefault(IsSameLocationPredicate(_selectedLocation));
        if (existing is null)
        {
            return;
        }

        existing.IsPinned = !existing.IsPinned;
        SortFavorites();
        RebuildFavoriteGroups();
        SaveLocationsToSettings();
        SettingsService.Save(_settings);
        UpdatePinButtonText();
    }

    private async void FavoriteList_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not LocationSuggestion location)
        {
            return;
        }

        _selectedLocation = location;
        SetLocationText(location.DisplayName);
        UpdateFavoriteButtonText();
        UpdatePinButtonText();
        await RefreshWeatherAsync();
    }

    private void FavoriteList_DragItemsCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        SyncFavoritesFromGroups();
        SaveLocationsToSettings();
        SettingsService.Save(_settings);
    }

    private void WeatherToggleTile_Click(object sender, TappedRoutedEventArgs e)
    {
        if (sender is FrameworkElement tile && tile.Name == "SunToggleTile")
        {
            _settings.ShowSunrise = !_settings.ShowSunrise;
            ViewModel.ToggleSunPhase();
        }
        else
        {
            _settings.ShowHumidity = !_settings.ShowHumidity;
            ViewModel.ToggleMoisturePressure();
        }

        SettingsService.Save(_settings);
    }

    private async void UnitSystemComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UnitSystemComboBox.SelectedItem is not string selected)
        {
            return;
        }

        _settings.UnitSystem = selected.Contains("Imperial", StringComparison.OrdinalIgnoreCase) ? "imperial" : "metric";
        SettingsService.Save(_settings);
        await RefreshWeatherAsync();
    }

    private async void WindUnitComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (WindUnitComboBox.SelectedItem is not string selected)
        {
            return;
        }

        _settings.WindUnit = selected;
        SettingsService.Save(_settings);
        await RefreshWeatherAsync();
    }

    private async void PressureUnitComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (PressureUnitComboBox.SelectedItem is not string selected)
        {
            return;
        }

        _settings.PressureUnit = selected;
        SettingsService.Save(_settings);
        await RefreshWeatherAsync();
    }

    private void GlassIntensityComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (GlassIntensityComboBox.SelectedItem is not string intensity)
        {
            return;
        }

        ApplyGlassIntensity(intensity);
        _settings.GlassIntensity = intensity;
        SettingsService.Save(_settings);
    }

    private void ApplyGlassIntensity(string intensity)
    {
        var shell = (SolidColorBrush)Resources["ShellBrush"];
        var shellBorder = (SolidColorBrush)Resources["ShellBorderBrush"];
        var tile = (SolidColorBrush)Resources["TileBrush"];
        var tileBorder = (SolidColorBrush)Resources["TileBorderBrush"];
        var subTile = (SolidColorBrush)Resources["SubTileBrush"];
        var forecast = (SolidColorBrush)Resources["ForecastCardBrush"];
        var forecastBorder = (SolidColorBrush)Resources["ForecastCardBorderBrush"];

        (Color shellColor, Color shellBorderColor, Color tileColor, Color tileBorderColor, Color subTileColor, Color forecastColor, Color forecastBorderColor) colors = intensity switch
        {
            "Low" => (
                Color.FromArgb(0x36, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x58, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x28, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x3C, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x20, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x42, 0xFF, 0xFF, 0xFF)
            ),
            "High" => (
                Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x3E, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x2A, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x0C, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x0A, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x2C, 0xFF, 0xFF, 0xFF)
            ),
            _ => (
                Color.FromArgb(0x20, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x46, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x30, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x15, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF),
                Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)
            )
        };

        shell.Color = colors.shellColor;
        shellBorder.Color = colors.shellBorderColor;
        tile.Color = colors.tileColor;
        tileBorder.Color = colors.tileBorderColor;
        subTile.Color = colors.subTileColor;
        forecast.Color = colors.forecastColor;
        forecastBorder.Color = colors.forecastBorderColor;
    }

    private void LoadSavedLocations()
    {
        FavoriteLocations.Clear();
        foreach (var saved in _settings.FavoriteLocations)
        {
            FavoriteLocations.Add(ToLocationSuggestion(saved));
        }
        RebuildFavoriteGroups();

        RecentLocations.Clear();
        foreach (var saved in _settings.RecentLocations)
        {
            RecentLocations.Add(ToLocationSuggestion(saved));
        }
    }

    private void SaveLocationsToSettings()
    {
        _settings.FavoriteLocations = FavoriteLocations.Select(ToSavedLocation).ToList();
        _settings.RecentLocations = RecentLocations.Select(ToSavedLocation).ToList();
    }

    private void AddRecent(LocationSuggestion location)
    {
        var existing = RecentLocations.FirstOrDefault(IsSameLocationPredicate(location));
        if (existing is not null)
        {
            RecentLocations.Remove(existing);
        }

        RecentLocations.Insert(0, CloneLocation(location));
        while (RecentLocations.Count > 8)
        {
            RecentLocations.RemoveAt(RecentLocations.Count - 1);
        }
    }

    private void UpdateFavoriteButtonText()
    {
        if (_selectedLocation is null)
        {
            FavoriteToggleButton.Content = "Add Favorite";
            return;
        }

        FavoriteToggleButton.Content = FavoriteLocations.Any(IsSameLocationPredicate(_selectedLocation))
            ? "Remove Favorite"
            : "Add Favorite";
    }

    private void UpdatePinButtonText()
    {
        if (_selectedLocation is null)
        {
            FavoritePinButton.Content = "Pin";
            return;
        }

        var favorite = FavoriteLocations.FirstOrDefault(IsSameLocationPredicate(_selectedLocation));
        FavoritePinButton.Content = favorite?.IsPinned == true ? "Unpin" : "Pin";
    }

    private void SortFavorites()
    {
        var ordered = FavoriteLocations
            .OrderByDescending(location => location.IsPinned)
            .ThenBy(location => location.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToList();

        FavoriteLocations.Clear();
        foreach (var favorite in ordered)
        {
            FavoriteLocations.Add(favorite);
        }
    }

    private void RebuildFavoriteGroups()
    {
        RebuildGroup(HomeFavorites, "Home");
        RebuildGroup(WorkFavorites, "Work");
        RebuildGroup(TravelFavorites, "Travel");
    }

    private void SyncFavoritesFromGroups()
    {
        FavoriteLocations.Clear();

        foreach (var location in HomeFavorites)
        {
            location.FavoriteCategory = "Home";
            FavoriteLocations.Add(location);
        }

        foreach (var location in WorkFavorites)
        {
            location.FavoriteCategory = "Work";
            FavoriteLocations.Add(location);
        }

        foreach (var location in TravelFavorites)
        {
            location.FavoriteCategory = "Travel";
            FavoriteLocations.Add(location);
        }
    }

    private void RebuildGroup(ObservableCollection<LocationSuggestion> target, string category)
    {
        target.Clear();
        foreach (var location in FavoriteLocations.Where(location => string.Equals(location.FavoriteCategory, category, StringComparison.OrdinalIgnoreCase)))
        {
            target.Add(location);
        }
    }

    private static Func<LocationSuggestion, bool> IsSameLocationPredicate(LocationSuggestion target)
        => location => Math.Abs(location.Latitude - target.Latitude) < 0.0001 && Math.Abs(location.Longitude - target.Longitude) < 0.0001;

    private static LocationSuggestion CloneLocation(LocationSuggestion location)
        => new()
        {
            DisplayName = location.DisplayName,
            Name = location.Name,
            Country = location.Country,
            State = location.State,
            Latitude = location.Latitude,
            Longitude = location.Longitude,
            FavoriteCategory = location.FavoriteCategory,
            IsPinned = location.IsPinned
        };

    private static SavedLocation ToSavedLocation(LocationSuggestion location)
        => new()
        {
            DisplayName = location.DisplayName,
            Name = location.Name,
            Country = location.Country,
            State = location.State,
            Latitude = location.Latitude,
            Longitude = location.Longitude,
            FavoriteCategory = location.FavoriteCategory,
            IsPinned = location.IsPinned
        };

    private static LocationSuggestion ToLocationSuggestion(SavedLocation location)
        => new()
        {
            DisplayName = location.DisplayName,
            Name = location.Name,
            Country = location.Country,
            State = location.State,
            Latitude = location.Latitude,
            Longitude = location.Longitude,
            FavoriteCategory = string.IsNullOrWhiteSpace(location.FavoriteCategory) ? "Travel" : location.FavoriteCategory,
            IsPinned = location.IsPinned
        };
}
