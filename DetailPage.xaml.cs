using Daily.Services;
using System.Windows.Input;

namespace Daily;

public partial class DetailPage : ContentPage
{
    private readonly IRefreshService _refreshService;
    private bool _isRefreshing;

    // Parameterless constructor is usually required if XAML creates it, 
    // BUT we are creating it manually in WindowManagerService, so we can define this one.
    // However, if some previewer tries to create it, might fail. 
    // Since we control creation, this is fine.
    public DetailPage(IRefreshService refreshService)
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
        await Task.Delay(500);
        IsRefreshing = false;
    }
}
