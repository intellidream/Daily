using Daily.Services;
using System.Windows.Input;

namespace Daily
{
    public partial class MainPage : ContentPage
    {
        private readonly IRefreshService _refreshService;
        private bool _isRefreshing;

        public MainPage(IRefreshService refreshService)
        {
            InitializeComponent();
            _refreshService = refreshService;
            BindingContext = this;
            RefreshCommand = new Command(async () => await ExecuteRefreshCommand());
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
