using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Microsoft.Extensions.DependencyInjection;
using Daily.Models;
using Daily.Services;

namespace Daily_WinUI.Controls
{
    public sealed partial class TagdosWidgetControl : UserControl
    {
        private ITagdosService? _tagdosService;
        private List<TagDoStream> _streams = new();
        private TagDoQuickNote? _pinnedNote;

        public event EventHandler? OpenHubRequested;

        public TagdosWidgetControl()
        {
            this.InitializeComponent();
        }

        private void UserControl_Loaded(object sender, RoutedEventArgs e)
        {
            _tagdosService = App.Current.Services.GetService<ITagdosService>();
            if (_tagdosService != null)
            {
                _tagdosService.DataChanged += TagdosService_DataChanged;
            }
            _ = LoadDataAsync();
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
            DispatcherQueue.TryEnqueue(() =>
            {
                _ = LoadDataAsync();
            });
        }

        public async Task LoadDataAsync()
        {
            if (_tagdosService == null)
            {
                _tagdosService = App.Current.Services.GetService<ITagdosService>();
                if (_tagdosService == null) return;
            }

            try
            {
                _streams = await _tagdosService.GetStreamsAsync();
                var notes = await _tagdosService.GetQuickNotesAsync();
                _pinnedNote = notes.FirstOrDefault(n => n.IsPinned) ?? notes.FirstOrDefault();

                RenderWidget();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TagdosWidgetControl] Error loading: {ex.Message}");
            }
        }

        private void RenderWidget()
        {
            int totalActivePills = _streams.Sum(s => s.AllPills.Count(p => !p.IsCompleted));
            ActivePillsCountText.Text = $"{totalActivePills} active tags";

            // Stream 1
            if (_streams.Count > 0)
            {
                var s1 = _streams[0];
                Stream1TitleText.Text = s1.DisplayTitle;
                Stream1ReminderText.Text = s1.StreamReminder.HasValue
                    ? $"• {s1.StreamReminder.Value:HH:mm}"
                    : string.Empty;

                PopulatePillsPanel(Stream1PillsPanel, s1);
            }

            // Stream 2
            if (_streams.Count > 1)
            {
                var s2 = _streams[1];
                Stream2TitleText.Text = s2.DisplayTitle;
                Stream2ReminderText.Text = s2.StreamReminder.HasValue
                    ? $"• {s2.StreamReminder.Value:HH:mm}"
                    : string.Empty;

                PopulatePillsPanel(Stream2PillsPanel, s2);
            }

            // Pinned Note
            if (_pinnedNote != null)
            {
                PinnedNoteCard.Visibility = Visibility.Visible;
                PinnedNoteTitleText.Text = _pinnedNote.Title;
                PinnedNoteContentText.Text = _pinnedNote.Content;
            }
            else
            {
                PinnedNoteCard.Visibility = Visibility.Collapsed;
            }
        }

        private void PopulatePillsPanel(VariableSizedWrapGrid panel, TagDoStream stream)
        {
            panel.Children.Clear();
            var pills = stream.AllPills.Take(8).ToList();

            foreach (var pill in pills)
            {
                var pillBorder = CreatePillUI(pill, stream);
                panel.Children.Add(pillBorder);
            }
        }

        private Border CreatePillUI(TagDoPill pill, TagDoStream stream)
        {
            (Color bg, Color border, Color fg) = GetPillColors(pill.Type);

            var borderCtrl = new Border
            {
                Background = new SolidColorBrush(bg),
                BorderBrush = new SolidColorBrush(border),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(10),
                Padding = new Thickness(7, 3, 7, 3),
                Margin = new Thickness(2, 2, 4, 2),
                Tag = (pill, stream)
            };

            var textBlock = new TextBlock
            {
                Text = pill.Text,
                FontSize = 10.5,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = new SolidColorBrush(fg),
                VerticalAlignment = VerticalAlignment.Center
            };

            if (pill.IsCompleted)
            {
                textBlock.TextDecorations = Windows.UI.Text.TextDecorations.Strikethrough;
            }

            borderCtrl.Child = textBlock;
            borderCtrl.Tapped += Pill_Tapped;
            return borderCtrl;
        }

        private void Pill_Tapped(object sender, TappedRoutedEventArgs e)
        {
            e.Handled = true;
            if (sender is FrameworkElement fe && fe.Tag is ValueTuple<TagDoPill, TagDoStream> tuple)
            {
                var (pill, stream) = tuple;
                TagdosParser.TogglePillCompletion(stream, pill.Id);
                _ = _tagdosService?.SaveStreamAsync(stream);
            }
        }

        private (Color bg, Color border, Color fg) GetPillColors(TagDoPillType type)
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

        private void Header_Tapped(object sender, TappedRoutedEventArgs e)
        {
            OpenHubRequested?.Invoke(this, EventArgs.Empty);

            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(3);
            }
            else if (MainPage.Current != null)
            {
                MainPage.Current.OpenDetailWindow(typeof(Views.TagdosNotesDetailPage));
            }
        }
    }
}
