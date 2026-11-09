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
            Detach();
        }

        public void Detach()
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
                string activeStreamName = firstStream?.DisplayTitle ?? "Focus";

                var quickNotes = await _tagdosService.GetQuickNotesAsync() ?? new List<TagDoQuickNote>();

                // ── 1. Small layout ─────────────────────────────────────────────
                SmallTaskCountText.Text = totalActive.ToString();
                SmallActiveStreamText.Text = $"Focus: {activeStreamName} ⚡";
                SmallTopTaskText.Text = activePills.Count > 0 
                    ? $"Next: {activePills[0].Text}" 
                    : "Next: All tasks done! 🌟";

                // ── 2. Medium layout ────────────────────────────────────────────
                MediumStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tasks";
                MediumFocusBadge.Text = $"Stream: {activeStreamName}";

                Task1Title.Text = activePills.Count > 0 
                    ? activePills[0].Text 
                    : "No pending tasks · All caught up! 🌟";
                Task1Tag.Text = activePills.Count > 0 && !string.IsNullOrEmpty(activePills[0].Tag)
                    ? activePills[0].Tag
                    : "Today";

                Task2Title.Text = activePills.Count > 1 
                    ? activePills[1].Text 
                    : (activePills.Count == 1 ? "Great momentum! Keep it going" : "Tap to open TagDos Hub");
                Task2Tag.Text = activePills.Count > 1 && !string.IsNullOrEmpty(activePills[1].Tag)
                    ? activePills[1].Tag
                    : (activePills.Count == 1 ? "Next" : "Hub");

                if (StreamNamesStatusText != null)
                {
                    string streamSummary = string.Join(" · ", streams.Take(5).Select(s => s.DisplayTitle));
                    StreamNamesStatusText.Text = string.IsNullOrWhiteSpace(streamSummary) ? "Daily TagDos Pipeline" : streamSummary;
                }

                // ── 3. Large layout ─────────────────────────────────────────────
                LargeStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tasks · {quickNotes.Count} notes";
                LargeFocusBadge.Text = $"Stream: {activeStreamName}";

                // Large Task 1
                LargeTask1Title.Text = activePills.Count > 0 ? activePills[0].Text : "All tasks completed! 🌟";
                LargeTask1Tag.Text = activePills.Count > 0 ? (activePills[0].Tag ?? "Priority 1") : "Done";

                // Large Task 2
                LargeTask2Title.Text = activePills.Count > 1 ? activePills[1].Text : (activePills.Count == 1 ? "Maintain daily habit streak" : "Take a mindful break");
                LargeTask2Tag.Text = activePills.Count > 1 ? (activePills[1].Tag ?? "Priority 2") : "Habits";

                // Large Task 3
                LargeTask3Title.Text = activePills.Count > 2 ? activePills[2].Text : (activePills.Count > 0 ? "Review evening goals & ledger" : "Organize notes");
                LargeTask3Tag.Text = activePills.Count > 2 ? (activePills[2].Tag ?? "Priority 3") : "Finances";

                // Large Task 4
                LargeTask4Title.Text = activePills.Count > 3 ? activePills[3].Text : "Sync health telemetry & sleep stages";
                LargeTask4Tag.Text = activePills.Count > 3 ? (activePills[3].Tag ?? "Priority 4") : "Health";

                // Large Task 5
                LargeTask5Title.Text = activePills.Count > 4 ? activePills[4].Text : "Stargazing & astronomical briefing";
                LargeTask5Tag.Text = activePills.Count > 4 ? (activePills[4].Tag ?? "Priority 5") : "Cosmos";

                // Quick Note preview
                var latestNote = quickNotes.OrderByDescending(n => n.UpdatedAt).FirstOrDefault();
                if (latestNote != null && !string.IsNullOrWhiteSpace(latestNote.Content))
                {
                    LargeQuickNotePreview.Text = $"Note: {latestNote.Content.Replace("\r", " ").Replace("\n", " ")}";
                }
                else
                {
                    LargeQuickNotePreview.Text = "No active quick notes · Tap to create";
                }
                LargeQuickNotesCount.Text = $"{quickNotes.Count} note(s)";

                string allStreams = string.Join(" · ", streams.Select(s => s.DisplayTitle));
                LargeStreamsSummary.Text = string.IsNullOrWhiteSpace(allStreams) ? "Streams: Work · Health · Finances · Personal" : $"Streams: {allStreams}";
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopTagdosWidget] Error refreshing: {ex.Message}");
            }
        }
    }
}
