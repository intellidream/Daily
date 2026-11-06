using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Daily_WinUI.Models;
using Daily_WinUI.Services;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Pickers;
using Windows.UI;

namespace Daily_WinUI.Views;

public sealed partial class SupabaseAdminPage : Page
{
    private readonly SupabaseAdminService _admin = SupabaseAdminService.Shared;
    private string _activeFilter = "ALL";
    private bool _suppressProjectComboEvent;
    private string? _transientToast;

    private static readonly Color CyanAccent = Color.FromArgb(255, 56, 189, 248);
    private static readonly Color EmeraldAccent = Color.FromArgb(255, 16, 185, 129);
    private static readonly Color PurpleAccent = Color.FromArgb(255, 168, 85, 247);
    private static readonly Color AmberAccent = Color.FromArgb(255, 245, 158, 11);
    private static readonly Color PinkAccent = Color.FromArgb(255, 236, 72, 153);
    private static readonly Color RedAccent = Color.FromArgb(255, 248, 113, 113);

    public SupabaseAdminPage()
    {
        InitializeComponent();
        Unloaded += SupabaseAdminPage_Unloaded;
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _admin.StateChanged -= OnAdminStateChanged;
        _admin.StateChanged += OnAdminStateChanged;

        UpdateFilterButtonStyles();
        RenderFromState();

        await _admin.EnsureLoadedOnAppearAsync();
    }

