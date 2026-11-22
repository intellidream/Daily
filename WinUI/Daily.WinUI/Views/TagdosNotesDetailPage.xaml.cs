using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
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
                var prevStreamId = (_selectedStreamIndex >= 0 && _selectedStreamIndex < _streams.Count)
                    ? _streams[_selectedStreamIndex].Id
                    : null;
                bool wasNotesTab = _streams.Count > 0 && _selectedStreamIndex >= _streams.Count;

                _streams = await _tagdosService.GetStreamsAsync();
                _notes = await _tagdosService.GetQuickNotesAsync();

                int nextIndex;
                if (wasNotesTab)
                {
                    nextIndex = _streams.Count;
                }
                else if (!string.IsNullOrEmpty(prevStreamId))
                {
                    int matchIdx = _streams.FindIndex(s => s.Id == prevStreamId);
                    nextIndex = matchIdx >= 0 ? matchIdx : Math.Clamp(_selectedStreamIndex, 0, Math.Max(0, _streams.Count - 1));
                }
                else
                {
                    nextIndex = Math.Clamp(_selectedStreamIndex, 0, _streams.Count);
                }
                _selectedStreamIndex = nextIndex;

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

                var menu = new MenuFlyout();
                if (tabIndex > 0)
                {
                    var moveLeftItem = new MenuFlyoutItem
                    {
                        Text = "Move Left",
                        Icon = new FontIcon { Glyph = "\xE72B", FontFamily = new FontFamily("Segoe Fluent Icons") }
                    };
                    moveLeftItem.Click += async (_, __) => await MoveStreamPreservingSelectionAsync(tabIndex, tabIndex - 1);
                    menu.Items.Add(moveLeftItem);
                }
                if (tabIndex < _streams.Count - 1)
                {
                    var moveRightItem = new MenuFlyoutItem
                    {
                        Text = "Move Right",
                        Icon = new FontIcon { Glyph = "\xE72A", FontFamily = new FontFamily("Segoe Fluent Icons") }
                    };
                    moveRightItem.Click += async (_, __) => await MoveStreamPreservingSelectionAsync(tabIndex, tabIndex + 1);
                    menu.Items.Add(moveRightItem);
                }
                if (menu.Items.Count > 0)
                {
                    menu.Items.Add(new MenuFlyoutSeparator());
                }
                var renameItem = new MenuFlyoutItem
                {
                    Text = "Rename Stream...",
                    Icon = new FontIcon { Glyph = "\xE70F", FontFamily = new FontFamily("Segoe Fluent Icons") }
                };
                renameItem.Click += async (_, __) =>
                {
                    SelectTab(tabIndex);
                    await RenameStreamForIndexAsync(tabIndex);
                };
                menu.Items.Add(renameItem);
                if (_streams.Count > 1)
                {
                    var reorderItem = new MenuFlyoutItem
                    {
                        Text = "Reorder Streams...",
                        Icon = new FontIcon { Glyph = "\xE8CB", FontFamily = new FontFamily("Segoe Fluent Icons") }
                    };
                    reorderItem.Click += async (_, __) => await ShowReorderStreamsDialogAsync();
                    menu.Items.Add(reorderItem);
                }
                btn.ContextFlyout = menu;

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

            if (_streams.Count > 1)
            {
                var reorderBtn = new Button
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x22, 0xAF, 0x52, 0xDE)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(0x66, 0xAF, 0x52, 0xDE)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(14),
                    Padding = new Thickness(10, 6, 10, 6),
                    Content = new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        Spacing = 4,
                        Children =
                        {
                            new FontIcon { Glyph = "\xE8CB", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 11, Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xD2, 0xA8, 0xFF)) },
                            new TextBlock { Text = "Reorder", FontSize = 11, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xD2, 0xA8, 0xFF)) }
                        }
                    }
                };
                ToolTipService.SetToolTip(reorderBtn, "Reorder streams");
                reorderBtn.Click += async (_, __) => await ShowReorderStreamsDialogAsync();
                StreamTabsPanel.Children.Add(reorderBtn);
            }

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
            await RenameStreamForIndexAsync(_selectedStreamIndex);
        }

        private async Task RenameStreamForIndexAsync(int index)
        {
            if (_tagdosService == null || index < 0 || index >= _streams.Count) return;
            var stream = _streams[index];
            int currentIdx = index;

            var input = new TextBox
            {
                Text = stream.CustomTitle ?? stream.DisplayTitle,
                PlaceholderText = "Custom stream title..."
            };

            var stack = new StackPanel { Spacing = 12, MinWidth = 340 };
            stack.Children.Add(input);

            Button? moveLeftBtn = null;
            Button? moveRightBtn = null;
            if (_streams.Count > 1)
            {
                void SyncMoveButtons()
                {
                    if (moveLeftBtn != null) moveLeftBtn.IsEnabled = currentIdx > 0;
                    if (moveRightBtn != null) moveRightBtn.IsEnabled = currentIdx < _streams.Count - 1;
                }

                moveLeftBtn = new Button
                {
                    Content = "← Move Left",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    IsEnabled = currentIdx > 0
                };
                moveRightBtn = new Button
                {
                    Content = "Move Right →",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    IsEnabled = currentIdx < _streams.Count - 1
                };

                moveLeftBtn.Click += async (_, __) =>
                {
                    if (currentIdx > 0)
                    {
                        int from = currentIdx;
                        currentIdx--;
                        await MoveStreamPreservingSelectionAsync(from, currentIdx);
                        SyncMoveButtons();
                    }
                };
                moveRightBtn.Click += async (_, __) =>
                {
                    if (currentIdx < _streams.Count - 1)
                    {
                        int from = currentIdx;
                        currentIdx++;
                        await MoveStreamPreservingSelectionAsync(from, currentIdx);
                        SyncMoveButtons();
                    }
                };

                var moveGrid = new Grid { ColumnSpacing = 8 };
                moveGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                moveGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                Grid.SetColumn(moveLeftBtn, 0);
                Grid.SetColumn(moveRightBtn, 1);
                moveGrid.Children.Add(moveLeftBtn);
                moveGrid.Children.Add(moveRightBtn);
                stack.Children.Add(moveGrid);
            }

            bool deleteConfirmed = false;
            bool confirmArmed = false;

            var dialog = new ContentDialog
            {
                Title = "Rename Stream",
                PrimaryButtonText = "Save",
                SecondaryButtonText = !string.IsNullOrWhiteSpace(stream.CustomTitle) ? "Reset to Auto" : null,
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                Content = stack,
                XamlRoot = this.XamlRoot
            };

            if (_streams.Count > 1)
            {
                var deleteRow = new Grid { ColumnSpacing = 8 };
                deleteRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                deleteRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                var keepBtn = new Button
                {
                    Content = "Keep Stream",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    Visibility = Visibility.Collapsed
                };

                var deleteBtn = new Button
                {
                    Content = "Delete Stream",
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0x5C, 0x8A)),
                    Background = new SolidColorBrush(Color.FromArgb(0x20, 0xFF, 0x5C, 0x8A)),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(0x55, 0xFF, 0x5C, 0x8A)),
                    BorderThickness = new Thickness(1)
                };
                Grid.SetColumnSpan(deleteBtn, 2);

                keepBtn.Click += (_, __) =>
                {
                    confirmArmed = false;
                    keepBtn.Visibility = Visibility.Collapsed;
                    Grid.SetColumn(deleteBtn, 0);
                    Grid.SetColumnSpan(deleteBtn, 2);
                    deleteBtn.Content = "Delete Stream";
                    deleteBtn.Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0x5C, 0x8A));
                    deleteBtn.Background = new SolidColorBrush(Color.FromArgb(0x20, 0xFF, 0x5C, 0x8A));
                };

                deleteBtn.Click += (_, __) =>
                {
                    if (!confirmArmed)
                    {
                        confirmArmed = true;
                        keepBtn.Visibility = Visibility.Visible;
                        Grid.SetColumn(keepBtn, 0);
                        Grid.SetColumn(deleteBtn, 1);
                        Grid.SetColumnSpan(deleteBtn, 1);
                        deleteBtn.Content = "Click again to delete";
                        deleteBtn.Foreground = new SolidColorBrush(Microsoft.UI.Colors.White);
                        deleteBtn.Background = new SolidColorBrush(Color.FromArgb(0xCC, 0xD9, 0x2B, 0x58));
                    }
                    else
                    {
                        deleteConfirmed = true;
                        dialog.Hide();
                    }
                };

                deleteRow.Children.Add(keepBtn);
                deleteRow.Children.Add(deleteBtn);
                stack.Children.Add(deleteRow);
            }

            var res = await dialog.ShowAsync();
            if (deleteConfirmed && _streams.Count > 1)
            {
                await _tagdosService.DeleteStreamAsync(stream.Id);
                _selectedStreamIndex = Math.Clamp(currentIdx - 1, 0, Math.Max(0, _streams.Count - 2));
                await LoadDataAsync();
            }
            else if (res == ContentDialogResult.Primary)
            {
                await _tagdosService.UpdateStreamTitleAsync(stream.Id, input.Text);
                await LoadDataAsync();
            }
            else if (res == ContentDialogResult.Secondary)
            {
                await _tagdosService.UpdateStreamTitleAsync(stream.Id, null);
                await LoadDataAsync();
            }
        }

        private async Task MoveStreamPreservingSelectionAsync(int fromIndex, int toIndex)
        {
            if (_tagdosService == null || fromIndex < 0 || toIndex < 0 || fromIndex >= _streams.Count || toIndex >= _streams.Count || fromIndex == toIndex)
            {
                return;
            }
            var activeId = (_selectedStreamIndex >= 0 && _selectedStreamIndex < _streams.Count)
                ? _streams[_selectedStreamIndex].Id
                : null;
            await _tagdosService.MoveStreamAsync(fromIndex, toIndex);
            _streams = await _tagdosService.GetStreamsAsync();
            if (!string.IsNullOrEmpty(activeId))
            {
                int updatedIdx = _streams.FindIndex(s => s.Id == activeId);
                _selectedStreamIndex = updatedIdx >= 0 ? updatedIdx : Math.Clamp(toIndex, 0, Math.Max(0, _streams.Count - 1));
            }
            RenderStreamTabs();
            SelectTab(_selectedStreamIndex);
        }

        private async Task ShowReorderStreamsDialogAsync()
        {
            if (_tagdosService == null || _streams.Count < 2) return;

            var uiRows = new ObservableCollection<Grid>();
            var listView = new ListView
            {
                ItemsSource = uiRows,
                CanReorderItems = true,
                AllowDrop = true,
                CanDragItems = true,
                SelectionMode = ListViewSelectionMode.None,
                MaxHeight = 360,
                MinWidth = 380
            };

            void RefreshRowBadges()
            {
                for (int idx = 0; idx < uiRows.Count; idx++)
                {
                    var row = uiRows[idx];
                    if (row.Children[0] is Border badgeBorder && badgeBorder.Child is TextBlock badgeText)
                    {
                        badgeText.Text = $"S{idx + 1}";
                    }
                    if (row.Children[2] is StackPanel btnStack && btnStack.Children.Count == 2)
                    {
                        if (btnStack.Children[0] is Button upBtn) upBtn.IsEnabled = idx > 0;
                        if (btnStack.Children[1] is Button downBtn) downBtn.IsEnabled = idx < uiRows.Count - 1;
                    }
                }
            }

            foreach (var stream in _streams)
            {
                var rowGrid = new Grid
                {
                    Tag = stream.Id,
                    ColumnSpacing = 10,
                    Padding = new Thickness(6, 6, 6, 6),
                    HorizontalAlignment = HorizontalAlignment.Stretch
                };
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var badge = new Border
                {
                    Background = new SolidColorBrush(Color.FromArgb(0x55, 0xAF, 0x52, 0xDE)),
                    CornerRadius = new CornerRadius(12),
                    Width = 30,
                    Height = 26,
                    Child = new TextBlock
                    {
                        FontSize = 11,
                        FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                        Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
                        HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Center
                    }
                };
                Grid.SetColumn(badge, 0);
                rowGrid.Children.Add(badge);

                var labelStack = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
                labelStack.Children.Add(new TextBlock
                {
                    Text = stream.DisplayTitle,
                    FontSize = 13,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
                var drivingRaw = stream.DrivingPill?.RawText;
                if (!string.IsNullOrWhiteSpace(stream.CustomTitle) && !string.IsNullOrWhiteSpace(drivingRaw))
                {
                    labelStack.Children.Add(new TextBlock
                    {
                        Text = drivingRaw,
                        FontSize = 11,
                        Foreground = new SolidColorBrush(Color.FromArgb(0x99, 0xFF, 0xFF, 0xFF)),
                        TextTrimming = TextTrimming.CharacterEllipsis
                    });
                }
                Grid.SetColumn(labelStack, 1);
                rowGrid.Children.Add(labelStack);

                var moveStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
                var upButton = new Button
                {
                    Content = new FontIcon { Glyph = "\xE70E", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 11 },
                    Padding = new Thickness(7, 5, 7, 5),
                    CornerRadius = new CornerRadius(8)
                };
                var downButton = new Button
                {
                    Content = new FontIcon { Glyph = "\xE70D", FontFamily = new FontFamily("Segoe Fluent Icons"), FontSize = 11 },
                    Padding = new Thickness(7, 5, 7, 5),
                    CornerRadius = new CornerRadius(8)
                };

                upButton.Click += (_, __) =>
                {
                    int cur = uiRows.IndexOf(rowGrid);
                    if (cur > 0)
                    {
                        uiRows.Move(cur, cur - 1);
                        RefreshRowBadges();
                    }
                };
                downButton.Click += (_, __) =>
                {
                    int cur = uiRows.IndexOf(rowGrid);
                    if (cur >= 0 && cur < uiRows.Count - 1)
                    {
                        uiRows.Move(cur, cur + 1);
                        RefreshRowBadges();
                    }
                };

                moveStack.Children.Add(upButton);
                moveStack.Children.Add(downButton);
                Grid.SetColumn(moveStack, 2);
                rowGrid.Children.Add(moveStack);

                uiRows.Add(rowGrid);
            }

            RefreshRowBadges();
            listView.DragItemsCompleted += (_, __) => RefreshRowBadges();

            var container = new StackPanel { Spacing = 8 };
            container.Children.Add(new TextBlock
            {
                Text = "Drag items or use Up/Down arrows to set your preferred stream order (S1..SN).",
                FontSize = 12,
                Foreground = new SolidColorBrush(Color.FromArgb(0xAA, 0xFF, 0xFF, 0xFF)),
                TextWrapping = TextWrapping.Wrap
            });
            container.Children.Add(listView);

            var dialog = new ContentDialog
            {
                Title = "Reorder Streams",
                PrimaryButtonText = "Save Order",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary,
                Content = container,
                XamlRoot = this.XamlRoot
            };

            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                var orderedIds = uiRows.Select(r => r.Tag as string ?? string.Empty).Where(id => !string.IsNullOrEmpty(id)).ToList();
                var activeId = (_selectedStreamIndex >= 0 && _selectedStreamIndex < _streams.Count)
                    ? _streams[_selectedStreamIndex].Id
                    : null;
                await _tagdosService.ReorderStreamsAsync(orderedIds);
                _streams = await _tagdosService.GetStreamsAsync();
                if (!string.IsNullOrEmpty(activeId))
                {
                    int match = _streams.FindIndex(s => s.Id == activeId);
                    if (match >= 0) _selectedStreamIndex = match;
                }
                RenderStreamTabs();
                SelectTab(_selectedStreamIndex);
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

        private sealed class WinUiTargetOption
        {
            public string Key { get; set; } = string.Empty;
            public string Label { get; set; } = string.Empty;
            public bool IsReplace { get; set; }
            public override string ToString() => Label;
        }

        private sealed class WinUiImportDraft
        {
            public string Id { get; set; } = string.Empty;
            public string OriginalTitle { get; set; } = string.Empty;
            public string? OriginalNotes { get; set; }
            public bool IsAlreadyDsl { get; set; }
            public string EditedTag { get; set; } = string.Empty;
            public bool IsSelected { get; set; } = false;
            public string TargetChoiceKey { get; set; } = "new";
            public string NewStreamTitle { get; set; } = string.Empty;
        }

        private static string StripHtmlToPlainText(string html)
        {
            if (string.IsNullOrWhiteSpace(html)) return string.Empty;
            var cleaned = Regex.Replace(html, "(?is)<head[^>]*>.*?</head>", string.Empty);
            cleaned = Regex.Replace(cleaned, "(?is)<style[^>]*>.*?</style>", string.Empty);
            cleaned = Regex.Replace(cleaned, "(?i)<br\\s*/?>", "\n");
            cleaned = Regex.Replace(cleaned, "(?i)</(p|div|li|tr|h[1-6])>", "\n");
            cleaned = Regex.Replace(cleaned, "<[^>]+>", " ");
            cleaned = WebUtility.HtmlDecode(cleaned).Replace("\r\n", "\n").Replace('\r', '\n').Replace('\u00A0', ' ');
            var lines = cleaned.Split('\n')
                .Select(l => Regex.Replace(l, "[ \\t]+", " ").Trim())
                .ToList();
            return Regex.Replace(string.Join("\n", lines), "\n{3,}", "\n\n").Trim();
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

            var targetOptions = new List<WinUiTargetOption>();
            for (int sIdx = 0; sIdx < _streams.Count; sIdx++)
            {
                var st = _streams[sIdx];
                targetOptions.Add(new WinUiTargetOption
                {
                    Key = $"replace:{st.Id}",
                    Label = $"Replace S{sIdx + 1}: {st.DisplayTitle}",
                    IsReplace = true
                });
            }
            for (int sIdx = 0; sIdx < _streams.Count; sIdx++)
            {
                var st = _streams[sIdx];
                targetOptions.Add(new WinUiTargetOption
                {
                    Key = $"append:{st.Id}",
                    Label = $"Append S{sIdx + 1}: {st.DisplayTitle}",
                    IsReplace = false
                });
            }
            targetOptions.Add(new WinUiTargetOption
            {
                Key = "new",
                Label = "+ New Stream",
                IsReplace = false
            });

            string fallbackTargetKey = (_selectedStreamIndex >= 0 && _selectedStreamIndex < _streams.Count)
                ? $"replace:{_streams[_selectedStreamIndex].Id}"
                : (_streams.Count > 0 ? $"replace:{_streams[0].Id}" : "new");

            var defaultTargetCombo = new ComboBox
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                ItemsSource = targetOptions,
                SelectedIndex = Math.Max(0, targetOptions.FindIndex(o => o.Key == fallbackTargetKey))
            };
            var applyDefaultBtn = new Button
            {
                Content = "Apply to Checked",
                FontSize = 11,
                Padding = new Thickness(10, 5, 10, 5)
            };
            var defaultTargetBar = new Grid
            {
                ColumnSpacing = 8,
                Visibility = Visibility.Collapsed
            };
            defaultTargetBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            defaultTargetBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            defaultTargetBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var defLabel = new TextBlock
            {
                Text = "Default:",
                FontSize = 11.5,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = new SolidColorBrush(Color.FromArgb(0xBB, 0xFF, 0xFF, 0xFF))
            };
            Grid.SetColumn(defLabel, 0);
            Grid.SetColumn(defaultTargetCombo, 1);
            Grid.SetColumn(applyDefaultBtn, 2);
            defaultTargetBar.Children.Add(defLabel);
            defaultTargetBar.Children.Add(defaultTargetCombo);
            defaultTargetBar.Children.Add(applyDefaultBtn);

            var summaryText = new TextBlock
            {
                FontSize = 11.5,
                Foreground = new SolidColorBrush(Color.FromArgb(0xDD, 0xFF, 0xFF, 0xFF)),
                Visibility = Visibility.Collapsed,
                TextWrapping = TextWrapping.Wrap
            };

            var replaceWarningText = new TextBlock
            {
                Text = "Note: Replace targets clear existing pills and active memos on those streams before combining mapped tasks.",
                FontSize = 11,
                Foreground = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0xB3, 0x00)),
                Visibility = Visibility.Collapsed,
                TextWrapping = TextWrapping.Wrap
            };

            var stagedByKey = new Dictionary<string, WinUiImportDraft>();
            var visibleKeys = new List<string>();
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
            dialog.Resources["ContentDialogMaxWidth"] = 780.0;

            List<WinUiImportDraft> GetSelectedDraftsOrdered()
            {
                var visibleSet = new HashSet<string>(visibleKeys);
                var visibleSel = visibleKeys
                    .Select(k => stagedByKey.TryGetValue(k, out var d) ? d : null)
                    .Where(d => d != null && d.IsSelected && !string.IsNullOrWhiteSpace(d.EditedTag))
                    .Cast<WinUiImportDraft>();
                var offListSel = stagedByKey.Values
                    .Where(d => !visibleSet.Contains(d.Id) && d.IsSelected && !string.IsNullOrWhiteSpace(d.EditedTag))
                    .OrderBy(d => d.Id, StringComparer.Ordinal);
                return visibleSel.Concat(offListSel).ToList();
            }

            void UpdateImportButtonState()
            {
                var chosenAll = GetSelectedDraftsOrdered();
                int count = chosenAll.Count;
                dialog.PrimaryButtonText = count > 0 ? $"Import ({count})" : "Import Selected";
                dialog.IsPrimaryButtonEnabled = count > 0 && !isBusy;

                if (count == 0)
                {
                    summaryText.Visibility = Visibility.Collapsed;
                    replaceWarningText.Visibility = Visibility.Collapsed;
                    return;
                }

                var countsByTarget = new Dictionary<string, int>();
                var orderKeys = new List<string>();
                foreach (var d in chosenAll)
                {
                    if (!countsByTarget.ContainsKey(d.TargetChoiceKey))
                    {
                        orderKeys.Add(d.TargetChoiceKey);
                        countsByTarget[d.TargetChoiceKey] = 0;
                    }
                    countsByTarget[d.TargetChoiceKey]++;
                }

                var summaryLines = orderKeys.Select(k =>
                {
                    var label = targetOptions.FirstOrDefault(o => o.Key == k)?.Label ?? k;
                    int c = countsByTarget[k];
                    return $"• {c} task{(c == 1 ? "" : "s")} → {label}";
                });
                summaryText.Text = $"Batch Summary ({count} staged):\n" + string.Join("\n", summaryLines);
                summaryText.Visibility = Visibility.Visible;

                bool hasReplace = chosenAll.Any(d => d.TargetChoiceKey.StartsWith("replace:", StringComparison.Ordinal));
                replaceWarningText.Visibility = hasReplace ? Visibility.Visible : Visibility.Collapsed;
            }

            void RenderDraftRows()
            {
                tasksPanel.Children.Clear();
                if (visibleKeys.Count == 0)
                {
                    tasksHeaderRow.Visibility = Visibility.Collapsed;
                    defaultTargetBar.Visibility = Visibility.Collapsed;
                    UpdateImportButtonState();
                    return;
                }

                tasksCountText.Text = $"{visibleKeys.Count} active tasks";
                tasksHeaderRow.Visibility = Visibility.Visible;
                defaultTargetBar.Visibility = Visibility.Visible;

                foreach (var key in visibleKeys)
                {
                    if (!stagedByKey.TryGetValue(key, out var draft)) continue;

                    var rowBorder = new Border
                    {
                        Background = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)),
                        BorderBrush = new SolidColorBrush(Color.FromArgb(0x28, 0xFF, 0xFF, 0xFF)),
                        BorderThickness = new Thickness(1),
                        CornerRadius = new CornerRadius(10),
                        Padding = new Thickness(10)
                    };

                    var rowStack = new StackPanel { Spacing = 6 };
                    var topGrid = new Grid { ColumnSpacing = 8 };
                    topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    topGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                    bool suppressEvents = true;
                    var chk = new CheckBox { IsChecked = draft.IsSelected, MinWidth = 0, Padding = new Thickness(0) };
                    chk.Checked += (_, __) => { if (!suppressEvents) { draft.IsSelected = true; UpdateImportButtonState(); } };
                    chk.Unchecked += (_, __) => { if (!suppressEvents) { draft.IsSelected = false; UpdateImportButtonState(); } };
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

                    var targetRowGrid = new Grid
                    {
                        ColumnSpacing = 8,
                        Margin = new Thickness(28, 0, 0, 0)
                    };
                    targetRowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    targetRowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

                    int optIdx = targetOptions.FindIndex(o => o.Key == draft.TargetChoiceKey);
                    if (optIdx < 0) optIdx = Math.Max(0, targetOptions.FindIndex(o => o.Key == "new"));

                    var rowTargetCombo = new ComboBox
                    {
                        ItemsSource = targetOptions,
                        SelectedIndex = optIdx,
                        MinWidth = 190
                    };
                    var newTitleBox = new TextBox
                    {
                        PlaceholderText = "Optional new stream title...",
                        Text = draft.NewStreamTitle,
                        Visibility = draft.TargetChoiceKey == "new" ? Visibility.Visible : Visibility.Collapsed
                    };
                    newTitleBox.TextChanged += (_, __) => { draft.NewStreamTitle = newTitleBox.Text; };

                    rowTargetCombo.SelectionChanged += (_, __) =>
                    {
                        if (suppressEvents) return;
                        if (rowTargetCombo.SelectedItem is WinUiTargetOption opt)
                        {
                            draft.TargetChoiceKey = opt.Key;
                            draft.IsSelected = true;
                            suppressEvents = true;
                            chk.IsChecked = true;
                            suppressEvents = false;
                            newTitleBox.Visibility = opt.Key == "new" ? Visibility.Visible : Visibility.Collapsed;
                            UpdateImportButtonState();
                        }
                    };

                    suppressEvents = false;

                    Grid.SetColumn(rowTargetCombo, 0);
                    Grid.SetColumn(newTitleBox, 1);
                    targetRowGrid.Children.Add(rowTargetCombo);
                    targetRowGrid.Children.Add(newTitleBox);
                    rowStack.Children.Add(targetRowGrid);

                    rowBorder.Child = rowStack;
                    tasksPanel.Children.Add(rowBorder);
                }

                UpdateImportButtonState();
            }

            selectAllBtn.Click += (_, __) =>
            {
                foreach (var k in visibleKeys)
                {
                    if (stagedByKey.TryGetValue(k, out var d)) d.IsSelected = true;
                }
                RenderDraftRows();
            };
            clearAllBtn.Click += (_, __) =>
            {
                foreach (var k in visibleKeys)
                {
                    if (stagedByKey.TryGetValue(k, out var d)) d.IsSelected = false;
                }
                RenderDraftRows();
            };
            applyDefaultBtn.Click += (_, __) =>
            {
                if (defaultTargetCombo.SelectedItem is WinUiTargetOption chosenOpt)
                {
                    foreach (var k in visibleKeys)
                    {
                        if (stagedByKey.TryGetValue(k, out var d) && d.IsSelected)
                        {
                            d.TargetChoiceKey = chosenOpt.Key;
                        }
                    }
                    RenderDraftRows();
                }
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
                visibleKeys.Clear();
                RenderDraftRows();
                statusBar.Text = $"Loading tasks from '{listOpt.Title}'...";

                string activeDefaultKey = (defaultTargetCombo.SelectedItem as WinUiTargetOption)?.Key ?? fallbackTargetKey;

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
                                var rawTaskId = item.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString();
                                var key = $"{acc.AccountType}::{acc.Id}::{listOpt.Id}::{rawTaskId}";
                                visibleKeys.Add(key);
                                if (!stagedByKey.ContainsKey(key))
                                {
                                    var notes = item.TryGetProperty("notes", out var n) ? n.GetString()?.Trim() : null;
                                    var prep = TagdosParser.PrepareImportItem(title, notes, false);
                                    stagedByKey[key] = new WinUiImportDraft
                                    {
                                        Id = key,
                                        OriginalTitle = title,
                                        OriginalNotes = string.IsNullOrWhiteSpace(notes) ? null : notes,
                                        IsAlreadyDsl = prep.IsAlreadyDsl,
                                        EditedTag = prep.TagOrDsl,
                                        IsSelected = false,
                                        TargetChoiceKey = activeDefaultKey
                                    };
                                }
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

                                var rawTaskId = item.TryGetProperty("id", out var idEl) ? idEl.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString();
                                var key = $"{acc.AccountType}::{acc.Id}::{listOpt.Id}::{rawTaskId}";
                                visibleKeys.Add(key);
                                if (!stagedByKey.ContainsKey(key))
                                {
                                    string notes = string.Empty;
                                    if (item.TryGetProperty("body", out var bodyObj))
                                    {
                                        var rawBody = bodyObj.TryGetProperty("content", out var c) ? c.GetString() ?? "" : "";
                                        var cType = bodyObj.TryGetProperty("contentType", out var ct) ? ct.GetString() ?? "" : "";
                                        notes = cType.Equals("html", StringComparison.OrdinalIgnoreCase)
                                            ? StripHtmlToPlainText(rawBody)
                                            : rawBody.Trim();
                                    }
                                    bool isHigh = item.TryGetProperty("importance", out var imp) &&
                                                  string.Equals(imp.GetString(), "high", StringComparison.OrdinalIgnoreCase);

                                    var prep = TagdosParser.PrepareImportItem(title, notes, isHigh);
                                    stagedByKey[key] = new WinUiImportDraft
                                    {
                                        Id = key,
                                        OriginalTitle = title,
                                        OriginalNotes = string.IsNullOrWhiteSpace(notes) ? null : notes,
                                        IsAlreadyDsl = prep.IsAlreadyDsl,
                                        EditedTag = prep.TagOrDsl,
                                        IsSelected = false,
                                        TargetChoiceKey = activeDefaultKey
                                    };
                                }
                            }
                        }
                    }

                    statusBar.Text = visibleKeys.Count == 0
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
                visibleKeys.Clear();
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
                visibleKeys.Clear();
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

            var contentStack = new StackPanel { Spacing = 10, Width = 640 };

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
            contentStack.Children.Add(defaultTargetBar);
            contentStack.Children.Add(tasksHeaderRow);
            contentStack.Children.Add(tasksScroll);
            contentStack.Children.Add(summaryText);
            contentStack.Children.Add(replaceWarningText);

            dialog.Content = contentStack;
            _ = RefreshAccountsForSelectedProviderAsync();

            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary)
            {
                var chosen = GetSelectedDraftsOrdered();
                if (chosen.Count == 0) return;

                var batchItems = new List<TagdosTaskImportItem>();
                foreach (var item in chosen)
                {
                    var tag = item.EditedTag.Trim();
                    var notes = item.OriginalNotes?.Trim() ?? string.Empty;
                    string? memoLine = item.IsAlreadyDsl
                        ? (string.IsNullOrEmpty(notes) ? null : notes)
                        : (string.IsNullOrEmpty(notes) ? $"• [{tag}] {item.OriginalTitle}" : $"• [{tag}] {item.OriginalTitle} — {notes}");

                    TagdosTaskImportMode mode = TagdosTaskImportMode.NewStream;
                    string? targetStreamId = null;
                    if (item.TargetChoiceKey.StartsWith("replace:", StringComparison.Ordinal))
                    {
                        mode = TagdosTaskImportMode.Replace;
                        targetStreamId = item.TargetChoiceKey.Substring("replace:".Length);
                    }
                    else if (item.TargetChoiceKey.StartsWith("append:", StringComparison.Ordinal))
                    {
                        mode = TagdosTaskImportMode.Append;
                        targetStreamId = item.TargetChoiceKey.Substring("append:".Length);
                    }

                    batchItems.Add(new TagdosTaskImportItem
                    {
                        DslOrTag = tag,
                        MemoLine = memoLine,
                        Mode = mode,
                        TargetStreamId = targetStreamId,
                        NewStreamTitle = item.NewStreamTitle
                    });
                }

                var importedId = await _tagdosService.ImportExternalTaskBatchAsync(batchItems);
                _streams = await _tagdosService.GetStreamsAsync();
                int newIndex = !string.IsNullOrEmpty(importedId)
                    ? _streams.FindIndex(s => s.Id == importedId)
                    : -1;
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
