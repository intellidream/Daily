using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopSmokesWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private IHabitsService? _habitsService;

        public DesktopSmokesWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
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
            try
            {
                _habitsService = App.Current.Services?.GetService<IHabitsService>();
                if (_habitsService != null)
                {
                    _habitsService.OnHabitsUpdated += HabitsService_OnHabitsUpdated;
                }
            }
            catch { }

            RefreshData();
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
            Detach();
        }

        public void Detach()
        {
            if (_habitsService != null)
            {
                _habitsService.OnHabitsUpdated -= HabitsService_OnHabitsUpdated;
            }
        }

        private void HabitsService_OnHabitsUpdated()
        {
            DispatcherQueue.TryEnqueue(RefreshData);
        }

        public async void RefreshData()
        {
            if (_habitsService == null)
            {
                try { _habitsService = App.Current.Services?.GetService<IHabitsService>(); } catch { }
            }
            if (_habitsService == null) return;

            try
            {
                var today = DateTime.Today;
                var logs = await _habitsService.GetLogsAsync("smokes", today);

                int totalSmokes = logs?.Count ?? 0;
                int cigarettes = logs?.Count(l => (l.Metadata?.ToLowerInvariant().Contains("heated") != true) && (l.Unit?.ToLowerInvariant() != "heated")) ?? 0;
                int heated = totalSmokes - cigarettes;

                var settingsService = App.Current.Services?.GetService<ISettingsService>();
                int maxSmokes = (settingsService?.Settings?.SmokesBaselineDaily > 0) ? settingsService.Settings.SmokesBaselineDaily : 40;

                // Lungs fill fraction: 0.0 (healthy pink) to 1.0 (tar darkened) based on baseline daily intake
                double fillFraction = Math.Clamp((double)totalSmokes / (double)maxSmokes, 0.0, 1.0);

                SmallLungsControl.FillFraction = fillFraction;
                MediumLungsControl.FillFraction = fillFraction;

                SmallCountText.Text = totalSmokes.ToString();
                SmallBaselineText.Text = $"of {maxSmokes} smokes";
                MediumTotalCountText.Text = totalSmokes.ToString();
                MediumBaselineText.Text = $"of {maxSmokes} smokes";
                CigarettesCountText.Text = $"🚬 {cigarettes} Cigarettes";
                HeatedCountText.Text = $"🔥 {heated} Heated";

                // Craving-free calculation with exact UTC timezone parity
                if (totalSmokes == 0)
                {
                    SmallCravingText.Text = "Free: All Day";
                    MediumCravingBadge.Text = "Smoke-Free Today! 🌟";
                    HealthStatusText.Text = "Optimal lung capacity (100%)";
                }
                else
                {
                    var lastLog = logs!.OrderByDescending(l => l.LoggedAt).First();
                    var lastUtc = lastLog.LoggedAt.Kind == DateTimeKind.Utc ? lastLog.LoggedAt : lastLog.LoggedAt.ToUniversalTime();
                    var timeSince = DateTime.UtcNow - lastUtc;
                    if (timeSince < TimeSpan.Zero) timeSince = TimeSpan.Zero;

                    string timeStr = timeSince.TotalHours >= 1 
                        ? $"{(int)timeSince.TotalHours}h {timeSince.Minutes}m" 
                        : $"{timeSince.Minutes}m";

                    SmallCravingText.Text = $"Free: {timeStr}";
                    MediumCravingBadge.Text = $"Craving-Free: {timeStr}";

                    int capacity = Math.Max(20, 100 - (int)((double)totalSmokes / maxSmokes * 70));
                    HealthStatusText.Text = $"Estimated lung recovery: {capacity}%";
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopSmokesWidget] Error refreshing: {ex.Message}");
            }
        }

        private async void LogCigarette_Click(object sender, RoutedEventArgs e)
        {
            await LogSmokeAsync("cigarette");
        }

        private async void LogHeated_Click(object sender, RoutedEventArgs e)
        {
            await LogSmokeAsync("heated");
        }

        private async Task LogSmokeAsync(string type)
        {
            if (_habitsService == null) return;
            try
            {
                await _habitsService.AddLogAsync("smokes", 1, type, DateTime.Now, type);
                RefreshData();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopSmokesWidget] Error logging smoke: {ex.Message}");
            }
        }
    }
}
