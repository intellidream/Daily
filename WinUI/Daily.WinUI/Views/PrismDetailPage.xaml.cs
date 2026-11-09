using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Services;
using Daily_WinUI.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;
using Windows.ApplicationModel.DataTransfer;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using Windows.UI;

namespace Daily_WinUI.Views;

public sealed partial class PrismDetailPage : Page
{
    private const string DesktopEdgeUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0";

    private const string PrismObserverJs = @"
(function() {
    if (window.__prismWinUIObserver) return;
    window.__prismWinUIObserver = true;

    function post(payload) {
        try {
            if (window.chrome && window.chrome.webview) {
                window.chrome.webview.postMessage(JSON.stringify(payload));
            }
        } catch (e) {}
    }

    function sniffMeta() {
        try {
            var rss = document.querySelector('link[rel=""alternate""][type*=""rss""], link[rel=""alternate""][type*=""atom""], link[rel=""alternate""][type*=""feed+json""]');
            var rssUrl = rss ? rss.href : '';
            var rssTitle = rss ? (rss.title || document.title || '') : '';
            var host = (location.hostname || '').toLowerCase();
            if (!rssUrl && host.endsWith('.substack.com') && host !== 'www.substack.com' && host !== 'open.substack.com') {
                rssUrl = location.protocol + '//' + host + '/feed';
                rssTitle = document.title || host;
            }
            var og = document.querySelector('meta[property=""og:image""], meta[name=""twitter:image""]');
            post({
                kind: 'metadata',
                title: document.title || '',
                ogImage: og ? og.content : '',
                rssUrl: rssUrl,
                rssTitle: rssTitle
            });
        } catch (e) {}
    }
    sniffMeta();

    var selTimer = null;
    document.addEventListener('selectionchange', function() {
        clearTimeout(selTimer);
        selTimer = setTimeout(function() {
            try {
                var sel = window.getSelection();
                var txt = sel ? sel.toString().trim() : '';
                if (txt.length >= 3) {
                    post({ kind: 'selection', text: txt.slice(0, 4000) });
                } else {
                    post({ kind: 'selection_clear' });
                }
            } catch (e) {}
        }, 160);
    }, { passive: true });

    window.__prismExtractDomContext = function() {
        var sel = window.getSelection ? window.getSelection().toString().trim() : '';
        var mainEl = document.querySelector('article, main, [role=""main""]') || document.body;
        var text = mainEl ? (mainEl.innerText || '').replace(/\n{3,}/g, '\n\n').trim().slice(0, 15000) : '';
        return { title: document.title || '', url: location.href, selectedText: sel.slice(0, 3000), bodyText: text };
    };
})();
";

    private readonly IPrismService _prismService;
    private readonly IRssFeedService _rssFeedService;

    private Task? _webViewInitTask;
    private CoreWebView2Environment? _sharedWebEnv;

    private string _currentUrl = string.Empty;
    private string _currentPageTitle = "Start Page";
    private string? _currentOgImageUrl;
    private string? _detectedRssUrl;
    private string? _detectedRssTitle;
    private string _selectedQuoteCandidate = string.Empty;
    private string _vaultFilterType = "all";
    private bool _isStudioPaneOpen = true;
    private bool _isReaderModeActive;
    private bool _isLoadingWeb;

    private byte[]? _pendingCropPreviewPng;
    private Point? _cropDragStart;
    private Point? _cropDragCurrent;

    private readonly List<PrismCoPilotTurn> _turns = new();

