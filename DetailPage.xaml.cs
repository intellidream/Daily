using Daily.Services;
using System.Windows.Input;

namespace Daily;

public partial class DetailPage : ContentPage
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

        BindingContext = this;
        RefreshCommand = new Command(async () => await ExecuteRefreshCommand());
    }

    private void OnOpenUrlRequest(string url)
    {
        Dispatcher.Dispatch(() =>
        {
            _currentBrowserUrl = url;
            // Reset Reader Mode on new URL
            _isReaderMode = false;
            ReaderButton.Text = "📖"; // or icon code
            
            BrowserTitle.Text = url;
            InternalBrowser.Source = url;
            BrowserContainer.IsVisible = true;
        });
    }

    private async void OnReaderModeClicked(object sender, EventArgs e)
    {
        if (string.IsNullOrEmpty(_currentBrowserUrl)) return;

        try
        {
            _isReaderMode = !_isReaderMode;
            
            if (_isReaderMode)
            {
                ReaderButton.TextColor = Colors.DeepSkyBlue; // Active indicator
                InternalBrowser.Source = new HtmlWebViewSource { Html = "<html><body style='background-color: transparent;'><h3>Loading Reader View...</h3></body></html>" };

                // Use a cancellation token if possible, or just check state after await
                var article = await _rssFeedService.FetchFullArticleAsync(_currentBrowserUrl);
                
                // Safety Check: If window closed during await, `InternalBrowser` might be invalid or we shouldn't update.
                // In MAUI, checking IsLoaded or similar is tricky across platforms, but Dispatcher.Dispatch usually handles thread safety.
                // However, accessing WebView properties after disposal is fatal.
                if (!this.IsLoaded) return; 

                if (article != null && !string.IsNullOrEmpty(article.Content))
                {
                    // Basic styling for reader view
                    string html = $@"
                        <html>
                        <head>
                            <meta name='viewport' content='width=device-width, initial-scale=1.0'>
                            <style>
                                body {{ font-family: 'Segoe UI', sans-serif; line-height: 1.6; padding: 20px; color: #333; }}
                                img {{ max-width: 100%; height: auto; border-radius: 8px; }}
                                h1 {{ font-size: 24px; }}
                                p {{ font-size: 18px; }}
                                @media (prefers-color-scheme: dark) {{
                                    body {{ background-color: #1E1E1E; color: #EEE; }}
                                    a {{ color: #4CC9F0; }}
                                }}
                            </style>
                        </head>
                        <body>
                            <h1>{article.Title}</h1>
                            {article.Content}
                        </body>
                        </html>";
                    
                    Dispatcher.Dispatch(() =>
                    {
                        try { InternalBrowser.Source = new HtmlWebViewSource { Html = html }; } catch { }
                    });
                }
                else
                {
                    // Fallback if failed
                    Dispatcher.Dispatch(() =>
                    {
                        try { InternalBrowser.Source = new HtmlWebViewSource { Html = "<html><body><h3>Reader view unavailable.</h3></body></html>" }; } catch { }
                    });
                }
            }
            else
            {
                 ReaderButton.TextColor = Application.Current?.RequestedTheme == AppTheme.Dark ? Colors.White : Colors.Black;
                 InternalBrowser.Source = _currentBrowserUrl;
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error in Reader Mode toggle: {ex.Message}");
            // Swallow crash if UI is disposing
        }
    }

    private void OnBrowserCloseClicked(object sender, EventArgs e)
    {
        BrowserContainer.IsVisible = false;
        InternalBrowser.Source = "about:blank"; // Reset
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _detailNavigationService.OnOpenUrlRequest -= OnOpenUrlRequest;
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
}
