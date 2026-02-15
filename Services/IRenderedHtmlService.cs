namespace Daily.Services;

public interface IRenderedHtmlService
{
    void Attach(WebView webView);
    Task<string?> GetRenderedHtmlAsync(string url, CancellationToken cancellationToken = default);
    Task<Daily.Models.RenderedArticle?> GetRenderedArticleAsync(string url, CancellationToken cancellationToken = default);
}
