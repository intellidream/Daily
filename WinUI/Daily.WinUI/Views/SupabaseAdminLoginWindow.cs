using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using Daily_WinUI.Models;
using Daily_WinUI.Services;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Web.WebView2.Core;
using Windows.Graphics;
using Windows.UI;

namespace Daily_WinUI.Views;

public sealed class SupabaseAdminLoginWindow : Window
{
    private readonly SupabaseCliHandshakeSession _handshake;
    private readonly Action _onAuthenticated;
    private readonly ElementTheme _theme;

    private readonly WebView2 _webView;
    private readonly ProgressRing _progressRing;
    private readonly StackPanel _patDrawer;
    private readonly PasswordBox _patPasswordBox;
    private readonly Button _patConnectButton;
    private readonly Border _errorBanner;
    private readonly TextBlock _errorText;

    private IntPtr _hWnd = IntPtr.Zero;
    private bool _handshakeDelivered;
    private bool _recoveredRedirect;

    private Windows.Foundation.TypedEventHandler<CoreWebView2, CoreWebView2DOMContentLoadedEventArgs>? _domLoadedHandler;
    private Windows.Foundation.TypedEventHandler<CoreWebView2, CoreWebView2NavigationCompletedEventArgs>? _navCompletedHandler;
    private Windows.Foundation.TypedEventHandler<CoreWebView2, CoreWebView2WebMessageReceivedEventArgs>? _webMsgHandler;
    private Windows.Foundation.TypedEventHandler<CoreWebView2, CoreWebView2NewWindowRequestedEventArgs>? _newWinHandler;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    public SupabaseAdminLoginWindow(Action onAuthenticated, ElementTheme theme = ElementTheme.Dark)
    {
        _handshake = SupabaseAdminService.CreateHandshakeSession("DayOne-Windows11");
        _onAuthenticated = onAuthenticated;
        _theme = theme == ElementTheme.Default ? ElementTheme.Dark : theme;

        Title = "DayOne – Supabase Admin Sign-In";
        SystemBackdrop = new MicaBackdrop();
        App.Current.RegisterSecondaryWindow(this);

        var rootGrid = new Grid
        {
            RequestedTheme = _theme,
            Background = new SolidColorBrush(Colors.Transparent)
        };
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Header
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // PAT Drawer
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Error Banner
        rootGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // WebView2

        // 1. Header Bar
        var headerBorder = new Border
        {
            Padding = new Thickness(20, 14, 20, 14),
            BorderThickness = new Thickness(0, 0, 0, 1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(28, 255, 255, 255))
        };
        var headerGrid = new Grid();
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var titleStack = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        titleStack.Children.Add(new TextBlock
        {
            Text = "Supabase Cloud Admin Sign-In",
            FontSize = 16,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });
        titleStack.Children.Add(new TextBlock
        {
            Text = "Sign in with GitHub via P-256 ECDH CLI Login (Read-Only Telemetry) or paste an sbp_... token.",
            FontSize = 11.5,
            Opacity = 0.68,
            TextWrapping = TextWrapping.Wrap
        });
        headerGrid.Children.Add(titleStack);

        var togglePatButton = new Button
        {
            Content = "Use PAT (sbp_...)",
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(12, 0, 0, 0)
        };
        Grid.SetColumn(togglePatButton, 1);
        headerGrid.Children.Add(togglePatButton);
        headerBorder.Child = headerGrid;
        Grid.SetRow(headerBorder, 0);
        rootGrid.Children.Add(headerBorder);

        // 2. Collapsible PAT Drawer
        _patDrawer = new StackPanel
        {
            Visibility = Visibility.Collapsed,
            Spacing = 8,
            Padding = new Thickness(20, 12, 20, 12),
            Background = new SolidColorBrush(Color.FromArgb(22, 56, 189, 248))
        };
        _patDrawer.Children.Add(new TextBlock
        {
            Text = "Manual Personal Access Token (https://supabase.com/dashboard/account/tokens)",
            FontSize = 11.5,
            Opacity = 0.78
        });

        var patRow = new Grid { ColumnSpacing = 10 };
        patRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        patRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        _patPasswordBox = new PasswordBox
        {
            PlaceholderText = "sbp_010203040506070809..."
        };
        patRow.Children.Add(_patPasswordBox);

        _patConnectButton = new Button
        {
            Content = "Connect PAT"
        };
        if (Application.Current.Resources.TryGetValue("AccentButtonStyle", out var accentStyle) && accentStyle is Style st)
        {
            _patConnectButton.Style = st;
        }
        _patConnectButton.Click += PatConnectButton_Click;
        Grid.SetColumn(_patConnectButton, 1);
        patRow.Children.Add(_patConnectButton);

        _patDrawer.Children.Add(patRow);
        Grid.SetRow(_patDrawer, 1);
        rootGrid.Children.Add(_patDrawer);

        togglePatButton.Click += (_, _) =>
        {
            bool opening = _patDrawer.Visibility != Visibility.Visible;
            _patDrawer.Visibility = opening ? Visibility.Visible : Visibility.Collapsed;
            togglePatButton.Content = opening ? "Hide PAT" : "Use PAT (sbp_...)";
        };

        // 3. Error Banner
        _errorBanner = new Border
        {
            Visibility = Visibility.Collapsed,
            Background = new SolidColorBrush(Color.FromArgb(48, 239, 68, 68)),
            Padding = new Thickness(20, 10, 20, 10)
        };
        _errorText = new TextBlock
        {
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap
        };
        _errorBanner.Child = _errorText;
        Grid.SetRow(_errorBanner, 2);
        rootGrid.Children.Add(_errorBanner);

        // 4. Embedded WebView2 + Spinner
        var webContainer = new Grid();
        _webView = new WebView2
        {
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
            DefaultBackgroundColor = _theme == ElementTheme.Dark
                ? Color.FromArgb(255, 16, 18, 24)
                : Color.FromArgb(255, 245, 247, 250)
        };
        _progressRing = new ProgressRing
        {
            IsActive = true,
            Width = 44,
            Height = 44,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        webContainer.Children.Add(_webView);
        webContainer.Children.Add(_progressRing);
        Grid.SetRow(webContainer, 3);
        rootGrid.Children.Add(webContainer);

        Content = rootGrid;

        Activated += OnWindowActivated;
        Closed += OnWindowClosed;
    }

    private async void PatConnectButton_Click(object sender, RoutedEventArgs e)
    {
        var raw = _patPasswordBox.Password?.Trim() ?? string.Empty;
        if (string.IsNullOrEmpty(raw))
        {
            ShowError("Please paste a valid Supabase Personal Access Token starting with sbp_.");
            return;
        }

        _patConnectButton.IsEnabled = false;
        _errorBanner.Visibility = Visibility.Collapsed;

        try
        {
            await SupabaseAdminService.Shared.AuthenticateWithPersonalAccessTokenAsync(raw);
            _handshakeDelivered = true;
            _onAuthenticated();
            Close();
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
            _patConnectButton.IsEnabled = true;
        }
    }

    private async void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        Activated -= OnWindowActivated;

        try
        {
            _hWnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var windowId = Win32Interop.GetWindowIdFromWindow(_hWnd);
            var appWindow = AppWindow.GetFromWindowId(windowId);
            appWindow.SetIcon("Assets/AppIcon.ico");

            var displayArea = DisplayArea.GetFromWindowId(windowId, DisplayAreaFallback.Primary);
            var workArea = displayArea.WorkArea;
            double scale = Math.Max(1.0, GetDpiForWindow(_hWnd) / 96.0);
            int w = Math.Min((int)(860 * scale), workArea.Width - 40);
            int h = Math.Min((int)(740 * scale), workArea.Height - 40);
            int x = workArea.X + (workArea.Width - w) / 2;
            int y = workArea.Y + (workArea.Height - h) / 2;
            appWindow.MoveAndResize(new RectInt32(x, y, w, h));

            int dark = _theme == ElementTheme.Dark ? 1 : 0;
            DwmSetWindowAttribute(_hWnd, 20, ref dark, sizeof(int));
        }
        catch { }

        try
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string userDataFolder = Path.Combine(localAppData, "Daily.WinUI", "WebView2");
            Directory.CreateDirectory(userDataFolder);

            var options = new CoreWebView2EnvironmentOptions();
            var env = await CoreWebView2Environment.CreateWithOptionsAsync(null, userDataFolder, options);
            await _webView.EnsureCoreWebView2Async(env);

            var core = _webView.CoreWebView2;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsStatusBarEnabled = false;

            await core.AddScriptToExecuteOnDocumentCreatedAsync(BuildVerificationHookScript());

            _newWinHandler = (s, newWinArgs) =>
            {
                if (!string.IsNullOrEmpty(newWinArgs.Uri))
                {
                    newWinArgs.Handled = true;
                    s.Navigate(newWinArgs.Uri);
                }
            };

            _domLoadedHandler = (_, _) =>
            {
                _progressRing.IsActive = false;
                _progressRing.Visibility = Visibility.Collapsed;
            };

            _navCompletedHandler = (s, _) =>
            {
                _progressRing.IsActive = false;
                _progressRing.Visibility = Visibility.Collapsed;

                var current = s.Source ?? string.Empty;
                if (!_handshakeDelivered && !_recoveredRedirect &&
                    (current.Contains("supabase.com/dashboard/projects", StringComparison.OrdinalIgnoreCase) ||
                     current.Contains("supabase.com/dashboard/org", StringComparison.OrdinalIgnoreCase)) &&
                    !current.Contains("/cli/login", StringComparison.OrdinalIgnoreCase))
                {
                    _recoveredRedirect = true;
                    s.Navigate(_handshake.AuthorizeUri.ToString());
                }
            };

            _webMsgHandler = async (_, msgArgs) =>
            {
                if (_handshakeDelivered) return;
                try
                {
                    var rawJson = msgArgs.WebMessageAsJson;
                    using var doc = JsonDocument.Parse(rawJson);
                    var root = doc.RootElement;
                    if (root.ValueKind == JsonValueKind.String)
                    {
                        using var nested = JsonDocument.Parse(root.GetString() ?? "{}");
                        await HandleHandshakePayloadAsync(nested.RootElement);
                    }
                    else
                    {
                        await HandleHandshakePayloadAsync(root);
                    }
                }
                catch (Exception ex)
                {
                    ShowError($"CLI handshake failed: {ex.Message}");
                }
            };

            core.NewWindowRequested += _newWinHandler;
            core.DOMContentLoaded += _domLoadedHandler;
            core.NavigationCompleted += _navCompletedHandler;
            core.WebMessageReceived += _webMsgHandler;

            _webView.Source = _handshake.AuthorizeUri;
        }
        catch (Exception ex)
        {
            _progressRing.IsActive = false;
            _progressRing.Visibility = Visibility.Collapsed;
            ShowError($"WebView2 initialization failed: {ex.Message}. You can connect directly using a Personal Access Token (sbp_...) above.");
            _patDrawer.Visibility = Visibility.Visible;
        }
    }

    private async Task HandleHandshakePayloadAsync(JsonElement el)
    {
        if (_handshakeDelivered || el.ValueKind != JsonValueKind.Object) return;
        if (!el.TryGetProperty("deviceCode", out var codeProp)) return;
        var deviceCode = codeProp.GetString()?.Trim();
        if (string.IsNullOrEmpty(deviceCode)) return;

        string? dashJson = el.TryGetProperty("dashJson", out var dProp) && dProp.ValueKind == JsonValueKind.String
            ? dProp.GetString()
            : null;

        _handshakeDelivered = true;
        DispatcherQueue.TryEnqueue(() =>
        {
            _progressRing.IsActive = true;
            _progressRing.Visibility = Visibility.Visible;
            _errorBanner.Visibility = Visibility.Collapsed;
        });

        try
        {
            await SupabaseAdminService.Shared.CompleteCliHandshakeAsync(_handshake, deviceCode, dashJson);
            DispatcherQueue.TryEnqueue(() =>
            {
                _onAuthenticated();
                Close();
            });
        }
        catch (Exception ex)
        {
            _handshakeDelivered = false;
            DispatcherQueue.TryEnqueue(() =>
            {
                _progressRing.IsActive = false;
                _progressRing.Visibility = Visibility.Collapsed;
                ShowError(ex.Message);
            });
        }
    }

    private void ShowError(string message)
    {
        _errorText.Text = message;
        _errorBanner.Visibility = Visibility.Visible;
    }

    private static string BuildVerificationHookScript() => """
        (function() {
            if (window.__dayOneSupaHookInstalled) return;
            window.__dayOneSupaHookInstalled = true;
            var sent = false;
            var emptyDashRetries = 0;
            function deliverCode(codeVal) {
                var dash = null;
                try { dash = window.localStorage.getItem('supabase.dashboard.auth.token'); } catch(e) {}
                if (!dash && emptyDashRetries < 3) {
                    emptyDashRetries++;
                    return;
                }
                sent = true;
                window.chrome.webview.postMessage({ deviceCode: codeVal, dashJson: dash });
            }
            function checkPage() {
                if (sent) return;
                try {
                    var href = String(window.location.href || '');
                    if (href.indexOf('supabase.com/dashboard/cli/login') === -1) return;
                    var params = new URLSearchParams(window.location.search || '');
                    var qCode = (params.get('device_code') || '').trim();
                    if (qCode.length > 0) {
                        deliverCode(qCode);
                        return;
                    }
                    var inputs = document.querySelectorAll('input[readonly], input[type="text"], code');
                    for (var i = 0; i < inputs.length; i++) {
                        var v = (inputs[i].value || inputs[i].textContent || '').trim();
                        if (/^[a-f0-9]{8}$/i.test(v)) {
                            deliverCode(v);
                            return;
                        }
                    }
                    var bodyTxt = (document.body && document.body.innerText) ? document.body.innerText : '';
                    if (bodyTxt.indexOf('verification code') !== -1 || bodyTxt.indexOf('Verification Code') !== -1 || bodyTxt.indexOf('Enter this code') !== -1) {
                        var m = bodyTxt.match(/\b([a-f0-9]{8})\b/i);
                        if (m && m[1]) {
                            deliverCode(m[1]);
                        }
                    }
                } catch (err) {}
            }
            setInterval(checkPage, 400);
            document.addEventListener('DOMContentLoaded', checkPage);
        })();
        """;

    private void OnWindowClosed(object sender, WindowEventArgs args)
    {
        Closed -= OnWindowClosed;
        try
        {
            if (_webView?.CoreWebView2 is CoreWebView2 core)
            {
                if (_newWinHandler != null) core.NewWindowRequested -= _newWinHandler;
                if (_domLoadedHandler != null) core.DOMContentLoaded -= _domLoadedHandler;
                if (_navCompletedHandler != null) core.NavigationCompleted -= _navCompletedHandler;
                if (_webMsgHandler != null) core.WebMessageReceived -= _webMsgHandler;
            }
        }
        catch { }
    }
}
