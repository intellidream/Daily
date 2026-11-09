import SwiftUI
import WebKit
import DailyCore

/// High-performance WKWebView container rendering articles in the signature DayOne Liquid Glass styling template on macOS.
public struct ArticleWebView: NSViewRepresentable {
    public let article: NewsArticle
    public let isDark: Bool
    public let fontSizeMultiplier: Double
    
    public init(article: NewsArticle, isDark: Bool = true, fontSizeMultiplier: Double = 1.0) {
        self.article = article
        self.isDark = isDark
        self.fontSizeMultiplier = fontSizeMultiplier
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        let html = generateReaderHtml(article: article, isDark: isDark, fontSizeMultiplier: fontSizeMultiplier)
        nsView.loadHTMLString(html, baseURL: URL(string: article.link))
    }
    
    private func generateReaderHtml(article: NewsArticle, isDark: Bool, fontSizeMultiplier: Double) -> String {
        let textColor = isDark ? "#E0E0E0" : "#1A1A1A"
        let linkColor = isDark ? "#66B2FF" : "#0066CC"
        let metaColor = isDark ? "#A0A0A0" : "#666666"
        let bodyBackground = isDark ? "#1A1423" : "#EDE5D9"
        let baseFontSize = Int(18.0 * fontSizeMultiplier)
        
        let featuredImageHtml: String
        if let imgUrl = article.imageUrl, !imgUrl.isEmpty {
            featuredImageHtml = "<img class='featured-image' src='\(imgUrl)' alt='Featured Image' />"
        } else {
            featuredImageHtml = ""
        }
        
        var metaHtml = "<div class='meta'>"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        metaHtml += "<span>Published: \(formatter.string(from: article.publishDate))</span>"
        if let author = article.author, !author.isEmpty {
            metaHtml += " &bull; <span>By \(author)</span>"
        }
        metaHtml += "</div>"
        
        let rawBody = article.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let contentBody: String
        if !rawBody.isEmpty {
            contentBody = rawBody
        } else if let desc = article.description, !desc.isEmpty {
            contentBody = """
            <div class='paywall-card'>
                <div class='paywall-icon'>📰</div>
                <h3>Preview from \(article.publicationName ?? "Publisher")</h3>
                <p>\(desc)</p>
                <a href='\(article.link)' class='open-browser-btn'>Open on \(article.publicationName ?? "Publisher")</a>
            </div>
            """
        } else {
            contentBody = """
            <div class='paywall-card'>
                <div class='paywall-icon'>📰</div>
                <h3>Full Story on \(article.publicationName ?? "Publisher")</h3>
                <p>This article can be read directly on the publisher's website.</p>
                <a href='\(article.link)' class='open-browser-btn'>Read on \(article.publicationName ?? "Publisher")</a>
            </div>
            """
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset='utf-8'/>
            <meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes'/>
            <style>
                * {
                    box-sizing: border-box;
                }
                html, body {
                    min-height: 100%;
                    background: transparent;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    background: \(bodyBackground);
                    color: \(textColor);
                    line-height: 1.65;
                    margin: 0;
                    padding: 0;
                    font-size: \(baseFontSize)px;
                    -webkit-text-size-adjust: 100%;
                }
                .article-wrap {
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 24px 28px 160px 28px;
                }
                h1.title {
                    font-size: \(Int(Double(baseFontSize) * 1.6))px;
                    font-weight: 800;
                    line-height: 1.25;
                    margin: 0 0 12px 0;
                    letter-spacing: -0.5px;
                }
                h2, h3, h4 {
                    margin-top: 32px;
                    margin-bottom: 16px;
                    font-weight: 700;
                    line-height: 1.3;
                }
                .meta {
                    font-size: 13px;
                    color: \(metaColor);
                    margin-bottom: 24px;
                    border-bottom: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.12)");
                    padding-bottom: 14px;
                }
                .featured-image {
                    width: 100%;
                    max-height: 420px;
                    object-fit: cover;
                    border-radius: 14px;
                    margin: 12px 0 28px 0;
                    box-shadow: 0 8px 24px rgba(0,0,0,0.25);
                }
                p {
                    margin-bottom: 20px;
                }
                a {
                    color: \(linkColor);
                    text-decoration: none;
                    font-weight: 500;
                }
                a:hover {
                    text-decoration: underline;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 10px;
                    margin: 24px 0;
                    display: block;
                }
                figure {
                    margin: 20px 0;
                }
                figcaption {
                    font-size: 12px;
                    color: \(metaColor);
                    text-align: center;
                    margin-top: 6px;
                }
                blockquote {
                    margin: 24px 0;
                    padding: 12px 20px;
                    border-left: 4px solid \(linkColor);
                    background: \(isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.04)");
                    border-radius: 0 8px 8px 0;
                    font-style: italic;
                }
                ul, ol {
                    margin: 16px 0 24px 20px;
                    padding-left: 10px;
                }
                li {
                    margin-bottom: 8px;
                }
                code {
                    font-family: Menlo, Monaco, Courier, monospace;
                    font-size: 0.9em;
                    background: \(isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.06)");
                    padding: 2px 6px;
                    border-radius: 4px;
                }
                pre {
                    background: \(isDark ? "#120D1A" : "#E2D8C7");
                    padding: 14px;
                    border-radius: 10px;
                    overflow-x: auto;
                }
                table {
                    width: 100%;
                    max-width: 100%;
                    border-collapse: collapse;
                    margin: 24px 0;
                    font-size: 0.9em;
                }
                th, td {
                    padding: 10px 14px;
                    border: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.12)");
                    text-align: left;
                }
                th {
                    background: \(isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)");
                    font-weight: 600;
                }
                iframe, video {
                    max-width: 100%;
                    width: 100%;
                    border-radius: 12px;
                    margin: 24px 0;
                    display: block;
                    border: none;
                }
                hr {
                    border: none;
                    border-top: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.12)");
                    margin: 32px 0;
                }
                .paywall-card {
                    background: \(isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.03)");
                    border: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.12)");
                    border-radius: 16px;
                    padding: 24px;
                    text-align: center;
                    margin: 32px 0;
                }
                .paywall-icon {
                    font-size: 32px;
                    margin-bottom: 12px;
                }
                .open-browser-btn {
                    display: inline-block;
                    margin-top: 16px;
                    padding: 10px 20px;
                    background: \(isDark ? "rgba(102, 178, 255, 0.15)" : "rgba(0, 102, 204, 0.1)");
                    color: \(linkColor) !important;
                    border: 1px solid \(isDark ? "rgba(102, 178, 255, 0.3)" : "rgba(0, 102, 204, 0.3)");
                    border-radius: 20px;
                    font-weight: 600;
                    font-size: 14px;
                }
                /* Substack Reader Refinements */
                .substack-subtitle {
                    font-size: 1.15em;
                    color: \(metaColor);
                    line-height: 1.45;
                    margin: -6px 0 22px 0;
                    font-weight: 400;
                }
                .captioned-image-container, .image2-inset {
                    margin: 22px 0;
                    width: 100%;
                }
                a.image-link {
                    display: block;
                    text-decoration: none !important;
                }
                .image-caption {
                    font-size: 13px;
                    color: \(metaColor);
                    text-align: center;
                    margin-top: 8px;
                    line-height: 1.4;
                }
                .image-link-expand,
                button.restack-image,
                button.view-image,
                .subscription-widget-wrap,
                .subscription-widget-wrap-editor,
                .subscription-widget,
                .subscribe-widget,
                .post-ufi,
                .like-button-container,
                .fake-input-wrapper {
                    display: none !important;
                }
                .pullquote {
                    margin: 28px 0;
                    padding: 16px 22px;
                    border-left: 4px solid #FF6719;
                    background: \(isDark ? "rgba(255, 103, 25, 0.08)" : "rgba(255, 103, 25, 0.06)");
                    border-radius: 0 12px 12px 0;
                    font-size: 1.1em;
                    font-weight: 500;
                    line-height: 1.55;
                }
                .pullquote p:last-child {
                    margin-bottom: 0;
                }
                .callout-block {
                    margin: 24px 0;
                    padding: 18px 20px;
                    background: \(isDark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.04)");
                    border: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.10)");
                    border-radius: 14px;
                }
                .callout-block h4 {
                    margin-top: 0;
                }
                .callout-block p:last-child {
                    margin-bottom: 0;
                }
                .embedded-post-wrap, .embedded-post {
                    margin: 24px 0;
                    padding: 16px 18px;
                    background: \(isDark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.03)");
                    border: 1px solid \(isDark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.10)");
                    border-radius: 14px;
                }
                img.embedded-post-publication-logo {
                    width: 24px;
                    height: 24px;
                    border-radius: 6px;
                    display: inline-block;
                    vertical-align: middle;
                    margin: 0 8px 0 0;
                }
                .button-wrapper {
                    text-align: center;
                    margin: 24px 0;
                }
                .button-wrapper a.button {
                    display: inline-block;
                    padding: 10px 22px;
                    border-radius: 999px;
                    background: \(isDark ? "rgba(102, 178, 255, 0.16)" : "rgba(0, 102, 204, 0.10)");
                    border: 1px solid \(isDark ? "rgba(102, 178, 255, 0.35)" : "rgba(0, 102, 204, 0.30)");
                    color: \(linkColor) !important;
                    font-weight: 600;
                    font-size: 0.92em;
                    text-decoration: none !important;
                }
                .footnote-anchor {
                    font-size: 0.75em;
                    vertical-align: super;
                    padding: 1px 6px;
                    border-radius: 6px;
                    background: \(isDark ? "rgba(102, 178, 255, 0.15)" : "rgba(0, 102, 204, 0.10)");
                    margin: 0 2px;
                    text-decoration: none !important;
                }
                .footnote {
                    font-size: 0.88em;
                    color: \(metaColor);
                    border-top: 1px solid \(isDark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.08)");
                    padding-top: 12px;
                    margin-top: 16px;
                }
                .substack-paid-card {
                    border-color: rgba(255, 103, 25, 0.35);
                    background: \(isDark ? "rgba(255, 103, 25, 0.08)" : "rgba(255, 103, 25, 0.05)");
                }
            </style>
        </head>
        <body>
            <div class='article-wrap'>
                <h1 class='title'>\(article.title)</h1>
                \(metaHtml)
                \(featuredImageHtml)
                <div class='content-body'>
                    \(contentBody)
                </div>
            </div>
        </body>
        </html>
        """
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate {
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               (scheme == "https" || scheme == "http") {
                PrismStore.shared.requestOpenInPrism(url: url.absoluteString, openInNewTab: true)
                NotificationCenter.default.post(name: .dailySelectTab, object: NavigationTab.prism)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
