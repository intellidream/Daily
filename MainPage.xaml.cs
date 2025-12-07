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
            IsRefreshing = true;
            await _refreshService.TriggerRefreshAsync();
            // Add a small delay to ensure the UI updates
            await Task.Delay(500);
            IsRefreshing = false;
        }
    }
}
