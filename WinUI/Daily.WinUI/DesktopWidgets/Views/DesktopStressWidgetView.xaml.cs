using System;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services.Health;
using Daily_WinUI.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopStressWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private IHealthHubService? _healthHubService;
        private bool _isBreathing = false;

        public DesktopStressWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
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
            try
            {
                _healthHubService = App.Current.Services?.GetService<IHealthHubService>();
            }
            catch { }

            RefreshData();
        }

        public void Detach()
        {
        }

        public async void RefreshData()
        {
            if (_healthHubService == null)
            {
                try { _healthHubService = App.Current.Services?.GetService<IHealthHubService>(); } catch { }
            }

            try
            {
                int stressScore = 22;
                double hrv = 64;
                int pulse = 62;

                if (_healthHubService != null)
                {
                    var summary = await _healthHubService.GetDailySummaryAsync(DateTime.Today);
                    if (summary != null)
                    {
                        stressScore = summary.StressAvg ?? 22;
                        hrv = summary.HrvRmssd ?? 64;
                        pulse = (int)Math.Round(summary.Rhr ?? 62);
                    }
                }

                SmallProgressRing.Value = stressScore;
                SmallScoreText.Text = stressScore.ToString();
                SmallHrvText.Text = $"HRV: {hrv:F0} ms ({(stressScore < 30 ? "Calm" : "Balanced")})";

                MediumProgressRing.Value = stressScore;
                MediumScoreText.Text = stressScore.ToString();
                MediumHrvBadge.Text = $"HRV: {hrv:F0} ms (High)";
                MediumPulseBadge.Text = $"Pulse: {pulse} bpm";

                if (stressScore < 30)
                {
                    MediumLevelLabel.Text = "Low";
                    MediumStatusSubtitle.Text = "Autonomic State: Relaxed & Focused";
                    MediumRecommendationText.Text = "Optimal autonomic nervous system balance.";

                    LargeLevelLabel.Text = "Low";
                    LargeStatusSubtitle.Text = "State: Relaxed & Focused · Calm";
                    LargeRecommendationText.Text = "Optimal autonomic balance. Parasympathetic tone dominant.";
                    LargeToneText.Text = "Parasympathetic";
                    LargeResilienceText.Text = "94% Optimal";
                }
                else if (stressScore < 60)
                {
                    MediumLevelLabel.Text = "Balanced";
                    MediumStatusSubtitle.Text = "Autonomic State: Productive & Active";
                    MediumRecommendationText.Text = "Healthy daytime arousal. Keep hydrated.";

                    LargeLevelLabel.Text = "Balanced";
                    LargeStatusSubtitle.Text = "State: Productive & Active";
                    LargeRecommendationText.Text = "Balanced sympathetic tone. Moderate cognitive load.";
                    LargeToneText.Text = "Homeostatic";
                    LargeResilienceText.Text = "82% Strong";
                }
                else
                {
                    MediumLevelLabel.Text = "Elevated";
                    MediumStatusSubtitle.Text = "Autonomic State: High Strain";
                    MediumRecommendationText.Text = "Consider taking a short pause or walk.";

                    LargeLevelLabel.Text = "Elevated";
                    LargeStatusSubtitle.Text = "State: Sympathetic Dominant";
                    LargeRecommendationText.Text = "Elevated autonomic arousal. High cognitive or physical demand.";
                    LargeToneText.Text = "Sympathetic";
                    LargeResilienceText.Text = "68% Recovering";
                }

                // Large Layout Population
                LargeProgressRing.Value = stressScore;
                LargeScoreText.Text = stressScore.ToString();
                LargeHrvText.Text = $"{hrv:F0} ms ({(hrv >= 55 ? "High" : "Normal")})";
                LargePulseText.Text = $"{pulse} bpm (RHR)";
                LargeBottomSyncText.Text = $"Pulse: {pulse} bpm · HRV: {hrv:F0} ms";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopStressWidget] Error refreshing: {ex.Message}");
            }
        }

        private async void BreatheAction_Click(object sender, RoutedEventArgs e)
        {
            if (_isBreathing) return;
            _isBreathing = true;
            UpdateBreatheText("Inhale deeply (4s)...");

            await Task.Delay(3000);
            UpdateBreatheText("Hold gently (4s)...");

            await Task.Delay(3000);
            UpdateBreatheText("Exhale slowly (4s)...");

            await Task.Delay(3000);
            UpdateBreatheText("Relaxed! Well done ✨");

            await Task.Delay(2500);
            UpdateBreatheText("1-Minute Mindful Breathing");
            _isBreathing = false;
        }

        private void UpdateBreatheText(string text)
        {
            BreatheButtonText.Text = text;
            LargeBreatheButtonText.Text = text;
        }
    }
}
