import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Shared JavaScript bridges and native WebKit Content Blocker (`Prism Shield`) rule generator for Prism.
public enum PrismWebScripts: Sendable {

    public static let bridgeHandlerName = "prismBridge"

    /// Injected at document end in the main frame to power:
    /// 1. Floating Glass Selection Pill (`selectionchange` / `mouseup` / `touchend` debounced)
    /// 2. RSS / Atom / JSON Feed & Substack / OpenGraph metadata auto-sniffing
    /// 3. Alt+Click / Long-Press Image quick capture (`imageCandidate`)
    /// 4. Throttled `scrollY` tracking for lossless tab hibernation
    /// 5. `window.__prismExtractPageContext()` for AI Co-Pilot & Reader extraction
    public static let pageObserverScript: String = """
    (function() {
        if (window.__prismObserverInstalled) return;
        window.__prismObserverInstalled = true;

        function postToNative(payload) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.prismBridge) {
                    window.webkit.messageHandlers.prismBridge.postMessage(payload);
                }
            } catch (e) {}
        }

        function sniffMetadata() {
            try {
                var rssLink = document.querySelector(
                    'link[rel="alternate"][type*="rss"], link[rel="alternate"][type*="atom"], link[rel="alternate"][type*="feed+json"]'
                );
                var rssUrl = rssLink ? rssLink.href : null;
                var rssTitle = rssLink ? (rssLink.title || document.title || '') : null;

                if (!rssUrl) {
                    var host = (location.hostname || '').toLowerCase();
                    if (host.endsWith('.substack.com') && host !== 'www.substack.com' && host !== 'open.substack.com') {
                        rssUrl = location.protocol + '//' + host + '/feed';
                        rssTitle = document.title || host;
                    } else if (document.querySelector('link[href*="substackcdn.com"], div.captioned-image-container')) {
                        rssUrl = location.origin + '/feed';
                        rssTitle = document.title || host;
                    }
                }

                var ogImg = document.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
                var canonical = document.querySelector('link[rel="canonical"]');

                postToNative({
                    type: 'metadata',
                    title: document.title || '',
                    canonicalUrl: canonical ? canonical.href : location.href,
                    ogImage: ogImg ? ogImg.content : null,
                    rssUrl: rssUrl,
                    rssTitle: rssTitle
                });
            } catch (e) {}
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', sniffMetadata, { once: true });
        } else {
            sniffMetadata();
        }
        window.addEventListener('load', sniffMetadata, { once: true });

        // Debounced text selection observer for Floating Glass Selection Pill
        var selTimer = null;
        function checkSelection() {
            clearTimeout(selTimer);
            selTimer = setTimeout(function() {
                try {
                    var sel = window.getSelection();
                    var text = sel ? sel.toString().trim() : '';
                    if (text && text.length >= 3 && sel.rangeCount > 0) {
                        var rect = sel.getRangeAt(0).getBoundingClientRect();
                        postToNative({
                            type: 'selection',
                            text: text.slice(0, 4000),
                            x: rect.left + (rect.width / 2),
                            y: rect.top,
                            bottom: rect.bottom,
                            viewportWidth: window.innerWidth,
                            viewportHeight: window.innerHeight
                        });
                    } else {
                        postToNative({ type: 'selectionCleared' });
                    }
                } catch (e) {}
            }, 180);
        }

        document.addEventListener('selectionchange', checkSelection, { passive: true });
        document.addEventListener('mouseup', checkSelection, { passive: true });
        document.addEventListener('touchend', checkSelection, { passive: true });

        // Option/Alt + Click on desktop or 550ms long-press on mobile over an <img> surfaces Quick Image Clip
        document.addEventListener('click', function(ev) {
            if (!ev.altKey) return;
            var img = ev.target && ev.target.closest ? ev.target.closest('img') : null;
            if (img && (img.currentSrc || img.src)) {
                ev.preventDefault();
                ev.stopPropagation();
                postToNative({
                    type: 'imageCandidate',
                    src: img.currentSrc || img.src,
                    alt: img.alt || document.title || 'Web Image',
                    width: img.naturalWidth || img.width || 0,
                    height: img.naturalHeight || img.height || 0
                });
            }
        }, true);

        var touchImgTimer = null;
        document.addEventListener('touchstart', function(ev) {
            var t = ev.touches && ev.touches[0];
            if (!t) return;
            var img = ev.target && ev.target.closest ? ev.target.closest('img') : null;
            if (!img || !(img.currentSrc || img.src)) return;
            if ((img.width || 0) < 72 && (img.height || 0) < 72) return;
            clearTimeout(touchImgTimer);
            touchImgTimer = setTimeout(function() {
                postToNative({
                    type: 'imageCandidate',
                    src: img.currentSrc || img.src,
                    alt: img.alt || document.title || 'Web Image',
                    width: img.naturalWidth || img.width || 0,
                    height: img.naturalHeight || img.height || 0
                });
            }, 560);
        }, { passive: true });
        document.addEventListener('touchmove', function() { clearTimeout(touchImgTimer); }, { passive: true });
        document.addEventListener('touchend', function() { clearTimeout(touchImgTimer); }, { passive: true });

        // Throttled scroll tracking for tab hibernation restoration
        var scrollTimer = null;
        window.addEventListener('scroll', function() {
            if (scrollTimer) return;
            scrollTimer = setTimeout(function() {
                scrollTimer = null;
                postToNative({
                    type: 'scroll',
                    scrollY: window.scrollY || window.pageYOffset || 0
                });
            }, 450);
        }, { passive: true });

        // Rich page context extraction for Prism Co-Pilot & Vault
        window.__prismExtractPageContext = function() {
            var sel = window.getSelection ? window.getSelection().toString().trim() : '';
            var mainEl = document.querySelector('article, main, [role="main"]') || document.body;
            var rawText = mainEl ? (mainEl.innerText || '') : '';
            var cleanText = rawText.replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 18000);
            var ogImg = document.querySelector('meta[property="og:image"], meta[name="twitter:image"]');
            var imgs = Array.from(document.querySelectorAll('img'))
                .filter(function(i) {
                    var s = i.currentSrc || i.src || '';
                    return s.startsWith('http') && (i.naturalWidth >= 160 || i.width >= 160);
                })
                .slice(0, 16)
                .map(function(i) {
                    return {
                        src: i.currentSrc || i.src,
                        alt: i.alt || '',
                        width: i.naturalWidth || i.width || 0,
                        height: i.naturalHeight || i.height || 0
                    };
                });
            return JSON.stringify({
                title: document.title || location.hostname,
                url: location.href,
                selectedText: sel.slice(0, 4000),
                bodyText: cleanText,
                ogImage: ogImg ? ogImg.content : null,
                images: imgs
            });
        };
    })();
    """

