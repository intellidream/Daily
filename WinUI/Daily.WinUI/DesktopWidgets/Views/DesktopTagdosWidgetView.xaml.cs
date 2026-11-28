using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.UI;
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
                Daily_WinUI.Services.SettingsService.SettingsChanged -= OnLoreenSettingsChanged;
                Daily_WinUI.Services.SettingsService.SettingsChanged += OnLoreenSettingsChanged;
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
            Daily_WinUI.Services.SettingsService.SettingsChanged -= OnLoreenSettingsChanged;
        }

        private void OnLoreenSettingsChanged(Daily_WinUI.Services.AppSettings _)
        {
            DispatcherQueue.TryEnqueue(RefreshData);
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
                bool isVeiled = Daily_WinUI.Services.SettingsService.Load().IsLoreenVeilActiveForWidgets;

                // ── 1. Small layout ─────────────────────────────────────────────
                SmallTaskCountText.Text = totalActive.ToString();
                SmallActiveStreamText.Text = $"Focus: {activeStreamName} ⚡";
                Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(SmallActiveStreamText, isVeiled);
                SmallTopTaskText.Text = activePills.Count > 0
                    ? $"Next: {activePills[0].Text}"
                    : "Next: All tasks done! 🌟";
                Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(SmallTopTaskText, isVeiled && activePills.Count > 0);

                // ── 2. Medium layout ────────────────────────────────────────────
                MediumStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tags";
                MediumFocusBadge.Text = $"Stream: {activeStreamName}";
                Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(MediumFocusBadge, isVeiled);

                MediumStreamsHost.Children.Clear();
                foreach (var stream in streams.Take(2))
                {
                    MediumStreamsHost.Children.Add(CreateStreamCardElement(stream, isVeiled));
                }

                if (StreamNamesStatusText != null)
                {
                    string streamSummary = string.Join(" · ", streams.Take(5).Select(s => s.DisplayTitle));
                    StreamNamesStatusText.Text = string.IsNullOrWhiteSpace(streamSummary) ? "Daily TagDoS Pipeline" : streamSummary;
                    Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(StreamNamesStatusText, isVeiled && !string.IsNullOrWhiteSpace(streamSummary));
                }

                // ── 3. Large layout ─────────────────────────────────────────────
                LargeStreamsSubtitle.Text = $"{streamCount} streams · {totalActive} open tags · {quickNotes.Count} notes";
                LargeFocusBadge.Text = $"Stream: {activeStreamName}";
                Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(LargeFocusBadge, isVeiled);

                LargeStreamsHost.Children.Clear();
                foreach (var stream in streams.Take(4))
                {
                    LargeStreamsHost.Children.Add(CreateStreamCardElement(stream, isVeiled));
                }

                var latestNote = quickNotes.OrderByDescending(n => n.UpdatedAt).FirstOrDefault();
                if (latestNote != null && !string.IsNullOrWhiteSpace(latestNote.Content))
                {
                    LargeQuickNotePreview.Text = $"Note: {latestNote.Content.Replace("\r", " ").Replace("\n", " ")}";
                    Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(LargeQuickNotePreview, isVeiled);
                }
                else
                {
                    LargeQuickNotePreview.Text = "No active quick notes · Click to create";
                    Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(LargeQuickNotePreview, false);
                }
                LargeQuickNotesCount.Text = $"{quickNotes.Count} note(s)";

                string allStreams = string.Join(" · ", streams.Select(s => s.DisplayTitle));
                LargeStreamsSummary.Text = string.IsNullOrWhiteSpace(allStreams) ? "Streams: Work · Health · Finances · Personal" : $"Streams: {allStreams}";
                Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(LargeStreamsSummary, isVeiled && !string.IsNullOrWhiteSpace(allStreams));
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopTagdosWidget] Error refreshing: {ex.Message}");
            }
        }

        private UIElement CreateStreamCardElement(TagDoStream stream, bool isVeiled)
        {
            var card = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0x16, 0xFF, 0xFF, 0xFF)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(9),
                Padding = new Thickness(9, 5, 9, 5)
            };

            var stack = new StackPanel { Spacing = 4 };

            // Row 0: Stream Title + Optional Schedule Time Only
            var titleRow = new Grid { ColumnSpacing = 6 };
            titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var titleBlock = new TextBlock
            {
                Text = stream.DisplayTitle,
                FontSize = 10.5,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Color.FromArgb(0xF0, 0xFF, 0xFF, 0xFF)),
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center
            };
            Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(titleBlock, isVeiled);
            titleBlock.Tapped += (_, e) =>
            {
                e.Handled = true;
                NavigateToMainHub(stream.Id, null);
            };
            Grid.SetColumn(titleBlock, 0);
            titleRow.Children.Add(titleBlock);

            DateTime? effectiveRem = stream.StreamReminder ?? stream.Clusters
                .Where(c => c.ClusterReminder.HasValue)
                .Select(c => c.ClusterReminder!.Value)
                .OrderBy(d => d)
                .FirstOrDefault();
            if (effectiveRem.HasValue && effectiveRem.Value != default)
            {
                var remPanel = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = 3,
                    VerticalAlignment = VerticalAlignment.Center
                };
                remPanel.Children.Add(new FontIcon
                {
                    Glyph = "\xE823",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 9,
                    Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF))
                });
                remPanel.Children.Add(new TextBlock
                {
                    Text = $"{effectiveRem.Value:HH:mm}",
                    FontSize = 9.5,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)),
                    VerticalAlignment = VerticalAlignment.Center
                });
                Grid.SetColumn(remPanel, 1);
                titleRow.Children.Add(remPanel);
            }
            stack.Children.Add(titleRow);

            // Row 1: Scrollable Pills Underneath Floating ✓ / ↻
            var pillsRowGrid = new Grid();
            var pillsScroll = new ScrollViewer
            {
                HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
                HorizontalScrollMode = ScrollMode.Enabled,
                VerticalScrollMode = ScrollMode.Disabled,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled
            };
            pillsScroll.PointerWheelChanged += (s, e) =>
            {
                if (s is ScrollViewer sv && sv.ScrollableWidth > 0)
                {
                    int delta = e.GetCurrentPoint(sv).Properties.MouseWheelDelta;
                    if (delta != 0)
                    {
                        sv.ChangeView(Math.Clamp(sv.HorizontalOffset - delta * 0.6, 0, sv.ScrollableWidth), null, null, false);
                        e.Handled = true;
                    }
                }
            };

            var focusPill = stream.AllPills.FirstOrDefault(p => !p.IsCompleted) ?? stream.DrivingPill;
            var pillsPanel = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 4,
                Padding = new Thickness(0, 0, focusPill != null ? 50 : 2, 0),
                VerticalAlignment = VerticalAlignment.Center
            };

            var displayPills = stream.AllPills.Where(p => !p.IsCompleted).ToList();
            if (displayPills.Count == 0) displayPills = stream.AllPills.ToList();

            foreach (var pill in displayPills)
            {
                (Color bg, Color border, Color fg) = GetPillColors(pill.Type);
                var pillText = new TextBlock
                {
                    Text = pill.Text,
                    FontSize = 10,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(fg),
                    VerticalAlignment = VerticalAlignment.Center
                };
                Daily_WinUI.Controls.LoreenVeilHelper.ApplyVeil(pillText, isVeiled);
                var pillBorder = new Border
                {
                    Background = new SolidColorBrush(bg),
                    BorderBrush = new SolidColorBrush(border),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(6, 2, 6, 2),
                    Child = pillText
                };
                pillBorder.Tapped += (_, e) =>
                {
                    e.Handled = true;
                    NavigateToMainHub(stream.Id, pill.Id);
                };
                pillsPanel.Children.Add(pillBorder);
            }

            pillsScroll.Content = pillsPanel;
            pillsRowGrid.Children.Add(pillsScroll);

            if (focusPill != null)
            {
                var overlay = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = 0,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    VerticalAlignment = VerticalAlignment.Center
                };
                overlay.Children.Add(CreateJewelActionSlot(
                    glyph: "✓",
                    accentColor: Color.FromArgb(0xFF, 0x00, 0xE6, 0x76),
                    coreColor: Color.FromArgb(0xFF, 0x0D, 0x30, 0x26),
                    onTapped: () => ExecuteStreamPillActionAsync(stream, focusPill, recycle: false)
                ));
                overlay.Children.Add(CreateJewelActionSlot(
                    glyph: "↻",
                    accentColor: Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF),
                    coreColor: Color.FromArgb(0xFF, 0x0D, 0x2B, 0x3D),
                    onTapped: () => ExecuteStreamPillActionAsync(stream, focusPill, recycle: true)
                ));
                pillsRowGrid.Children.Add(overlay);
            }

            stack.Children.Add(pillsRowGrid);
            card.Child = stack;
            return card;
        }

        private static Grid CreateJewelActionSlot(string glyph, Color accentColor, Color coreColor, Func<Task> onTapped)
        {
            var glow = new Microsoft.UI.Xaml.Shapes.Ellipse
            {
                Width = 24,
                Height = 24,
                IsHitTestVisible = false,
                Fill = new RadialGradientBrush
                {
                    Center = new Point(0.5, 0.5),
                    RadiusX = 0.5,
                    RadiusY = 0.5,
                    GradientStops =
                    {
                        new GradientStop { Color = Color.FromArgb(0x45, accentColor.R, accentColor.G, accentColor.B), Offset = 0.55 },
                        new GradientStop { Color = Color.FromArgb(0x00, accentColor.R, accentColor.G, accentColor.B), Offset = 1.0 }
                    }
                }
            };
            var btn = new Border
            {
                Width = 19,
                Height = 19,
                CornerRadius = new CornerRadius(9.5),
                Background = new SolidColorBrush(coreColor),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x94, accentColor.R, accentColor.G, accentColor.B)),
                BorderThickness = new Thickness(1),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock
                {
                    Text = glyph,
                    FontSize = 9,
                    FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                    Foreground = new SolidColorBrush(accentColor),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                }
            };
            btn.Tapped += async (_, e) =>
            {
                e.Handled = true;
                await onTapped();
            };

            var slot = new Grid { Width = 24, Height = 24 };
            slot.Children.Add(glow);
            slot.Children.Add(btn);
            return slot;
        }

        private async Task ExecuteStreamPillActionAsync(TagDoStream stream, TagDoPill pill, bool recycle)
        {
            if (_tagdosService == null) return;
            if (recycle)
                TagdosParser.RecyclePillToBack(stream, pill.Id);
            else
                TagdosParser.TogglePillCompletion(stream, pill.Id);

            await _tagdosService.SaveStreamAsync(stream);
            RefreshData();
        }

        private static (Color bg, Color border, Color fg) GetPillColors(TagDoPillType type)
        {
            return type switch
            {
                TagDoPillType.Financial => (
                    Color.FromArgb(0x22, 0x00, 0xD0, 0x9C),
                    Color.FromArgb(0x66, 0x00, 0xD0, 0x9C),
                    Color.FromArgb(0xFF, 0x00, 0xD0, 0x9C)),
                TagDoPillType.Urgent => (
                    Color.FromArgb(0x22, 0xFF, 0x2D, 0x55),
                    Color.FromArgb(0x66, 0xFF, 0x2D, 0x55),
                    Color.FromArgb(0xFF, 0xFF, 0x2D, 0x55)),
                TagDoPillType.TemporalOrMetric => (
                    Color.FromArgb(0x22, 0xFF, 0xB3, 0x00),
                    Color.FromArgb(0x66, 0xFF, 0xB3, 0x00),
                    Color.FromArgb(0xFF, 0xFF, 0xB3, 0x00)),
                TagDoPillType.Completed => (
                    Color.FromArgb(0x0E, 0xFF, 0xFF, 0xFF),
                    Color.FromArgb(0x26, 0xFF, 0xFF, 0xFF),
                    Color.FromArgb(0x77, 0xFF, 0xFF, 0xFF)),
                _ => (
                    Color.FromArgb(0x22, 0x00, 0xE5, 0xFF),
                    Color.FromArgb(0x66, 0x00, 0xE5, 0xFF),
                    Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF))
            };
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
            await ExecuteStreamPillActionAsync(stream, pill, recycle);
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
                else if (!string.IsNullOrWhiteSpace(streamId))
                {
                    WidgetsHostIpc.ForwardUriToMainApp(
                        $"daily://tagdos?streamId={Uri.EscapeDataString(streamId)}");
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
    }
}
