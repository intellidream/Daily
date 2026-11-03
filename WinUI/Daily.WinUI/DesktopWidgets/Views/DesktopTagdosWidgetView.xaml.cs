using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Daily.Models;
using Daily.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopTagdosWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private ITagdosService? _tagdosService;

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
            try
            {
                _tagdosService = App.Current.Services?.GetService<ITagdosService>();
                if (_tagdosService != null)
                {
                    _tagdosService.DataChanged += TagdosService_DataChanged;
                }
            }
            catch { }

            RefreshData();
        }

        private void UserControl_Unloaded(object sender, RoutedEventArgs e)
        {
            if (_tagdosService != null)
            {
                _tagdosService.DataChanged -= TagdosService_DataChanged;
            }
        }

        private void TagdosService_DataChanged(object? sender, EventArgs e)
        {
            DispatcherQueue.TryEnqueue(RefreshData);
        }

        public async void RefreshData()
        {
            if (_tagdosService == null)
            {
                try { _tagdosService = App.Current.Services?.GetService<ITagdosService>(); } catch { }
            }
            if (_tagdosService == null) return;

            try
            {
                var streams = await _tagdosService.GetStreamsAsync() ?? new List<TagDoStream>();
                var activePills = streams.SelectMany(s => s.AllPills.Where(p => !p.IsCompleted)).ToList();
                int totalActive = activePills.Count;
                int streamCount = streams.Count;

                var firstStream = streams.FirstOrDefault();
                string activeStreamName = firstStream?.DisplayTitle ?? "Inbox";

                // Small layout
                SmallTaskCountText.Text = totalActive.ToString();
                SmallActiveStreamText.Text = $"Focus: {activeStreamName} ⚡";
                SmallTopTaskText.Text = activePills.Count > 0 
                    ? $"Next: {activePills[0].Text}" 
                    : "Next: All tasks done! 🌟";

                // Medium layout
                MediumStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tasks";
                MediumFocusBadge.Text = $"Stream: {activeStreamName}";

                Task1Title.Text = activePills.Count > 0 
                    ? activePills[0].Text 
                    : "No pending tasks · All caught up! 🌟";

                Task2Title.Text = activePills.Count > 1 
                    ? activePills[1].Text 
                    : (activePills.Count == 1 ? "Great momentum! Keep it going" : "Tap to open TagDos Hub");

                if (StreamNamesStatusText != null)
                {
                    string streamSummary = string.Join(" · ", streams.Take(4).Select(s => s.DisplayTitle));
                    StreamNamesStatusText.Text = string.IsNullOrWhiteSpace(streamSummary) ? "Daily TagDos Pipeline" : streamSummary;
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopTagdosWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
