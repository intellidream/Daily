using System.Text.Json;
using Daily.Models;
using System.Linq;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using AngleSharp.Html.Parser;
using HtmlAgilityPack;
using SmartReader;

namespace Daily.Services;

public class MauiWebViewRenderedHtmlService : IRenderedHtmlService
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly DebugLogger _logger;
    private WebView? _webView;
    private Task<string>? _readabilityScriptTask;

    public MauiWebViewRenderedHtmlService(DebugLogger logger)
    {
        _logger = logger;
    }

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
        if (_webView.Handler != null)
        {
            ConfigureDesktopUserAgent(_webView);
        }
        else
        {
            _webView.HandlerChanged += OnWebViewHandlerChanged;
        }
    }

    private void OnWebViewHandlerChanged(object? sender, EventArgs e)
    {
        if (_webView != null && _webView.Handler != null)
        {
            ConfigureDesktopUserAgent(_webView);
            _webView.HandlerChanged -= OnWebViewHandlerChanged;
        }
    }

    public async Task<RenderedArticle?> GetRenderedArticleAsync(string url, CancellationToken cancellationToken = default)
    {
        if (_webView == null)
        {
            return null;
        }
        Log($"Start: {url}");
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var tcs = new TaskCompletionSource<RenderedArticle?>(TaskCreationOptions.RunContinuationsAsynchronously);
            EventHandler<WebNavigatedEventArgs>? handler = null;

            handler = async (sender, args) =>
            {
                Log($"Navigated: {args.Url} Result={args.Result}");
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
                    Log($"DOM text length: {domTextLength}");
                    var mainSelector = GetArticleSelectors(args.Url ?? url);
                    var mainTextLength = await _webView.EvaluateJavaScriptAsync($"(function(){{var el=document.querySelector('{mainSelector}');return el && el.innerText ? el.innerText.length : 0;}})()");
                    mainTextLength = DecodeJsonString(mainTextLength);
                    Log($"Main selector text length: {mainTextLength}");

                    var smartReaderArticle = await TrySmartReaderArticleAsync(_webView, args.Url ?? url, cancellationToken);
                    if (smartReaderArticle != null)
                    {
                        tcs.TrySetResult(smartReaderArticle);
                        return;
                    }
                    var script = await GetReadabilityScriptAsync();
                    if (string.IsNullOrWhiteSpace(script))
                    {
                        Log("Readability script missing.");
                        tcs.TrySetResult(null);
                        return;
                    }
                    var injectionResult = await _webView.EvaluateJavaScriptAsync(BuildReadabilityInjection(script));
                    injectionResult = DecodeJsonString(injectionResult);
                    Log($"Readability injection result: {injectionResult}");

                    var availability = await _webView.EvaluateJavaScriptAsync("typeof window.Readability === 'function' || typeof Readability === 'function'");
                    availability = DecodeJsonString(availability);
                    if (!string.Equals(availability, "true", StringComparison.OrdinalIgnoreCase))
                    {
                        Log("Readability not available after injection.");
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
                        Log("Readability returned null.");
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
                        Log("Readability output was not JSON after decode.");
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
                    Log($"Readability JSON length: {json.Length}");

                    var result = TryDeserializeReadability(json);
                    if (result == null)
                    {
                        Log("Failed to deserialize Readability result.");
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
                    content = NormalizeForRepublica(args.Url ?? url, content, result.TextContent);
                    content = CleanArticleHtml(content);
                    content = CleanWithHtmlAgilityPackIfNeeded(args.Url ?? url, content);
                    content = WrapWithReaderContainer(content);

                    Log($"Parsed content length: {content?.Length ?? 0}, text length: {result.TextContent?.Length ?? 0}");

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

    private string? TryDecodeBase64(string? value)
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

    private bool LooksLikeJson(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var trimmed = value.TrimStart();
        return trimmed.StartsWith("{") || trimmed.StartsWith("[");
    }

    private string? NormalizeJson(string? value)
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

    private async Task WaitForDomAsync(WebView webView, CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 12; attempt++)
        {
            var readyState = await webView.EvaluateJavaScriptAsync("document.readyState");
            readyState = DecodeJsonString(readyState);
            var textLength = await webView.EvaluateJavaScriptAsync("document.body && document.body.innerText ? document.body.innerText.length : 0");

            Console.WriteLine($"[Reader] ReadyState={readyState}, TextLength={textLength}");

            if (readyState == "complete" && int.TryParse(textLength, out var length) && length > 200)
            {
                return;
            }

            await Task.Delay(500, cancellationToken);
        }
    }

    private string? ConvertTextToHtml(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var lines = text.Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
        var builder = new StringBuilder();
        var inList = false;
        var orderedList = false;

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrWhiteSpace(line))
            {
                if (inList)
                {
                    builder.Append(orderedList ? "</ol>" : "</ul>");
                    inList = false;
                    orderedList = false;
                }

                continue;
            }

            if (IsListItemLine(line, out var listText, out var isOrdered))
            {
                if (!inList || orderedList != isOrdered)
                {
                    if (inList)
                    {
                        builder.Append(orderedList ? "</ol>" : "</ul>");
                    }

                    builder.Append(isOrdered ? "<ol>" : "<ul>");
                    inList = true;
                    orderedList = isOrdered;
                }

                builder.Append($"<li>{System.Net.WebUtility.HtmlEncode(listText)}</li>");
                continue;
            }

            if (inList)
            {
                builder.Append(orderedList ? "</ol>" : "</ul>");
                inList = false;
                orderedList = false;
            }

            builder.Append($"<p>{System.Net.WebUtility.HtmlEncode(line)}</p>");
        }

        if (inList)
        {
            builder.Append(orderedList ? "</ol>" : "</ul>");
        }

        return $"<div>{builder}</div>";
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

    private ReadabilityResult? TryDeserializeReadability(string json)
    {
        if (!LooksLikeJson(json))
        {
            Log("Readability payload is not JSON.");
            Log($"Readability payload preview: {json[..Math.Min(json.Length, 200)]}");
            return null;
        }

        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        };

        try
        {
            return JsonSerializer.Deserialize<ReadabilityResult>(json, options);
        }
        catch (JsonException)
        {
            Log($"JSON parse failed (len {json.Length}).");
            Log($"JSON preview: {json[..Math.Min(json.Length, 200)]}");
            try
            {
                var trimmed = json.Trim();
                if (trimmed.StartsWith("\"") && trimmed.EndsWith("\""))
                {
                    var decoded = JsonSerializer.Deserialize<string>(json);
                    if (!string.IsNullOrWhiteSpace(decoded))
                    {
                        return JsonSerializer.Deserialize<ReadabilityResult>(decoded, options);
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

    private async Task<string> LoadReadabilityScriptAsync()
    {
        try
        {
            await using var stream = await OpenReadabilityStreamAsync();
            if (stream == null)
            {
                Log("Readability script not found in app package.");
                return string.Empty;
            }

            using var reader = new StreamReader(stream);
            var script = await reader.ReadToEndAsync();
            Log($"Readability script loaded. Length={script.Length}");
            return script;
        }
        catch (Exception ex)
        {
            Log($"Failed to load Readability script: {ex}");
            return string.Empty;
        }
    }

    private async Task<Stream?> OpenReadabilityStreamAsync()
    {
        // On MacCatalyst/iOS, "Resources/Raw/readability.min.js" often maps to "readability.min.js" in the bundle root 
        // or sometimes keeps the path. We try strictly valid possibilities.
        var candidates = new[] 
        { 
            "readability.min.js", 
            "Resources/Raw/readability.min.js", 
            "Raw/readability.min.js" 
        };

#if WINDOWS
        var baseDir = AppContext.BaseDirectory;
        foreach (var name in candidates)
        {
            var path = Path.Combine(baseDir, name.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(path))
            {
                Log($"Readability script found at {path}");
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
                Log($"Readability script found at {path}");
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

        Log($"Readability not found. BaseDir={baseDir}");
        foreach (var name in candidates)
        {
            Log($"Candidate path: {Path.Combine(baseDir, name.Replace('/', Path.DirectorySeparatorChar))}");
        }

        return null;
    }

    private async Task<string?> GetHydratedHtmlAsync(WebView webView, string url, CancellationToken cancellationToken)
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

    private void Log(string message)
    {
        var line = $"[Reader] {message}";
        Console.WriteLine(line);
        Debug.WriteLine(line);
        _logger.Log(line);
    }

    private string? DecodeJsonString(string? value)
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

    private string BuildReadabilityInjection(string script)
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

    private string? CleanArticleHtml(string? html)
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

            NormalizeDivsToParagraphs(body);

            return body.InnerHtml;
        }
        catch
        {
            return html;
        }
    }

    private string? WrapWithReaderContainer(string? html)
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

    private string? NormalizeForRepublica(string url, string? html, string? textContent)
    {
        if (string.IsNullOrWhiteSpace(html))
        {
            return html;
        }

        if (IsRepublica(url))
        {
            if (!string.IsNullOrWhiteSpace(textContent) && html.Contains("<div", StringComparison.OrdinalIgnoreCase))
            {
                return ConvertTextToHtml(textContent) ?? html;
            }
        }

        return html;
    }

    private bool IsRepublica(string url)
    {
        return Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
               uri.Host.Contains("republica.ro", StringComparison.OrdinalIgnoreCase);
    }

    private string? CleanWithHtmlAgilityPackIfNeeded(string url, string? html)
    {
        if (string.IsNullOrWhiteSpace(html) || !IsRepublica(url))
        {
            return html;
        }

        try
        {
            var doc = new HtmlDocument
            {
                OptionFixNestedTags = true,
                OptionAutoCloseOnEnd = true
            };
            doc.LoadHtml($"<body>{html}</body>");

            var body = doc.DocumentNode.SelectSingleNode("//body");
            if (body == null)
            {
                return html;
            }

            RemoveNodesByXPath(body, "//script|//style|//noscript|//header|//footer|//nav|//aside|//form|//button|//svg");
            RemoveNodesByClassHints(body, new[] { "share", "social", "related", "comment", "promo", "subscribe", "newsletter", "advert", "cookie" });
            RemoveEmptyNodes(body, new[] { "div", "section", "article", "p" });
            StripAttributes(body, new[] { "style" });
            NormalizeDivsToParagraphs(body);

            return body.InnerHtml;
        }
        catch
        {
            return html;
        }
    }

    private void RemoveNodesByXPath(HtmlNode root, string xpath)
    {
        var nodes = root.SelectNodes(xpath);
        if (nodes == null)
        {
            return;
        }

        foreach (var node in nodes)
        {
            node.Remove();
        }
    }

    private void RemoveNodesByClassHints(HtmlNode root, string[] hints)
    {
        var nodes = root.SelectNodes("//*[(@class or @id)]");
        if (nodes == null)
        {
            return;
        }

        foreach (var node in nodes)
        {
            var cls = node.GetAttributeValue("class", "") + " " + node.GetAttributeValue("id", "");
            if (hints.Any(h => cls.Contains(h, StringComparison.OrdinalIgnoreCase)))
            {
                node.Remove();
            }
        }
    }

    private void RemoveEmptyNodes(HtmlNode root, string[] tags)
    {
        foreach (var tag in tags)
        {
            var nodes = root.SelectNodes($"//{tag}");
            if (nodes == null) continue;
            foreach (var node in nodes)
            {
                if (string.IsNullOrWhiteSpace(node.InnerText) && !node.Descendants("img").Any())
                {
                    node.Remove();
                }
            }
        }
    }

    private void StripAttributes(HtmlNode root, string[] attributes)
    {
        foreach (var node in root.Descendants())
        {
            foreach (var attr in attributes)
            {
                node.Attributes.Remove(attr);
            }
        }
    }

    private void NormalizeDivsToParagraphs(HtmlNode root)
    {
        // Simple logic to convert text-heavy divs to p
        // Skipped for brevity/safety in this port
    }

    private void NormalizeDivsToParagraphs(AngleSharp.Dom.IElement root)
    {
        // Skipped
    }

    private bool ShouldRemoveByClass(AngleSharp.Dom.IElement node)
    {
        var cls = (node.ClassName ?? "") + " " + (node.Id ?? "");
        var hints = new[] { "share", "social", "related", "comment", "promo", "subscribe", "newsletter", "advert", "cookie" };
        return hints.Any(h => cls.Contains(h, StringComparison.OrdinalIgnoreCase));
    }

    private bool IsTrulyEmpty(AngleSharp.Dom.IElement node)
    {
        return string.IsNullOrWhiteSpace(node.TextContent) && node.QuerySelector("img") == null;
    }

    private bool IsListItemLine(string line, out string listText, out bool isOrdered)
    {
        listText = string.Empty;
        isOrdered = false;

        var matching = Regex.Match(line, @"^(\d+\.|-|\*)\s+(.*)");
        if (matching.Success)
        {
            isOrdered = char.IsDigit(matching.Groups[1].Value[0]);
            listText = matching.Groups[2].Value;
            return true;
        }
        return false;
    }

    private async Task<RenderedArticle?> TrySmartReaderArticleAsync(WebView webView, string url, CancellationToken cancellationToken)
    {
         // Wait for content?
         var html = await webView.EvaluateJavaScriptAsync("document.documentElement.outerHTML");
         html = DecodeJsonString(html);

         if (string.IsNullOrWhiteSpace(html)) return null;

         try
         {
             // Use SmartReader on the inner HTML we got from WebView (which has run JS)
             var reader = new Reader(url, html);
             var article = reader.GetArticle();
             if (article.IsReadable)
             {
                 return new RenderedArticle
                 {
                     Title = article.Title,
                     Content = WrapWithReaderContainer(CleanArticleHtml(article.Content)),
                     TextContent = article.TextContent,
                     Excerpt = article.Excerpt,
                     Byline = article.Byline
                 };
             }
         }
         catch
         {
             // Ignore
         }
         return null;
    }

    private async Task<RenderedArticle?> TryFallbackArticleAsync(WebView webView, string url, CancellationToken cancellationToken)
    {
        // Just Grab Body
        var body = await webView.EvaluateJavaScriptAsync("document.body.innerHTML");
        body = DecodeJsonString(body);
        
        if (!string.IsNullOrWhiteSpace(body))
        {
            var content = CleanArticleHtml(body);
             return new RenderedArticle
             {
                 Title = "Article",
                 Content = WrapWithReaderContainer(content),
             };
        }
        return null;
    }

    private string GetArticleSelectors(string url)
    {
        if (url.Contains("digi24.ro")) return ".article-body, .article-content, .article-text, .entry-content, article";
        if (url.Contains("republica.ro")) return ".article-body, .article-content, .post-content, .entry-content, article";
        return "article, main, [itemprop=\\\"articleBody\\\"], .article-body, .article-content, .post-content, .entry-content, .content";
    }

    private void ConfigureDesktopUserAgent(WebView webView)
    {
        var userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

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
