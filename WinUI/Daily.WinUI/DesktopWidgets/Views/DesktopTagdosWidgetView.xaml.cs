using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopTagdosWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;

        public DesktopTagdosWidgetView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
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
                SmallTaskCountText.Text = "4";
                SmallActiveStreamText.Text = "Focus: Work ⚡";
                SmallTopTaskText.Text = "Next: Weekly finance review";

                MediumStreamsSubtitle.Text = "4 active streams · 5 tasks open";
                MediumFocusBadge.Text = "Active Stream: Work";
                Task1Title.Text = "Complete weekly finance review";
                Task2Title.Text = "Hydration & evening breathwork";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopTagdosWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
