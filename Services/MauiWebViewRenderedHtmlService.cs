using System.Text.Json;
using Daily.Models;
using System.Linq;
using System.Diagnostics;
using System.IO;
using System.Text;
using AngleSharp.Html.Parser;
using SmartReader;

namespace Daily.Services;

public class MauiWebViewRenderedHtmlService : IRenderedHtmlService
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private WebView? _webView;
    private Task<string>? _readabilityScriptTask;

    private const string ReadabilityRunnerScript =
        "(function(){" +
        "try{" +
        "var ctor = window.Readability || Readability;" +
        "if(!ctor) return null;" +
        "var docClone = document.cloneNode(true);" +
        "var article = new ctor(docClone).parse();" +
        "if(!article) return null;" +
        "var json = JSON.stringify(article);" +
        "return btoa(unescape(encodeURIComponent(json)));" +
        "}catch(err){return null;}" +
        "})()";

    private const string CookieCleanupScript =
        "(function(){" +
        "var selectors=['#cmp-app-container','.cookie-banner','#cookie-consent','.gdpr-modal','[class*=\"cookie\"]','[id*=\"cookie\"]','[class*=\"consent\"]'];" +
        "selectors.forEach(function(s){document.querySelectorAll(s).forEach(function(e){e.remove();});});" +
        "document.body.style.overflow='auto';document.documentElement.style.overflow='auto';" +
        "var main=document.querySelector('article')||document.querySelector('main');" +
        "if(main){main.style.display='block';main.style.visibility='visible';main.style.opacity='1';}" +
        "})()";

    public void Attach(WebView webView)
    {
        _webView = webView;
        ConfigureDesktopUserAgent(webView);
    }

    public async Task<RenderedArticle?> GetRenderedArticleAsync(string url, CancellationToken cancellationToken = default)
    {
        if (_webView == null)
        {
            return null;
        }
        Log($"[Reader] Start: {url}");
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var tcs = new TaskCompletionSource<RenderedArticle?>(TaskCreationOptions.RunContinuationsAsynchronously);
            EventHandler<WebNavigatedEventArgs>? handler = null;

            handler = async (sender, args) =>
            {
                Log($"[Reader] Navigated: {args.Url} Result={args.Result}");
                if (args.Result != WebNavigationResult.Success)
                {
                    tcs.TrySetResult(null);
                    return;
                }

                try
                {
                    await WaitForDomAsync(_webView, cancellationToken);
                    await _webView.EvaluateJavaScriptAsync(CookieCleanupScript);
                    var domTextLength = await _webView.EvaluateJavaScriptAsync("document.body && document.body.innerText ? document.body.innerText.length : 0");
                    domTextLength = DecodeJsonString(domTextLength);
                    Log($"[Reader] DOM text length: {domTextLength}");
                    var mainSelector = GetArticleSelectors(args.Url ?? url);
                    var mainTextLength = await _webView.EvaluateJavaScriptAsync($"(function(){{var el=document.querySelector('{mainSelector}');return el && el.innerText ? el.innerText.length : 0;}})()");
                    mainTextLength = DecodeJsonString(mainTextLength);
                    Log($"[Reader] Main selector text length: {mainTextLength}");
                    var script = await GetReadabilityScriptAsync();
                    if (string.IsNullOrWhiteSpace(script))
                    {
                        Log("[Reader] Readability script missing.");
                        tcs.TrySetResult(null);
                        return;
                    }
                    var injectionResult = await _webView.EvaluateJavaScriptAsync(BuildReadabilityInjection(script));
                    injectionResult = DecodeJsonString(injectionResult);
                    Log($"[Reader] Readability injection result: {injectionResult}");

                    var availability = await _webView.EvaluateJavaScriptAsync("typeof window.Readability === 'function' || typeof Readability === 'function'");
                    availability = DecodeJsonString(availability);
                    if (!string.Equals(availability, "true", StringComparison.OrdinalIgnoreCase))
                    {
                        Log("[Reader] Readability not available after injection.");
                        var fallback = await TryFallbackArticleAsync(_webView, args.Url ?? url, cancellationToken);
                        if (fallback != null)
                        {
                            tcs.TrySetResult(fallback);
                        }
                        else
                        {
                            tcs.TrySetResult(null);
                        }
                        return;
                    }

                    var encoded = await _webView.EvaluateJavaScriptAsync(ReadabilityRunnerScript);
                    encoded = NormalizeJson(encoded);
                    if (string.IsNullOrWhiteSpace(encoded) || encoded == "null")
                    {
                        Log("[Reader] Readability returned null.");
                        var fallback = await TryFallbackArticleAsync(_webView, args.Url ?? url, cancellationToken);
                        if (fallback != null)
                        {
                            tcs.TrySetResult(fallback);
                        }
                        else
                        {
                            tcs.TrySetResult(null);
                        }
                        return;
                    }

                    var json = TryDecodeBase64(encoded) ?? encoded;
                    json = NormalizeJson(json);
                    if (!LooksLikeJson(json))
                    {
                        Log("[Reader] Readability output was not JSON after decode.");
                        var fallback = await TryFallbackArticleAsync(_webView, args.Url ?? url, cancellationToken);
                        if (fallback != null)
                        {
                            tcs.TrySetResult(fallback);
                        }
                        else
                        {
                            tcs.TrySetResult(null);
                        }
                        return;
                    }
                    Log($"[Reader] Readability JSON length: {json.Length}");

                    var result = TryDeserializeReadability(json);
                    if (result == null)
                    {
                        Log("[Reader] Failed to deserialize Readability result.");
                        var fallback = await TryFallbackArticleAsync(_webView, args.Url ?? url, cancellationToken);
                        if (fallback != null)
                        {
                            tcs.TrySetResult(fallback);
                        }
                        else
                        {
                            tcs.TrySetResult(null);
                        }
                        return;
                    }

                    var content = string.IsNullOrWhiteSpace(result.Content)
                        ? ConvertTextToHtml(result.TextContent)
                        : result.Content;
                    content = CleanArticleHtml(content);
                    content = WrapWithReaderContainer(content);

                    Log($"[Reader] Parsed content length: {content?.Length ?? 0}, text length: {result.TextContent?.Length ?? 0}");

                    tcs.TrySetResult(new RenderedArticle
                    {
                        Title = result.Title,
                        Content = content,
                        TextContent = result.TextContent,
                        Excerpt = result.Excerpt,
                        Byline = result.Byline
                    });
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

            var completed = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(25), cancellationToken));
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

    private static string? TryDecodeBase64(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim().Trim('"');
        if (LooksLikeJson(trimmed))
        {
            return null;
        }

        trimmed = trimmed.Replace("-", "+").Replace("_", "/");
        trimmed = string.Concat(trimmed.Where(c => !char.IsWhiteSpace(c)));
        var padding = trimmed.Length % 4;
        if (padding != 0)
        {
            trimmed = trimmed.PadRight(trimmed.Length + (4 - padding), '=');
        }

        try
        {
            var bytes = Convert.FromBase64String(trimmed);
            return System.Text.Encoding.UTF8.GetString(bytes);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    private static bool LooksLikeJson(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var trimmed = value.TrimStart();
        return trimmed.StartsWith("{") || trimmed.StartsWith("[");
    }

    private static string? NormalizeJson(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        var decoded = DecodeJsonString(value);
        if (string.IsNullOrWhiteSpace(decoded))
        {
            return decoded;
        }

        decoded = decoded.Trim();
        if (decoded.StartsWith("\"") && decoded.EndsWith("\""))
        {
            try
            {
                decoded = JsonSerializer.Deserialize<string>(decoded) ?? decoded;
            }
            catch
            {
                decoded = decoded.Trim('"');
            }
        }

        return decoded;
    }

    private static async Task WaitForDomAsync(WebView webView, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 12; attempt++)
        {
            var readyState = await webView.EvaluateJavaScriptAsync("document.readyState");
            readyState = DecodeJsonString(readyState);
            var textLength = await webView.EvaluateJavaScriptAsync("document.body && document.body.innerText ? document.body.innerText.length : 0");

            Console.WriteLine($"[Reader] ReadyState={readyState}, TextLength={textLength}");

            if (readyState == "complete" && int.TryParse(textLength, out var length) && length > 1200)
            {
                return;
            }

            await Task.Delay(500, cancellationToken);
        }
    }

    private static string? ConvertTextToHtml(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var lines = text.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
        var paragraphs = string.Join("", lines.Select(line => $"<p>{System.Net.WebUtility.HtmlEncode(line.Trim())}</p>"));
        return $"<div>{paragraphs}</div>";
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
                    var html = await GetHydratedHtmlAsync(_webView, url, cancellationToken);
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

            var completed = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(25), cancellationToken));
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

    private static ReadabilityResult? TryDeserializeReadability(string json)
    {
        if (!LooksLikeJson(json))
        {
            Log("[Reader] Readability payload is not JSON.");
            Log($"[Reader] Readability payload preview: {json[..Math.Min(json.Length, 200)]}");
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<ReadabilityResult>(json);
        }
        catch (JsonException)
        {
            Log($"[Reader] JSON parse failed (len {json.Length}).");
            Log($"[Reader] JSON preview: {json[..Math.Min(json.Length, 200)]}");
            try
            {
                var trimmed = json.Trim();
                if (trimmed.StartsWith("\"") && trimmed.EndsWith("\""))
                {
                    var decoded = JsonSerializer.Deserialize<string>(json);
                    if (!string.IsNullOrWhiteSpace(decoded))
                    {
                        return JsonSerializer.Deserialize<ReadabilityResult>(decoded);
                    }
                }
            }
            catch (JsonException)
            {
                return null;
            }
        }

        return null;
    }

    private Task<string> GetReadabilityScriptAsync()
    {
        _readabilityScriptTask ??= LoadReadabilityScriptAsync();
        return _readabilityScriptTask;
    }

    private static async Task<string> LoadReadabilityScriptAsync()
    {
        try
        {
            await using var stream = await OpenReadabilityStreamAsync();
            if (stream == null)
            {
                Log("[Reader] Readability script not found in app package.");
                return string.Empty;
            }

            using var reader = new StreamReader(stream);
            var script = await reader.ReadToEndAsync();
            Log($"[Reader] Readability script loaded. Length={script.Length}");
            return script;
        }
        catch (Exception ex)
        {
            Log($"[Reader] Failed to load Readability script: {ex}");
            return string.Empty;
        }
    }

    private static async Task<Stream?> OpenReadabilityStreamAsync()
    {
        var candidates = new[] { "readability.min.js", "Resources/Raw/readability.min.js" };

#if WINDOWS
        var baseDir = AppContext.BaseDirectory;
        foreach (var name in candidates)
        {
            var path = Path.Combine(baseDir, name.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(path))
            {
                Log($"[Reader] Readability script found at {path}");
                return File.OpenRead(path);
            }
        }
#endif

        foreach (var name in candidates)
        {
            try
            {
                return await FileSystem.OpenAppPackageFileAsync(name);
            }
            catch (Exception ex) when (ex is FileNotFoundException || ex is DirectoryNotFoundException)
            {
                // try next
            }
        }

#if !WINDOWS
        var baseDir = AppContext.BaseDirectory;
        foreach (var name in candidates)
        {
            var path = Path.Combine(baseDir, name.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(path))
            {
                Log($"[Reader] Readability script found at {path}");
                return File.OpenRead(path);
            }
        }
#endif

        var assembly = typeof(MauiWebViewRenderedHtmlService).Assembly;
        var resourceName = assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("readability.min.js", StringComparison.OrdinalIgnoreCase));
        if (!string.IsNullOrWhiteSpace(resourceName))
        {
            return assembly.GetManifestResourceStream(resourceName);
        }

        Log($"[Reader] Readability not found. BaseDir={baseDir}");
        foreach (var name in candidates)
        {
            Log($"[Reader] Candidate path: {Path.Combine(baseDir, name.Replace('/', Path.DirectorySeparatorChar))}");
        }

        return null;
    }

    private static async Task<string?> GetHydratedHtmlAsync(WebView webView, string url, CancellationToken cancellationToken)
    {
        var extraDelay = TimeSpan.Zero;
        var selectors = "article, main, [itemprop=\\\"articleBody\\\"], .article-body, .article-content, .post-content, .entry-content, .content, .post__content, .post-body";

        if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            var host = uri.Host.ToLowerInvariant();
            if (host.Contains("digi24.ro"))
            {
                extraDelay = TimeSpan.FromSeconds(3);
                selectors = ".article-body, .article-content, .article-text, .entry-content, article";
            }
            else if (host.Contains("republica.ro"))
            {
                extraDelay = TimeSpan.FromSeconds(3);
                selectors = ".article-body, .article-content, .post-content, .entry-content, article";
            }
        }

        for (var attempt = 0; attempt < 5; attempt++)
        {
            if (attempt > 0)
            {
                await Task.Delay(1000, cancellationToken);
            }

            if (extraDelay > TimeSpan.Zero)
            {
                await Task.Delay(extraDelay, cancellationToken);
            }

            var html = await webView.EvaluateJavaScriptAsync("document.documentElement.outerHTML");
            html = DecodeJsonString(html);

            if (!string.IsNullOrWhiteSpace(html) && html.Length > 8000)
            {
                return html;
            }

            var articleHtml = await webView.EvaluateJavaScriptAsync(
                "(function(){" +
                "var selector = '" + selectors + "';" +
                "var el = document.querySelector(selector);" +
                "if (!el) return null;" +
                "return '<html><head><meta charset=\\\"utf-8\\\" /></head><body>' + el.outerHTML + '</body></html>';" +
                "})()"
            );
            articleHtml = DecodeJsonString(articleHtml);
            if (!string.IsNullOrWhiteSpace(articleHtml) && articleHtml.Length > 1000)
            {
                return articleHtml;
            }
        }

        return null;
    }

    private static void Log(string message)
    {
        var line = $"{DateTimeOffset.Now:O} {message}";
        Console.WriteLine(line);
        Debug.WriteLine(line);
        try
        {
            var path = Path.Combine(FileSystem.AppDataDirectory, "reader.log");
            File.AppendAllText(path, line + Environment.NewLine);
        }
        catch
        {
            // Ignore logging failures
        }
    }

    private static string? DecodeJsonString(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        var trimmed = value.Trim();
        if (!(trimmed.StartsWith("\"") && trimmed.EndsWith("\"")))
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

    private static string BuildReadabilityInjection(string script)
    {
        var base64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(script));
        return "(function(){" +
               "try{" +
               "var code=atob('" + base64 + "');" +
               "(0, eval)(code);" +
               "if(typeof Readability!=='undefined'){window.Readability=Readability;}" +
               "if(typeof module!=='undefined'&&module.exports){window.Readability=module.exports;}" +
               "return typeof window.Readability;" +
               "}catch(e){return 'error:'+e.message;}" +
               "})()";
    }

    private static string? CleanArticleHtml(string? html)
    {
        if (string.IsNullOrWhiteSpace(html))
        {
            return html;
        }

        try
        {
            var parser = new HtmlParser();
            var document = parser.ParseDocument($"<html><body>{html}</body></html>");
            var body = document.Body;
            if (body == null)
            {
                return html;
            }

            var removeSelectors = "script,style,noscript,header,footer,aside,nav,form,button,svg";
            foreach (var node in body.QuerySelectorAll(removeSelectors))
            {
                node.Remove();
            }

            foreach (var node in body.QuerySelectorAll("[style]"))
            {
                node.RemoveAttribute("style");
            }

            foreach (var node in body.QuerySelectorAll("[class],[id]"))
            {
                if (ShouldRemoveByClass(node))
                {
                    node.Remove();
                }
            }

            foreach (var node in body.QuerySelectorAll("p,div,section,article"))
            {
                if (IsTrulyEmpty(node))
                {
                    node.Remove();
                }
            }

            return body.InnerHtml;
        }
        catch
        {
            return html;
        }
    }

    private static string? WrapWithReaderContainer(string? html)
    {
        if (string.IsNullOrWhiteSpace(html))
        {
            return html;
        }

        if (html.Contains("reader-content", StringComparison.OrdinalIgnoreCase))
        {
            return html;
        }

        return $"<div class=\"reader-content\">{html}</div>";
    }

    private static bool ShouldRemoveByClass(AngleSharp.Dom.IElement element)
    {
        var value = string.Join(" ", element.ClassList) + " " + element.Id;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var lowered = value.ToLowerInvariant();
        return lowered.Contains("share") ||
               lowered.Contains("social") ||
               lowered.Contains("related") ||
               lowered.Contains("comment") ||
               lowered.Contains("promo") ||
               lowered.Contains("subscribe") ||
               lowered.Contains("newsletter") ||
               lowered.Contains("advert") ||
               lowered.Contains("cookie");
    }

    private static bool IsTrulyEmpty(AngleSharp.Dom.IElement element)
    {
        if (element.QuerySelector("img,video,iframe") != null)
        {
            return false;
        }

        return string.IsNullOrWhiteSpace(element.TextContent);
    }

    private static string GetArticleSelectors(string url)
    {
        var selectors = "article, main, [itemprop=\"articleBody\"], .article-body, .article-content, .post-content, .entry-content, .content, .post__content, .post-body";
        if (Uri.TryCreate(url, UriKind.Absolute, out var uri))
        {
            var host = uri.Host.ToLowerInvariant();
            if (host.Contains("digi24.ro"))
            {
                selectors = ".article-body, .article-content, .article-text, .entry-content, article";
            }
            else if (host.Contains("republica.ro"))
            {
                selectors = ".article-body, .article-content, .post-content, .entry-content, article";
            }
        }

        return selectors;
    }

    private static async Task<RenderedArticle?> TryFallbackArticleAsync(WebView webView, string url, CancellationToken cancellationToken)
    {
        var hydratedHtml = await GetHydratedHtmlAsync(webView, url, cancellationToken);
        if (!string.IsNullOrWhiteSpace(hydratedHtml))
        {
            try
            {
                var reader = new Reader(url, hydratedHtml);
                var article = reader.GetArticle();
                if (article.IsReadable)
                {
                    var content = string.IsNullOrWhiteSpace(article.Content)
                        ? ConvertTextToHtml(article.TextContent)
                        : article.Content;
                    content = CleanArticleHtml(content);
                    content = WrapWithReaderContainer(content);

                    Log($"[Reader] SmartReader fallback content length: {content?.Length ?? 0}");

                    return new RenderedArticle
                    {
                        Title = article.Title,
                        Content = content,
                        TextContent = article.TextContent,
                        Excerpt = article.Excerpt,
                        Byline = article.Byline
                    };
                }
            }
            catch (Exception ex)
            {
                Log($"[Reader] SmartReader fallback failed: {ex.Message}");
            }
        }

        var selectors = GetArticleSelectors(url);
        var title = await webView.EvaluateJavaScriptAsync("document.title");
        title = DecodeJsonString(title);

        var html = await webView.EvaluateJavaScriptAsync(
            "(function(){" +
            "var selector='" + selectors + "';" +
            "var el=document.querySelector(selector);" +
            "if(!el) return null;" +
            "return el.outerHTML;" +
            "})()"
        );
        html = DecodeJsonString(html);
        if (string.IsNullOrWhiteSpace(html) || html == "null")
        {
            Log("[Reader] Fallback selector returned no HTML.");
            return null;
        }

        var text = await webView.EvaluateJavaScriptAsync(
            "(function(){" +
            "var selector='" + selectors + "';" +
            "var el=document.querySelector(selector);" +
            "if(!el || !el.innerText) return '';" +
            "return el.innerText;" +
            "})()"
        );
        text = DecodeJsonString(text);

        Log($"[Reader] Fallback selector content length: {html.Length}");

        string? excerpt = null;
        if (!string.IsNullOrWhiteSpace(text))
        {
            excerpt = text.Length > 280 ? text[..280] + "..." : text;
        }

        return new RenderedArticle
        {
            Title = title,
            Content = WrapWithReaderContainer(CleanArticleHtml(html)),
            TextContent = text,
            Excerpt = excerpt
        };
    }

    private static void ConfigureDesktopUserAgent(WebView webView)
    {
        const string userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

#if ANDROID
        if (webView.Handler?.PlatformView is Android.Webkit.WebView androidWebView)
        {
            androidWebView.Settings.UserAgentString = userAgent;
        }
#elif IOS || MACCATALYST
        if (webView.Handler?.PlatformView is WebKit.WKWebView wkWebView)
        {
            wkWebView.CustomUserAgent = userAgent;
        }
#elif WINDOWS
        if (webView.Handler?.PlatformView is Microsoft.UI.Xaml.Controls.WebView2 webView2)
        {
            if (webView2.CoreWebView2 != null)
            {
                webView2.CoreWebView2.Settings.UserAgent = userAgent;
            }
            else
            {
                webView2.CoreWebView2Initialized += (_, _) =>
                {
                    if (webView2.CoreWebView2 != null)
                    {
                        webView2.CoreWebView2.Settings.UserAgent = userAgent;
                    }
                };
            }
        }
#endif
    }
}
