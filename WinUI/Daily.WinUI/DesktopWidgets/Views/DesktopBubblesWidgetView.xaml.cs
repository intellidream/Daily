using System;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopBubblesWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private IHabitsService? _habitsService;

        public DesktopBubblesWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
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
                var currentMl = await _habitsService.GetDailyProgressAsync("water", today);
                var goal = await _habitsService.GetGoalAsync("water");
                var targetMl = goal?.TargetValue > 0 ? goal.TargetValue : 2500;
                var breakdown = await _habitsService.GetDailyBreakdownAsync("water", today);

                double percent = Math.Clamp((currentMl / targetMl) * 100.0, 0, 100);

                // Small layout
                SmallProgressRing.Value = percent;
                SmallPercentText.Text = $"{(int)percent}%";
                SmallAmountText.Text = $"{(int)currentMl} ml";

                // Medium layout
                MediumProgressRing.Value = percent;
                MediumPercentBadge.Text = $"{(int)percent}%";
                CurrentIntakeText.Text = $"{(int)currentMl:N0}";
                MediumSubtitleText.Text = $"Goal: {targetMl:N0} ml";

                double water = breakdown.TryGetValue("Water", out var wVal) ? wVal : (breakdown.TryGetValue("water", out var w2Val) ? w2Val : currentMl);
                double coffee = breakdown.TryGetValue("Coffee", out var cVal) ? cVal : 0;
                double tea = breakdown.TryGetValue("Tea", out var tVal) ? tVal : 0;

                WaterAmountText.Text = $"💧 {(int)water} ml";
                CoffeeAmountText.Text = $"☕ {(int)coffee} ml";
                TeaAmountText.Text = $"🍵 {(int)tea} ml";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopBubblesWidget] Error refreshing: {ex.Message}");
            }
        }

        private async void LogCoffee100_Click(object sender, RoutedEventArgs e)
        {
            await LogDrinkAsync(100, "Coffee");
        }

        private async void LogWater150_Click(object sender, RoutedEventArgs e)
        {
            await LogDrinkAsync(150, "Water");
        }

        private async void LogWater300_Click(object sender, RoutedEventArgs e)
        {
            await LogDrinkAsync(300, "Water");
        }

        private async Task LogDrinkAsync(double amountMl, string drinkType)
        {
            if (_habitsService == null) return;
            try
            {
                await _habitsService.AddLogAsync("water", amountMl, "ml", DateTime.Now, drinkType);
                RefreshData();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopBubblesWidget] Error logging drink: {ex.Message}");
            }
        }
    }
}
