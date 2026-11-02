using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
                MediumLargeLayout.Visibility = Visibility.Collapsed;
            }
            else
            {
                SmallLayout.Visibility = Visibility.Collapsed;
                MediumLargeLayout.Visibility = Visibility.Visible;
            }
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            RefreshData();
        }

        public void RefreshData()
        {
            try
            {
                var now = DateTime.UtcNow;
                var moon = _astronomyService.GetMoonPhase(now);
                double illumination = Math.Round(moon.IlluminatedFraction * 100.0);
                string phaseName = !string.IsNullOrWhiteSpace(moon.Description) ? moon.Description : "Waxing Gibbous";
                string glyph = GetMoonGlyph(moon.IlluminatedFraction);

                int skyScore = 84;
                if (illumination > 85) skyScore = 65; // Bright moon washes out faint stars
                else if (illumination < 25) skyScore = 95; // Dark sky

                SmallMoonGlyph.Text = glyph;
                SmallMoonPhaseText.Text = phaseName;
                SmallIllumText.Text = $"{illumination:F0}% illuminated";
                SmallStargazingText.Text = $"Stargazing: {skyScore}/100 ✨";

                MediumMoonGlyph.Text = glyph;
                MediumMoonSubtitle.Text = $"{phaseName} · {illumination:F0}% illumination";
                MediumScoreText.Text = skyScore.ToString();

                SkyQualityText.Text = skyScore >= 80 
                    ? "Excellent dark sky conditions for stargazing." 
                    : "Moderate sky brightness from lunar illumination.";

                PlanetsText.Text = "🪐 Jupiter & Saturn visible";
                IssPassText.Text = "🛰️ Next ISS Pass: 21:42";
                MoonTimesText.Text = "Moonrise: 17:15 · Moonset: 05:40";
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
