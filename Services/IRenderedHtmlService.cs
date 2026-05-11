#if WINUI_NATIVE
using WebView = Microsoft.UI.Xaml.Controls.WebView2;
#else
using Microsoft.Maui.Controls;
#endif
namespace Daily.Services;

public interface IRenderedHtmlService
{
    void Attach(WebView webView);
    Task<string?> GetRenderedHtmlAsync(string url, CancellationToken cancellationToken = default);
    Task<Daily.Models.RenderedArticle?> GetRenderedArticleAsync(string url, CancellationToken cancellationToken = default);
}
