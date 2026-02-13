using Daily.ViewModels;

namespace Daily.Pages;

public partial class HomePage : ContentPage
{
    private readonly WeatherViewModel _weatherViewModel;

    public HomePage(WeatherViewModel weatherViewModel)
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

    private async void OnWeatherWidgetTapped(object? sender, TappedEventArgs e)
    {
        await Navigation.PushAsync(new WeatherDetailPage(_weatherViewModel));
    }
}
