import SwiftUI
import WebKit
import AppKit
import DailyCore

public struct PrismPageContextPayload: Decodable, Sendable {
    public struct PageImageInfo: Decodable, Sendable, Identifiable {
        public var id: String { src }
        public let src: String
        public let alt: String
        public let width: Int
        public let height: Int
    }
    public let title: String
    public let url: String
    public let selectedText: String
    public let bodyText: String
    public let ogImage: String?
    public let images: [PageImageInfo]
}

public struct PrismSelectionOverlayState: Equatable, Sendable {
    public let text: String
    public let centerX: CGFloat
    public let topY: CGFloat
    public let bottomY: CGFloat
    public let viewportWidth: CGFloat
    public let viewportHeight: CGFloat
}

public struct PrismImageCandidate: Identifiable, Equatable, Sendable {
    public var id: String { src }
    public let src: String
    public let alt: String
    public let width: Int
    public let height: Int
}

/// Manages the Single-Active `WKWebView` instance on macOS, enforcing:
/// - Shared persistent cookie/storage profile with News (`WKWebsiteDataStore.default()`) + isolated ephemeral mode (`nonPersistent()`).
/// - OAuth popup window delegation (`WKUIDelegate.createWebViewWith`) inside an in-app modal sheet.
/// - Native WebKit bytecode content blocking (`Prism Shield`) with per-domain toggle.
/// - Floating text selection coordinates, image candidate capture, Reader extraction, and Viewport Region Cropping.
@MainActor
public final class PrismWebEngineModel: NSObject, ObservableObject {

    @Published public var currentURLString: String = ""
    @Published public var pageTitle: String = ""
    @Published public var isLoading: Bool = false
    @Published public var estimatedProgress: Double = 0.0
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var isSecureHTTPS: Bool = true
    @Published public var detectedRssUrl: String? = nil
    @Published public var detectedRssTitle: String? = nil
    @Published public var ogImageUrl: String? = nil

    @Published public var selectionState: PrismSelectionOverlayState? = nil
    @Published public var imageCandidate: PrismImageCandidate? = nil
    @Published public var oauthPopupWebView: WKWebView? = nil
    @Published public var oauthPopupTitle: String = "Sign In"

    @Published public var isReaderModeActive: Bool = false
    @Published public var extractedReaderArticle: NewsArticle? = nil
    @Published public var isExtractingReader: Bool = false

    @Published public var toastMessage: String? = nil

    public private(set) var persistentWebView: WKWebView?
    public private(set) var privateWebView: WKWebView?
    private var activeIsPrivate: Bool = false
    private var loadedTabId: UUID? = nil
    private var pendingScrollRestoreY: Double = 0
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?

    public static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

    public override init() {
        super.init()
    }

    public var activeWebView: WKWebView {
        if activeIsPrivate {
            if let existing = privateWebView { return existing }
            let created = buildWebView(isPrivate: true)
            privateWebView = created
            attachKVO(to: created)
            return created
        } else {
            if let existing = persistentWebView { return existing }
            let created = buildWebView(isPrivate: false)
            persistentWebView = created
            attachKVO(to: created)
            return created
        }
    }

