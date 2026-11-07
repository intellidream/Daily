using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using Daily.Configuration;
using Daily.Services;
using Daily_WinUI.Models;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.UI;

namespace Daily_WinUI.Views;

public sealed partial class DataSyncSettingsPage : Page
{
    private readonly SupabaseAdminService _admin = SupabaseAdminService.Shared;
    private AppSettings _appSettings;
    private bool _isInitializingUi;

    public DataSyncSettingsPage()
    {
        InitializeComponent();
        _appSettings = Daily_WinUI.Services.SettingsService.Load();
        Unloaded += DataSyncSettingsPage_Unloaded;
    }

    protected override async void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _admin.StateChanged -= OnAdminStateChanged;
        _admin.StateChanged += OnAdminStateChanged;

        RefreshGeneralSyncUi();
        await _admin.InitializeAsync();
        RefreshAdminRowUi();
    }

    private void DataSyncSettingsPage_Unloaded(object sender, RoutedEventArgs e)
    {
        _admin.StateChanged -= OnAdminStateChanged;
    }

    private void OnAdminStateChanged()
    {
        DispatcherQueue?.TryEnqueue(RefreshAdminRowUi);
    }

    private void RefreshGeneralSyncUi()
    {
        _isInitializingUi = true;
        try
        {
            _appSettings = Daily_WinUI.Services.SettingsService.Load();
            CloudBehaviorSyncSwitch.IsOn = _appSettings.SyncSmartBehaviorToCloud;

            var session = App.SupabaseClient?.Auth?.CurrentSession;
            var email = session?.User?.Email;
            if (!string.IsNullOrWhiteSpace(email))
            {
                CloudAccountText.Text = $"Authenticated as {email}";
                ConnectionBadgeText.Text = "ONLINE";
                ConnectionBadgeText.Foreground = new SolidColorBrush(Color.FromArgb(255, 16, 185, 129));
                ConnectionBadgeBorder.Background = new SolidColorBrush(Color.FromArgb(34, 16, 185, 129));
                ConnectionBadgeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(85, 16, 185, 129));
            }
            else
            {
                CloudAccountText.Text = "Local-first mode (not signed into cloud user account)";
                ConnectionBadgeText.Text = "LOCAL";
                ConnectionBadgeText.Foreground = new SolidColorBrush(Color.FromArgb(255, 245, 158, 11));
                ConnectionBadgeBorder.Background = new SolidColorBrush(Color.FromArgb(34, 245, 158, 11));
                ConnectionBadgeBorder.BorderBrush = new SolidColorBrush(Color.FromArgb(85, 245, 158, 11));
            }

            var syncSvc = App.Current?.Services?.GetService<ISyncService>();
            if (syncSvc != null && !string.IsNullOrWhiteSpace(syncSvc.LastSyncMessage))
            {
                SyncStatusText.Text = syncSvc.LastSyncMessage;
            }

            // Local SQLite DB footprint
            var dbPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "DailyApp",
                "Daily.db3");

            if (File.Exists(dbPath))
            {
                var info = new FileInfo(dbPath);
                LocalDbFootprintText.Text = $"Daily.db3 · {SupabaseAdminFormatter.FormatBytes(info.Length)} · Modified {info.LastWriteTime:yyyy-MM-dd HH:mm}";
            }
            else
            {
                LocalDbFootprintText.Text = "Daily.db3 · Initialized on demand";
            }
        }
        finally
        {
            _isInitializingUi = false;
        }
    }

    private void RefreshAdminRowUi()
    {
        var creds = _admin.Credentials;
        var snap = _admin.Snapshot;

        if (creds.IsAuthenticated)
        {
            AdminConnectedBadge.Visibility = Visibility.Visible;
            AdminDisconnectButton.Visibility = Visibility.Visible;
            AdminPrimaryActionButton.Content = "Open Console";

            if (Application.Current.Resources.TryGetValue("AccentButtonStyle", out var accent) && accent is Style st)
            {
                AdminPrimaryActionButton.Style = st;
            }

            if (snap != null)
            {
                AdminSubtitleText.Text =
                    $"{creds.AdminIdentity ?? "Admin"} · {snap.Project.Name} · DB {SupabaseAdminFormatter.FormatBytes(snap.DbTotalBytes)} · Egress {snap.EgressUsedGb:F3}/{snap.EgressQuotaGb:F0} GB";
            }
            else
            {
                AdminSubtitleText.Text =
                    $"{creds.AdminIdentity ?? "Admin"} · Project {creds.SelectedProjectRef} · Ready to inspect read-only telemetry";
            }
        }
        else
        {
            AdminConnectedBadge.Visibility = Visibility.Collapsed;
            AdminDisconnectButton.Visibility = Visibility.Collapsed;
            AdminPrimaryActionButton.Content = "Admin Sign-In";

            if (Application.Current.Resources.TryGetValue("DefaultButtonStyle", out var defStyle) && defStyle is Style dst)
            {
                AdminPrimaryActionButton.Style = dst;
            }

            AdminSubtitleText.Text = "Read-only cloud quotas, DB size, egress, gateway logs, Edge Functions & Realtime";
        }
    }

    private void CloudBehaviorSyncSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_isInitializingUi) return;
        _appSettings.SyncSmartBehaviorToCloud = CloudBehaviorSyncSwitch.IsOn;
        Daily_WinUI.Services.SettingsService.Save(_appSettings);
    }

    private async void SyncNowButton_Click(object sender, RoutedEventArgs e)
    {
        var syncSvc = App.Current?.Services?.GetService<ISyncService>();
        if (syncSvc == null)
        {
            SyncStatusText.Text = "Sync service unavailable.";
            return;
        }

        SyncNowButton.IsEnabled = false;
        SyncStatusText.Text = "Synchronizing all domains with Supabase...";
        try
        {
            await syncSvc.SyncAsync(SyncScope.All);
            SyncStatusText.Text = string.IsNullOrWhiteSpace(syncSvc.LastSyncError)
                ? $"Synced at {DateTime.Now:HH:mm:ss}"
                : $"Warning: {syncSvc.LastSyncError}";
            RefreshGeneralSyncUi();
        }
        catch (Exception ex)
        {
            SyncStatusText.Text = $"Sync error: {ex.Message}";
        }
        finally
        {
            SyncNowButton.IsEnabled = true;
        }
    }

    private async void PingCloudButton_Click(object sender, RoutedEventArgs e)
    {
        PingCloudButton.IsEnabled = false;
        SyncStatusText.Text = "Measuring HTTPS latency to Supabase gateway...";
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
            var url = $"{Secrets.SupabaseUrl.TrimEnd('/')}/rest/v1/";
            using var req = new HttpRequestMessage(HttpMethod.Head, url);
            req.Headers.Add("apikey", Secrets.SupabaseKey);

            var sw = Stopwatch.StartNew();
            using var resp = await http.SendAsync(req);
            sw.Stop();
            SyncStatusText.Text = $"Gateway reachable ({(int)resp.StatusCode}) · {sw.ElapsedMilliseconds} ms";
        }
        catch (Exception ex)
        {
            SyncStatusText.Text = $"Gateway unreachable: {ex.Message}";
        }
        finally
        {
            PingCloudButton.IsEnabled = true;
        }
    }

    private async void ReloadCacheButton_Click(object sender, RoutedEventArgs e)
    {
        ReloadCacheButton.IsEnabled = false;
        try
        {
            var settingsSvc = App.Current?.Services?.GetService<ISettingsService>();
            if (settingsSvc != null)
            {
                await settingsSvc.ReloadFromDatabaseAsync();
            }
            RefreshGeneralSyncUi();
            SyncStatusText.Text = $"Local cache reloaded at {DateTime.Now:HH:mm:ss}";
        }
        catch (Exception ex)
        {
            SyncStatusText.Text = $"Cache reload warning: {ex.Message}";
        }
        finally
        {
            ReloadCacheButton.IsEnabled = true;
        }
    }

    private async void AdminPrimaryActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (_admin.Credentials.IsAuthenticated)
        {
            if (await _admin.UnlockIfNeededAsync())
            {
                Frame?.Navigate(typeof(SupabaseAdminPage));
            }
            return;
        }

        var theme = ActualTheme == ElementTheme.Default ? ElementTheme.Dark : ActualTheme;
        var loginWin = new SupabaseAdminLoginWindow(
            onAuthenticated: () =>
            {
                DispatcherQueue?.TryEnqueue(() =>
                {
                    RefreshAdminRowUi();
                    Frame?.Navigate(typeof(SupabaseAdminPage));
                });
            },
            theme: theme);
        loginWin.Activate();
    }

    private void AdminDisconnectButton_Click(object sender, RoutedEventArgs e)
    {
        _admin.Disconnect();
        RefreshAdminRowUi();
    }
}
