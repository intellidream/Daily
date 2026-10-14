using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Microsoft.Extensions.DependencyInjection;
using Daily.Models;
using Daily.Services;

namespace Daily_WinUI.Views
{
    public sealed partial class TagdosNotesDetailPage : Page
    {
        private ITagdosService? _tagdosService;
        private List<TagDoStream> _streams = new();
        private List<TagDoQuickNote> _notes = new();
        private int _selectedStreamIndex = 0; // 0..4 for Streams 1..5, 5 for Quick Notes
        private bool _isRawEditMode = false;

        public TagdosNotesDetailPage()
        {
            this.InitializeComponent();
        }

        private void Page_Loaded(object sender, RoutedEventArgs e)
        {
            if (this.Frame != App.Current?.MainWindow?.RootFrame)
            {
                if (BackButton != null) BackButton.Visibility = Visibility.Collapsed;
                if (PopOutButton != null) PopOutButton.Visibility = Visibility.Collapsed;
            }

            _tagdosService = App.Current.Services.GetService<ITagdosService>();
            if (_tagdosService != null)
            {
                _tagdosService.DataChanged += TagdosService_DataChanged;
            }
            _ = LoadDataAsync();
        }

        private void TagdosService_DataChanged(object? sender, EventArgs e)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                _ = LoadDataAsync();
            });
        }

        private async Task LoadDataAsync()
        {
            if (_tagdosService == null)
            {
                _tagdosService = App.Current.Services.GetService<ITagdosService>();
                if (_tagdosService == null) return;
            }

            try
            {
                _streams = await _tagdosService.GetStreamsAsync();
                _notes = await _tagdosService.GetQuickNotesAsync();

                RenderStreamTabs();
                SelectTab(_selectedStreamIndex);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TagdosNotesDetailPage] Error loading: {ex.Message}");
            }
        }

        // ── Stream Selector Segmented Tabs ───────────────────────────────────

        private void RenderStreamTabs()
        {
            StreamTabsPanel.Children.Clear();

            // Tabs for Streams 0..4
            for (int i = 0; i < _streams.Count; i++)
            {
                var stream = _streams[i];
                int tabIndex = i;
                bool isSelected = tabIndex == _selectedStreamIndex;

                var btn = new Button
                {
                    Background = isSelected ? new SolidColorBrush(Color.FromArgb(0x40, 0xAF, 0x52, 0xDE)) : new SolidColorBrush(Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF)),
                    BorderBrush = isSelected ? new SolidColorBrush(Color.FromArgb(0x99, 0xAF, 0x52, 0xDE)) : new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(14),
                    Padding = new Thickness(14, 6, 14, 6),
                    Tag = tabIndex
                };

                var contentStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                contentStack.Children.Add(new TextBlock
                {
                    Text = $"Stream {i + 1}: {stream.DisplayTitle}",
                    FontSize = 12,
                    FontWeight = isSelected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
                    Foreground = isSelected ? new SolidColorBrush(Microsoft.UI.Colors.White) : new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF))
                });

                int activePills = stream.AllPills.Count(p => !p.IsCompleted);
                if (activePills > 0)
                {
                    var badge = new Border
                    {
                        Background = isSelected ? new SolidColorBrush(Color.FromArgb(0x66, 0xAF, 0x52, 0xDE)) : new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                        CornerRadius = new CornerRadius(8),
                        Padding = new Thickness(6, 1, 6, 1),
                        Child = new TextBlock
                        {
                            Text = activePills.ToString(),
                            FontSize = 10,
                            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                            Foreground = isSelected ? new SolidColorBrush(Microsoft.UI.Colors.White) : new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF))
                        }
                    };
                    contentStack.Children.Add(badge);
                }

                btn.Content = contentStack;
                btn.Click += (s, ev) => SelectTab(tabIndex);
                StreamTabsPanel.Children.Add(btn);
            }

            // Tab 5: Quick Notes
            int notesIndex = _streams.Count;
            bool isNotesSelected = _selectedStreamIndex == notesIndex;

            var notesBtn = new Button
            {
                Background = isNotesSelected ? new SolidColorBrush(Color.FromArgb(0x40, 0x00, 0xE5, 0xFF)) : new SolidColorBrush(Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF)),
                BorderBrush = isNotesSelected ? new SolidColorBrush(Color.FromArgb(0x99, 0x00, 0xE5, 0xFF)) : new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(14, 6, 14, 6),
                Tag = notesIndex
            };

            var notesStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            notesStack.Children.Add(new FontIcon
            {
                Glyph = "\xE70B",
                FontFamily = new FontFamily("Segoe Fluent Icons"),
                FontSize = 12,
                Foreground = isNotesSelected ? new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)) : new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF))
            });
            notesStack.Children.Add(new TextBlock
            {
                Text = "Quick Notes",
                FontSize = 12,
                FontWeight = isNotesSelected ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
                Foreground = isNotesSelected ? new SolidColorBrush(Microsoft.UI.Colors.White) : new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF))
            });

            if (_notes.Count > 0)
            {
                var notesBadge = new Border
                {
                    Background = isNotesSelected ? new SolidColorBrush(Color.FromArgb(0x66, 0x00, 0xE5, 0xFF)) : new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(6, 1, 6, 1),
                    Child = new TextBlock
                    {
                        Text = _notes.Count.ToString(),
                        FontSize = 10,
                        FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                        Foreground = isNotesSelected ? new SolidColorBrush(Microsoft.UI.Colors.White) : new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF))
                    }
                };
                notesStack.Children.Add(notesBadge);
            }

            notesBtn.Content = notesStack;
            notesBtn.Click += (s, ev) => SelectTab(notesIndex);
            StreamTabsPanel.Children.Add(notesBtn);
        }

        private void SelectTab(int index)
        {
            _selectedStreamIndex = index;
            RenderStreamTabs();

            if (index < _streams.Count)
            {
                StreamViewPanel.Visibility = Visibility.Visible;
                QuickNotesViewPanel.Visibility = Visibility.Collapsed;
                RenderStreamView(_streams[index]);
            }
            else
            {
                StreamViewPanel.Visibility = Visibility.Collapsed;
                QuickNotesViewPanel.Visibility = Visibility.Visible;
                RenderQuickNotes(NoteSearchBox.Text);
            }
        }

        // ── Stream View & Visual Canvas ──────────────────────────────────────

        private void RenderStreamView(TagDoStream stream)
        {
            StreamHeaderTitle.Text = stream.DisplayTitle;
            StreamReminderText.Text = stream.StreamReminder.HasValue
                ? $"Reminder: {stream.StreamReminder.Value:HH:mm}"
                : "No reminder set";

            int totalActive = stream.AllPills.Count(p => !p.IsCompleted);
            StreamStatsText.Text = $"• {totalActive} active pills ({stream.Clusters.Count} clusters)";
            StreamMemosTextBox.Text = stream.ActiveMemos;

            RenderAttachments(stream);
            RenderClusters(stream);
        }

        private void RenderClusters(TagDoStream stream)
        {
            ClustersContainer.Children.Clear();

            for (int cIdx = 0; cIdx < stream.Clusters.Count; cIdx++)
            {
                var cluster = stream.Clusters[cIdx];
                int clusterNum = cIdx + 1;

                var clusterBorder = new Border
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(12),
                    Padding = new Thickness(12, 10, 12, 10),
                    Margin = new Thickness(0, 0, 0, 4)
                };

                var clusterGrid = new Grid();
                clusterGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(80) });
                clusterGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                // Cluster Header label
                var clusterLabel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                clusterLabel.Children.Add(new TextBlock
                {
                    Text = $"Batch #{clusterNum}",
                    FontSize = 11,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xAF, 0x52, 0xDE))
                });
                clusterLabel.Children.Add(new TextBlock
                {
                    Text = $"{cluster.Pills.Count} items",
                    FontSize = 9.5,
                    Foreground = new SolidColorBrush(Color.FromArgb(0x88, 0xFF, 0xFF, 0xFF))
                });
                Grid.SetColumn(clusterLabel, 0);
                clusterGrid.Children.Add(clusterLabel);

                // Pills horizontal flow
                var pillsWrap = new VariableSizedWrapGrid
                {
                    Orientation = Orientation.Horizontal,
                    ItemHeight = 36,
                    VerticalAlignment = VerticalAlignment.Center
                };

                for (int pIdx = 0; pIdx < cluster.Pills.Count; pIdx++)
                {
                    var pill = cluster.Pills[pIdx];
                    var pillUI = CreateInteractivePillUI(pill, stream, cIdx);
                    pillsWrap.Children.Add(pillUI);

                    // Add subtle separator slash between pills in cluster
                    if (pIdx < cluster.Pills.Count - 1)
                    {
                        var slash = new TextBlock
                        {
                            Text = "/",
                            FontSize = 11,
                            Opacity = 0.35,
                            VerticalAlignment = VerticalAlignment.Center,
                            Margin = new Thickness(2, 0, 2, 0)
                        };
                        pillsWrap.Children.Add(slash);
                    }
                }

                Grid.SetColumn(pillsWrap, 1);
                clusterGrid.Children.Add(pillsWrap);

                clusterBorder.Child = clusterGrid;
                ClustersContainer.Children.Add(clusterBorder);
            }
        }

        private FrameworkElement CreateInteractivePillUI(TagDoPill pill, TagDoStream stream, int clusterIndex)
        {
            (Color bg, Color border, Color fg) = GetPillColors(pill.Type);

            var pillBorder = new Border
            {
                Background = new SolidColorBrush(bg),
                BorderBrush = new SolidColorBrush(border),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(11),
                Padding = new Thickness(10, 5, 10, 5),
                Margin = new Thickness(3, 2, 3, 2),
                Tag = (pill, stream, clusterIndex)
            };

            var textBlock = new TextBlock
            {
                Text = pill.Text,
                FontSize = 12,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = new SolidColorBrush(fg),
                VerticalAlignment = VerticalAlignment.Center
            };

            if (pill.IsCompleted)
            {
                textBlock.TextDecorations = Windows.UI.Text.TextDecorations.Strikethrough;
            }

            pillBorder.Child = textBlock;

            // Context/Action Flyout
            var flyout = new MenuFlyout();

            var toggleDoneItem = new MenuFlyoutItem
            {
                Text = pill.IsCompleted ? "Mark Incomplete" : "Mark Done",
                Icon = new FontIcon { Glyph = "\xE73E" }
            };
            toggleDoneItem.Click += (s, e) =>
            {
                TagdosParser.TogglePillCompletion(stream, pill.Id);
                _ = _tagdosService?.SaveStreamAsync(stream);
                RenderStreamView(stream);
            };
            flyout.Items.Add(toggleDoneItem);

            var recycleItem = new MenuFlyoutItem
            {
                Text = "Recycle to Back",
                Icon = new FontIcon { Glyph = "\xE777" }
            };
            recycleItem.Click += (s, e) =>
            {
                TagdosParser.RecyclePillToBack(stream, pill.Id);
                _ = _tagdosService?.SaveStreamAsync(stream);
                RenderStreamView(stream);
            };
            flyout.Items.Add(recycleItem);

            var moveFrontItem = new MenuFlyoutItem
            {
                Text = "Prioritize to Front",
                Icon = new FontIcon { Glyph = "\xE74B" }
            };
            moveFrontItem.Click += (s, e) =>
            {
                TagdosParser.MovePillToFront(stream, pill.Id);
                _ = _tagdosService?.SaveStreamAsync(stream);
                RenderStreamView(stream);
            };
            flyout.Items.Add(moveFrontItem);

            flyout.Items.Add(new MenuFlyoutSeparator());

            var deleteItem = new MenuFlyoutItem
            {
                Text = "Delete Tag",
                Icon = new FontIcon { Glyph = "\xE74D" }
            };
            deleteItem.Click += (s, e) =>
            {
                TagdosParser.RemovePill(stream, pill.Id);
                _ = _tagdosService?.SaveStreamAsync(stream);
                RenderStreamView(stream);
            };
            flyout.Items.Add(deleteItem);

            pillBorder.ContextFlyout = flyout;
            pillBorder.Tapped += (s, e) =>
            {
                flyout.ShowAt(pillBorder);
            };

            return pillBorder;
        }

        private (Color bg, Color border, Color fg) GetPillColors(TagDoPillType type)
        {
            return type switch
            {
                TagDoPillType.Financial => (
                    Color.FromArgb(0x28, 0x00, 0xD0, 0x9C),
                    Color.FromArgb(0x77, 0x00, 0xD0, 0x9C),
                    Color.FromArgb(0xFF, 0x00, 0xD0, 0x9C)),
                TagDoPillType.Urgent => (
                    Color.FromArgb(0x28, 0xFF, 0x2D, 0x55),
                    Color.FromArgb(0x77, 0xFF, 0x2D, 0x55),
                    Color.FromArgb(0xFF, 0xFF, 0x2D, 0x55)),
                TagDoPillType.TemporalOrMetric => (
                    Color.FromArgb(0x28, 0xFF, 0xB3, 0x00),
                    Color.FromArgb(0x77, 0xFF, 0xB3, 0x00),
                    Color.FromArgb(0xFF, 0xFF, 0xB3, 0x00)),
                TagDoPillType.Completed => (
                    Color.FromArgb(0x10, 0xFF, 0xFF, 0xFF),
                    Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF),
                    Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)),
                _ => (
                    Color.FromArgb(0x28, 0x00, 0xE5, 0xFF),
                    Color.FromArgb(0x77, 0x00, 0xE5, 0xFF),
                    Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF))
            };
        }

        // ── Stream Operations: Add Tag, Rename, Reminder ─────────────────────

        private async void AddTagButton_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedStreamIndex >= _streams.Count) return;
            var stream = _streams[_selectedStreamIndex];

            var input = new TextBox { PlaceholderText = "e.g. WRK, $100, 45m, EXP!" };
            var dialog = new ContentDialog
            {
                Title = "Add New Tag to Stream",
                PrimaryButtonText = "Add",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                Content = input,
                XamlRoot = this.XamlRoot
            };

            if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(input.Text))
            {
                TagdosParser.AddPill(stream, 0, input.Text);
                await (_tagdosService?.SaveStreamAsync(stream) ?? Task.CompletedTask);
                RenderStreamView(stream);
            }
        }

        private async void RenameStream_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedStreamIndex >= _streams.Count) return;
            var stream = _streams[_selectedStreamIndex];

            var input = new TextBox { Text = stream.DisplayTitle };
            var dialog = new ContentDialog
            {
                Title = "Rename Stream",
                PrimaryButtonText = "Save",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                Content = input,
                XamlRoot = this.XamlRoot
            };

            if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(input.Text))
            {
                stream.CustomTitle = input.Text.Trim();
                await (_tagdosService?.SaveStreamAsync(stream) ?? Task.CompletedTask);
                RenderStreamTabs();
                RenderStreamView(stream);
            }
        }

        private async void ChangeReminder_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedStreamIndex >= _streams.Count) return;
            var stream = _streams[_selectedStreamIndex];

            var timePicker = new TimePicker
            {
                Time = stream.StreamReminder.HasValue
                    ? new TimeSpan(stream.StreamReminder.Value.Hour, stream.StreamReminder.Value.Minute, 0)
                    : new TimeSpan(9, 0, 0)
            };

            var dialog = new ContentDialog
            {
                Title = "Set Stream Reminder Time",
                PrimaryButtonText = "Save",
                SecondaryButtonText = "Clear Reminder",
                CloseButtonText = "Cancel",
                Content = timePicker,
                XamlRoot = this.XamlRoot
            };

            var res = await dialog.ShowAsync();
            if (res == ContentDialogResult.Primary)
            {
                var now = DateTime.UtcNow;
                stream.StreamReminder = new DateTime(now.Year, now.Month, now.Day, timePicker.Time.Hours, timePicker.Time.Minutes, 0, DateTimeKind.Utc);
                await (_tagdosService?.SaveStreamAsync(stream) ?? Task.CompletedTask);
                RenderStreamView(stream);
            }
            else if (res == ContentDialogResult.Secondary)
            {
                stream.StreamReminder = null;
                await (_tagdosService?.SaveStreamAsync(stream) ?? Task.CompletedTask);
                RenderStreamView(stream);
            }
        }

        // ── Raw Shorthand Syntax Editor ──────────────────────────────────────

        private void ToggleRawEdit_Click(object sender, RoutedEventArgs e)
        {
            _isRawEditMode = !_isRawEditMode;
            if (_selectedStreamIndex < _streams.Count)
            {
                var stream = _streams[_selectedStreamIndex];
                if (_isRawEditMode)
                {
                    VisualCanvasBorder.Visibility = Visibility.Collapsed;
                    RawEditorBorder.Visibility = Visibility.Visible;
                    RawSyntaxTextBox.Text = stream.RawText;
                    ToggleRawEditText.Text = "Visual Mode";
                }
                else
                {
                    VisualCanvasBorder.Visibility = Visibility.Visible;
                    RawEditorBorder.Visibility = Visibility.Collapsed;
                    ToggleRawEditText.Text = "Syntax Mode";
                }
            }
        }

        private void CancelRawEdit_Click(object sender, RoutedEventArgs e)
        {
            _isRawEditMode = false;
            VisualCanvasBorder.Visibility = Visibility.Visible;
            RawEditorBorder.Visibility = Visibility.Collapsed;
            ToggleRawEditText.Text = "Syntax Mode";
        }

        private async void ApplyRawEdit_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedStreamIndex >= _streams.Count) return;
            var stream = _streams[_selectedStreamIndex];

            string newRaw = RawSyntaxTextBox.Text.Trim();
            await (_tagdosService?.UpdateStreamRawTextAsync(stream.Id, newRaw) ?? Task.CompletedTask);

            _isRawEditMode = false;
            VisualCanvasBorder.Visibility = Visibility.Visible;
            RawEditorBorder.Visibility = Visibility.Collapsed;
            ToggleRawEditText.Text = "Syntax Mode";

            await LoadDataAsync();
        }

        // ── Active Memos & Drag and Drop Attachments ─────────────────────────

        private void StreamMemosTextBox_LostFocus(object sender, RoutedEventArgs e)
        {
            if (_selectedStreamIndex >= _streams.Count) return;
            var stream = _streams[_selectedStreamIndex];

            if (stream.ActiveMemos != StreamMemosTextBox.Text)
            {
                stream.ActiveMemos = StreamMemosTextBox.Text;
                _ = _tagdosService?.UpdateStreamMemosAsync(stream.Id, stream.ActiveMemos, stream.AttachmentsJson);
            }
        }

        private void DropFileZone_DragOver(object sender, DragEventArgs e)
        {
            e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Attach file to stream";
            e.DragUIOverride.IsCaptionVisible = true;
        }

        private async void DropFileZone_Drop(object sender, DragEventArgs e)
        {
            if (_selectedStreamIndex >= _streams.Count) return;
            var stream = _streams[_selectedStreamIndex];

            if (e.DataView.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems))
            {
                var items = await e.DataView.GetStorageItemsAsync();
                List<string> attachments = new();
                try
                {
                    if (!string.IsNullOrWhiteSpace(stream.AttachmentsJson))
                    {
                        attachments = JsonSerializer.Deserialize<List<string>>(stream.AttachmentsJson) ?? new();
                    }
                }
                catch { }

                foreach (var item in items)
                {
                    if (!attachments.Contains(item.Path))
                    {
                        attachments.Add(item.Path);
                    }
                }

                stream.AttachmentsJson = JsonSerializer.Serialize(attachments);
                await (_tagdosService?.UpdateStreamMemosAsync(stream.Id, stream.ActiveMemos, stream.AttachmentsJson) ?? Task.CompletedTask);
                RenderAttachments(stream);
            }
        }

        private void RenderAttachments(TagDoStream stream)
        {
            AttachmentsListPanel.Children.Clear();
            List<string> attachments = new();
            try
            {
                if (!string.IsNullOrWhiteSpace(stream.AttachmentsJson))
                {
                    attachments = JsonSerializer.Deserialize<List<string>>(stream.AttachmentsJson) ?? new();
                }
            }
            catch { }

            foreach (var path in attachments)
            {
                string filename = System.IO.Path.GetFileName(path);
                var chip = new Border
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x22, 0x00, 0xE5, 0xFF)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(0x66, 0x00, 0xE5, 0xFF)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(10),
                    Padding = new Thickness(8, 4, 8, 4),
                    Margin = new Thickness(2, 0, 2, 0)
                };

                var chipStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
                chipStack.Children.Add(new FontIcon { Glyph = "\xE8B7", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 10, Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)) });
                chipStack.Children.Add(new TextBlock { Text = filename, FontSize = 11, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) });

                chip.Child = chipStack;
                chip.Tapped += async (s, ev) =>
                {
                    try
                    {
                        var file = await Windows.Storage.StorageFile.GetFileFromPathAsync(path);
                        await Windows.System.Launcher.LaunchFileAsync(file);
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"Failed to launch attachment: {ex.Message}");
                    }
                };

                AttachmentsListPanel.Children.Add(chip);
            }
        }

        // ── Quick Notes Tab ──────────────────────────────────────────────────

        private void NoteSearchBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            RenderQuickNotes(NoteSearchBox.Text);
        }

        private void RenderQuickNotes(string filter = "")
        {
            NotesGridPanel.Children.Clear();
            var filtered = string.IsNullOrWhiteSpace(filter)
                ? _notes
                : _notes.Where(n => n.Title.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                                    n.Content.Contains(filter, StringComparison.OrdinalIgnoreCase) ||
                                    n.Tags.Any(t => t.Contains(filter, StringComparison.OrdinalIgnoreCase))).ToList();

            foreach (var note in filtered)
            {
                var card = CreateNoteCard(note);
                NotesGridPanel.Children.Add(card);
            }
        }

        private FrameworkElement CreateNoteCard(TagDoQuickNote note)
        {
            var border = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0x18, 0xFF, 0xFF, 0xFF)),
                BorderBrush = note.IsPinned ? new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xB3, 0x00)) : new SolidColorBrush(Color.FromArgb(0x2A, 0xFF, 0xFF, 0xFF)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(14),
                Margin = new Thickness(6),
                Width = 280,
                MinHeight = 140
            };

            var grid = new Grid();
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

            // Header: Title + Pin button + Delete button
            var headerGrid = new Grid();
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var titleBlock = new TextBlock
            {
                Text = note.Title,
                FontSize = 13,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(titleBlock, 0);
            headerGrid.Children.Add(titleBlock);

            var pinBtn = new Button
            {
                Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4),
                Content = new FontIcon
                {
                    Glyph = "\xE718",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 12,
                    Foreground = note.IsPinned ? new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0xB3, 0x00)) : new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF))
                }
            };
            pinBtn.Click += async (s, e) =>
            {
                await (_tagdosService?.TogglePinQuickNoteAsync(note.Id) ?? Task.CompletedTask);
                _notes = await (_tagdosService?.GetQuickNotesAsync() ?? Task.FromResult(new List<TagDoQuickNote>()));
                RenderQuickNotes(NoteSearchBox.Text);
            };
            Grid.SetColumn(pinBtn, 1);
            headerGrid.Children.Add(pinBtn);

            var deleteBtn = new Button
            {
                Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4),
                Content = new FontIcon
                {
                    Glyph = "\xE74D",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 12,
                    Foreground = new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0x4D, 0x4D))
                }
            };
            deleteBtn.Click += async (s, e) =>
            {
                await (_tagdosService?.DeleteQuickNoteAsync(note.Id) ?? Task.CompletedTask);
                _notes = await (_tagdosService?.GetQuickNotesAsync() ?? Task.FromResult(new List<TagDoQuickNote>()));
                RenderQuickNotes(NoteSearchBox.Text);
            };
            Grid.SetColumn(deleteBtn, 2);
            headerGrid.Children.Add(deleteBtn);

            Grid.SetRow(headerGrid, 0);
            grid.Children.Add(headerGrid);

            // Content
            var contentBlock = new TextBlock
            {
                Text = note.Content,
                FontSize = 11.5,
                Foreground = new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF)),
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 6, 0, 8)
            };
            Grid.SetRow(contentBlock, 1);
            grid.Children.Add(contentBlock);

            // Footer: Timestamp
            var footerBlock = new TextBlock
            {
                Text = $"{note.UpdatedAt.ToLocalTime():MMM dd, HH:mm}",
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF))
            };
            Grid.SetRow(footerBlock, 2);
            grid.Children.Add(footerBlock);

            border.Child = grid;
            return border;
        }

        private async void TopBarAddNote_Click(object sender, RoutedEventArgs e)
        {
            var titleBox = new TextBox { PlaceholderText = "Note title...", Margin = new Thickness(0, 0, 0, 8) };
            var contentBox = new TextBox { PlaceholderText = "Write your thoughts, checklist, or tags...", TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, MinHeight = 100 };

            var stack = new StackPanel();
            stack.Children.Add(titleBox);
            stack.Children.Add(contentBox);

            var dialog = new ContentDialog
            {
                Title = "Create Quick Note",
                PrimaryButtonText = "Save",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                Content = stack,
                XamlRoot = this.XamlRoot
            };

            if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(titleBox.Text))
            {
                await (_tagdosService?.CreateQuickNoteAsync(titleBox.Text.Trim(), contentBox.Text.Trim(), isPinned: false) ?? Task.FromResult(new TagDoQuickNote()));
                _notes = await (_tagdosService?.GetQuickNotesAsync() ?? Task.FromResult(new List<TagDoQuickNote>()));
                SelectTab(_streams.Count); // Switch to notes tab
            }
        }

        // ── Navigation & Actions ─────────────────────────────────────────────

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(1);
            }
            else if (Frame.CanGoBack)
            {
                Frame.GoBack();
            }
            else
            {
                Frame.Navigate(typeof(MainPage));
            }
        }

        public async Task RefreshFromTitleBarAsync()
        {
            if (_tagdosService != null)
            {
                await _tagdosService.SyncWithRemoteAsync();
                await LoadDataAsync();
            }
        }

        private void PopOutButton_Click(object sender, RoutedEventArgs e)
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.OpenDetailWindow(typeof(TagdosNotesDetailPage));
                mw.NavigateToTab(1);
            }
        }
    }
}