    private void SupabaseAdminPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _admin.StateChanged -= OnAdminStateChanged;
    }

    private void OnAdminStateChanged()
    {
        DispatcherQueue?.TryEnqueue(RenderFromState);
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (Frame != null && Frame.CanGoBack)
        {
            Frame.GoBack();
        }
        else
        {
            Frame?.Navigate(typeof(DataSyncSettingsPage));
        }
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        _transientToast = null;
        await _admin.RefreshSnapshotAsync(force: true);
    }

    private async void AnalyzeAiButton_Click(object sender, RoutedEventArgs e)
    {
        await _admin.AnalyzeWithAiAsync();
    }

    private void CopyReportButton_Click(object sender, RoutedEventArgs e)
    {
        var md = _admin.Snapshot?.ToMarkdownReport();
        if (string.IsNullOrEmpty(md)) return;

        var pkg = new DataPackage();
        pkg.SetText(md);
        Clipboard.SetContent(pkg);
        _transientToast = "Forensic Markdown report copied to clipboard!";
        RenderFromState();
    }

    private async void SaveReportButton_Click(object sender, RoutedEventArgs e)
    {
        var snap = _admin.Snapshot;
        if (snap == null) return;

        try
        {
            var picker = new FileSavePicker
            {
                SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
                SuggestedFileName = $"Supabase_Forensics_{snap.Project.Ref}_{DateTime.Now:yyyyMMdd_HHmm}"
            };
            picker.FileTypeChoices.Add("Markdown Report", new List<string> { ".md" });

            Window? hostWin = App.Current.ActiveSecondaryWindows.FirstOrDefault() ?? App.Current.MainWindow;
            if (hostWin != null)
            {
                var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(hostWin);
                WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
            }

            var file = await picker.PickSaveFileAsync();
            if (file != null)
            {
                await File.WriteAllTextAsync(file.Path, snap.ToMarkdownReport());
                _transientToast = $"Saved report to {file.Name}";
                RenderFromState();
            }
        }
        catch (Exception ex)
        {
            _transientToast = $"Export warning: {ex.Message}";
            RenderFromState();
        }
    }

    private void DisconnectButton_Click(object sender, RoutedEventArgs e)
    {
        _admin.Disconnect();
        Frame?.Navigate(typeof(DataSyncSettingsPage));
    }

    private async void ProjectSelectorCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressProjectComboEvent) return;
        if (ProjectSelectorCombo.SelectedItem is ComboBoxItem item && item.Tag is string projRef)
        {
            await _admin.SelectProjectAsync(projRef);
        }
    }

    private void FilterTab_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string tag)
        {
            _activeFilter = tag;
            UpdateFilterButtonStyles();
            RenderFromState();
        }
    }

    private void UpdateFilterButtonStyles()
    {
        Style? accentStyle = Application.Current.Resources.TryGetValue("AccentButtonStyle", out var st) ? st as Style : null;
        Style? defaultStyle = Application.Current.Resources.TryGetValue("DefaultButtonStyle", out var dst) ? dst as Style : null;

        foreach (var child in FilterTabsPanel.Children)
        {
            if (child is Button btn && btn.Tag is string tag)
            {
                btn.Style = (tag == _activeFilter) ? accentStyle : defaultStyle;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Dynamic Fluent Telemetry Renderer
    // -------------------------------------------------------------------------

    private void RenderFromState()
    {
        var snap = _admin.Snapshot;
        var creds = _admin.Credentials;

        LoadingBanner.Visibility = _admin.IsLoading ? Visibility.Visible : Visibility.Collapsed;
        RefreshButton.IsEnabled = !_admin.IsLoading;
        AnalyzeAiButton.IsEnabled = snap != null && !_admin.IsAnalyzingAi;
        AnalyzeAiButtonLabel.Text = _admin.IsAnalyzingAi ? "Analyzing..." : "Analyze SRE";
        CopyReportButton.IsEnabled = snap != null;
        SaveReportButton.IsEnabled = snap != null;

        if (!string.IsNullOrWhiteSpace(_admin.ErrorMessage))
        {
            ErrorBannerText.Text = _admin.ErrorMessage;
            ErrorBanner.Visibility = Visibility.Visible;
        }
        else
        {
            ErrorBanner.Visibility = Visibility.Collapsed;
        }

        if (snap != null)
        {
            ProjectTitleText.Text = $"{snap.Project.Name} ({snap.Project.Ref})";
            PlanBadgeText.Text = snap.OrgPlan.ToUpperInvariant();
            var fetchedLocal = DateTimeOffset.FromUnixTimeMilliseconds(snap.FetchedAtEpochMs).ToLocalTime();
            SubtitleStatusText.Text = _transientToast ??
                $"{creds.AdminIdentity ?? "Admin"} · {snap.OrgName} · Compute {snap.ComputeTier} · {snap.Project.Region} · PG {snap.Project.PostgresVersion} · Updated {fetchedLocal:HH:mm:ss}";

            if (snap.AvailableProjects.Count > 1)
            {
                _suppressProjectComboEvent = true;
                ProjectSelectorCombo.Items.Clear();
                ComboBoxItem? toSelect = null;
                foreach (var p in snap.AvailableProjects)
                {
                    var cbi = new ComboBoxItem { Content = $"{p.Name} ({p.Ref})", Tag = p.Ref };
                    if (p.Ref == snap.Project.Ref) toSelect = cbi;
                    ProjectSelectorCombo.Items.Add(cbi);
                }
                ProjectSelectorCombo.SelectedItem = toSelect;
                ProjectSelectorCombo.Visibility = Visibility.Visible;
                _suppressProjectComboEvent = false;
            }
            else
            {
                ProjectSelectorCombo.Visibility = Visibility.Collapsed;
            }
        }
        else
        {
            ProjectTitleText.Text = "Supabase Cloud Console";
            PlanBadgeText.Text = "CONNECTING";
            SubtitleStatusText.Text = _transientToast ?? "Waiting for read-only telemetry snapshot...";
        }

        DynamicSectionsHost.Children.Clear();
        if (snap == null) return;

        // AI Co-Pilot Card
        if (!string.IsNullOrWhiteSpace(_admin.AiAnalysis))
        {
            DynamicSectionsHost.Children.Add(BuildAiAnalysisCard(_admin.AiAnalysis!));
        }

        bool showAll = _activeFilter == "ALL";

        if (showAll || _activeFilter == "QUOTAS")
        {
            DynamicSectionsHost.Children.Add(BuildQuotaGrid(snap));
            DynamicSectionsHost.Children.Add(BuildDailyEgressCard(snap));
        }

        if (showAll || _activeFilter == "DATABASE")
        {
            DynamicSectionsHost.Children.Add(BuildDatabaseAndTablesCard(snap));
            DynamicSectionsHost.Children.Add(BuildCronAndSqlCard(snap));
        }

        if (showAll || _activeFilter == "GATEWAY")
        {
            DynamicSectionsHost.Children.Add(BuildGatewayForensicsCard(snap));
        }

        if (showAll || _activeFilter == "RUNTIME")
        {
            DynamicSectionsHost.Children.Add(BuildRuntimeAndRealtimeCard(snap));
        }

        if (showAll || _activeFilter == "FLEET")
        {
            DynamicSectionsHost.Children.Add(BuildFleetAndAdvisorsCard(snap));
        }
    }

    private Border BuildCardContainer(double padding = 18)
    {
        return new Border
        {
            Background = Application.Current.Resources["CardBackgroundFillColorDefaultBrush"] as Brush,
            BorderBrush = Application.Current.Resources["CardStrokeColorDefaultBrush"] as Brush,
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(padding)
        };
    }

    private UIElement BuildAiAnalysisCard(string analysisText)
    {
        var card = BuildCardContainer();
        card.BorderBrush = new SolidColorBrush(Color.FromArgb(110, 56, 189, 248));
        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(new TextBlock
        {
            Text = "Cloud SRE Diagnostic Summary",
            FontSize = 14.5,
            FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(CyanAccent)
        });
        stack.Children.Add(new TextBlock
        {
            Text = analysisText,
            FontSize = 12.5,
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true,
            Opacity = 0.9
        });
        card.Child = stack;
        return card;
    }

    private UIElement BuildQuotaGrid(SupabaseAdminSnapshot snap)
    {
        var grid = new Grid { ColumnSpacing = 12, RowSpacing = 12 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var c1 = BuildQuotaTile(
            "Database Size",
            SupabaseAdminFormatter.FormatBytes(snap.DbTotalBytes),
            $"of {SupabaseAdminFormatter.FormatBytes(snap.DbQuotaBytes)} ({snap.DbUsagePercent:F1}%)",
            $"Heap {SupabaseAdminFormatter.FormatBytes(snap.DbHeapBytes)} · Indexes {SupabaseAdminFormatter.FormatBytes(snap.DbIndexBytes)}",
            snap.DbUsagePercent,
            CyanAccent);
        Grid.SetRow(c1, 0);
        Grid.SetColumn(c1, 0);
        grid.Children.Add(c1);

        var egressBadge = snap.HasExactBillingMetrics ? "Exact Billing" : "24h Gateway Est.";
        var c2 = BuildQuotaTile(
            $"Unified Egress ({egressBadge})",
            $"{snap.EgressUsedGb:F3} GB",
            $"of {snap.EgressQuotaGb:F1} GB ({snap.EgressUsagePercent:F1}%)",
            $"Cached {snap.CachedEgressUsedGb:F3} GB · 24h Payload {SupabaseAdminFormatter.FormatBytes(snap.GatewayEgressBytes24h)}",
            snap.EgressUsagePercent,
            EmeraldAccent);
        Grid.SetRow(c2, 0);
        Grid.SetColumn(c2, 1);
        grid.Children.Add(c2);

        var c3 = BuildQuotaTile(
            "Storage Buckets",
            SupabaseAdminFormatter.FormatBytes(snap.StorageTotalBytes),
            $"of {SupabaseAdminFormatter.FormatBytes(snap.StorageQuotaBytes)} ({snap.StorageUsagePercent:F1}%)",
            $"{snap.StorageObjectCount} objects across {snap.StorageBucketCount} buckets",
            snap.StorageUsagePercent,
            PurpleAccent);
        Grid.SetRow(c3, 1);
        Grid.SetColumn(c3, 0);
        grid.Children.Add(c3);

        double mauPct = snap.MauQuota > 0 ? Math.Min(100.0, (double)snap.MonthlyActiveUsers / snap.MauQuota * 100.0) : 0.0;
        var c4 = BuildQuotaTile(
            "Auth & Active Fleet",
            $"{snap.MonthlyActiveUsers} MAU",
            $"of {snap.MauQuota:N0} quota",
            $"{snap.ActiveSessionsCount} active sessions · {snap.PairedWatchesCount} paired watches",
            mauPct,
            AmberAccent);
        Grid.SetRow(c4, 1);
        Grid.SetColumn(c4, 1);
        grid.Children.Add(c4);

        return grid;
    }

    private Border BuildQuotaTile(string title, string headline, string quotaLabel, string footer, double pct, Color accent)
    {
        var card = BuildCardContainer(16);
        var stack = new StackPanel { Spacing = 6 };
        stack.Children.Add(new TextBlock { Text = title, FontSize = 12, Opacity = 0.72, FontWeight = FontWeights.SemiBold });

        var valRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Bottom };
        valRow.Children.Add(new TextBlock { Text = headline, FontSize = 22, FontWeight = FontWeights.Bold });
        valRow.Children.Add(new TextBlock { Text = quotaLabel, FontSize = 11.5, Opacity = 0.65, Margin = new Thickness(0, 0, 0, 3) });
        stack.Children.Add(valRow);

        var barColor = pct >= 85 ? RedAccent : pct >= 65 ? AmberAccent : accent;
        var pb = new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = Math.Clamp(pct, 1.0, 100.0),
            Foreground = new SolidColorBrush(barColor),
            Margin = new Thickness(0, 4, 0, 2)
        };
        stack.Children.Add(pb);

        stack.Children.Add(new TextBlock { Text = footer, FontSize = 11.5, Opacity = 0.65, TextTrimming = CharacterEllipsis });
        card.Child = stack;
        return card;
    }

    private UIElement BuildDailyEgressCard(SupabaseAdminSnapshot snap)
    {
        var card = BuildCardContainer();
        var stack = new StackPanel { Spacing = 12 };

        stack.Children.Add(SectionHeader(
            "14-Day Stacked Egress & Service Traffic",
            $"24h Requests — PostgREST: {snap.RestRequests24h:N0} · Auth: {snap.AuthRequests24h:N0} · Realtime: {snap.RealtimeRequests24h:N0} · Storage: {snap.StorageRequests24h:N0}"));

        if (snap.DailyEgressSeries.Count == 0)
        {
            stack.Children.Add(MutedLabel("No daily analytics points returned for the current window."));
        }
        else
        {
            long maxDay = Math.Max(1L, snap.DailyEgressSeries.Max(d => d.TotalBytes));
            var barsGrid = new Grid { Height = 126, ColumnSpacing = 6, Margin = new Thickness(0, 6, 0, 2) };
            for (int i = 0; i < snap.DailyEgressSeries.Count; i++)
            {
                barsGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var pt = snap.DailyEgressSeries[i];

                var colStack = new Grid();
                colStack.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
                colStack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

                double totalPx = Math.Max(4.0, (double)pt.TotalBytes / maxDay * 96.0);
                var segStack = new StackPanel
                {
                    VerticalAlignment = VerticalAlignment.Bottom,
                    CornerRadius = new CornerRadius(3)
                };
                ToolTipService.SetToolTip(segStack, $"{pt.DateLabel}: {pt.TotalFormatted}");

                AddBarSegment(segStack, pt.StorageBytes, pt.TotalBytes, totalPx, PurpleAccent);
                AddBarSegment(segStack, pt.RealtimeBytes, pt.TotalBytes, totalPx, AmberAccent);
                AddBarSegment(segStack, pt.AuthBytes, pt.TotalBytes, totalPx, EmeraldAccent);
                AddBarSegment(segStack, pt.FunctionsBytes, pt.TotalBytes, totalPx, PinkAccent);
                AddBarSegment(segStack, Math.Max(1L, pt.RestBytes), Math.Max(1L, pt.TotalBytes), totalPx, CyanAccent);

                colStack.Children.Add(segStack);

                var lbl = new TextBlock
                {
                    Text = pt.DateLabel,
                    FontSize = 9.5,
                    Opacity = 0.6,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    Margin = new Thickness(0, 4, 0, 0)
                };
                Grid.SetRow(lbl, 1);
                colStack.Children.Add(lbl);

                Grid.SetColumn(colStack, i);
                barsGrid.Children.Add(colStack);
            }
            stack.Children.Add(barsGrid);

            var legend = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
            legend.Children.Add(LegendDot("PostgREST", CyanAccent));
            legend.Children.Add(LegendDot("Auth", EmeraldAccent));
            legend.Children.Add(LegendDot("Realtime", AmberAccent));
            legend.Children.Add(LegendDot("Storage", PurpleAccent));
            legend.Children.Add(LegendDot("Functions", PinkAccent));
            stack.Children.Add(legend);
        }

        card.Child = stack;
        return card;
    }

    private static void AddBarSegment(StackPanel host, long partBytes, long totalBytes, double totalPx, Color color)
    {
        if (partBytes <= 0 || totalBytes <= 0) return;
        double h = Math.Max(2.0, (double)partBytes / totalBytes * totalPx);
        host.Children.Add(new Border
        {
            Height = h,
            Background = new SolidColorBrush(color),
            HorizontalAlignment = HorizontalAlignment.Stretch
        });
    }

    private UIElement BuildDatabaseAndTablesCard(SupabaseAdminSnapshot snap)
    {
        var card = BuildCardContainer();
        var stack = new StackPanel { Spacing = 10 };

        stack.Children.Add(SectionHeader(
            "PostgreSQL Storage, Index Bloat & Disk Spec",
            $"Disk {snap.DiskType.ToUpperInvariant()} · {snap.DiskSizeGb} GB Provisioned · {snap.DiskIops:N0} IOPS · {snap.DiskThroughputMbps} MB/s Throughput"));

        foreach (var t in snap.TopTables.Take(12))
        {
            var row = new Grid
            {
                Padding = new Thickness(10, 8, 10, 8),
                CornerRadius = new CornerRadius(6),
                Background = new SolidColorBrush(Color.FromArgb(14, 255, 255, 255))
            };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel { Spacing = 2 };
            var titleLine = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            titleLine.Children.Add(new TextBlock
            {
                Text = t.QualifiedName,
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12.5,
                FontWeight = FontWeights.SemiBold
            });
            if (t.HasIndexBloatWarning)
            {
                titleLine.Children.Add(PillBadge($"INDEX BLOAT {t.IndexToHeapRatio:F1}x", RedAccent));
            }
            left.Children.Add(titleLine);
            left.Children.Add(new TextBlock
            {
                Text = $"Heap {t.HeapFormatted} · Indexes {t.IndexFormatted} · Live {t.LiveRows:N0} · Dead {t.DeadRows:N0} · Writes {t.WritesTotal:N0}",
                FontSize = 11,
                Opacity = 0.65
            });
            row.Children.Add(left);

            var right = new TextBlock
            {
                Text = t.TotalFormatted,
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12.5,
                FontWeight = FontWeights.Bold,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(right, 1);
            row.Children.Add(right);

            stack.Children.Add(row);
        }

        card.Child = stack;
        return card;
    }

    private UIElement BuildCronAndSqlCard(SupabaseAdminSnapshot snap)
    {
        var card = BuildCardContainer();
        var stack = new StackPanel { Spacing = 12 };

        stack.Children.Add(SectionHeader(
            "pg_cron Retention Jobs & Top pg_stat_statements",
            $"{snap.CronJobs.Count} scheduled database jobs · {snap.TopSqlStatements.Count} tracked SQL hotspots"));

        if (snap.CronJobs.Count > 0)
        {
            foreach (var job in snap.CronJobs.Take(8))
            {
                var jRow = new Grid { ColumnSpacing = 10 };
                jRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                jRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                jRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                jRow.Children.Add(PillBadge(job.IsHealthy ? "OK" : "CHECK", job.IsHealthy ? EmeraldAccent : RedAccent));

                var mid = new TextBlock
                {
                    Text = $"{job.JobName} ({job.Schedule})",
                    FontFamily = new FontFamily("Consolas"),
                    FontSize = 12,
                    VerticalAlignment = VerticalAlignment.Center,
                    TextTrimming = TextTrimming.CharacterEllipsis
                };
                Grid.SetColumn(mid, 1);
                jRow.Children.Add(mid);

                var statusTxt = new TextBlock
                {
                    Text = job.LastStatus ?? (job.Active ? "scheduled" : "inactive"),
                    FontSize = 11,
                    Opacity = 0.68,
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(statusTxt, 2);
                jRow.Children.Add(statusTxt);

                stack.Children.Add(jRow);
            }
        }

        if (snap.TopSqlStatements.Count > 0)
        {
            stack.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Color.FromArgb(24, 255, 255, 255)), Margin = new Thickness(0, 4, 0, 4) });
            foreach (var s in snap.TopSqlStatements.Take(5))
            {
                var sBox = new StackPanel { Spacing = 2 };
                sBox.Children.Add(new TextBlock
                {
                    Text = s.QueryPreview,
                    FontFamily = new FontFamily("Consolas"),
                    FontSize = 11.5,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    IsTextSelectionEnabled = true
                });
                sBox.Children.Add(new TextBlock
                {
                    Text = $"{s.Calls:N0} calls · mean {s.MeanExecTimeMs:F2} ms · total {s.TotalExecTimeMs:F0} ms · {s.RowsReturned:N0} rows",
                    FontSize = 11,
                    Opacity = 0.62
                });
                stack.Children.Add(sBox);
            }
        }

        card.Child = stack;
        return card;
    }

    private UIElement BuildGatewayForensicsCard(SupabaseAdminSnapshot snap)
    {
        var card = BuildCardContainer();
        var stack = new StackPanel { Spacing = 12 };

        stack.Children.Add(SectionHeader(
            "24h API Gateway & ClickHouse Log Forensics",
            $"Total {snap.GatewayRequests24h:N0} reqs · 2xx: {snap.Gateway2xx24h:N0} · 4xx: {snap.Gateway4xx24h:N0} · 5xx: {snap.Gateway5xx24h:N0} ({snap.GatewayErrorRatePercent:F2}% errors) · {SupabaseAdminFormatter.FormatBytes(snap.GatewayEgressBytes24h)} payload"));

        foreach (var r in snap.TopGatewayRoutes.Take(8))
        {
            var g = new Grid { ColumnSpacing = 10 };
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var routeText = new TextBlock
            {
                Text = r.RouteLabel,
                FontFamily = new FontFamily("Consolas"),
                FontSize = 12,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            g.Children.Add(routeText);

            var statText = new TextBlock
            {
                Text = $"{r.RequestCount:N0} reqs · {r.ErrorCount} err · {r.EgressFormatted}",
                FontSize = 11.5,
                Opacity = 0.78
            };
            Grid.SetColumn(statText, 1);
            g.Children.Add(statText);

            stack.Children.Add(g);
        }

        if (snap.RecentGatewayErrors.Count > 0)
        {
            stack.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Color.FromArgb(24, 255, 255, 255)), Margin = new Thickness(0, 4, 0, 4) });
            stack.Children.Add(new TextBlock { Text = "Recent 4xx / 5xx Gateway Events", FontSize = 12, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(RedAccent) });
            foreach (var err in snap.RecentGatewayErrors.Take(5))
            {
                stack.Children.Add(new TextBlock
                {
                    Text = $"[{err.StatusCode}] {err.Method} {err.Path} — {err.Message}",
                    FontFamily = new FontFamily("Consolas"),
                    FontSize = 11,
                    Opacity = 0.78,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    IsTextSelectionEnabled = true
                });
            }
        }

        card.Child = stack;
        return card;
    }

    private UIElement BuildRuntimeAndRealtimeCard(SupabaseAdminSnapshot snap)
    {
        var card = BuildCardContainer();
        var stack = new StackPanel { Spacing = 12 };

        stack.Children.Add(SectionHeader(
            "Edge Functions & Realtime WAL Telemetry",
            $"Active Realtime Subscriptions: {snap.ActiveRealtimeSubscriptions} · realtime.list_changes CPU Share: {snap.RealtimeListChangesCpuPercent:F1}% ({snap.RealtimeListChangesCalls:N0} polls)"));

        if (snap.RealtimeSubscriptionsByTable.Count > 0)
        {
            var rtLine = string.Join(" · ", snap.RealtimeSubscriptionsByTable.Select(kv => $"{kv.Key}: {kv.Value}"));
            stack.Children.Add(new TextBlock { Text = $"Listeners by entity: {rtLine}", FontSize = 11.5, Opacity = 0.75, TextWrapping = TextWrapping.Wrap });
        }

        if (snap.EdgeFunctions.Count == 0)
        {
            stack.Children.Add(MutedLabel("No deployed Edge Functions found on this project."));
        }
        else
        {
            foreach (var fn in snap.EdgeFunctions)
            {
                var row = new Grid
                {
                    Padding = new Thickness(10, 8, 10, 8),
                    CornerRadius = new CornerRadius(6),
                    Background = new SolidColorBrush(Color.FromArgb(14, 255, 255, 255))
                };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                left.Children.Add(new TextBlock { Text = fn.Slug, FontFamily = new FontFamily("Consolas"), FontSize = 12.5, FontWeight = FontWeights.SemiBold });
                left.Children.Add(PillBadge($"v{fn.Version}", CyanAccent));
                if (fn.VerifyJwt) left.Children.Add(PillBadge("JWT", EmeraldAccent));
                row.Children.Add(left);

                var right = new TextBlock
                {
                    Text = $"{fn.Invocations24h:N0} calls · {fn.Errors24h} err · {fn.AvgExecutionMs:F0} ms",
                    FontSize = 11.5,
                    Opacity = 0.78,
                    VerticalAlignment = VerticalAlignment.Center
                };
                Grid.SetColumn(right, 1);
                row.Children.Add(right);

                stack.Children.Add(row);
            }
        }

        card.Child = stack;
        return card;
    }

    private UIElement BuildFleetAndAdvisorsCard(SupabaseAdminSnapshot snap)
    {
        var card = BuildCardContainer();
        var stack = new StackPanel { Spacing = 12 };

        stack.Children.Add(SectionHeader(
            "DayOne Ecosystem Fleet Footprint & Advisors",
            $"24h User-Agent distribution across iOS, macOS, Android, Windows 11, Smartwatches & Cloud Cron"));

        foreach (var client in snap.EcosystemClients)
        {
            var cStack = new StackPanel { Spacing = 3 };
            var hdr = new Grid();
            hdr.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            hdr.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            hdr.Children.Add(new TextBlock { Text = client.PlatformLabel, FontSize = 12, FontWeight = FontWeights.SemiBold });
            var right = new TextBlock { Text = $"{client.RequestCount24h:N0} reqs ({client.SharePercentLabel}) · {client.EgressFormatted}", FontSize = 11.5, Opacity = 0.72 };
            Grid.SetColumn(right, 1);
            hdr.Children.Add(right);
            cStack.Children.Add(hdr);

            cStack.Children.Add(new ProgressBar
            {
                Minimum = 0,
                Maximum = 100,
                Value = Math.Clamp(client.ShareRatio * 100.0, 1.0, 100.0),
                Foreground = new SolidColorBrush(CyanAccent)
            });
            stack.Children.Add(cStack);
        }

        if (snap.Advisors.Count > 0)
        {
            stack.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Color.FromArgb(24, 255, 255, 255)), Margin = new Thickness(0, 4, 0, 4) });
            stack.Children.Add(new TextBlock { Text = $"Supabase Performance & Security Advisors ({snap.Advisors.Count})", FontSize = 12.5, FontWeight = FontWeights.SemiBold });
            foreach (var adv in snap.Advisors.Take(8))
            {
                var color = adv.Level.Contains("ERROR") ? RedAccent : adv.Level.Contains("WARN") ? AmberAccent : CyanAccent;
                var aRow = new StackPanel { Spacing = 2 };
                var top = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                top.Children.Add(PillBadge($"{adv.Category} · {adv.Level}", color));
                top.Children.Add(new TextBlock { Text = adv.Title, FontSize = 12, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
                aRow.Children.Add(top);
                if (!string.IsNullOrWhiteSpace(adv.Description))
                {
                    aRow.Children.Add(new TextBlock { Text = adv.Description, FontSize = 11.5, Opacity = 0.68, TextWrapping = TextWrapping.Wrap });
                }
                stack.Children.Add(aRow);
            }
        }

        card.Child = stack;
        return card;
    }

    private static StackPanel SectionHeader(string title, string subtitle)
    {
        var sp = new StackPanel { Spacing = 2 };
        sp.Children.Add(new TextBlock { Text = title, FontSize = 14.5, FontWeight = FontWeights.SemiBold });
        sp.Children.Add(new TextBlock { Text = subtitle, FontSize = 11.5, Opacity = 0.65, TextWrapping = TextWrapping.Wrap });
        return sp;
    }

    private static Border PillBadge(string text, Color accent)
    {
        return new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(36, accent.R, accent.G, accent.B)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(95, accent.R, accent.G, accent.B)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(6, 1, 6, 1),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = text,
                FontSize = 9.5,
                FontWeight = FontWeights.Bold,
                Foreground = new SolidColorBrush(accent)
            }
        };
    }

    private static StackPanel LegendDot(string label, Color color)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
        sp.Children.Add(new Border
        {
            Width = 8,
            Height = 8,
            CornerRadius = new CornerRadius(4),
            Background = new SolidColorBrush(color),
            VerticalAlignment = VerticalAlignment.Center
        });
        sp.Children.Add(new TextBlock { Text = label, FontSize = 11, Opacity = 0.72 });
        return sp;
    }

    private static TextBlock MutedLabel(string text) =>
        new() { Text = text, FontSize = 12, Opacity = 0.6 };

    private const TextTrimming CharacterEllipsis = TextTrimming.CharacterEllipsis;
}