    public PrismDetailPage()
    {
        InitializeComponent();
        _prismService = App.Current.Services.GetRequiredService<IPrismService>();
        _rssFeedService = App.Current.Services.GetRequiredService<IRssFeedService>();

        Loaded += PrismDetailPage_Loaded;
        Unloaded += PrismDetailPage_Unloaded;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is string targetUrl && !string.IsNullOrWhiteSpace(targetUrl))
        {
            _prismService.RequestOpenUrlInPrism(targetUrl);
        }
    }

    private async void PrismDetailPage_Loaded(object sender, RoutedEventArgs e)
    {
        if (Frame != App.Current?.MainWindow?.RootFrame)
        {
            BackToDashboardButton.Visibility = Visibility.Collapsed;
            PopOutWindowButton.Visibility = Visibility.Collapsed;
        }

        _prismService.DataChanged -= OnPrismServiceDataChanged;
        _prismService.DataChanged += OnPrismServiceDataChanged;

        await _prismService.EnsureLoadedAsync();
        UpdateSearchEngineBadge();
        await CheckSystemClipboardAsync();
        RefreshAllUiFromService();

        await EnsureWebViewsInitializedAsync();

        string? pending = _prismService.ConsumePendingUrlRequest();
        if (!string.IsNullOrWhiteSpace(pending))
        {
            NavigateActiveTabToUrl(pending);
        }
        else
        {
            SyncViewportToActiveTab();
        }
    }

    private void PrismDetailPage_Unloaded(object sender, RoutedEventArgs e)
    {
        if (NavigationCacheMode != NavigationCacheMode.Required)
        {
            _prismService.DataChanged -= OnPrismServiceDataChanged;
        }
    }

    private void OnPrismServiceDataChanged(object? sender, EventArgs e)
    {
        DispatcherQueue?.TryEnqueue(() =>
        {
            RefreshAllUiFromService();
            string? pending = _prismService.ConsumePendingUrlRequest();
            if (!string.IsNullOrWhiteSpace(pending))
            {
                NavigateActiveTabToUrl(pending);
            }
        });
    }

    public async Task RefreshFromTitleBarAsync()
    {
        await _prismService.SyncWithRemoteAsync();
        RefreshAllUiFromService();
    }

    // ── Single-Flight WebView2 Initialization (Shared Cookies + InPrivate) ────

    private Task EnsureWebViewsInitializedAsync()
    {
        if (_webViewInitTask == null || _webViewInitTask.IsFaulted || _webViewInitTask.IsCanceled)
        {
            _webViewInitTask = InitializeWebViewsCoreAsync();
        }

        return _webViewInitTask;
    }

    private async Task InitializeWebViewsCoreAsync()
    {
        try
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string sharedUserDataFolder = Path.Combine(localAppData, "Daily.WinUI", "WebView2");
            Directory.CreateDirectory(sharedUserDataFolder);

            var envOptions = new CoreWebView2EnvironmentOptions();
            _sharedWebEnv = await CoreWebView2Environment.CreateWithOptionsAsync(null, sharedUserDataFolder, envOptions);

            await PrismWebView.EnsureCoreWebView2Async(_sharedWebEnv);
            ConfigureCoreWebView(PrismWebView.CoreWebView2, isPrivate: false);

            var privateOptions = _sharedWebEnv.CreateCoreWebView2ControllerOptions();
            privateOptions.IsInPrivateModeEnabled = true;
            await PrivateWebView.EnsureCoreWebView2Async(_sharedWebEnv, privateOptions);
            ConfigureCoreWebView(PrivateWebView.CoreWebView2, isPrivate: true);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[PrismDetailPage] WebView2 init warning: {ex.Message}");
        }
    }

    private void ConfigureCoreWebView(CoreWebView2? core, bool isPrivate)
    {
        if (core == null)
        {
            return;
        }

        core.Settings.UserAgent = DesktopEdgeUserAgent;
        core.Settings.AreDefaultScriptDialogsEnabled = true;
        core.Settings.IsStatusBarEnabled = false;

        core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, args) =>
        {
            var settings = Daily_WinUI.Services.SettingsService.Load();
            if (PrismShieldRules.ShouldBlockRequest(
                    args.Request.Uri,
                    _currentUrl,
                    settings.PrismShieldEnabled,
                    settings.PrismShieldAllowlist))
            {
                args.Response = core.Environment.CreateWebResourceResponse(null, 204, "No Content", string.Empty);
            }
        };

        core.NavigationStarting += (_, args) =>
        {
            _isLoadingWeb = true;
            WebLoadProgressBar.Visibility = Visibility.Visible;
            WebReloadIcon.Glyph = "\uE711";
            FloatingSelectionPill.Visibility = Visibility.Collapsed;

            if (!string.IsNullOrWhiteSpace(args.Uri) && !args.Uri.Equals("about:blank", StringComparison.OrdinalIgnoreCase))
            {
                _currentUrl = args.Uri;
                OmniboxTextBox.Text = args.Uri;
                _prismService.UpdateActiveTabMetadata(url: args.Uri);
                UpdateShieldIndicator();
            }
        };

        core.NavigationCompleted += async (_, _) =>
        {
            _isLoadingWeb = false;
            WebLoadProgressBar.Visibility = Visibility.Collapsed;
            WebReloadIcon.Glyph = "\uE72C";
            WebBackButton.IsEnabled = core.CanGoBack || _isReaderModeActive;
            WebForwardButton.IsEnabled = core.CanGoForward;

            if (!string.IsNullOrWhiteSpace(core.DocumentTitle))
            {
                _currentPageTitle = core.DocumentTitle;
                _prismService.UpdateActiveTabMetadata(title: core.DocumentTitle);
                RenderTabStrip();
            }

            try
            {
                await core.ExecuteScriptAsync(PrismObserverJs);
            }
            catch { }
        };

        core.DocumentTitleChanged += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(core.DocumentTitle))
            {
                _currentPageTitle = core.DocumentTitle;
                _prismService.UpdateActiveTabMetadata(title: core.DocumentTitle);
                RenderTabStrip();
            }
        };

        core.WebMessageReceived += (_, args) =>
        {
            try
            {
                string raw = args.TryGetWebMessageAsString();
                if (string.IsNullOrWhiteSpace(raw))
                {
                    return;
                }

                var msg = JObject.Parse(raw);
                string kind = msg["kind"]?.ToString() ?? string.Empty;
                switch (kind)
                {
                    case "metadata":
                        string title = msg["title"]?.ToString() ?? string.Empty;
                        if (!string.IsNullOrWhiteSpace(title))
                        {
                            _currentPageTitle = title;
                        }

                        _currentOgImageUrl = msg["ogImage"]?.ToString();
                        _detectedRssUrl = msg["rssUrl"]?.ToString();
                        _detectedRssTitle = msg["rssTitle"]?.ToString();
                        DetectedRssButton.Visibility = !string.IsNullOrWhiteSpace(_detectedRssUrl) ? Visibility.Visible : Visibility.Collapsed;
                        _prismService.UpdateActiveTabMetadata(
                            title: _currentPageTitle,
                            detectedRssUrl: string.IsNullOrWhiteSpace(_detectedRssUrl) ? null : _detectedRssUrl,
                            detectedRssTitle: string.IsNullOrWhiteSpace(_detectedRssTitle) ? null : _detectedRssTitle);
                        break;

                    case "selection":
                        string sel = msg["text"]?.ToString() ?? string.Empty;
                        if (sel.Length >= 3)
                        {
                            _selectedQuoteCandidate = sel;
                            FloatingSelectionPill.Visibility = Visibility.Visible;
                        }
                        break;

                    case "selection_clear":
                        FloatingSelectionPill.Visibility = Visibility.Collapsed;
                        break;
                }
            }
            catch { }
        };

        // Native right-click image capture into Prism Vault
        core.ContextMenuRequested += (_, args) =>
        {
            if (args.ContextMenuTarget.Kind == CoreWebView2ContextMenuTargetKind.Image &&
                !string.IsNullOrWhiteSpace(args.ContextMenuTarget.SourceUri))
            {
                string imgSrc = args.ContextMenuTarget.SourceUri;
                var saveImgItem = core.Environment.CreateContextMenuItem(
                    "Save Image to Prism Vault",
                    null,
                    CoreWebView2ContextMenuItemKind.Command);

                saveImgItem.CustomItemSelected += async (_, _) =>
                {
                    await _prismService.SaveImageClipAsync(
                        rawImageBytes: null,
                        remoteImageUrl: imgSrc,
                        sourceUrl: _currentUrl,
                        title: _currentPageTitle);
                    ShowToast("Image saved to Prism Vault");
                };

                args.MenuItems.Insert(0, saveImgItem);
            }
        };

        // OAuth / SSO popup delegation
        core.NewWindowRequested += async (_, args) =>
        {
            if (isPrivate || string.IsNullOrWhiteSpace(args.Uri))
            {
                return;
            }

            string target = args.Uri;
            bool isSsoFlow = target.Contains("accounts.google.com", StringComparison.OrdinalIgnoreCase) ||
                             target.Contains("github.com/login", StringComparison.OrdinalIgnoreCase) ||
                             target.Contains("appleid.apple.com", StringComparison.OrdinalIgnoreCase) ||
                             target.Contains("oauth", StringComparison.OrdinalIgnoreCase) ||
                             target.Contains("substack.com", StringComparison.OrdinalIgnoreCase) ||
                             target.Contains("medium.com", StringComparison.OrdinalIgnoreCase);

            if (!isSsoFlow)
            {
                args.Handled = true;
                _prismService.OpenNewTab(target);
                SyncViewportToActiveTab();
                return;
            }

            var deferral = args.GetDeferral();
            try
            {
                OAuthPopupOverlay.Visibility = Visibility.Visible;
                if (_sharedWebEnv != null && OAuthPopupWebView.CoreWebView2 == null)
                {
                    await OAuthPopupWebView.EnsureCoreWebView2Async(_sharedWebEnv);
                    OAuthPopupWebView.CoreWebView2.WindowCloseRequested += (_, _) =>
                    {
                        OAuthPopupOverlay.Visibility = Visibility.Collapsed;
                    };
                }

                if (OAuthPopupWebView.CoreWebView2 != null)
                {
                    args.NewWindow = OAuthPopupWebView.CoreWebView2;
                    args.Handled = true;
                }
            }
            catch
            {
                OAuthPopupOverlay.Visibility = Visibility.Collapsed;
            }
            finally
            {
                deferral.Complete();
            }
        };
    }

    private WebView2 ActiveWebViewControl =>
        (_prismService.GetActiveTab()?.IsPrivate == true) ? PrivateWebView : PrismWebView;

    // ── Viewport State Synchronization ────────────────────────────────────────

    private void RefreshAllUiFromService()
    {
        RenderTabStrip();
        SpeedDialGridView.ItemsSource = _prismService.PinnedSites;

        var recent = _prismService.Clips.Take(5).ToList();
        StartPageRecentItemsControl.ItemsSource = recent;
        StartPageRecentPanel.Visibility = recent.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

        string? clipCandidate = _prismService.ClipboardCandidateUrl;
        if (!string.IsNullOrWhiteSpace(clipCandidate))
        {
            ClipboardUrlText.Text = clipCandidate;
            ClipboardBanner.Visibility = Visibility.Visible;
        }
        else
        {
            ClipboardBanner.Visibility = Visibility.Collapsed;
        }

        int totalClips = _prismService.Clips.Count;
        StudioVaultTabLabel.Text = $"💎 Vault ({totalClips})";
        StudioButtonCountText.Text = totalClips > 0 ? $"Studio ({totalClips})" : "Studio";

        ApplyVaultFilter();
        UpdateShieldIndicator();
    }

    private void RenderTabStrip()
    {
        TabPillsPanel.Children.Clear();
        string? activeId = _prismService.ActiveTabId;
        var tabs = _prismService.Tabs;

        foreach (var tab in tabs)
        {
            bool isActive = tab.Id == activeId;
            var pillGrid = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };

            if (tab.IsPrivate)
            {
                pillGrid.Children.Add(new FontIcon
                {
                    Glyph = "\uE727",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 11,
                    Foreground = new SolidColorBrush(Color.FromArgb(255, 168, 85, 247))
                });
            }

            pillGrid.Children.Add(new TextBlock
            {
                Text = string.IsNullOrWhiteSpace(tab.Title) ? "Tab" : tab.Title,
                FontSize = 11.5,
                FontWeight = isActive ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.SemiBold,
                MaxWidth = 140,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = new SolidColorBrush(isActive ? Colors.White : Color.FromArgb(190, 255, 255, 255))
            });

            if (tabs.Count > 1)
            {
                var closeBtn = new Button
                {
                    Tag = tab.Id,
                    Padding = new Thickness(3, 1, 3, 1),
                    Background = new SolidColorBrush(Colors.Transparent),
                    BorderThickness = new Thickness(0),
                    CornerRadius = new CornerRadius(8),
                    Content = new FontIcon
                    {
                        Glyph = "\uE711",
                        FontFamily = new FontFamily("Segoe Fluent Icons"),
                        FontSize = 9,
                        Foreground = new SolidColorBrush(Color.FromArgb(180, 255, 255, 255))
                    }
                };
                closeBtn.Click += (s, _) =>
                {
                    if (s is Button b && b.Tag is string tid)
                    {
                        _prismService.CloseTab(tid);
                        SyncViewportToActiveTab();
                    }
                };
                pillGrid.Children.Add(closeBtn);
            }

            var tabButton = new Button
            {
                Tag = tab.Id,
                Content = pillGrid,
                Height = 32,
                Padding = new Thickness(11, 0, 9, 0),
                CornerRadius = new CornerRadius(16),
                Background = new SolidColorBrush(isActive ? Color.FromArgb(64, 0, 229, 255) : Color.FromArgb(22, 255, 255, 255)),
                BorderBrush = new SolidColorBrush(isActive ? Color.FromArgb(140, 0, 229, 255) : Color.FromArgb(36, 255, 255, 255)),
                BorderThickness = new Thickness(1)
            };

            tabButton.Click += (s, _) =>
            {
                if (s is Button b && b.Tag is string tid)
                {
                    _prismService.SelectTab(tid);
                    SyncViewportToActiveTab();
                }
            };

            TabPillsPanel.Children.Add(tabButton);
        }
    }

    private void SyncViewportToActiveTab()
    {
        var tab = _prismService.GetActiveTab();
        if (tab == null)
        {
            return;
        }

        _isReaderModeActive = false;
        ReaderModeOverlay.Visibility = Visibility.Collapsed;
        FloatingSelectionPill.Visibility = Visibility.Collapsed;

        _currentUrl = tab.Url;
        _currentPageTitle = tab.Title;
        _detectedRssUrl = tab.DetectedRssUrl;
        _detectedRssTitle = tab.DetectedRssTitle;
        OmniboxTextBox.Text = tab.Url;
        DetectedRssButton.Visibility = !string.IsNullOrWhiteSpace(_detectedRssUrl) ? Visibility.Visible : Visibility.Collapsed;
        UpdateShieldIndicator();

        if (tab.IsStartPage)
        {
            StartPageContainer.Visibility = Visibility.Visible;
            PrismWebView.Opacity = 0;
            PrismWebView.IsHitTestVisible = false;
            PrivateWebView.Opacity = 0;
            PrivateWebView.IsHitTestVisible = false;
            return;
        }

        StartPageContainer.Visibility = Visibility.Collapsed;
        if (tab.IsPrivate)
        {
            PrismWebView.Opacity = 0;
            PrismWebView.IsHitTestVisible = false;
            PrivateWebView.Opacity = 1;
            PrivateWebView.IsHitTestVisible = true;
            if (PrivateWebView.CoreWebView2 != null && !string.Equals(PrivateWebView.CoreWebView2.Source, tab.Url, StringComparison.OrdinalIgnoreCase))
            {
                PrivateWebView.CoreWebView2.Navigate(tab.Url);
            }
        }
        else
        {
            PrivateWebView.Opacity = 0;
            PrivateWebView.IsHitTestVisible = false;
            PrismWebView.Opacity = 1;
            PrismWebView.IsHitTestVisible = true;
            if (PrismWebView.CoreWebView2 != null && !string.Equals(PrismWebView.CoreWebView2.Source, tab.Url, StringComparison.OrdinalIgnoreCase))
            {
                PrismWebView.CoreWebView2.Navigate(tab.Url);
            }
        }
    }

    private async void NavigateActiveTabToUrl(string rawInput)
    {
        var settings = Daily_WinUI.Services.SettingsService.Load();
        var engine = PrismSearchEngineHelper.FromId(settings.PrismSearchEngine);
        string? resolved = PrismSearchEngineHelper.ResolveOmniboxInput(rawInput, engine);
        if (string.IsNullOrWhiteSpace(resolved))
        {
            return;
        }

        _isReaderModeActive = false;
        ReaderModeOverlay.Visibility = Visibility.Collapsed;
        _currentUrl = resolved;
        OmniboxTextBox.Text = resolved;
        _prismService.UpdateActiveTabMetadata(url: resolved, isReaderMode: false, detectedRssUrl: null, detectedRssTitle: null);

        await EnsureWebViewsInitializedAsync();
        SyncViewportToActiveTab();

        var activeCore = ActiveWebViewControl.CoreWebView2;
        if (activeCore != null && !string.Equals(activeCore.Source, resolved, StringComparison.OrdinalIgnoreCase))
        {
            activeCore.Navigate(resolved);
        }
    }

    private async Task CheckSystemClipboardAsync()
    {
        try
        {
            var settings = Daily_WinUI.Services.SettingsService.Load();
            if (!settings.PrismClipboardDetectEnabled)
            {
                return;
            }

            var content = Clipboard.GetContent();
            if (content != null && content.Contains(StandardDataFormats.Text))
            {
                string text = await content.GetTextAsync();
                _prismService.CheckClipboardCandidate(text, enabled: true);
            }
        }
        catch { }
    }

    private void UpdateSearchEngineBadge()
    {
        var engine = PrismSearchEngineHelper.FromId(Daily_WinUI.Services.SettingsService.Load().PrismSearchEngine);
        SearchEngineBadgeText.Text = engine switch
        {
            PrismSearchEngine.DuckDuckGo => "DDG",
            PrismSearchEngine.Brave => "BRV",
            PrismSearchEngine.Perplexity => "AI",
            _ => "G"
        };
    }

    private void UpdateShieldIndicator()
    {
        var settings = Daily_WinUI.Services.SettingsService.Load();
        string domain = PrismSearchEngineHelper.ExtractCleanDomain(_currentUrl);
        bool active = settings.PrismShieldEnabled &&
                      (string.IsNullOrEmpty(domain) || !settings.PrismShieldAllowlist.Any(d => string.Equals(d, domain, StringComparison.OrdinalIgnoreCase)));
        ShieldIcon.Foreground = new SolidColorBrush(active ? Color.FromArgb(255, 16, 185, 129) : Color.FromArgb(140, 255, 255, 255));
    }

    private async void ShowToast(string message)
    {
        ToastBannerText.Text = message;
        ToastBanner.Visibility = Visibility.Visible;
        await Task.Delay(2200);
        if (ToastBannerText.Text == message)
        {
            ToastBanner.Visibility = Visibility.Collapsed;
        }
    }

    // ── Command Bar & Navigation Event Handlers ───────────────────────────────

    private void BackToDashboardButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current?.MainWindow is MainWindow mw)
        {
            mw.NavigateToTab(1);
        }
    }

    private void NewTabButton_Click(object sender, RoutedEventArgs e)
    {
        _prismService.OpenNewTab(isPrivate: false);
        SyncViewportToActiveTab();
    }

    private void NewPrivateTabButton_Click(object sender, RoutedEventArgs e)
    {
        _prismService.OpenNewTab(isPrivate: true);
        SyncViewportToActiveTab();
        ShowToast("Opened Ephemeral InPrivate Tab");
    }

    private void PopOutWindowButton_Click(object sender, RoutedEventArgs e)
    {
        if (App.Current?.MainWindow is MainWindow mw)
        {
            mw.OpenDetailWindow(typeof(PrismDetailPage), string.IsNullOrWhiteSpace(_currentUrl) ? null : _currentUrl);
        }
    }

    private void WebBackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isReaderModeActive)
        {
            _isReaderModeActive = false;
            ReaderModeOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        var core = ActiveWebViewControl.CoreWebView2;
        if (core?.CanGoBack == true)
        {
            core.GoBack();
        }
    }

    private void WebForwardButton_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveWebViewControl.CoreWebView2;
        if (core?.CanGoForward == true)
        {
            core.GoForward();
        }
    }

    private void WebReloadButton_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveWebViewControl.CoreWebView2;
        if (core == null)
        {
            return;
        }

        if (_isLoadingWeb)
        {
            core.Stop();
        }
        else
        {
            core.Reload();
        }
    }

    private void OmniboxTextBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            e.Handled = true;
            NavigateActiveTabToUrl(OmniboxTextBox.Text);
        }
    }

    private void SearchEngineItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuFlyoutItem item && item.Tag is string engineId)
        {
            var settings = Daily_WinUI.Services.SettingsService.Load();
            settings.PrismSearchEngine = engineId;
            Daily_WinUI.Services.SettingsService.Save(settings);
            UpdateSearchEngineBadge();
            ShowToast($"Default search set to {item.Text}");
        }
    }

    private void ShieldToggleButton_Click(object sender, RoutedEventArgs e)
    {
        var settings = Daily_WinUI.Services.SettingsService.Load();
        string domain = PrismSearchEngineHelper.ExtractCleanDomain(_currentUrl);
        if (string.IsNullOrEmpty(domain))
        {
            settings.PrismShieldEnabled = !settings.PrismShieldEnabled;
        }
        else
        {
            int idx = settings.PrismShieldAllowlist.FindIndex(d => string.Equals(d, domain, StringComparison.OrdinalIgnoreCase));
            if (idx >= 0)
            {
                settings.PrismShieldAllowlist.RemoveAt(idx);
                settings.PrismShieldEnabled = true;
            }
            else
            {
                settings.PrismShieldAllowlist.Add(domain);
            }
        }

        Daily_WinUI.Services.SettingsService.Save(settings);
        UpdateShieldIndicator();
        ActiveWebViewControl.CoreWebView2?.Reload();
        ShowToast("Updated Prism Shield protection");
    }

    private async void DetectedRssButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_detectedRssUrl))
        {
            return;
        }

        await _prismService.SubscribeRssFeedAsync(_detectedRssUrl, _detectedRssTitle ?? _currentPageTitle);
        ShowToast("Subscribed to RSS feed in News Hub!");
    }

    private async void SaveLinkButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_currentUrl))
        {
            return;
        }

        await _prismService.SaveLinkClipAsync(_currentUrl, _currentPageTitle, _currentOgImageUrl);
        ShowToast("Saved Link to Prism Vault");
    }

    private async void PinSiteButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_currentUrl))
        {
            return;
        }

        await _prismService.TogglePinSiteAsync(_currentPageTitle, _currentUrl);
        ShowToast("Updated Speed Dial");
    }

    private async void ReaderModeButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_currentUrl))
        {
            return;
        }

        if (_isReaderModeActive)
        {
            _isReaderModeActive = false;
            ReaderModeOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        try
        {
            ShowToast("Extracting clean Reader view...");
            var article = await _rssFeedService.FetchFullArticleAsync(_currentUrl);
            string plain = Regex.Replace(article.Content ?? article.Description ?? string.Empty, "<[^>]+>", "\n");
            plain = System.Net.WebUtility.HtmlDecode(Regex.Replace(plain, @"\n{3,}", "\n\n")).Trim();

            if (string.IsNullOrWhiteSpace(plain))
            {
                var (_, bodyText, _) = await ExtractLiveDomContextAsync();
                plain = bodyText;
            }

            ReaderTitleText.Text = !string.IsNullOrWhiteSpace(article.Title) ? article.Title : _currentPageTitle;
            ReaderMetaText.Text = $"{PrismSearchEngineHelper.ExtractCleanDomain(_currentUrl)} • Distraction-Free Reader";
            ReaderBodyText.Text = string.IsNullOrWhiteSpace(plain) ? "No article body detected on this page." : plain;
            _isReaderModeActive = true;
            ReaderModeOverlay.Visibility = Visibility.Visible;
        }
        catch (Exception ex)
        {
            ShowToast($"Reader warning: {ex.Message}");
        }
    }

    private void ToggleStudioPaneButton_Click(object sender, RoutedEventArgs e)
    {
        _isStudioPaneOpen = !_isStudioPaneOpen;
        if (_isStudioPaneOpen)
        {
            WebCanvasColumn.Width = new GridLength(65, GridUnitType.Star);
            StudioSplitterColumn.Width = new GridLength(1);
            StudioPaneColumn.Width = new GridLength(35, GridUnitType.Star);
            StudioPaneRoot.Visibility = Visibility.Visible;
            StudioSplitterLine.Visibility = Visibility.Visible;
        }
        else
        {
            WebCanvasColumn.Width = new GridLength(1, GridUnitType.Star);
            StudioSplitterColumn.Width = new GridLength(0);
            StudioPaneColumn.Width = new GridLength(0);
            StudioPaneRoot.Visibility = Visibility.Collapsed;
            StudioSplitterLine.Visibility = Visibility.Collapsed;
        }
    }

    // ── Interactive Viewport Region Crop ──────────────────────────────────────

    private async void RegionCropButton_Click(object sender, RoutedEventArgs e)
    {
        var core = ActiveWebViewControl.CoreWebView2;
        if (core == null || string.IsNullOrWhiteSpace(_currentUrl))
        {
            return;
        }

        try
        {
            using var ms = new InMemoryRandomAccessStream();
            await core.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, ms);
            ms.Seek(0);

            byte[] pngBytes = new byte[ms.Size];
            using (var reader = new DataReader(ms.GetInputStreamAt(0)))
            {
                await reader.LoadAsync((uint)ms.Size);
                reader.ReadBytes(pngBytes);
            }

            ms.Seek(0);
            var bmp = new BitmapImage();
            await bmp.SetSourceAsync(ms);
            RegionCropPreviewImage.Source = bmp;

            _pendingCropPreviewPng = pngBytes;
            _cropDragStart = null;
            RegionCropRect.Visibility = Visibility.Collapsed;
            RegionCropOverlay.Visibility = Visibility.Visible;
        }
        catch (Exception ex)
        {
            ShowToast($"Snapshot capture failed: {ex.Message}");
        }
    }

    private void CancelRegionCrop_Click(object sender, RoutedEventArgs e)
    {
        RegionCropOverlay.Visibility = Visibility.Collapsed;
        _pendingCropPreviewPng = null;
    }

    private void RegionCropOverlay_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        var pt = e.GetCurrentPoint(RegionCropCanvas).Position;
        _cropDragStart = pt;
        _cropDragCurrent = pt;
        RegionCropOverlay.CapturePointer(e.Pointer);
        Canvas.SetLeft(RegionCropRect, pt.X);
        Canvas.SetTop(RegionCropRect, pt.Y);
        RegionCropRect.Width = 1;
        RegionCropRect.Height = 1;
        RegionCropRect.Visibility = Visibility.Visible;
    }

    private void RegionCropOverlay_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_cropDragStart == null)
        {
            return;
        }

        var cur = e.GetCurrentPoint(RegionCropCanvas).Position;
        _cropDragCurrent = cur;
        double x = Math.Min(_cropDragStart.Value.X, cur.X);
        double y = Math.Min(_cropDragStart.Value.Y, cur.Y);
        double w = Math.Abs(cur.X - _cropDragStart.Value.X);
        double h = Math.Abs(cur.Y - _cropDragStart.Value.Y);

        Canvas.SetLeft(RegionCropRect, x);
        Canvas.SetTop(RegionCropRect, y);
        RegionCropRect.Width = Math.Max(1, w);
        RegionCropRect.Height = Math.Max(1, h);
    }

    private async void RegionCropOverlay_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        RegionCropOverlay.ReleasePointerCapture(e.Pointer);
        var s = _cropDragStart;
        var c = _cropDragCurrent;
        var png = _pendingCropPreviewPng;

        _cropDragStart = null;
        _cropDragCurrent = null;
        RegionCropOverlay.Visibility = Visibility.Collapsed;

        if (s == null || c == null || png == null || RegionCropOverlay.ActualWidth <= 10 || RegionCropOverlay.ActualHeight <= 10)
        {
            return;
        }

        double rx = Math.Min(s.Value.X, c.Value.X) / RegionCropOverlay.ActualWidth;
        double ry = Math.Min(s.Value.Y, c.Value.Y) / RegionCropOverlay.ActualHeight;
        double rw = Math.Abs(c.Value.X - s.Value.X) / RegionCropOverlay.ActualWidth;
        double rh = Math.Abs(c.Value.Y - s.Value.Y) / RegionCropOverlay.ActualHeight;

        if (rw < 0.03 || rh < 0.03)
        {
            return;
        }

        try
        {
            byte[] croppedBytes = await CropPngRegionAsync(png, rx, ry, rw, rh);
            await _prismService.SaveImageClipAsync(
                rawImageBytes: croppedBytes,
                remoteImageUrl: null,
                sourceUrl: _currentUrl,
                title: $"{_currentPageTitle} (Snapshot)",
                tags: new[] { "snapshot" });
            ShowToast("Visual Region saved to Prism Vault!");
        }
        catch (Exception ex)
        {
            ShowToast($"Crop failed: {ex.Message}");
        }
    }

    private static async Task<byte[]> CropPngRegionAsync(byte[] pngBytes, double rx, double ry, double rw, double rh)
    {
        using var inStream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(inStream.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(pngBytes);
            await writer.StoreAsync();
        }

        var decoder = await BitmapDecoder.CreateAsync(inStream);
        uint x = (uint)Math.Clamp(Math.Round(rx * decoder.PixelWidth), 0, decoder.PixelWidth - 1);
        uint y = (uint)Math.Clamp(Math.Round(ry * decoder.PixelHeight), 0, decoder.PixelHeight - 1);
        uint w = (uint)Math.Clamp(Math.Round(rw * decoder.PixelWidth), 1, decoder.PixelWidth - x);
        uint h = (uint)Math.Clamp(Math.Round(rh * decoder.PixelHeight), 1, decoder.PixelHeight - y);

        var transform = new BitmapTransform
        {
            Bounds = new BitmapBounds { X = x, Y = y, Width = w, Height = h }
        };

        var softwareBmp = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            transform,
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);

        using var outStream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, outStream);
        encoder.SetSoftwareBitmap(softwareBmp);
        await encoder.FlushAsync();
        softwareBmp.Dispose();

        byte[] result = new byte[outStream.Size];
        using (var reader = new DataReader(outStream.GetInputStreamAt(0)))
        {
            await reader.LoadAsync((uint)outStream.Size);
            reader.ReadBytes(result);
        }

        return result;
    }

    // ── Start Page & Floating Selection Handlers ──────────────────────────────

    private void ClipboardOpen_Click(object sender, RoutedEventArgs e)
    {
        string? url = _prismService.ClipboardCandidateUrl;
        _prismService.DismissClipboardCandidate();
        if (!string.IsNullOrWhiteSpace(url))
        {
            NavigateActiveTabToUrl(url);
        }
    }

    private async void ClipboardSave_Click(object sender, RoutedEventArgs e)
    {
        string? url = _prismService.ClipboardCandidateUrl;
        _prismService.DismissClipboardCandidate();
        if (!string.IsNullOrWhiteSpace(url))
        {
            await _prismService.SaveLinkClipAsync(url, PrismSearchEngineHelper.ExtractCleanDomain(url));
            ShowToast("Saved Clipboard Link to Vault");
        }
    }

    private void ClipboardDismiss_Click(object sender, RoutedEventArgs e)
    {
        _prismService.DismissClipboardCandidate();
    }

    private async void AddSpeedDialSite_Click(object sender, RoutedEventArgs e)
    {
        var titleBox = new TextBox { PlaceholderText = "Title (e.g. GitHub)", Margin = new Thickness(0, 0, 0, 8) };
        var urlBox = new TextBox { PlaceholderText = "https://github.com", Text = _currentUrl };
        var panel = new StackPanel();
        panel.Children.Add(titleBox);
        panel.Children.Add(urlBox);

        var dialog = new ContentDialog
        {
            Title = "Pin Site to Speed Dial",
            Content = panel,
            PrimaryButtonText = "Pin Site",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Primary,
            XamlRoot = XamlRoot
        };

        if (await dialog.ShowAsync() == ContentDialogResult.Primary && !string.IsNullOrWhiteSpace(urlBox.Text))
        {
            await _prismService.TogglePinSiteAsync(titleBox.Text, urlBox.Text);
            ShowToast("Pinned to Speed Dial");
        }
    }

    private void SpeedDialGridView_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is PrismPinnedSite site)
        {
            NavigateActiveTabToUrl(site.Url);
        }
    }

    private async void RemoveSpeedDialPin_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string pinId)
        {
            await _prismService.DeletePinnedSiteAsync(pinId);
        }
    }

    private void RecentClipRow_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string url && !string.IsNullOrWhiteSpace(url))
        {
            NavigateActiveTabToUrl(url);
        }
    }

    private async void SelectionSaveQuote_Click(object sender, RoutedEventArgs e)
    {
        FloatingSelectionPill.Visibility = Visibility.Collapsed;
        if (string.IsNullOrWhiteSpace(_selectedQuoteCandidate))
        {
            return;
        }

        await _prismService.SaveQuoteClipAsync(_selectedQuoteCandidate, _currentUrl, _currentPageTitle);
        ShowToast("Saved Quote to Prism Vault");
    }

    private async void SelectionSendTagdos_Click(object sender, RoutedEventArgs e)
    {
        FloatingSelectionPill.Visibility = Visibility.Collapsed;
        if (string.IsNullOrWhiteSpace(_selectedQuoteCandidate))
        {
            return;
        }

        var clip = await _prismService.SaveQuoteClipAsync(_selectedQuoteCandidate, _currentUrl, _currentPageTitle);
        await _prismService.SendClipToTagdosAsync(clip);
        ShowToast("Sent Quote to TagDoS (#prism)");
    }

    private async void SelectionExplain_Click(object sender, RoutedEventArgs e)
    {
        FloatingSelectionPill.Visibility = Visibility.Collapsed;
        if (!_isStudioPaneOpen)
        {
            ToggleStudioPaneButton_Click(sender, e);
        }

        StudioTabCoPilotBtn_Click(sender, e);
        await ExecuteCoPilotActionAsync(PrismCoPilotAction.ExplainSelection, _selectedQuoteCandidate);
    }

    private void CloseOAuthPopup_Click(object sender, RoutedEventArgs e)
    {
        OAuthPopupOverlay.Visibility = Visibility.Collapsed;
    }

    // ── Prism Studio Tabs (`Co-Pilot` & `Vault`) ──────────────────────────────

    private void StudioTabCoPilotBtn_Click(object sender, RoutedEventArgs e)
    {
        CoPilotPaneGrid.Visibility = Visibility.Visible;
        VaultPaneGrid.Visibility = Visibility.Collapsed;
        StudioTabCoPilotBtn.Background = new SolidColorBrush(Color.FromArgb(51, 0, 229, 255));
        StudioTabVaultBtn.Background = new SolidColorBrush(Colors.Transparent);
    }

    private void StudioTabVaultBtn_Click(object sender, RoutedEventArgs e)
    {
        CoPilotPaneGrid.Visibility = Visibility.Collapsed;
        VaultPaneGrid.Visibility = Visibility.Visible;
        StudioTabVaultBtn.Background = new SolidColorBrush(Color.FromArgb(51, 0, 229, 255));
        StudioTabCoPilotBtn.Background = new SolidColorBrush(Colors.Transparent);
        ApplyVaultFilter();
    }

    private async Task<(string Title, string BodyText, string SelectedText)> ExtractLiveDomContextAsync()
    {
        var core = ActiveWebViewControl.CoreWebView2;
        if (core == null || string.IsNullOrWhiteSpace(_currentUrl))
        {
            return (_currentPageTitle, string.Empty, _selectedQuoteCandidate);
        }

        try
        {
            string jsonResult = await core.ExecuteScriptAsync("window.__prismExtractDomContext ? window.__prismExtractDomContext() : ({ title: document.title, bodyText: document.body ? document.body.innerText.slice(0, 12000) : '', selectedText: '' })");
            if (!string.IsNullOrWhiteSpace(jsonResult) && jsonResult != "null")
            {
                var obj = JObject.Parse(jsonResult);
                string title = obj["title"]?.ToString() ?? _currentPageTitle;
                string body = obj["bodyText"]?.ToString() ?? string.Empty;
                string sel = obj["selectedText"]?.ToString() ?? _selectedQuoteCandidate;
                return (title, body, sel);
            }
        }
        catch { }

        return (_currentPageTitle, string.Empty, _selectedQuoteCandidate);
    }

    private async Task ExecuteCoPilotActionAsync(PrismCoPilotAction action, string? explicitSelection = null)
    {
        CoPilotSpinner.Visibility = Visibility.Visible;
        CoPilotSpinner.IsActive = true;
        try
        {
            var (title, body, sel) = await ExtractLiveDomContextAsync();
            string effectiveSel = !string.IsNullOrWhiteSpace(explicitSelection) ? explicitSelection : sel;
            var turn = await _prismService.RunCoPilotActionAsync(action, title, _currentUrl, body, effectiveSel);
            _turns.Insert(0, turn);
            RenderCoPilotTurns();
        }
        finally
        {
            CoPilotSpinner.IsActive = false;
            CoPilotSpinner.Visibility = Visibility.Collapsed;
        }
    }

    private async void CoPilotTldr_Click(object sender, RoutedEventArgs e) => await ExecuteCoPilotActionAsync(PrismCoPilotAction.TldrSummary);
    private async void CoPilotTasks_Click(object sender, RoutedEventArgs e) => await ExecuteCoPilotActionAsync(PrismCoPilotAction.ExtractTasks);
    private async void CoPilotFacts_Click(object sender, RoutedEventArgs e) => await ExecuteCoPilotActionAsync(PrismCoPilotAction.KeyFactsAndNumbers);
    private async void CoPilotExplain_Click(object sender, RoutedEventArgs e) => await ExecuteCoPilotActionAsync(PrismCoPilotAction.ExplainSelection);

    private void CoPilotQuestionBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == Windows.System.VirtualKey.Enter)
        {
            e.Handled = true;
            CoPilotSendQuestion_Click(sender, e);
        }
    }

    private async void CoPilotSendQuestion_Click(object sender, RoutedEventArgs e)
    {
        string question = CoPilotQuestionBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(question))
        {
            return;
        }

        CoPilotQuestionBox.Text = string.Empty;
        CoPilotSpinner.Visibility = Visibility.Visible;
        CoPilotSpinner.IsActive = true;
        try
        {
            var (title, body, sel) = await ExtractLiveDomContextAsync();
            var turn = await _prismService.AskCoPilotQuestionAsync(question, title, _currentUrl, body, sel);
            _turns.Insert(0, turn);
            RenderCoPilotTurns();
        }
        finally
        {
            CoPilotSpinner.IsActive = false;
            CoPilotSpinner.Visibility = Visibility.Collapsed;
        }
    }

    private void RenderCoPilotTurns()
    {
        CoPilotTurnsStack.Children.Clear();
        CoPilotEmptyHint.Visibility = _turns.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        foreach (var turn in _turns)
        {
            var stack = new StackPanel { Spacing = 6 };
            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var promptText = new TextBlock
            {
                Text = turn.Prompt,
                FontSize = 12,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                Foreground = new SolidColorBrush(Color.FromArgb(255, 0, 229, 255)),
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            var badgeText = new TextBlock
            {
                Text = turn.EngineBadge,
                FontSize = 10,
                Foreground = new SolidColorBrush(Color.FromArgb(180, 168, 85, 247))
            };
            Grid.SetColumn(badgeText, 1);
            header.Children.Add(promptText);
            header.Children.Add(badgeText);
            stack.Children.Add(header);

            stack.Children.Add(new TextBlock
            {
                Text = turn.ResponseMarkdown,
                FontSize = 12,
                LineHeight = 18,
                TextWrapping = TextWrapping.Wrap,
                IsTextSelectionEnabled = true
            });

            foreach (string bullet in turn.KeyBullets)
            {
                stack.Children.Add(new TextBlock
                {
                    Text = $"• {bullet}",
                    FontSize = 11.5,
                    TextWrapping = TextWrapping.Wrap,
                    Opacity = 0.88
                });
            }

            var actionsRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Margin = new Thickness(0, 4, 0, 0) };
            var saveAiBtn = new Button { Content = "Save AI Note", Padding = new Thickness(8, 3, 8, 3), CornerRadius = new CornerRadius(8), FontSize = 11 };
            var capturedTurn = turn;
            saveAiBtn.Click += async (_, _) =>
            {
                await _prismService.SaveAiSummaryClipAsync(capturedTurn);
                ShowToast("Saved AI Note to Prism Vault");
            };
            actionsRow.Children.Add(saveAiBtn);

            if (turn.SuggestedTasks.Count > 0)
            {
                var sendTasksBtn = new Button { Content = "→ Tasks to TagDoS", Padding = new Thickness(8, 3, 8, 3), CornerRadius = new CornerRadius(8), FontSize = 11 };
                sendTasksBtn.Click += async (_, _) =>
                {
                    await _prismService.SendTasksToTagdosAsync(capturedTurn.SuggestedTasks, capturedTurn.PageTitle, capturedTurn.SourceUrl);
                    ShowToast("Sent Tasks to TagDoS (#prism)");
                };
                actionsRow.Children.Add(sendTasksBtn);
            }

            stack.Children.Add(actionsRow);

            CoPilotTurnsStack.Children.Add(new Border
            {
                Padding = new Thickness(12, 10, 12, 10),
                CornerRadius = new CornerRadius(12),
                Background = new SolidColorBrush(Color.FromArgb(22, 255, 255, 255)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                BorderThickness = new Thickness(1),
                Child = stack
            });
        }
    }

    // ── Vault Filter & Item Actions ───────────────────────────────────────────

    private void VaultSearchBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyVaultFilter();

    private void VaultFilterChip_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string filterTag)
        {
            _vaultFilterType = filterTag;
            ApplyVaultFilter();
        }
    }

    private void ApplyVaultFilter()
    {
        string query = (VaultSearchBox?.Text ?? string.Empty).Trim();
        var filtered = _prismService.Clips.AsEnumerable();

        if (_vaultFilterType != "all")
        {
            var expected = PrismClipTypeExtensions.FromRawValue(_vaultFilterType);
            filtered = filtered.Where(c => c.ClipType == expected);
        }

        if (!string.IsNullOrEmpty(query))
        {
            string cleanTag = query.TrimStart('#');
            filtered = filtered.Where(c =>
                c.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                c.ContentText.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                c.Domain.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                c.Tags.Any(t => t.Contains(cleanTag, StringComparison.OrdinalIgnoreCase)));
        }

        if (VaultClipsListView != null)
        {
            VaultClipsListView.ItemsSource = filtered.ToList();
        }
    }

    private void VaultClipOpen_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string url && !string.IsNullOrWhiteSpace(url))
        {
            NavigateActiveTabToUrl(url);
        }
    }

    private async void VaultClipSendTagdos_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string clipId)
        {
            var clip = _prismService.Clips.FirstOrDefault(c => c.Id == clipId);
            if (clip != null)
            {
                await _prismService.SendClipToTagdosAsync(clip);
                ShowToast("Mirrored Clip to TagDoS (#prism)");
            }
        }
    }

    private async void VaultClipReadLater_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string clipId)
        {
            var clip = _prismService.Clips.FirstOrDefault(c => c.Id == clipId);
            if (clip != null)
            {
                await _prismService.SaveClipToReadLaterAsync(clip);
                ShowToast("Saved to News Read Later");
            }
        }
    }

    private async void VaultClipDelete_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string clipId)
        {
            await _prismService.DeleteClipAsync(clipId);
            ShowToast("Removed from Prism Vault");
        }
    }
}
