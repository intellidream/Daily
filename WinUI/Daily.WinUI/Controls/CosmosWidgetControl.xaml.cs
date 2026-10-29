using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Daily.Models;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Daily_WinUI.Controls
{
    public sealed partial class CosmosWidgetControl : UserControl
    {
        private static readonly (double RaH, double DecD, float Mag)[] MiniStars =
        {
            (6.7525, -16.7161, -1.46f),
            (14.2610, 19.1825, -0.05f),
            (18.6156, 38.7837, 0.03f),
            (5.2782, 45.9980, 0.08f),
            (5.2423, -8.2016, 0.13f),
            (7.6550, 5.2250, 0.34f),
            (5.9195, 7.4071, 0.42f),
            (19.8464, 8.8683, 0.76f),
            (4.5987, 16.5093, 0.86f),
            (16.4901, -26.4320, 0.96f),
            (13.4199, -11.1613, 0.97f),
            (7.7553, 28.0262, 1.14f),
            (20.6905, 45.2803, 1.25f),
            (10.1395, 11.9672, 1.36f),
            (2.5303, 89.2641, 1.98f)
        };

        private readonly AstronomyService _astronomyService = AstronomyService.Shared;
        private readonly CosmosCatalogRepository _catalogRepo = CosmosCatalogRepository.Shared;
        private readonly CosmosLiveService _liveService = CosmosLiveService.Shared;
        private readonly LocationService _locationService = new();

        private double _lat = 44.4323;
        private double _lon = 26.1063;
        private List<CelestialCoordinates> _cachedBodies = new();

        public CosmosWidgetControl()
        {
            InitializeComponent();
            Loaded += CosmosWidgetControl_Loaded;
        }

        private async void CosmosWidgetControl_Loaded(object sender, RoutedEventArgs e)
        {
            var task = RefreshAsync();
            MainPage.Current?.RegisterLoadingTask(task);
            await task;
        }

        public async Task RefreshAsync()
        {
            LoadingOverlay.Visibility = Visibility.Visible;
            try
            {
                var appSettings = SettingsService.Load();
                if (appSettings.LastLatitude.HasValue && appSettings.LastLongitude.HasValue)
                {
                    _lat = appSettings.LastLatitude.Value;
                    _lon = appSettings.LastLongitude.Value;
                }

                var coords = await _locationService.GetCurrentCoordinatesAsync();
                if (coords.HasValue)
                {
                    _lat = coords.Value.Latitude;
                    _lon = coords.Value.Longitude;
                }

                await _catalogRepo.EnsureLoadedAsync();
                int bortle = _catalogRepo.GetBortleClass(_lat, _lon);

                DateTime utcNow = DateTime.UtcNow;

                var moon = _astronomyService.GetMoonPhase(utcNow, _lat, _lon);
                MoonPhaseText.Text = moon.Description;
                MoonIllumText.Text = $"{moon.IlluminationPercent}% illuminated";

                _cachedBodies = _astronomyService.GetAllVisibleBodies(utcNow, _lat, _lon);
                var visiblePlanets = _cachedBodies
                    .Where(b => b.Body != CelestialBody.Sun && b.Body != CelestialBody.Moon && b.IsAboveHorizon)
                    .Select(b => b.Body.DisplayName())
                    .ToList();

                VisiblePlanetsText.Text = visiblePlanets.Count > 0
                    ? $"Visible now: {string.Join(", ", visiblePlanets)}"
                    : "Explore 15,544 stars & 219 deep-sky objects";

                var liveBundle = await _liveService.FetchLiveBundleAsync(_lat, _lon);
                var w = liveBundle.WeatherOverlay;
                var stargazing = _astronomyService.EvaluateStargazingConditions(
                    _lat, _lon, utcNow,
                    w?.CloudTotalPercent, w?.CloudLowPercent, w?.CloudMidPercent, w?.CloudHighPercent,
                    bortle, w?.SeeingArcseconds, w?.TransparencyLabel, w?.TemperatureCelsius, w?.DewPointCelsius,
                    w?.Provenance ?? TelemetryProvenance.OfflineCalculated("Offline Ephemeris"));

                ScoreText.Text = stargazing.Score.ToString();
                ProvenanceLabelText.Text = $"BORTLE {bortle} • {stargazing.Provenance.BadgeText}";
                ConditionSummaryText.Text = stargazing.BestWindowDescription ?? stargazing.Summary;
                QualityBadgeText.Text = $"Sky: {stargazing.Quality}";

                var color = stargazing.Quality switch
                {
                    StargazingQuality.Excellent => Color.FromArgb(255, 0, 229, 255),
                    StargazingQuality.Good => Color.FromArgb(255, 0, 208, 156),
                    StargazingQuality.Fair => Color.FromArgb(255, 255, 209, 102),
                    _ => Color.FromArgb(255, 255, 143, 163)
                };

                QualityBadge.BorderBrush = new SolidColorBrush(color);
                QualityBadgeText.Foreground = new SolidColorBrush(color);
                ScoreText.Foreground = new SolidColorBrush(color);
                MiniDomeCanvas.Invalidate();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CosmosWidgetControl] Error: {ex}");
                ConditionSummaryText.Text = "Astronomical ephemeris ready";
            }
            finally
            {
                LoadingOverlay.Visibility = Visibility.Collapsed;
            }
        }

        private void MiniDomeCanvas_Draw(CanvasControl sender, CanvasDrawEventArgs args)
        {
            float cx = (float)(sender.ActualWidth * 0.5);
            float cy = (float)(sender.ActualHeight * 0.5);
            float r = Math.Min(cx, cy) - 3f;
            if (r <= 4f) return;

            var ds = args.DrawingSession;
            ds.FillCircle(cx, cy, r, Color.FromArgb(255, 5, 10, 24));
            ds.DrawCircle(cx, cy, r * 0.5f, Color.FromArgb(30, 255, 255, 255), 0.7f);

            DateTime nowUtc = DateTime.UtcNow;
            foreach (var s in MiniStars)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(s.RaH, s.DecD, nowUtc, _lat, _lon);
                if (alt <= 0.0) continue;
                double zRad = (90.0 - alt) * (Math.PI / 180.0);
                float rho = (float)(r * Math.Tan(zRad * 0.5));
                double azRad = az * (Math.PI / 180.0);
                float sx = cx - rho * (float)Math.Sin(azRad);
                float sy = cy - rho * (float)Math.Cos(azRad);
                ds.FillCircle(sx, sy, s.Mag < 0.2f ? 1.8f : 1.2f, Color.FromArgb(215, 255, 255, 255));
            }

            foreach (var b in _cachedBodies)
            {
                if (b.Body == CelestialBody.Sun || !b.IsAboveHorizon) continue;
                double zRad = (90.0 - b.Altitude) * (Math.PI / 180.0);
                float rho = (float)(r * Math.Tan(zRad * 0.5));
                double azRad = b.Azimuth * (Math.PI / 180.0);
                float sx = cx - rho * (float)Math.Sin(azRad);
                float sy = cy - rho * (float)Math.Cos(azRad);
                Color col = b.Body == CelestialBody.Moon ? Color.FromArgb(255, 255, 214, 102) : Color.FromArgb(255, 0, 229, 255);
                ds.FillCircle(sx, sy, b.Body == CelestialBody.Moon ? 2.8f : 2.1f, col);
            }
        }

        private void OpenHubButton_Click(object sender, RoutedEventArgs e)
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(9);
            }
        }
    }
}
