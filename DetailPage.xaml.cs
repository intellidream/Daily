using Daily.Services;
using System.Windows.Input;

namespace Daily;

public partial class DetailPage : ContentPage, IDisposable
{
    private readonly IDetailNavigationService _detailNavigationService;
    private readonly IRefreshService _refreshService;
    private readonly IRssFeedService _rssFeedService;
    private bool _isRefreshing;
    private string _currentBrowserUrl = "";
    private bool _isReaderMode = false;

    // Parameterless constructor is usually required if XAML creates it, 
    // BUT we are creating it manually in WindowManagerService, so we can define this one.
    // However, if some previewer tries to create it, might fail. 
    // Since we control creation, this is fine.
    // NOTE: This fallback constructor would need fixing if used, but for now we focus on the main one used by WindowManagerService
    public DetailPage(IRefreshService refreshService) : this(refreshService, new DetailNavigationService(), new Services.RssFeedService()) 
    {
        // Fallback constructor for previewers if needed, though dependency injection is preferred pattern
    }

    // Actual constructor used by WindowManagerService
    public DetailPage(IRefreshService refreshService, IDetailNavigationService detailNavigationService, IRssFeedService rssFeedService)
    {
        InitializeComponent();
        
        InternalBrowser.Loaded += (s, e) =>
        {
#if MACCATALYST
            ConfigureMacWebView();
#endif
        };
        
#if ANDROID || IOS || WINDOWS
        // Set initial color based on current theme, but verify in OnAppearing too
        UpdateBackgroundColor();
        
        if (Application.Current != null)
        {
            Application.Current.RequestedThemeChanged += (s, e) => UpdateBackgroundColor();
        }
#else
        BackgroundColor = Colors.Transparent;
#endif

        _refreshService = refreshService;
        _detailNavigationService = detailNavigationService;
        _rssFeedService = rssFeedService;
        
        _detailNavigationService.OnOpenUrlRequest += OnOpenUrlRequest;
        _detailNavigationService.OnBrowserStateChanged += OnBrowserStateChanged;
        _detailNavigationService.OnReaderModeChanged += OnReaderModeChanged;
        _detailNavigationService.OnToolbarHeightChanged += OnToolbarHeightChanged;

        BindingContext = this;
        RefreshCommand = new Command(async () => await ExecuteRefreshCommand());
    }

    private void OnOpenUrlRequest(string url)
    {
        Dispatcher.Dispatch(() =>
        {
            _currentBrowserUrl = url;
            InternalBrowser.Source = url;
            
            // Ensure Reader Mode is OFF when opening a fresh URL
            if (_isReaderMode)
            {
                _isReaderMode = false;
                _detailNavigationService.SetReaderMode(false);
            }
        });
    }

    private void OnBrowserStateChanged(bool isOpen)
    {
        Dispatcher.Dispatch(() =>
        {
            // Only show WebView if Browser is Open AND NOT in Reader Mode
            InternalBrowser.IsVisible = isOpen && !_isReaderMode;
            
            if (!isOpen)
            {
                 InternalBrowser.Source = "about:blank"; // Reset
                 _isReaderMode = false; 
            }
        });
    }

    private void OnReaderModeChanged(bool isEnabled)
    {
        Dispatcher.Dispatch(() =>
        {
            _isReaderMode = isEnabled;
            // Hide WebView if Reader Mode is ON (Blazor handles it)
            // Show WebView if Reader Mode is OFF (but Browser is Open)
            InternalBrowser.IsVisible = _detailNavigationService.IsBrowserOpen && !isEnabled;
        });
    }

    private void OnToolbarHeightChanged(double height)
    {
        Dispatcher.Dispatch(() =>
        {
            // Adjust top margin to avoid covering the toolbar
            // We preserve the existing side/bottom margins (0)
            InternalBrowser.Margin = new Thickness(0, height, 0, 0);
        });
    }
    
    // Reader Mode logic moved to Blazor (RssFeedDetail.razor)
    // We kept the field _isReaderMode just for local state tracking if needed, 
    // but the heavy lifting is gone.

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _detailNavigationService.OnOpenUrlRequest -= OnOpenUrlRequest;
        _detailNavigationService.OnBrowserStateChanged -= OnBrowserStateChanged;
        _detailNavigationService.OnReaderModeChanged -= OnReaderModeChanged;
        _detailNavigationService.OnToolbarHeightChanged -= OnToolbarHeightChanged;
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
#if WINDOWS
        UpdateBackgroundColor();
#endif
    }

    private void UpdateBackgroundColor()
    {
        if (Application.Current == null) return;
        
        // Ensure we are on UI thread
        Dispatcher.Dispatch(() =>
        {
             // Prioritize UserAppTheme if set, otherwise fallback to system RequestedTheme
             var theme = Application.Current.UserAppTheme;
             if (theme == AppTheme.Unspecified)
             {
                 theme = Application.Current.RequestedTheme;
             }
             
             var color = theme == AppTheme.Dark ? Color.FromArgb("#121212") : Colors.White;

             // Explicitly set background on Windows to match App Theme (fixing Light Mode spinner)
#if WINDOWS || ANDROID || IOS
             BackgroundColor = color;
             if (blazorWebView != null)
             {
                 blazorWebView.BackgroundColor = color;
             }
#endif
        });
    }



    public ICommand RefreshCommand { get; }

    public bool IsRefreshing
    {
        get => _isRefreshing;
        set
        {
            _isRefreshing = value;
            OnPropertyChanged();
        }
    }

    private async Task ExecuteRefreshCommand()
    {
        await _refreshService.TriggerDetailRefreshAsync();
        // Wait 1 second to ensure the refresh feels substantial and UI animation settles
        await Task.Delay(1000);
        Dispatcher.Dispatch(() => 
        {
            IsRefreshing = false;
        });
    }

#if MACCATALYST
    private void ConfigureMacWebView()
    {
        if (InternalBrowser.Handler?.PlatformView is WebKit.WKWebView wkWebView)
        {
            // Enable Full Screen
            if (wkWebView.Configuration.Preferences != null)
            {
                wkWebView.Configuration.Preferences.ElementFullscreenEnabled = true;
                wkWebView.Configuration.AllowsInlineMediaPlayback = true; 
                wkWebView.Configuration.AllowsPictureInPictureMediaPlayback = true;
            }
            
            // Allow Inspection for Debugging
            wkWebView.Inspectable = true;

            // Optional: User Agent (Might help with login, but Passkeys specifically rely on entitlements)
            // wkWebView.CustomUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
        }
    }
#endif

    public void Dispose()
    {
        // Cleanup Native WebView
        if (InternalBrowser != null)
        {
            InternalBrowser.Source = "about:blank";
            InternalBrowser.Handler?.DisconnectHandler();
        }
// ...

        // Cleanup Blazor WebView
        if (blazorWebView != null)
        {
            blazorWebView.Handler?.DisconnectHandler();
        }
    }
}
