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
            // Safely retrieve the window without relying on internal types
            // Application.Current.Windows gives us the MAUI Windows.
            // We need the Native Window (Microsoft.UI.Xaml.Window).
            if (App.Current != null && App.Current.Windows.Count > 0)
            {
                var mauiWindow = App.Current.Windows.FirstOrDefault();
                if (mauiWindow?.Handler?.PlatformView is Microsoft.UI.Xaml.Window nativeWindow)
                {
                    Daily.Platforms.Windows.WindowHelpers.ApplySquareCorners(nativeWindow);
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
