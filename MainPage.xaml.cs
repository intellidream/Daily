using Daily.Services;
using System.Windows.Input;

namespace Daily
{
    public partial class MainPage : ContentPage
    {
        private readonly IRefreshService _refreshService;
        private readonly IBackButtonService _backButtonService;
        private bool _isRefreshing;

        public MainPage(IRefreshService refreshService, IBackButtonService backButtonService)
        {
            InitializeComponent();
            _refreshService = refreshService;
            _backButtonService = backButtonService;
            BindingContext = this;
            RefreshCommand = new Command(async () => await ExecuteRefreshCommand());
        }

        protected override void OnHandlerChanged()
        {
            base.OnHandlerChanged();
#if WINDOWS
            if (Handler?.PlatformView is Microsoft.UI.Xaml.Controls.ContentPanel panel)
            {
                // We need the Window, not just the Panel. 
                // In MAUI Windows, Application.Current.Windows or just accessing the App Window is tricky from a Page.
                // However, the cleanest way is often via the window associated with the page handler.
                // Actually, the easiest way to get the window safely in MainPage is:
                var window = App.Current.Windows.FirstOrDefault()?.Handler?.PlatformView as Microsoft.UI.Xaml.Window;
                if (window != null)
                {
                   Daily.Platforms.Windows.WindowHelpers.ApplySquareCorners(window);
                }
            }
#endif
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
    }
}
