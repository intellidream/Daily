using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Daily.Models;
using Daily.Services;

namespace Daily_WinUI.DesktopWidgets.Views
{
    public sealed partial class DesktopTagdosWidgetView : UserControl, IDesktopWidgetView
    {
        private readonly DesktopWidgetModel _model;
        private readonly DesktopWidgetWindow _hostWindow;
        private ITagdosService? _tagdosService;
        private List<(TagDoStream Stream, TagDoPill Pill)> _displayedEntries = new();

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
                    _tagdosService.DataChanged -= TagdosService_DataChanged;
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
                var entries = streams
                    .SelectMany(s => s.AllPills.Where(p => !p.IsCompleted).Select(p => (Stream: s, Pill: p)))
                    .ToList();
                _displayedEntries = entries;

                var activePills = entries.Select(e => e.Pill).ToList();
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
                MediumStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tags";
                MediumFocusBadge.Text = $"Stream: {activeStreamName}";

                Task1Title.Text = activePills.Count > 0
                    ? activePills[0].Text
                    : "No pending tags · All caught up! 🌟";
                Task1Tag.Text = activePills.Count > 0
                    ? FormatPillTag(activePills[0], "Today")
                    : "Today";

                Task2Title.Text = activePills.Count > 1
                    ? activePills[1].Text
                    : (activePills.Count == 1 ? "Great momentum! Keep it going" : "Click to open TagDoS Hub");
                Task2Tag.Text = activePills.Count > 1
                    ? FormatPillTag(activePills[1], "Next")
                    : (activePills.Count == 1 ? "Next" : "Hub");

                if (StreamNamesStatusText != null)
                {
                    string streamSummary = string.Join(" · ", streams.Take(5).Select(s => s.DisplayTitle));
                    StreamNamesStatusText.Text = string.IsNullOrWhiteSpace(streamSummary) ? "Daily TagDoS Pipeline" : streamSummary;
                }

                // ── 3. Large layout ─────────────────────────────────────────────
                LargeStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tags · {quickNotes.Count} notes";
                LargeFocusBadge.Text = $"Stream: {activeStreamName}";

                LargeTask1Title.Text = activePills.Count > 0 ? activePills[0].Text : "All tags completed! 🌟";
                LargeTask1Tag.Text = activePills.Count > 0 ? FormatPillTag(activePills[0], "Priority 1") : "Done";

                LargeTask2Title.Text = activePills.Count > 1 ? activePills[1].Text : (activePills.Count == 1 ? "Maintain daily habit streak" : "Take a mindful break");
                LargeTask2Tag.Text = activePills.Count > 1 ? FormatPillTag(activePills[1], "Priority 2") : "Habits";

                LargeTask3Title.Text = activePills.Count > 2 ? activePills[2].Text : (activePills.Count > 0 ? "Review evening goals & ledger" : "Organize notes");
                LargeTask3Tag.Text = activePills.Count > 2 ? FormatPillTag(activePills[2], "Priority 3") : "Finances";

                LargeTask4Title.Text = activePills.Count > 3 ? activePills[3].Text : "Sync health telemetry & sleep stages";
                LargeTask4Tag.Text = activePills.Count > 3 ? FormatPillTag(activePills[3], "Priority 4") : "Health";

                LargeTask5Title.Text = activePills.Count > 4 ? activePills[4].Text : "Stargazing & astronomical briefing";
                LargeTask5Tag.Text = activePills.Count > 4 ? FormatPillTag(activePills[4], "Priority 5") : "Cosmos";

                var latestNote = quickNotes.OrderByDescending(n => n.UpdatedAt).FirstOrDefault();
                if (latestNote != null && !string.IsNullOrWhiteSpace(latestNote.Content))
                {
                    LargeQuickNotePreview.Text = $"Note: {latestNote.Content.Replace("\r", " ").Replace("\n", " ")}";
                }
                else
                {
                    LargeQuickNotePreview.Text = "No active quick notes · Click to create";
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

        private static int ParseSlotTag(object sender)
        {
            if (sender is FrameworkElement fe && fe.Tag != null && int.TryParse(fe.Tag.ToString(), out int idx))
            {
                return idx;
            }
            return -1;
        }

        private void OpenHub_Tapped(object sender, TappedRoutedEventArgs e)
        {
            e.Handled = true;
            NavigateToMainHub(streamId: null, pillId: null);
        }

        private void TaskRow_Tapped(object sender, TappedRoutedEventArgs e)
        {
            e.Handled = true;
            int idx = ParseSlotTag(sender);
            if (idx >= 0 && idx < _displayedEntries.Count)
            {
                var entry = _displayedEntries[idx];
                NavigateToMainHub(entry.Stream.Id, entry.Pill.Id);
            }
            else
            {
                NavigateToMainHub(null, null);
            }
        }

        private async void DoneSlot_Tapped(object sender, TappedRoutedEventArgs e)
        {
            e.Handled = true;
            await ExecutePillActionAsync(ParseSlotTag(sender), recycle: false);
        }

        private async void RecycleSlot_Tapped(object sender, TappedRoutedEventArgs e)
        {
            e.Handled = true;
            await ExecutePillActionAsync(ParseSlotTag(sender), recycle: true);
        }

        private async Task ExecutePillActionAsync(int slotIndex, bool recycle)
        {
            if (_tagdosService == null || slotIndex < 0 || slotIndex >= _displayedEntries.Count)
                return;

            var (stream, pill) = _displayedEntries[slotIndex];
            if (recycle)
                TagdosParser.RecyclePillToBack(stream, pill.Id);
            else
                TagdosParser.TogglePillCompletion(stream, pill.Id);

            await _tagdosService.SaveStreamAsync(stream);
            RefreshData();
        }

        private void NavigateToMainHub(string? streamId, string? pillId)
        {
            if (WidgetsHostIpc.IsRunningInHostProcess)
            {
                if (!string.IsNullOrWhiteSpace(streamId) && !string.IsNullOrWhiteSpace(pillId))
                {
                    WidgetsHostIpc.ForwardUriToMainApp(
                        $"daily://tagdos?streamId={Uri.EscapeDataString(streamId)}&pillId={Uri.EscapeDataString(pillId)}&edit=1");
                }
                else
                {
                    WidgetsHostIpc.ForwardNavigationToMainApp(3);
                }
                return;
            }

            _tagdosService?.RequestNavigation(
                streamId: streamId,
                pillId: pillId,
                openPillEditor: !string.IsNullOrWhiteSpace(pillId));

#if !WIDGETS_HOST
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.ShowAndActivate();
                mw.NavigateToTab(3);
            }
#endif
        }

        private static string FormatPillTag(TagDoPill pill, string fallback) =>
            pill.Type switch
            {
                TagDoPillType.Urgent => "Urgent",
                TagDoPillType.Financial => "Finances",
                TagDoPillType.TemporalOrMetric => "Metric",
                TagDoPillType.Completed => "Done",
                _ => fallback
            };
    }
}
