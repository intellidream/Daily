using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI;
using Microsoft.Extensions.DependencyInjection;
using Daily.Configuration;
using Daily.Models;
using Daily.Services;
using Daily.Services.Auth;
using Daily_WinUI.Services;

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
            this.Unloaded += Page_Unloaded;
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
                _tagdosService.DataChanged -= TagdosService_DataChanged;
                _tagdosService.DataChanged += TagdosService_DataChanged;
            }
            _ = LoadDataAsync();
            if (_tagdosService != null)
            {
                _ = _tagdosService.SyncWithRemoteAsync();
            }
        }

        private void Page_Unloaded(object sender, RoutedEventArgs e)
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
                var displayTitle = stream.DisplayTitle ?? string.Empty;
                var streamPrefix = $"Stream {i + 1}";
                var tabTitle = displayTitle.StartsWith(streamPrefix, StringComparison.OrdinalIgnoreCase)
                    ? displayTitle
                    : $"{streamPrefix}: {displayTitle}";
                contentStack.Children.Add(new TextBlock
                {
                    Text = tabTitle,
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

            // Add New Stream Button
            var addStreamBtn = new Button
            {
                Background = new SolidColorBrush(Color.FromArgb(0x22, 0x00, 0xE5, 0xFF)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(0x66, 0x00, 0xE5, 0xFF)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(10, 6, 10, 6),
                Content = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = 4,
                    Children =
                    {
                        new FontIcon { Glyph = "\xE710", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 11, Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)) },
                        new TextBlock { Text = "New", FontSize = 11, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)) }
                    }
                }
            };
            ToolTipService.SetToolTip(addStreamBtn, "Create new stream");
            addStreamBtn.Click += async (s, ev) =>
            {
                if (_tagdosService == null) return;
                await _tagdosService.CreateStreamAsync();
                _streams = await _tagdosService.GetStreamsAsync();
                SelectTab(Math.Max(0, _streams.Count - 1));
            };
            StreamTabsPanel.Children.Add(addStreamBtn);

            // Tab N: Quick Notes
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
            _selectedStreamIndex = Math.Clamp(index, 0, _streams.Count);
            RenderStreamTabs();

            if (_selectedStreamIndex < _streams.Count)
            {
                StreamViewPanel.Visibility = Visibility.Visible;
                QuickNotesViewPanel.Visibility = Visibility.Collapsed;
                RenderStreamView(_streams[_selectedStreamIndex]);
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

            if (stream.Clusters.Count == 0)
            {
                ClustersContainer.Children.Add(new Border
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x0D, 0xFF, 0xFF, 0xFF)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(12),
                    Padding = new Thickness(16),
                    Child = new TextBlock
                    {
                        Text = "No clusters yet. Click 'Add Tag' or 'Import Tasks' to populate this stream.",
                        FontSize = 12,
                        Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF))
                    }
                });
                return;
            }

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

            var editItem = new MenuFlyoutItem
            {
                Text = "Edit Tag...",
                Icon = new FontIcon { Glyph = "\xE70F" }
            };
            editItem.Click += async (s, e) =>
            {
                var input = new TextBox { Text = pill.Text };
                input.SelectAll();
                var dlg = new ContentDialog
                {
                    Title = "Edit Tag",
                    PrimaryButtonText = "Save",
                    CloseButtonText = "Cancel",
                    DefaultButton = ContentDialogButton.Primary,
                    Content = input,
                    XamlRoot = this.XamlRoot
                };
                if (await dlg.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(input.Text))
                {
                    if (TagdosParser.UpdatePillText(stream, pill.Id, input.Text))
                    {
                        await (_tagdosService?.SaveStreamAsync(stream) ?? Task.CompletedTask);
                        RenderStreamView(stream);
                    }
                }
            };
            flyout.Items.Add(editItem);

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
                SecondaryButtonText = _streams.Count > 1 ? "Delete Stream" : null,
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                Content = input,
                XamlRoot = this.XamlRoot
            };

            var res = await dialog.ShowAsync();
            if (res == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(input.Text))
            {
                stream.CustomTitle = input.Text.Trim();
                await (_tagdosService?.SaveStreamAsync(stream) ?? Task.CompletedTask);
                RenderStreamTabs();
                RenderStreamView(stream);
            }
            else if (res == ContentDialogResult.Secondary && _streams.Count > 1 && _tagdosService != null)
            {
                await _tagdosService.DeleteStreamAsync(stream.Id);
                _selectedStreamIndex = Math.Max(0, _selectedStreamIndex - 1);
                await LoadDataAsync();
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

        // ── External Tasks Import (Microsoft To Do & Google Tasks) ────────────

        private sealed class WinUiImportDraft
        {
            public string Id { get; set; } = string.Empty;
            public string OriginalTitle { get; set; } = string.Empty;
            public string? OriginalNotes { get; set; }
            public bool IsAlreadyDsl { get; set; }
            public string EditedTag { get; set; } = string.Empty;
            public bool IsSelected { get; set; } = true;
        }

        private sealed class WinUiTaskListOption
        {
            public string Id { get; set; } = string.Empty;
            public string Title { get; set; } = string.Empty;
            public bool IsDefault { get; set; }
            public override string ToString() => Title;
        }

        private sealed class WinUiAccountOption
        {
            public LocalCalendarAccount Account { get; set; } = null!;
            public override string ToString() => Account.Email;
        }

        private async void ImportTasks_Click(object sender, RoutedEventArgs e)
        {
            if (_tagdosService == null) return;

            var calendarService = App.Current.Services.GetService<ICalendarService>();
            var httpClient = App.Current.Services.GetService<HttpClient>() ?? new HttpClient();

            var providerCombo = new ComboBox
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                ItemsSource = new[] { "Microsoft To Do", "Google Tasks" },
                SelectedIndex = 0
            };

            var accountCombo = new ComboBox
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                PlaceholderText = "Select account..."
            };

            var signInBtn = new Button
            {
                Content = "Sign In / Add",
                Background = new SolidColorBrush(Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF)),
                Foreground = new SolidColorBrush(Microsoft.UI.Colors.Black),
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                CornerRadius = new CornerRadius(8)
            };

            var listCombo = new ComboBox
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                PlaceholderText = "Select task list..."
            };

            var refreshBtn = new Button
            {
                Content = new FontIcon { Glyph = "\xE72C", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 13 },
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(10, 8, 10, 8)
            };

            var statusBar = new TextBlock
            {
                Text = "Checking connected accounts...",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromArgb(0xCC, 0xFF, 0xFF, 0xFF)),
                TextWrapping = TextWrapping.Wrap
            };

            var tasksPanel = new StackPanel { Spacing = 8 };
            var tasksScroll = new ScrollViewer
            {
                Content = tasksPanel,
                MaxHeight = 250,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            };

            var selectAllBtn = new Button { Content = "Select All", FontSize = 11, Padding = new Thickness(10, 4, 10, 4) };
            var clearAllBtn = new Button { Content = "Clear", FontSize = 11, Padding = new Thickness(10, 4, 10, 4) };
            var tasksHeaderRow = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                Visibility = Visibility.Collapsed
            };
            var tasksCountText = new TextBlock
            {
                FontSize = 11.5,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = new SolidColorBrush(Color.FromArgb(0xAA, 0xFF, 0xFF, 0xFF))
            };
            tasksHeaderRow.Children.Add(tasksCountText);
            tasksHeaderRow.Children.Add(selectAllBtn);
            tasksHeaderRow.Children.Add(clearAllBtn);

            var destModeCombo = new ComboBox
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                ItemsSource = new[] { "Append to Stream", "Replace Stream", "Create New Stream" },
                SelectedIndex = 0
            };

            var streamItems = _streams.Select((s, idx) => $"S{idx + 1}: {s.DisplayTitle}").ToList();
            var targetStreamCombo = new ComboBox
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                ItemsSource = streamItems,
                SelectedIndex = _selectedStreamIndex < _streams.Count ? _selectedStreamIndex : 0
            };

            var newStreamTitleBox = new TextBox
            {
                PlaceholderText = "New stream title...",
                Visibility = Visibility.Collapsed
            };

            var replaceWarningText = new TextBlock
            {
                Text = "Warning: Existing pills and active memos in the selected stream will be replaced.",
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0xB3, 0x00)),
                Visibility = Visibility.Collapsed,
                TextWrapping = TextWrapping.Wrap
            };

            var drafts = new List<WinUiImportDraft>();
            bool isBusy = false;

            var dialog = new ContentDialog
            {
                Title = "Import Tasks to TagDoS",
                PrimaryButtonText = "Import Selected",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                IsPrimaryButtonEnabled = false,
                XamlRoot = this.XamlRoot
            };
            dialog.Resources["ContentDialogMaxWidth"] = 740.0;

            void UpdateImportButtonState()
            {
                int count = drafts.Count(d => d.IsSelected && !string.IsNullOrWhiteSpace(d.EditedTag));
                dialog.PrimaryButtonText = count > 0 ? $"Import ({count})" : "Import Selected";
                dialog.IsPrimaryButtonEnabled = count > 0 && !isBusy;
            }

            void RenderDraftRows()
            {
                tasksPanel.Children.Clear();
                if (drafts.Count == 0)
                {
                    tasksHeaderRow.Visibility = Visibility.Collapsed;
                    UpdateImportButtonState();
                    return;
                }

                tasksCountText.Text = $"{drafts.Count} active tasks";
                tasksHeaderRow.Visibility = Visibility.Visible;

                foreach (var draft in drafts)
                {
                    var rowBorder = new Border
                    {
                        Background = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
                        BorderBrush = new SolidColorBrush(Color.FromArgb(0x28, 0xFF, 0xFF, 0xFF)),
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(10),
                        Padding = new Thickness(10)
                    };

                    var rowStack = new StackPanel { Spacing = 4 };
                    var topGrid = new Grid { ColumnSpacing = 8 };
                    topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                    var chk = new CheckBox { IsChecked = draft.IsSelected, MinWidth = 0, Padding = new Thickness(0) };
                    chk.Checked += (_, __) => { draft.IsSelected = true; UpdateImportButtonState(); };
                    chk.Unchecked += (_, __) => { draft.IsSelected = false; UpdateImportButtonState(); };
                    Grid.SetColumn(chk, 0);
                    topGrid.Children.Add(chk);

                    var tagBox = new TextBox
                    {
                        Text = draft.EditedTag,
                        FontFamily = new FontFamily("Consolas, Cascadia Code, Courier New"),
                        FontSize = 12.5,
                        FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
                    };
                    tagBox.TextChanged += (_, __) => { draft.EditedTag = tagBox.Text; UpdateImportButtonState(); };
                    Grid.SetColumn(tagBox, 1);
                    topGrid.Children.Add(tagBox);

                    var badge = new Border
                    {
                        Background = new SolidColorBrush(draft.IsAlreadyDsl ? Color.FromArgb(0x28, 0x00, 0xE5, 0xFF) : Color.FromArgb(0x28, 0xFF, 0xB3, 0x00)),
                        CornerRadius = new CornerRadius(8),
                        Padding = new Thickness(7, 3, 7, 3),
                        VerticalAlignment = VerticalAlignment.Center,
                        Child = new TextBlock
                        {
                            Text = draft.IsAlreadyDsl ? "DSL" : "AUTO + MEMO",
                            FontSize = 10,
                            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                            Foreground = new SolidColorBrush(draft.IsAlreadyDsl ? Color.FromArgb(0xFF, 0x00, 0xE5, 0xFF) : Color.FromArgb(0xFF, 0xFF, 0xB3, 0x00))
                        }
                    };
                    Grid.SetColumn(badge, 2);
                    topGrid.Children.Add(badge);

                    rowStack.Children.Add(topGrid);

                    if (!draft.IsAlreadyDsl)
                    {
                        rowStack.Children.Add(new TextBlock
                        {
                            Text = draft.OriginalTitle,
                            FontSize = 11.5,
                            Foreground = new SolidColorBrush(Color.FromArgb(0xAA, 0xFF, 0xFF, 0xFF)),
                            TextWrapping = TextWrapping.Wrap,
                            Margin = new Thickness(28, 0, 0, 0)
                        });
                    }
                    if (!string.IsNullOrWhiteSpace(draft.OriginalNotes))
                    {
                        rowStack.Children.Add(new TextBlock
                        {
                            Text = draft.OriginalNotes,
                            FontSize = 10.5,
                            Foreground = new SolidColorBrush(Color.FromArgb(0x77, 0xFF, 0xFF, 0xFF)),
                            TextWrapping = TextWrapping.Wrap,
                            MaxLines = 2,
                            Margin = new Thickness(28, 0, 0, 0)
                        });
                    }

                    rowBorder.Child = rowStack;
                    tasksPanel.Children.Add(rowBorder);
                }

                UpdateImportButtonState();
            }

            selectAllBtn.Click += (_, __) =>
            {
                foreach (var d in drafts) d.IsSelected = true;
                RenderDraftRows();
            };
            clearAllBtn.Click += (_, __) =>
            {
                foreach (var d in drafts) d.IsSelected = false;
                RenderDraftRows();
            };

            async Task<string> EnsureValidAccessTokenAsync(LocalCalendarAccount acc)
            {
                string access = DecryptTokenSafely(acc.AccessToken, acc.UserId);
                string refresh = DecryptTokenSafely(acc.RefreshToken, acc.UserId);

                if (DateTime.UtcNow.AddMinutes(2) < acc.TokenExpiresAt.ToUniversalTime() && !string.IsNullOrEmpty(access))
                {
                    return access;
                }
                if (string.IsNullOrEmpty(refresh))
                {
                    return access;
                }

                if (acc.AccountType.Equals("Google", StringComparison.OrdinalIgnoreCase))
                {
                    var content = new FormUrlEncodedContent(new[]
                    {
                        new KeyValuePair<string, string>("client_id", Secrets.WindowsClientId),
                        new KeyValuePair<string, string>("client_secret", Secrets.WindowsClientSecret),
                        new KeyValuePair<string, string>("grant_type", "refresh_token"),
                        new KeyValuePair<string, string>("refresh_token", refresh)
                    });
                    var resp = await httpClient.PostAsync("https://oauth2.googleapis.com/token", content);
                    if (resp.IsSuccessStatusCode)
                    {
                        var json = await resp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        access = doc.RootElement.GetProperty("access_token").GetString() ?? access;
                        var exp = doc.RootElement.GetProperty("expires_in").GetInt32();
                        acc.AccessToken = EncryptionHelper.Encrypt(access, acc.UserId);
                        acc.TokenExpiresAt = DateTime.UtcNow.AddSeconds(exp);
                    }
                }
                else
                {
                    var content = new FormUrlEncodedContent(new[]
                    {
                        new KeyValuePair<string, string>("client_id", Secrets.MicrosoftClientId),
                        new KeyValuePair<string, string>("grant_type", "refresh_token"),
                        new KeyValuePair<string, string>("refresh_token", refresh),
                        new KeyValuePair<string, string>("redirect_uri", "com.intellidream.daily.desktop://login-callback")
                    });
                    var resp = await httpClient.PostAsync("https://login.microsoftonline.com/common/oauth2/v2.0/token", content);
                    if (resp.IsSuccessStatusCode)
                    {
                        var json = await resp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        access = doc.RootElement.GetProperty("access_token").GetString() ?? access;
                        var exp = doc.RootElement.GetProperty("expires_in").GetInt32();
                        acc.AccessToken = EncryptionHelper.Encrypt(access, acc.UserId);
                        acc.TokenExpiresAt = DateTime.UtcNow.AddSeconds(exp);
                    }
                }
                return access;
            }

            async Task LoadTasksForListAsync(LocalCalendarAccount acc, WinUiTaskListOption listOpt)
            {
                isBusy = true;
                UpdateImportButtonState();
                drafts.Clear();
                RenderDraftRows();
                statusBar.Text = $"Loading tasks from '{listOpt.Title}'...";

                try
                {
                    var token = await EnsureValidAccessTokenAsync(acc);
                    if (acc.AccountType.Equals("Google", StringComparison.OrdinalIgnoreCase))
                    {
                        var url = $"https://tasks.googleapis.com/tasks/v1/lists/{Uri.EscapeDataString(listOpt.Id)}/tasks?showCompleted=false&showHidden=false&maxResults=100";
                        var req = new HttpRequestMessage(HttpMethod.Get, url);
                        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                        var resp = await httpClient.SendAsync(req);
                        if (resp.StatusCode == HttpStatusCode.Forbidden)
                        {
                            statusBar.Text = "Google Tasks read permission is required. Click 'Sign In / Add' to grant Tasks access.";
                            return;
                        }
                        if (!resp.IsSuccessStatusCode)
                        {
                            statusBar.Text = $"Failed to load Google tasks (HTTP {(int)resp.StatusCode}).";
                            return;
                        }

                        var json = await resp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        if (doc.RootElement.TryGetProperty("items", out var items))
                        {
                            foreach (var item in items.EnumerateArray())
                            {
                                var status = item.TryGetProperty("status", out var st) ? st.GetString() ?? "needsAction" : "needsAction";
                                if (status.Equals("completed", StringComparison.OrdinalIgnoreCase)) continue;
                                var title = item.TryGetProperty("title", out var t) ? t.GetString()?.Trim() ?? "" : "";
                                if (string.IsNullOrEmpty(title)) continue;
                                var notes = item.TryGetProperty("notes", out var n) ? n.GetString()?.Trim() : null;
                                var prep = TagdosParser.PrepareImportItem(title, notes, false);
                                drafts.Add(new WinUiImportDraft
                                {
                                    Id = item.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString(),
                                    OriginalTitle = title,
                                    OriginalNotes = string.IsNullOrWhiteSpace(notes) ? null : notes,
                                    IsAlreadyDsl = prep.IsAlreadyDsl,
                                    EditedTag = prep.TagOrDsl
                                });
                            }
                        }
                    }
                    else
                    {
                        var url = $"https://graph.microsoft.com/v1.0/me/todo/lists/{Uri.EscapeDataString(listOpt.Id)}/tasks?$top=100";
                        var req = new HttpRequestMessage(HttpMethod.Get, url);
                        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                        var resp = await httpClient.SendAsync(req);
                        if (resp.StatusCode == HttpStatusCode.Forbidden || resp.StatusCode == HttpStatusCode.Unauthorized)
                        {
                            statusBar.Text = "Microsoft To Do access expired or missing Tasks.Read permission. Click 'Sign In / Add' to reconnect.";
                            return;
                        }
                        if (!resp.IsSuccessStatusCode)
                        {
                            statusBar.Text = $"Failed to load Microsoft To Do tasks (HTTP {(int)resp.StatusCode}).";
                            return;
                        }

                        var json = await resp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        if (doc.RootElement.TryGetProperty("value", out var values))
                        {
                            foreach (var item in values.EnumerateArray())
                            {
                                var status = item.TryGetProperty("status", out var st) ? st.GetString() ?? "notStarted" : "notStarted";
                                if (status.Equals("completed", StringComparison.OrdinalIgnoreCase)) continue;
                                var title = item.TryGetProperty("title", out var t) ? t.GetString()?.Trim() ?? "" : "";
                                if (string.IsNullOrEmpty(title)) continue;

                                string notes = string.Empty;
                                if (item.TryGetProperty("body", out var bodyObj))
                                {
                                    var rawBody = bodyObj.TryGetProperty("content", out var c) ? c.GetString() ?? "" : "";
                                    var cType = bodyObj.TryGetProperty("contentType", out var ct) ? ct.GetString() ?? "" : "";
                                    notes = cType.Equals("html", StringComparison.OrdinalIgnoreCase)
                                        ? Regex.Replace(rawBody, "<[^>]+>", " ").Trim()
                                        : rawBody.Trim();
                                }
                                bool isHigh = item.TryGetProperty("importance", out var imp) &&
                                              string.Equals(imp.GetString(), "high", StringComparison.OrdinalIgnoreCase);

                                var prep = TagdosParser.PrepareImportItem(title, notes, isHigh);
                                drafts.Add(new WinUiImportDraft
                                {
                                    Id = item.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString(),
                                    OriginalTitle = title,
                                    OriginalNotes = string.IsNullOrWhiteSpace(notes) ? null : notes,
                                    IsAlreadyDsl = prep.IsAlreadyDsl,
                                    EditedTag = prep.TagOrDsl
                                });
                            }
                        }
                    }

                    statusBar.Text = drafts.Count == 0
                        ? $"No active tasks found in '{listOpt.Title}'."
                        : $"Ready to import from '{listOpt.Title}'.";
                    RenderDraftRows();
                }
                catch (Exception ex)
                {
                    statusBar.Text = $"Error loading tasks: {ex.Message}";
                }
                finally
                {
                    isBusy = false;
                    UpdateImportButtonState();
                }
            }

            async Task LoadListsForAccountAsync(LocalCalendarAccount acc)
            {
                isBusy = true;
                UpdateImportButtonState();
                listCombo.ItemsSource = null;
                drafts.Clear();
                RenderDraftRows();
                statusBar.Text = $"Loading lists for {acc.Email}...";

                try
                {
                    var token = await EnsureValidAccessTokenAsync(acc);
                    var lists = new List<WinUiTaskListOption>();

                    if (acc.AccountType.Equals("Google", StringComparison.OrdinalIgnoreCase))
                    {
                        var req = new HttpRequestMessage(HttpMethod.Get, "https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100");
                        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                        var resp = await httpClient.SendAsync(req);
                        if (resp.StatusCode == HttpStatusCode.Forbidden || resp.StatusCode == HttpStatusCode.Unauthorized)
                        {
                            statusBar.Text = "Google Tasks permission missing or expired. Click 'Sign In / Add' to grant Tasks access.";
                            return;
                        }
                        if (!resp.IsSuccessStatusCode)
                        {
                            statusBar.Text = $"Failed to fetch Google task lists (HTTP {(int)resp.StatusCode}).";
                            return;
                        }
                        var json = await resp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        if (doc.RootElement.TryGetProperty("items", out var items))
                        {
                            int idx = 0;
                            foreach (var item in items.EnumerateArray())
                            {
                                var id = item.GetProperty("id").GetString() ?? "";
                                var title = item.GetProperty("title").GetString() ?? "Tasks";
                                lists.Add(new WinUiTaskListOption { Id = id, Title = title, IsDefault = idx == 0 });
                                idx++;
                            }
                        }
                    }
                    else
                    {
                        var req = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me/todo/lists");
                        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                        var resp = await httpClient.SendAsync(req);
                        if (resp.StatusCode == HttpStatusCode.Forbidden || resp.StatusCode == HttpStatusCode.Unauthorized)
                        {
                            statusBar.Text = "Microsoft To Do permission missing or expired. Click 'Sign In / Add' to authenticate.";
                            return;
                        }
                        if (!resp.IsSuccessStatusCode)
                        {
                            statusBar.Text = $"Failed to fetch Microsoft To Do lists (HTTP {(int)resp.StatusCode}).";
                            return;
                        }
                        var json = await resp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        if (doc.RootElement.TryGetProperty("value", out var values))
                        {
                            foreach (var item in values.EnumerateArray())
                            {
                                var id = item.GetProperty("id").GetString() ?? "";
                                var title = item.GetProperty("displayName").GetString() ?? "Tasks";
                                var wk = item.TryGetProperty("wellknownListName", out var wkEl) ? wkEl.GetString() ?? "" : "";
                                lists.Add(new WinUiTaskListOption
                                {
                                    Id = id,
                                    Title = title,
                                    IsDefault = wk.Equals("defaultList", StringComparison.OrdinalIgnoreCase)
                                });
                            }
                        }
                    }

                    listCombo.ItemsSource = lists;
                    var def = lists.FirstOrDefault(l => l.IsDefault) ?? lists.FirstOrDefault();
                    if (def != null)
                    {
                        listCombo.SelectedItem = def;
                        if (string.IsNullOrWhiteSpace(newStreamTitleBox.Text))
                        {
                            newStreamTitleBox.Text = def.Title;
                        }
                        await LoadTasksForListAsync(acc, def);
                    }
                    else
                    {
                        statusBar.Text = "No task lists found on this account.";
                    }
                }
                catch (Exception ex)
                {
                    statusBar.Text = $"Error loading lists: {ex.Message}";
                }
                finally
                {
                    isBusy = false;
                    UpdateImportButtonState();
                }
            }

            async Task RefreshAccountsForSelectedProviderAsync()
            {
                bool isGoogle = providerCombo.SelectedIndex == 1;
                var all = calendarService != null ? await calendarService.GetAccountsAsync() : new List<LocalCalendarAccount>();
                var filtered = all
                    .Where(a => isGoogle
                        ? a.AccountType.Equals("Google", StringComparison.OrdinalIgnoreCase)
                        : (a.AccountType.Equals("MicrosoftPersonal", StringComparison.OrdinalIgnoreCase) ||
                           a.AccountType.Equals("MicrosoftWork", StringComparison.OrdinalIgnoreCase)))
                    .Select(a => new WinUiAccountOption { Account = a })
                    .ToList();

                accountCombo.ItemsSource = filtered;
                listCombo.ItemsSource = null;
                drafts.Clear();
                RenderDraftRows();

                if (filtered.Count > 0)
                {
                    accountCombo.SelectedIndex = 0;
                    await LoadListsForAccountAsync(filtered[0].Account);
                }
                else
                {
                    statusBar.Text = $"No {(isGoogle ? "Google Tasks" : "Microsoft To Do")} account connected yet. Click 'Sign In / Add'.";
                }
            }

            providerCombo.SelectionChanged += async (_, __) => await RefreshAccountsForSelectedProviderAsync();
            accountCombo.SelectionChanged += async (_, __) =>
            {
                if (!isBusy && accountCombo.SelectedItem is WinUiAccountOption opt)
                {
                    await LoadListsForAccountAsync(opt.Account);
                }
            };
            listCombo.SelectionChanged += async (_, __) =>
            {
                if (!isBusy && accountCombo.SelectedItem is WinUiAccountOption opt && listCombo.SelectedItem is WinUiTaskListOption listOpt)
                {
                    if (string.IsNullOrWhiteSpace(newStreamTitleBox.Text) ||
                        (listCombo.ItemsSource is List<WinUiTaskListOption> ls && ls.Any(x => x.Title == newStreamTitleBox.Text)))
                    {
                        newStreamTitleBox.Text = listOpt.Title;
                    }
                    await LoadTasksForListAsync(opt.Account, listOpt);
                }
            };
            refreshBtn.Click += async (_, __) =>
            {
                if (accountCombo.SelectedItem is WinUiAccountOption opt)
                {
                    await LoadListsForAccountAsync(opt.Account);
                }
                else
                {
                    await RefreshAccountsForSelectedProviderAsync();
                }
            };

            signInBtn.Click += async (_, __) =>
            {
                bool isGoogle = providerCombo.SelectedIndex == 1;
                isBusy = true;
                signInBtn.IsEnabled = false;
                statusBar.Text = "Opening browser for authentication...";
                try
                {
                    LocalCalendarAccount? connectedAcc = isGoogle
                        ? await SignInGoogleForTasksAsync(httpClient)
                        : await SignInMicrosoftForTasksAsync(httpClient);

                    if (connectedAcc != null && calendarService != null)
                    {
                        await calendarService.AddAccountAsync(connectedAcc);
                        await RefreshAccountsForSelectedProviderAsync();
                    }
                    else if (connectedAcc != null)
                    {
                        var opt = new WinUiAccountOption { Account = connectedAcc };
                        accountCombo.ItemsSource = new List<WinUiAccountOption> { opt };
                        accountCombo.SelectedItem = opt;
                        await LoadListsForAccountAsync(connectedAcc);
                    }
                }
                catch (Exception ex)
                {
                    statusBar.Text = $"Authentication failed: {ex.Message}";
                }
                finally
                {
                    isBusy = false;
                    signInBtn.IsEnabled = true;
                    UpdateImportButtonState();
                }
            };

            destModeCombo.SelectionChanged += (_, __) =>
            {
                int idx = destModeCombo.SelectedIndex;
                targetStreamCombo.Visibility = idx == 2 ? Visibility.Collapsed : Visibility.Visible;
                newStreamTitleBox.Visibility = idx == 2 ? Visibility.Visible : Visibility.Collapsed;
                replaceWarningText.Visibility = idx == 1 ? Visibility.Visible : Visibility.Collapsed;
                if (idx == 2 && string.IsNullOrWhiteSpace(newStreamTitleBox.Text) && listCombo.SelectedItem is WinUiTaskListOption l)
                {
                    newStreamTitleBox.Text = l.Title;
                }
            };

            var contentStack = new StackPanel { Spacing = 10, Width = 580 };

            var providerAndAccountGrid = new Grid { ColumnSpacing = 8 };
            providerAndAccountGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
            providerAndAccountGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            providerAndAccountGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(providerCombo, 0);
            Grid.SetColumn(accountCombo, 1);
            Grid.SetColumn(signInBtn, 2);
            providerAndAccountGrid.Children.Add(providerCombo);
            providerAndAccountGrid.Children.Add(accountCombo);
            providerAndAccountGrid.Children.Add(signInBtn);
            contentStack.Children.Add(providerAndAccountGrid);

            var listGrid = new Grid { ColumnSpacing = 8 };
            listGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            listGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(listCombo, 0);
            Grid.SetColumn(refreshBtn, 1);
            listGrid.Children.Add(listCombo);
            listGrid.Children.Add(refreshBtn);
            contentStack.Children.Add(listGrid);

            contentStack.Children.Add(statusBar);
            contentStack.Children.Add(tasksHeaderRow);
            contentStack.Children.Add(tasksScroll);

            var destGrid = new Grid { ColumnSpacing = 8, Margin = new Thickness(0, 6, 0, 0) };
            destGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
            destGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(destModeCombo, 0);
            Grid.SetColumn(targetStreamCombo, 1);
            Grid.SetColumn(newStreamTitleBox, 1);
            destGrid.Children.Add(destModeCombo);
            destGrid.Children.Add(targetStreamCombo);
            destGrid.Children.Add(newStreamTitleBox);
            contentStack.Children.Add(destGrid);
            contentStack.Children.Add(replaceWarningText);

            dialog.Content = contentStack;
            _ = RefreshAccountsForSelectedProviderAsync();

            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary)
            {
                var chosen = drafts.Where(d => d.IsSelected && !string.IsNullOrWhiteSpace(d.EditedTag)).ToList();
                if (chosen.Count == 0) return;

                var dslChunks = new List<string>();
                var memoLines = new List<string>();
                foreach (var item in chosen)
                {
                    var tag = item.EditedTag.Trim();
                    dslChunks.Add(tag);
                    var notes = item.OriginalNotes?.Trim() ?? "";
                    if (item.IsAlreadyDsl)
                    {
                        if (!string.IsNullOrEmpty(notes)) memoLines.Add($"• [{tag}] {notes}");
                    }
                    else
                    {
                        memoLines.Add(string.IsNullOrEmpty(notes) ? $"• [{tag}] {item.OriginalTitle}" : $"• [{tag}] {item.OriginalTitle} — {notes}");
                    }
                }

                string mode = destModeCombo.SelectedIndex switch
                {
                    1 => "replace",
                    2 => "new",
                    _ => "append"
                };

                int targetIdx = targetStreamCombo.SelectedIndex;
                string? targetId = (targetIdx >= 0 && targetIdx < _streams.Count) ? _streams[targetIdx].Id : _streams.FirstOrDefault()?.Id;
                var resultStream = await _tagdosService.ImportExternalTasksAsync(mode, targetId, newStreamTitleBox.Text, dslChunks, memoLines);
                _streams = await _tagdosService.GetStreamsAsync();
                int newIndex = _streams.FindIndex(s => s.Id == resultStream.Id);
                SelectTab(newIndex >= 0 ? newIndex : Math.Max(0, _streams.Count - 1));
            }
        }

        private static string DecryptTokenSafely(string cipherText, string userId)
        {
            if (string.IsNullOrEmpty(cipherText) || string.IsNullOrEmpty(userId)) return cipherText;
            string current = cipherText;
            for (int i = 0; i < 2; i++)
            {
                string next = EncryptionHelper.Decrypt(current, userId);
                if (next == current) break;
                current = next;
            }
            return current;
        }

        private async Task<LocalCalendarAccount?> SignInGoogleForTasksAsync(HttpClient httpClient)
        {
            var listenerTcp = new TcpListener(IPAddress.Loopback, 0);
            listenerTcp.Start();
            var port = ((IPEndPoint)listenerTcp.LocalEndpoint).Port;
            listenerTcp.Stop();

            var redirectUri = $"http://localhost:{port}/";
            var state = Guid.NewGuid().ToString();

            using var listener = new HttpListener();
            listener.Prefixes.Add(redirectUri);
            listener.Start();

            var authUrl = $"https://accounts.google.com/o/oauth2/v2/auth?client_id={Secrets.WindowsClientId}&redirect_uri={Uri.EscapeDataString(redirectUri)}&response_type=code&scope={Uri.EscapeDataString("https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/tasks.readonly")}&access_type=offline&prompt=select_account%20consent&state={state}";
            await Launcher.LaunchUriAsync(new Uri(authUrl));

            var contextTask = listener.GetContextAsync();
            if (await Task.WhenAny(contextTask, Task.Delay(TimeSpan.FromMinutes(2))) != contextTask)
            {
                throw new TimeoutException("Google sign-in timed out.");
            }

            var context = await contextTask;
            var code = context.Request.QueryString["code"];
            var buffer = Encoding.UTF8.GetBytes("<html><body style='font-family: sans-serif; text-align: center; padding-top: 50px;'><h1>Authentication Successful!</h1><p>You can close this window and return to DayOne.</p></body></html>");
            context.Response.ContentLength64 = buffer.Length;
            context.Response.OutputStream.Write(buffer, 0, buffer.Length);
            context.Response.OutputStream.Close();

            if (string.IsNullOrEmpty(code)) return null;

            var content = new FormUrlEncodedContent(new[]
            {
                new KeyValuePair<string, string>("client_id", Secrets.WindowsClientId),
                new KeyValuePair<string, string>("client_secret", Secrets.WindowsClientSecret),
                new KeyValuePair<string, string>("code", code),
                new KeyValuePair<string, string>("redirect_uri", redirectUri),
                new KeyValuePair<string, string>("grant_type", "authorization_code")
            });

            var tokenResp = await httpClient.PostAsync("https://oauth2.googleapis.com/token", content);
            if (!tokenResp.IsSuccessStatusCode)
            {
                throw new Exception(await tokenResp.Content.ReadAsStringAsync());
            }

            var json = await tokenResp.Content.ReadAsStringAsync();
            using var doc = JsonDocument.Parse(json);
            var accessToken = doc.RootElement.GetProperty("access_token").GetString() ?? "";
            var refreshToken = doc.RootElement.TryGetProperty("refresh_token", out var rt) ? rt.GetString() ?? "" : "";
            var expiresIn = doc.RootElement.GetProperty("expires_in").GetInt32();

            var email = "Google Calendar";
            var calReq = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/calendar/v3/calendars/primary");
            calReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            var calResp = await httpClient.SendAsync(calReq);
            if (calResp.IsSuccessStatusCode)
            {
                using var calDoc = JsonDocument.Parse(await calResp.Content.ReadAsStringAsync());
                email = calDoc.RootElement.GetProperty("id").GetString() ?? email;
            }

            var userId = App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
            var accountId = Daily_WinUI.Helpers.UuidHelper.GenerateDeterministicGuid($"{userId}_Google_{email}").ToString().ToLowerInvariant();
            return new LocalCalendarAccount
            {
                Id = accountId,
                UserId = userId,
                Email = email,
                AccountType = "Google",
                AccessToken = EncryptionHelper.Encrypt(accessToken, userId),
                RefreshToken = EncryptionHelper.Encrypt(refreshToken, userId),
                TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn),
                Color = "#0078D4",
                IsActive = true,
                UpdatedAt = DateTime.UtcNow
            };
        }

        private async Task<LocalCalendarAccount?> SignInMicrosoftForTasksAsync(HttpClient httpClient)
        {
            var verifierBytes = new byte[32];
            System.Security.Cryptography.RandomNumberGenerator.Fill(verifierBytes);
            static string B64Url(byte[] b) => Convert.ToBase64String(b).Replace("+", "-").Replace("/", "_").TrimEnd('=');
            var codeVerifier = B64Url(verifierBytes);
            using var sha = System.Security.Cryptography.SHA256.Create();
            var codeChallenge = B64Url(sha.ComputeHash(Encoding.UTF8.GetBytes(codeVerifier)));

            var authUrl = $"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id={Secrets.MicrosoftClientId}&response_type=code&redirect_uri={Uri.EscapeDataString("com.intellidream.daily.desktop://login-callback")}&response_mode=query&scope={Uri.EscapeDataString("offline_access https://graph.microsoft.com/User.Read https://graph.microsoft.com/Calendars.Read https://graph.microsoft.com/Tasks.Read")}&prompt=select_account&code_challenge={codeChallenge}&code_challenge_method=S256";

            WinUIAuthService.OAuthCallbackTcs = new TaskCompletionSource<string>();
            try
            {
                await Launcher.LaunchUriAsync(new Uri(authUrl));
                if (await Task.WhenAny(WinUIAuthService.OAuthCallbackTcs.Task, Task.Delay(TimeSpan.FromMinutes(2))) != WinUIAuthService.OAuthCallbackTcs.Task)
                {
                    throw new TimeoutException("Microsoft sign-in timed out.");
                }

                var code = await WinUIAuthService.OAuthCallbackTcs.Task;
                var content = new FormUrlEncodedContent(new[]
                {
                    new KeyValuePair<string, string>("client_id", Secrets.MicrosoftClientId),
                    new KeyValuePair<string, string>("code", code),
                    new KeyValuePair<string, string>("redirect_uri", "com.intellidream.daily.desktop://login-callback"),
                    new KeyValuePair<string, string>("grant_type", "authorization_code"),
                    new KeyValuePair<string, string>("code_verifier", codeVerifier)
                });

                var resp = await httpClient.PostAsync("https://login.microsoftonline.com/common/oauth2/v2.0/token", content);
                if (!resp.IsSuccessStatusCode)
                {
                    throw new Exception(await resp.Content.ReadAsStringAsync());
                }

                var json = await resp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(json);
                var accessToken = doc.RootElement.GetProperty("access_token").GetString() ?? "";
                var refreshToken = doc.RootElement.TryGetProperty("refresh_token", out var rt) ? rt.GetString() ?? "" : "";
                var expiresIn = doc.RootElement.GetProperty("expires_in").GetInt32();

                var email = "Outlook Calendar";
                var accountType = "MicrosoftPersonal";
                var meReq = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me");
                meReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                var meResp = await httpClient.SendAsync(meReq);
                if (meResp.IsSuccessStatusCode)
                {
                    using var meDoc = JsonDocument.Parse(await meResp.Content.ReadAsStringAsync());
                    if (meDoc.RootElement.TryGetProperty("mail", out var m)) email = m.GetString() ?? email;
                    if (email == "Outlook Calendar" && meDoc.RootElement.TryGetProperty("userPrincipalName", out var upn))
                        email = upn.GetString() ?? email;
                }
                if (email != "Outlook Calendar" && !email.EndsWith("@outlook.com") && !email.EndsWith("@hotmail.com") && !email.EndsWith("@live.com"))
                {
                    accountType = "MicrosoftWork";
                }

                var userId = App.SupabaseClient.Auth.CurrentSession?.User?.Id ?? "local_user";
                var accountId = Daily_WinUI.Helpers.UuidHelper.GenerateDeterministicGuid($"{userId}_{accountType}_{email}").ToString().ToLowerInvariant();
                return new LocalCalendarAccount
                {
                    Id = accountId,
                    UserId = userId,
                    Email = email,
                    AccountType = accountType,
                    AccessToken = EncryptionHelper.Encrypt(accessToken, userId),
                    RefreshToken = EncryptionHelper.Encrypt(refreshToken, userId),
                    TokenExpiresAt = DateTime.UtcNow.AddSeconds(expiresIn),
                    Color = "#107C41",
                    IsActive = true,
                    UpdatedAt = DateTime.UtcNow
                };
            }
            finally
            {
                WinUIAuthService.OAuthCallbackTcs = null;
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