    private func buildWebView(isPrivate: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()
        let observerScript = WKUserScript(
            source: PrismWebScripts.pageObserverScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(observerScript)
        contentController.add(WeakScriptMessageProxy(target: self), name: PrismWebScripts.bridgeHandlerName)
        config.userContentController = contentController

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.desktopSafariUserAgent
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = self
        wv.uiDelegate = self

        Task { @MainActor [weak self, weak wv] in
            guard let self = self, let wv = wv else { return }
            await self.refreshShieldRules(on: wv)
        }
        return wv
    }

    private func attachKVO(to webView: WKWebView) {
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.estimatedProgress = wv.estimatedProgress
            }
        }
        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                if let t = wv.title, !t.isEmpty {
                    self?.pageTitle = t
                    PrismStore.shared.updateActiveTabMetadata(title: t)
                }
            }
        }
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                if let u = wv.url?.absoluteString, !u.isEmpty, u != "about:blank" {
                    self?.currentURLString = u
                    self?.isSecureHTTPS = u.lowercased().hasPrefix("https://")
                    PrismStore.shared.updateActiveTabMetadata(url: u)
                }
            }
        }
        backObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.canGoBack = wv.canGoBack
            }
        }
        forwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            Task { @MainActor [weak self] in
                self?.canGoForward = wv.canGoForward
            }
        }
    }

    // MARK: - Prism Shield Management

    public var isShieldActiveForCurrentDomain: Bool {
        let settings = SettingsService.shared.settings
        guard settings.prismShieldEnabled else { return false }
        let domain = PrismSearchEngine.extractCleanDomain(from: currentURLString)
        guard !domain.isEmpty else { return true }
        return !settings.prismShieldAllowlist.contains(where: { $0.caseInsensitiveCompare(domain) == .orderedSame })
    }

    public func toggleShieldForCurrentDomain() {
        let domain = PrismSearchEngine.extractCleanDomain(from: currentURLString)
        guard !domain.isEmpty else {
            SettingsService.shared.update { $0.prismShieldEnabled.toggle() }
            Task { await reloadShieldAndPage() }
            return
        }

        SettingsService.shared.update { settings in
            if !settings.prismShieldEnabled {
                settings.prismShieldEnabled = true
                settings.prismShieldAllowlist.removeAll { $0.caseInsensitiveCompare(domain) == .orderedSame }
            } else if let idx = settings.prismShieldAllowlist.firstIndex(where: { $0.caseInsensitiveCompare(domain) == .orderedSame }) {
                settings.prismShieldAllowlist.remove(at: idx)
            } else {
                settings.prismShieldAllowlist.append(domain)
            }
        }
        Task { await reloadShieldAndPage() }
    }

    private func reloadShieldAndPage() async {
        await refreshShieldRules(on: activeWebView)
        activeWebView.reload()
        showToast(isShieldActiveForCurrentDomain ? "Prism Shield Enabled" : "Shield Paused for Domain")
    }

    public func refreshShieldRules(on webView: WKWebView) async {
        let settings = SettingsService.shared.settings
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard settings.prismShieldEnabled else { return }
        if let compiled = await PrismWebScripts.compileShieldRuleList(allowlistedDomains: settings.prismShieldAllowlist) {
            controller.add(compiled)
        }
    }

    // MARK: - Tab Synchronization & Hibernation Restoration

    public func syncWithActiveTab(_ tab: PrismTabState?) {
        guard let tab = tab else { return }

        if tab.isPrivate != activeIsPrivate {
            if activeIsPrivate && !tab.isPrivate {
                // Tear down ephemeral private WebView when leaving private mode
                privateWebView?.stopLoading()
                privateWebView = nil
            }
            activeIsPrivate = tab.isPrivate
            attachKVO(to: activeWebView)
        }

        let switchedTab = (loadedTabId != tab.id)
        loadedTabId = tab.id

        if tab.isStartPage {
            currentURLString = ""
            pageTitle = tab.isPrivate ? "Private Tab" : "Start Page"
            detectedRssUrl = nil
            detectedRssTitle = nil
            selectionState = nil
            isReaderModeActive = false
            extractedReaderArticle = nil
            return
        }

        if switchedTab || activeWebView.url?.absoluteString != tab.url {
            selectionState = nil
            isReaderModeActive = tab.isReaderMode
            extractedReaderArticle = nil
            detectedRssUrl = tab.detectedRssUrl
            detectedRssTitle = tab.detectedRssTitle
            pendingScrollRestoreY = tab.scrollY
            loadURLString(tab.url)
        }
    }

    public func loadOmniboxInput(_ input: String) {
        let engine = SettingsService.shared.settings.prismSearchEngine
        guard let url = PrismSearchEngine.resolveOmniboxInput(input, engine: engine) else {
            showToast("Blocked or invalid address")
            return
        }
        isReaderModeActive = false
        extractedReaderArticle = nil
        selectionState = nil
        PrismStore.shared.updateActiveTabMetadata(
            url: url.absoluteString,
            isReaderMode: false,
            detectedRssUrl: .some(nil),
            detectedRssTitle: .some(nil)
        )
        loadURLString(url.absoluteString)
    }

    public func loadURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        currentURLString = urlString
        isSecureHTTPS = urlString.lowercased().hasPrefix("https://")
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25)
        activeWebView.load(request)
    }

    public func goBack() {
        if isReaderModeActive {
            isReaderModeActive = false
            return
        }
        activeWebView.goBack()
    }

    public func goForward() {
        activeWebView.goForward()
    }

    public func reloadOrStop() {
        if isLoading {
            activeWebView.stopLoading()
        } else {
            activeWebView.reload()
        }
    }

    public func pauseBackgroundMedia() {
        persistentWebView?.evaluateJavaScript("document.querySelectorAll('video, audio').forEach(m => m.pause());", completionHandler: nil)
        privateWebView?.evaluateJavaScript("document.querySelectorAll('video, audio').forEach(m => m.pause());", completionHandler: nil)
    }

    public func openInSystemBrowser() {
        guard let url = URL(string: currentURLString), !currentURLString.isEmpty else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 1-Tap Distraction-Free Reader Mode

    public func toggleReaderMode() {
        guard !currentURLString.isEmpty else { return }
        if isReaderModeActive {
            isReaderModeActive = false
            PrismStore.shared.updateActiveTabMetadata(isReaderMode: false)
            return
        }

        isReaderModeActive = true
        PrismStore.shared.updateActiveTabMetadata(isReaderMode: true)
        isExtractingReader = true

        let targetUrl = currentURLString
        let baseArticle = NewsArticle(
            title: pageTitle.isEmpty ? PrismSearchEngine.extractCleanDomain(from: targetUrl) : pageTitle,
            link: targetUrl,
            imageUrl: ogImageUrl,
            publicationName: PrismSearchEngine.extractCleanDomain(from: targetUrl),
            publicationIconUrl: PrismSearchEngine.faviconURLString(from: targetUrl)
        )

        Task {
            let full = await NewsService.shared.fetchFullArticle(article: baseArticle)
            self.extractedReaderArticle = full
            self.isExtractingReader = false
        }
    }

    // MARK: - Rich Context Extraction & Viewport Region Crop

    public func extractPageContext() async -> PrismPageContextPayload {
        do {
            if let raw = try await activeWebView.evaluateJavaScript("window.__prismExtractPageContext ? window.__prismExtractPageContext() : ''") as? String,
               !raw.isEmpty,
               let data = raw.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(PrismPageContextPayload.self, from: data) {
                return decoded
            }
        } catch {}

        return PrismPageContextPayload(
            title: pageTitle,
            url: currentURLString,
            selectedText: selectionState?.text ?? "",
            bodyText: "",
            ogImage: ogImageUrl,
            images: []
        )
    }

    /// Captures a specific rectangular region (in view coordinates) of the live `WKWebView` as JPEG Data.
    public func captureViewportCrop(rectInView: CGRect, viewBounds: CGRect) async -> Data? {
        guard viewBounds.width > 10, viewBounds.height > 10, rectInView.width > 8, rectInView.height > 8 else {
            return nil
        }
        let config = WKSnapshotConfiguration()
        let clamped = rectInView.intersection(CGRect(origin: .zero, size: viewBounds.size))
        guard !clamped.isNull, clamped.width > 4, clamped.height > 4 else { return nil }
        config.rect = clamped

        return await withCheckedContinuation { continuation in
            activeWebView.takeSnapshot(with: config) { image, _ in
                guard let nsImage = image,
                      let tiff = nsImage.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: jpeg)
            }
        }
    }

    public func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = message
        }
        if SettingsService.shared.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self?.toastMessage == message {
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.toastMessage = nil
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate & WKUIDelegate & Script Bridge

extension PrismWebEngineModel: WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = (url.scheme ?? "").lowercased()
        let allowedSchemes: Set<String> = ["https", "http", "about", "blob"]
        guard allowedSchemes.contains(scheme) else {
            decisionHandler(.cancel)
            return
        }

        // Route regular `_blank` anchor clicks smoothly into the active WebView (while `createWebViewWith` handles true JS OAuth popups)
        if navigationAction.targetFrame == nil && navigationAction.navigationType == .linkActivated {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === oauthPopupWebView { return }
        isLoading = true
        selectionState = nil
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === oauthPopupWebView {
            oauthPopupTitle = webView.title ?? "Sign In"
            return
        }
        isLoading = false
        if pendingScrollRestoreY > 10 {
            let y = pendingScrollRestoreY
            pendingScrollRestoreY = 0
            webView.evaluateJavaScript("window.scrollTo({ top: \(y), behavior: 'instant' });", completionHandler: nil)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView !== oauthPopupWebView {
            isLoading = false
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView !== oauthPopupWebView {
            isLoading = false
        }
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let host = (url.host ?? "").lowercased()

        // True federated OAuth / SSO popup windows keep `window.opener` intact inside a modal sub-sheet
        let isOAuthPopup = host.contains("accounts.google.com") ||
            host.contains("appleid.apple.com") ||
            host.contains("facebook.com") ||
            host.contains("github.com/login") ||
            host.contains("oauth") ||
            host.contains("auth0") ||
            windowFeatures.width != nil

        if isOAuthPopup {
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.customUserAgent = Self.desktopSafariUserAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self
            self.oauthPopupTitle = host.isEmpty ? "Authenticate" : host
            self.oauthPopupWebView = popup
            return popup
        }

        webView.load(navigationAction.request)
        return nil
    }

    public func webViewDidClose(_ webView: WKWebView) {
        if webView === oauthPopupWebView {
            oauthPopupWebView = nil
        }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == PrismWebScripts.bridgeHandlerName,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }

        switch type {
        case "metadata":
            let rssUrl = body["rssUrl"] as? String
            let rssTitle = body["rssTitle"] as? String
            let ogImg = body["ogImage"] as? String
            self.detectedRssUrl = (rssUrl?.isEmpty == false) ? rssUrl : nil
            self.detectedRssTitle = rssTitle
            self.ogImageUrl = ogImg
            PrismStore.shared.updateActiveTabMetadata(
                detectedRssUrl: .some(self.detectedRssUrl),
                detectedRssTitle: .some(self.detectedRssTitle)
            )

        case "selection":
            if let text = body["text"] as? String,
               let x = body["x"] as? Double,
               let y = body["y"] as? Double,
               let bottom = body["bottom"] as? Double,
               let vw = body["viewportWidth"] as? Double,
               let vh = body["viewportHeight"] as? Double {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    self.selectionState = PrismSelectionOverlayState(
                        text: text,
                        centerX: CGFloat(x),
                        topY: CGFloat(y),
                        bottomY: CGFloat(bottom),
                        viewportWidth: CGFloat(max(1, vw)),
                        viewportHeight: CGFloat(max(1, vh))
                    )
                }
            }

        case "selectionCleared":
            if selectionState != nil {
                withAnimation(.easeOut(duration: 0.18)) {
                    self.selectionState = nil
                }
            }

        case "imageCandidate":
            if let src = body["src"] as? String, !src.isEmpty {
                let alt = (body["alt"] as? String) ?? pageTitle
                let w = (body["width"] as? Int) ?? 0
                let h = (body["height"] as? Int) ?? 0
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    self.imageCandidate = PrismImageCandidate(src: src, alt: alt, width: w, height: h)
                }
            }

        case "scroll":
            if let sy = body["scrollY"] as? Double {
                PrismStore.shared.updateActiveTabMetadata(scrollY: sy)
            }

        default:
            break
        }
    }
}

/// Prevents retain cycles between `WKUserContentController` and `PrismWebEngineModel`.
private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) {
        self.target = target
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

private extension PrismSearchEngine {
    static func faviconURLString(from urlString: String) -> String {
        faviconURLString(for: urlString)
    }
}

/// Thin `NSViewRepresentable` wrapper hosting the single active `WKWebView` without recreating it on SwiftUI state ticks.
public struct PrismHostedWebView: NSViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        embed(webView, into: container)
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if webView.superview !== nsView {
            nsView.subviews.forEach { $0.removeFromSuperview() }
            embed(webView, into: nsView)
        }
    }

    private func embed(_ child: WKWebView, into container: NSView) {
        child.removeFromSuperview()
        child.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.topAnchor.constraint(equalTo: container.topAnchor),
            child.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
