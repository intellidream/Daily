using Daily.Services;
using System.Windows.Input;

namespace Daily;

public partial class DetailPage : ContentPage
{
    private readonly IDetailNavigationService _detailNavigationService;
    private readonly IRefreshService _refreshService;
    private bool _isRefreshing;

    // Parameterless constructor is usually required if XAML creates it, 
    // BUT we are creating it manually in WindowManagerService, so we can define this one.
    // However, if some previewer tries to create it, might fail. 
    // Since we control creation, this is fine.
    public DetailPage(IRefreshService refreshService) : this(refreshService, new DetailNavigationService()) 
    {
        // Fallback constructor for previewers if needed, though dependency injection is preferred pattern
    }

    // Actual constructor used by WindowManagerService
    public DetailPage(IRefreshService refreshService, IDetailNavigationService detailNavigationService)
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
        
        _detailNavigationService.OnOpenUrlRequest += OnOpenUrlRequest;

        BindingContext = this;
        RefreshCommand = new Command(async () => await ExecuteRefreshCommand());
    }

    private void OnOpenUrlRequest(string url)
    {
        Dispatcher.Dispatch(() =>
        {
            BrowserTitle.Text = url;
            InternalBrowser.Source = url;
            BrowserContainer.IsVisible = true;
        });
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
