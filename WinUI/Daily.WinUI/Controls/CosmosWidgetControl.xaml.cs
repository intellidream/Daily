using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Daily.Models;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;

namespace Daily_WinUI.Controls
{
    public sealed partial class CosmosWidgetControl : UserControl
    {
        private readonly AstronomyService _astronomyService = AstronomyService.Shared;
        private readonly LocationService _locationService = new();

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
                var coords = await _locationService.GetCurrentCoordinatesAsync();
                double lat = coords?.Latitude ?? 44.4323;
                double lon = coords?.Longitude ?? 26.1063;

                DateTime utcNow = DateTime.UtcNow;

                // 1. Moon phase
                var moon = _astronomyService.GetMoonPhase(utcNow);
                int illumPct = (int)Math.Round(moon.IlluminatedFraction * 100.0);
                MoonPhaseText.Text = moon.Description;
                MoonIllumText.Text = $"{illumPct}% iluminat";

                // 2. Visible planets
                var bodies = _astronomyService.GetAllVisibleBodies(utcNow, lat, lon);
                var visiblePlanets = bodies
                    .Where(b => b.Body != CelestialBody.Sun && b.Body != CelestialBody.Moon && b.IsAboveHorizon)
                    .Select(b => b.Body.ToString())
                    .ToList();

                if (visiblePlanets.Count > 0)
                {
                    VisiblePlanetsText.Text = $"Planete vizibile: {string.Join(", ", visiblePlanets)}";
                }
                else
                {
                    VisiblePlanetsText.Text = "No planets above the horizon";
                }

                // 3. Stargazing evaluation
                var stargazing = _astronomyService.EvaluateStargazingQuality(15.0, moon.IlluminatedFraction, 4);
                ScoreText.Text = stargazing.Score.ToString();
                ConditionSummaryText.Text = stargazing.Summary;
                QualityBadgeText.Text = $"Stargazing: {stargazing.Quality}";

                var color = stargazing.Quality switch
                {
                    StargazingQuality.Excellent => Color.FromArgb(255, 0, 229, 255), // Cyan
                    StargazingQuality.Good => Color.FromArgb(255, 0, 208, 156),     // Mint
                    StargazingQuality.Fair => Color.FromArgb(255, 255, 209, 102),   // Yellow
                    _ => Color.FromArgb(255, 255, 143, 163)                          // Red/Pink
                };

                QualityBadge.BorderBrush = new SolidColorBrush(color);
                QualityBadgeText.Foreground = new SolidColorBrush(color);
                ScoreText.Foreground = new SolidColorBrush(color);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[CosmosWidgetControl] Error: {ex}");
                ConditionSummaryText.Text = "Date astronomice indisponibile";
            }
            finally
            {
                LoadingOverlay.Visibility = Visibility.Collapsed;
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
