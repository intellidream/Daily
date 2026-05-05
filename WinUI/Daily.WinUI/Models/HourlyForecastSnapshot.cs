namespace Daily_WinUI.Models;

using Microsoft.UI.Xaml.Media.Imaging;

public sealed class HourlyForecastSnapshot
{
    public required string HourLabel { get; init; }
    public long UnixTime { get; init; }
    public string IconCode { get; init; } = "01d";
    public int Temperature { get; init; }
    public int FeelsLike { get; init; }
    public int PrecipitationChance { get; init; }
    public Uri IconUri => new($"https://openweathermap.org/img/wn/{IconCode}@2x.png");
    public BitmapImage IconImage
    {
        get
        {
            var image = new BitmapImage();
            image.UriSource = IconUri;
            return image;
        }
    }
    public string TemperatureText => $"{Temperature}°";
    public string FeelsLikeText => $"{FeelsLike}°";
    public string PrecipitationText => $"{PrecipitationChance}%";
}
