using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using System.Text;
using Windows.Storage.Streams;

namespace Daily_WinUI.Services;

/// <summary>
/// Shared helper that generates and loads weather SVG art into an Image control.
/// Extracted as a standalone async Task to avoid async-void + using-disposal bugs
/// that occur when awaiting inside DispatcherQueue.TryEnqueue lambdas.
/// </summary>
public static class WeatherBannerLoader
{
    public static async Task LoadAsync(Image target, string iconCode)
    {
        var svg = WeatherTopBarGenerator.Generate(iconCode);
        var bytes = Encoding.UTF8.GetBytes(svg);

        // Keep the stream alive for the full duration of SetSourceAsync
        var ms = new InMemoryRandomAccessStream();
        try
        {
            using (var writer = new DataWriter(ms.GetOutputStreamAt(0)))
            {
                writer.WriteBytes(bytes);
                await writer.StoreAsync();
                await writer.FlushAsync();
            }
            ms.Seek(0);

            var source = new SvgImageSource();
            await source.SetSourceAsync(ms);
            target.Source = source;
            target.Opacity = 0.8;
        }
        finally
        {
            ms.Dispose();
        }
    }
}