    // MARK: - Prism Shield (Native WebKit Content Rule List)

    public static let blockedTrackerDomains: [String] = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "google-analytics.com",
        "googletagmanager.com",
        "adnxs.com",
        "criteo.com",
        "criteo.net",
        "taboola.com",
        "outbrain.com",
        "scorecardresearch.com",
        "quantserve.com",
        "rubiconproject.com",
        "pubmatic.com",
        "openx.net",
        "casalemedia.com",
        "moatads.com",
        "adsrvr.org",
        "hotjar.com",
        "popads.net",
        "adform.net",
        "smartadserver.com",
        "teads.tv",
        "zemanta.com"
    ]

    public static func contentBlockerRulesJSON(allowlistedDomains: [String] = []) -> String {
        let sanitizedAllowlist = allowlistedDomains
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("*") ? $0 : "*\($0)" }

        var rules: [[String: Any]] = blockedTrackerDomains.map { domain in
            var trigger: [String: Any] = [
                "url-filter": "^https?://([a-z0-9-]+\\.)*\(domain.replacingOccurrences(of: ".", with: "\\."))/",
                "load-type": ["third-party"]
            ]
            if !sanitizedAllowlist.isEmpty {
                trigger["unless-domain"] = sanitizedAllowlist
            }
            return [
                "trigger": trigger,
                "action": ["type": "block"]
            ]
        }

        // Hide common intrusive ad containers cleanly via native CSS selector injection
        var cosmeticTrigger: [String: Any] = [
            "url-filter": ".*"
        ]
        if !sanitizedAllowlist.isEmpty {
            cosmeticTrigger["unless-domain"] = sanitizedAllowlist
        }
        rules.append([
            "trigger": cosmeticTrigger,
            "action": [
                "type": "css-display-none",
                "selector": ".adsbygoogle, ins.adsbygoogle, div[id^='google_ads_iframe'], .taboola-below-article-thumbnails, .OUTBRAIN"
            ]
        ])

        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    #if canImport(WebKit)
    @MainActor
    public static func compileShieldRuleList(allowlistedDomains: [String]) async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        let identifier = "PrismShieldRules_v1_\(allowlistedDomains.sorted().joined(separator: "_").hashValue)"
        if let existing = try? await store.contentRuleList(forIdentifier: identifier) {
            return existing
        }
        let json = contentBlockerRulesJSON(allowlistedDomains: allowlistedDomains)
        return try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
    }
    #endif
}
