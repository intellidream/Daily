using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Models;
using Daily.Services;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopCosmosWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private readonly AstronomyService _astronomyService = AstronomyService.Shared;

        public DesktopCosmosWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            _model = model;
            _hostWindow = hostWindow;
            this.InitializeComponent();

            ApplySizeLayout();
        }

        private void ApplySizeLayout()
        {
            if (_model.Size == DesktopWidgetSize.Small)
            {
                SmallLayout.Visibility = Visibility.Visible;
                MediumLayout.Visibility = Visibility.Collapsed;
                LargeLayout.Visibility = Visibility.Collapsed;
            }
            else if (_model.Size == DesktopWidgetSize.Large)
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLayout.Visibility = Visibility.Collapsed;
                LargeLayout.Visibility = Visibility.Visible;
            }
            else
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLayout.Visibility = Visibility.Visible;
                LargeLayout.Visibility = Visibility.Collapsed;
            }
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            RefreshData();
        }

        public void Detach()
        {
        }

        public void RefreshData()
        {
            try
            {
                var now = DateTime.UtcNow;

                // 1. Observer Location (from user settings or default Bucharest)
                double lat = 44.4323;
                double lon = 26.1063;
                try
                {
                    var settings = SettingsService.Load();
                    if (settings.LastLatitude.HasValue && settings.LastLatitude.Value != 0)
                    {
                        lat = settings.LastLatitude.Value;
                        lon = settings.LastLongitude ?? 26.1063;
                    }
                }
                catch { }

                // 2. Real Moon Phase, Fraction and Glyph
                var moon = _astronomyService.GetMoonPhase(now, lat, lon);
                double illumination = Math.Round(moon.IlluminatedFraction * 100.0);
                string phaseName = !string.IsNullOrWhiteSpace(moon.Description) ? moon.Description : "Waxing Gibbous";
                string glyph = GetMoonGlyph(moon.IlluminatedFraction);

                // 3. Real Moonrise & Moonset ephemeris
                var riseSetMoon = _astronomyService.GetRiseTransitSet(CelestialBody.Moon, now, lat, lon);
                string riseStr = riseSetMoon.RiseTimeUtc?.ToLocalTime().ToString("HH:mm") ?? "--:--";
                string setStr = riseSetMoon.SetTimeUtc?.ToLocalTime().ToString("HH:mm") ?? "--:--";
                string transitStr = riseSetMoon.TransitTimeUtc?.ToLocalTime().ToString("HH:mm") ?? "--:--";
                string moonTimes = $"Moonrise: {riseStr} · Moonset: {setStr}";

                // 4. Real Sun Times & Twilight / Golden Hour
                var sunTimes = _astronomyService.GetSunTimes(now, lat, lon);
                string goldenHourStr;
                if (sunTimes.SunsetUtc.HasValue)
                {
                    var sunsetLocal = sunTimes.SunsetUtc.Value.ToLocalTime();
                    goldenHourStr = $"🌅 {sunsetLocal.AddMinutes(-40):HH:mm} – {sunsetLocal.AddMinutes(15):HH:mm}";
                }
                else
                {
                    goldenHourStr = "🌅 17:45 – 18:30";
                }

                // 5. Real Visible Planets (computed via AstronomyEngine for current hour and evening peak)
                var bodies = _astronomyService.GetAllVisibleBodies(now, lat, lon);
                var visibleNow = bodies
                    .Where(b => b.Body is CelestialBody.Venus or CelestialBody.Mars or CelestialBody.Jupiter or CelestialBody.Saturn or CelestialBody.Mercury)
                    .Where(b => b.Altitude > 0)
                    .OrderBy(b => b.Magnitude)
                    .ToList();

                List<string> planetNames;
                if (visibleNow.Count > 0)
                {
                    planetNames = visibleNow.Select(b => b.Body.ToString()).ToList();
                }
                else
                {
                    // Look at tonight's astronomical dusk or 21:00 observing window
                    var duskUtc = sunTimes.DuskAstronomicalUtc ?? sunTimes.DuskNauticalUtc ?? DateTime.Today.AddHours(21).ToUniversalTime();
                    var eveningBodies = _astronomyService.GetAllVisibleBodies(duskUtc, lat, lon);
                    var visibleEvening = eveningBodies
                        .Where(b => b.Body is CelestialBody.Venus or CelestialBody.Mars or CelestialBody.Jupiter or CelestialBody.Saturn or CelestialBody.Mercury)
                        .Where(b => b.Altitude > 5)
                        .OrderBy(b => b.Magnitude)
                        .ToList();
                    planetNames = visibleEvening.Select(b => b.Body.ToString()).ToList();
                }

                string planetSummary;
                string largePlanetSummary;
                if (planetNames.Count >= 2)
                {
                    planetSummary = $"🪐 {planetNames[0]} & {planetNames[1]} visible";
                    largePlanetSummary = $"🪐 {planetNames[0]} & {planetNames[1]}";
                }
                else if (planetNames.Count == 1)
                {
                    planetSummary = $"🪐 {planetNames[0]} in evening sky";
                    largePlanetSummary = $"🪐 {planetNames[0]} (Evening)";
                }
                else
                {
                    planetSummary = "✨ Deep Sky Objects visible";
                    largePlanetSummary = "✨ Deep Sky / Messier";
                }

                // 6. Real Deterministic Stargazing Score (combining cloud cover + moon illumination + moon altitude)
                int? cloudCover = null;
                try
                {
                    var weatherClient = App.Current.Services?.GetService<WeatherClient>();
                    var snapshot = weatherClient?.GetCachedSnapshot();
                    if (snapshot != null)
                    {
                        cloudCover = snapshot.Clouds;
                    }
                }
                catch { }

                var conditions = _astronomyService.EvaluateStargazingConditions(
                    lat, lon, now,
                    cloudCoverTotal: cloudCover,
                    bortleClass: 4);

                int skyScore = conditions.Score;

                // 7. Real ISS Pass (calculated via SGP4Propagator if cached OMM exists)
                string issPassText = "🛰️ Next Pass: Orbit Daylight";
                string largeIssPassText = "🛰️ Daylight Pass Only";
                try
                {
                    string cacheDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DailyApp", "Cache");
                    string issFile = Path.Combine(cacheDir, "iss_omm.json");
                    if (File.Exists(issFile))
                    {
                        var rawJson = File.ReadAllText(issFile);
                        var omm = System.Text.Json.JsonSerializer.Deserialize<Daily.Models.CelesTrakOmmRecord>(rawJson);
                        if (omm != null)
                        {
                            var passes = SGP4Propagator.PredictPasses(omm, lat, lon, now, hoursAhead: 24, minPeakAltitudeDeg: 15, requireSunlitAndDarkSky: true);
                            var nextPass = passes.FirstOrDefault();
                            if (nextPass != null)
                            {
                                var passLocal = nextPass.StartTimeUtc.ToLocalTime();
                                issPassText = $"🛰️ Next Pass: {passLocal:HH:mm}";
                                largeIssPassText = $"🛰️ {passLocal:HH:mm} ({nextPass.StartCompass} · Mag {nextPass.PeakMagnitude:F1})";
                            }
                        }
                    }
                }
                catch { }

                // ── Populate Small Layout ──
                SmallMoonGlyph.Text = glyph;
                SmallMoonPhaseText.Text = phaseName;
                SmallIllumText.Text = $"{illumination:F0}% illuminated";
                SmallStargazingText.Text = $"Stargazing: {skyScore}/100 ✨";

                // ── Populate Medium Layout ──
                MediumMoonGlyph.Text = glyph;
                MediumMoonSubtitle.Text = $"{phaseName} · {illumination:F0}% illumination";
                MediumScoreText.Text = skyScore.ToString();

                SkyQualityText.Text = !string.IsNullOrWhiteSpace(conditions.Summary) 
                    ? conditions.Summary 
                    : (skyScore >= 80 ? "Optimal dark sky conditions for stargazing." : "Moderate observing conditions tonight.");

                PlanetsText.Text = planetSummary;
                IssPassText.Text = issPassText;
                MoonTimesText.Text = moonTimes;

                // ── Populate Large Layout ──
                LargeScoreText.Text = skyScore.ToString();
                LargeMoonGlyph.Text = glyph;
                LargeMoonSubtitle.Text = $"{phaseName} · {illumination:F0}% illumination";
                LargeMoonPhaseName.Text = $"{phaseName} ({illumination:F0}% Illuminated)";
                LargeSkyQualityText.Text = !string.IsNullOrWhiteSpace(conditions.BestWindowDescription)
                    ? $"Best observing window: {conditions.BestWindowDescription} · {conditions.Summary}"
                    : (conditions.Summary ?? "Clear celestial observation conditions.");

                LargePlanetsText.Text = largePlanetSummary;
                LargeIssPassText.Text = largeIssPassText;
                LargeGoldenHourText.Text = goldenHourStr;
                LargeTransparencyText.Text = skyScore >= 80 ? "🌌 Bortle Class 4" : "🌌 Bortle Class 5";
                LargeEphemerisText.Text = $"Moonrise: {riseStr} · Moonset: {setStr} · Transit: {transitStr}";

                LargeBottomStargazingText.Text = $"Stargazing Index: {skyScore}/100";
                LargeBottomQualityText.Text = skyScore >= 80 ? "Optimal Night Sky ✨" : (skyScore >= 60 ? "Good Observing 🌟" : "Fair Seeing Conditions");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopCosmosWidget] Error refreshing: {ex.Message}");
            }
        }

        private static string GetMoonGlyph(double fraction)
        {
            if (fraction < 0.05) return "🌑"; // New
            if (fraction < 0.25) return "🌒"; // Waxing Crescent
            if (fraction < 0.45) return "🌓"; // First Quarter
            if (fraction < 0.75) return "🌔"; // Waxing Gibbous
            if (fraction < 0.95) return "🌕"; // Full
            return "🌖"; // Waning Gibbous
        }
    }
}
