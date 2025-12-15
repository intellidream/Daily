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
        
#if ANDROID || IOS
        // Set initial color based on current theme
        UpdateMobileBackgroundColor();
        // Subscribe to changes
        if (Application.Current != null)
        {
            Application.Current.RequestedThemeChanged += (s, e) => UpdateMobileBackgroundColor();
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

    private void UpdateMobileBackgroundColor()
    {
        if (Application.Current == null) return;
        var theme = Application.Current.RequestedTheme;
        BackgroundColor = theme == AppTheme.Dark ? Color.FromArgb("#121212") : Colors.White;
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
            //refreshView.IsRefreshing = false; // Force direct update
        });
    }
    public void Dispose()
    {
        // Cleanup Native WebView
        if (InternalBrowser != null)
        {
            InternalBrowser.Source = "about:blank";
            InternalBrowser.Handler?.DisconnectHandler();
        }

        // Cleanup Blazor WebView
        if (blazorWebView != null)
        {
            blazorWebView.Handler?.DisconnectHandler();
        }
    }
}
