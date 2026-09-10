import SwiftUI
import WebKit
import DailyCore

/// High-performance WKWebView container rendering articles in the signature DayOne Liquid Glass styling template.
public struct ArticleWebView: UIViewRepresentable {
    public let article: NewsArticle
    public let isDark: Bool
    public let fontSizeMultiplier: Double
    
    public init(article: NewsArticle, isDark: Bool = true, fontSizeMultiplier: Double = 1.0) {
        self.article = article
        self.isDark = isDark
        self.fontSizeMultiplier = fontSizeMultiplier
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsVerticalScrollIndicator = true
        return webView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        let html = generateReaderHtml(article: article, isDark: isDark, fontSizeMultiplier: fontSizeMultiplier)
        uiView.loadHTMLString(html, baseURL: URL(string: article.link))
    }
    
    private func generateReaderHtml(article: NewsArticle, isDark: Bool, fontSizeMultiplier: Double) -> String {
        let textColor = isDark ? "#E0E0E0" : "#1A1A1A"
        let linkColor = isDark ? "#00D2FF" : "#0066CC"
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
        
        var pubHeaderHtml = ""
        if let pubName = article.publicationName, !pubName.isEmpty {
            let iconUrl = article.publicationIconUrl ?? "https://www.google.com/s2/favicons?domain=rss.com&sz=64"
            pubHeaderHtml = """
            <div class='publication-header'>
                <img class='publication-logo' src='\(iconUrl)' />
                <span class='publication-name'>\(pubName)</span>
            </div>
            """
        }
        
        let contentBody = article.content ?? article.description ?? "<p>No content preview available.</p>"
        
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
                    max-width: 720px;
                    margin: 0 auto;
                    padding: 20px 18px 40px 18px;
                }
                .publication-header {
                    display: flex;
                    align-items: center;
                    margin-bottom: 14px;
                    opacity: 0.9;
                }
                .publication-logo {
                    width: 24px;
                    height: 24px;
                    border-radius: 50%;
                    margin-right: 10px;
                    background: white;
                    padding: 2px;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.15);
                }
                .publication-name {
                    font-size: 13px;
                    font-weight: 700;
                    text-transform: uppercase;
                    letter-spacing: 0.6px;
                    color: \(metaColor);
                }
                h1.title {
                    font-size: \(Int(Double(baseFontSize) * 1.6))px;
                    font-weight: 800;
                    line-height: 1.25;
                    margin: 0 0 12px 0;
                    letter-spacing: -0.5px;
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
                    max-height: 380px;
                    object-fit: cover;
                    border-radius: 16px;
                    margin: 12px 0 24px 0;
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
                    border-radius: 12px;
                    margin: 20px 0;
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
            </style>
        </head>
        <body>
            <div class='article-wrap'>
                \(pubHeaderHtml)
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
}
