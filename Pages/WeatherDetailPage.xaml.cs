using Daily.ViewModels;

namespace Daily.Pages;

public partial class WeatherDetailPage : ContentPage
{
    private readonly WeatherViewModel _weatherViewModel;

    public WeatherDetailPage(WeatherViewModel weatherViewModel)
    {
        InitializeComponent();
        _weatherViewModel = weatherViewModel;
        BindingContext = _weatherViewModel;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        await _weatherViewModel.InitializeAsync();
    }
}
