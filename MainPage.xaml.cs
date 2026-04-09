using Daily.Services;
using System.Windows.Input;

namespace Daily
{
    public partial class MainPage : ContentPage
    {
        private readonly IRefreshService _refreshService;
        private readonly IBackButtonService _backButtonService;
        private bool _isRefreshing;

        public ICommand ShowCommand { get; }
        public ICommand ExitCommand { get; }

        public MainPage(IRefreshService refreshService, IBackButtonService backButtonService, IRenderedHtmlService renderedHtmlService)
        {
            InitializeComponent();
            _refreshService = refreshService;
            _backButtonService = backButtonService;

            ShowCommand = new Command(() => {
                var trayService = Application.Current?.Handler?.MauiContext?.Services.GetService<ITrayService>();
                trayService?.ClickHandler?.Invoke();
            });
            ExitCommand = new Command(() => Application.Current?.Quit());

            BindingContext = this;

            // Attach RenderedHtmlService to hidden WebView
            renderedHtmlService.Attach(RenderedWebView);

            RefreshCommand = new Command(async () => await ExecuteRefreshCommand());
        }



        protected override bool OnBackButtonPressed()
        {
            if (_backButtonService.HandleBack())
            {
                return true;
            }
            return base.OnBackButtonPressed();
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
            await _refreshService.TriggerRefreshAsync();
            // Wait 1 second to ensure the refresh feels substantial and UI animation settles
            await Task.Delay(1000);
            Dispatcher.Dispatch(() => 
            {
                IsRefreshing = false;
                //refreshView.IsRefreshing = false; // Force direct update
            });
        }

        // Expose Overlay for Mac Catalyst WindowManager
        public ContentView MacDetailOverlay => DetailOverlay;
        public Microsoft.AspNetCore.Components.WebView.Maui.BlazorWebView MainWebView => blazorWebView;
    }
}
