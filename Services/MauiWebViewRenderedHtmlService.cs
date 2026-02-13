using System.Text.Json;

namespace Daily.Services;

public class MauiWebViewRenderedHtmlService : IRenderedHtmlService
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private WebView? _webView;

    public void Attach(WebView webView)
    {
        _webView = webView;
    }

    public async Task<string?> GetRenderedHtmlAsync(string url, CancellationToken cancellationToken = default)
    {
        if (_webView == null)
        {
            return null;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var tcs = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
            EventHandler<WebNavigatedEventArgs>? handler = null;

            handler = async (sender, args) =>
            {
                if (args.Result != WebNavigationResult.Success)
                {
                    tcs.TrySetResult(null);
                    return;
                }

                try
                {
                    var html = await GetHydratedHtmlAsync(_webView, cancellationToken);
                    tcs.TrySetResult(html);
                }
                catch (Exception ex)
                {
                    tcs.TrySetException(ex);
                }
                finally
                {
                    _webView.Navigated -= handler;
                }
            };

            await MainThread.InvokeOnMainThreadAsync(() =>
            {
                _webView.Navigated += handler;
                _webView.Source = url;
            });

            var completed = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(15), cancellationToken));
            if (completed != tcs.Task)
            {
                await MainThread.InvokeOnMainThreadAsync(() => _webView.Navigated -= handler);
                return null;
            }

            return await tcs.Task;
        }
        finally
        {
            _gate.Release();
        }
    }

    private static async Task<string?> GetHydratedHtmlAsync(WebView webView, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 4; attempt++)
        {
            if (attempt > 0)
            {
                await Task.Delay(750, cancellationToken);
            }

            var html = await webView.EvaluateJavaScriptAsync("document.documentElement.outerHTML");
            html = DecodeJsonString(html);

            if (!string.IsNullOrWhiteSpace(html) && html.Length > 4000)
            {
                return html;
            }
        }

        return null;
    }

    private static string? DecodeJsonString(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        try
        {
            return JsonSerializer.Deserialize<string>(value) ?? value;
        }
        catch
        {
            return value;
        }
    }
}
