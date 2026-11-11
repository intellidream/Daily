import SwiftUI
import WebKit
import UIKit
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

/// Manages the Single-Active `WKWebView` instance on iOS & Foldables (`SimulaDuo` / `Schmitz`).
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

    @Published public var isBottomOmniboxCollapsed: Bool = false
    @Published public var selectionState: PrismSelectionOverlayState? = nil
    @Published public var imageCandidate: PrismImageCandidate? = nil
    @Published public var oauthPopupWebView: WKWebView? = nil
    @Published public var oauthPopupTitle: String = "Sign In"

    @Published public var isReaderModeActive: Bool = false
    @Published public var extractedReaderArticle: NewsArticle? = nil
    @Published public var isExtractingReader: Bool = false
    @Published public var toastMessage: String? = nil

    @Published public private(set) var activeTabId: UUID? = nil
    private var tabWebViews: [UUID: WKWebView] = [:]
    private var activeIsPrivate: Bool = false
    private var pendingScrollRestoreY: Double = 0
    private var lastScrollY: Double = 0

    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?

    public static let mobileSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1"

    public override init() {
        super.init()
    }

    public var activeWebView: WKWebView {
        if let currentId = activeTabId, let existing = tabWebViews[currentId] {
            return existing
        }
        if let first = tabWebViews.values.first {
            return first
        }
        let fallback = buildWebView(isPrivate: activeIsPrivate)
        if let currentId = activeTabId {
            tabWebViews[currentId] = fallback
        }
        attachKVO(to: fallback)
        return fallback
    }

    public func removeTabWebView(for tabId: UUID) {
        if let wv = tabWebViews[tabId] {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            tabWebViews.removeValue(forKey: tabId)
        }
    }

    private func buildWebView(isPrivate: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        config.allowsInlineMediaPlayback = true
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
        wv.customUserAgent = Self.mobileSafariUserAgent
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = .clear
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
        showToast(isShieldActiveForCurrentDomain ? "Prism Shield Active" : "Shield Paused for Site")
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

    // MARK: - Tab Synchronization & Multi-Tab WebViews Pool

    public func syncWithActiveTab(_ tab: PrismTabState?) {
        guard let tab = tab else { return }

        // Clean up webViews for tabs that were removed from PrismStore
        let validIds = Set(PrismStore.shared.tabs.map(\.id))
        let closedIds = tabWebViews.keys.filter { !validIds.contains($0) }
        for id in closedIds {
            removeTabWebView(for: id)
        }

        activeTabId = tab.id
        activeIsPrivate = tab.isPrivate

        if tab.isStartPage {
            currentURLString = ""
            pageTitle = tab.isPrivate ? "Private Tab" : "Start Page"
            detectedRssUrl = nil
            detectedRssTitle = nil
            selectionState = nil
            isReaderModeActive = false
            extractedReaderArticle = nil
            isBottomOmniboxCollapsed = false
            objectWillChange.send()
            return
        }

        if let existingWv = tabWebViews[tab.id] {
            // Tab already active and loaded in memory!
            // Seamless switch - DO NOT RELOAD!
            attachKVO(to: existingWv)
            currentURLString = existingWv.url?.absoluteString ?? tab.url
            pageTitle = existingWv.title ?? tab.title
            canGoBack = existingWv.canGoBack
            canGoForward = existingWv.canGoForward
            isLoading = existingWv.isLoading
            estimatedProgress = existingWv.estimatedProgress
            isSecureHTTPS = currentURLString.lowercased().hasPrefix("https://")
            isReaderModeActive = tab.isReaderMode
            detectedRssUrl = tab.detectedRssUrl
            detectedRssTitle = tab.detectedRssTitle
            selectionState = nil
            isBottomOmniboxCollapsed = false

            if (existingWv.url == nil || existingWv.url?.absoluteString == "about:blank") && !tab.url.isEmpty {
                loadURLString(tab.url)
            }
            objectWillChange.send()
        } else {
            // First time loading this tab: instantiate its dedicated WKWebView
            let wv = buildWebView(isPrivate: tab.isPrivate)
            tabWebViews[tab.id] = wv
            attachKVO(to: wv)
            selectionState = nil
            isReaderModeActive = tab.isReaderMode
            extractedReaderArticle = nil
            detectedRssUrl = tab.detectedRssUrl
            detectedRssTitle = tab.detectedRssTitle
            pendingScrollRestoreY = tab.scrollY
            isBottomOmniboxCollapsed = false
            if !tab.url.isEmpty {
                loadURLString(tab.url)
            }
            objectWillChange.send()
        }
    }

    public func loadOmniboxInput(_ input: String) {
        let engine = SettingsService.shared.settings.prismSearchEngine
        guard let url = PrismSearchEngine.resolveOmniboxInput(input, engine: engine) else {
            showToast("Invalid or blocked address")
            return
        }
        isReaderModeActive = false
        extractedReaderArticle = nil
        selectionState = nil
        isBottomOmniboxCollapsed = false
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
        for wv in tabWebViews.values {
            wv.evaluateJavaScript("document.querySelectorAll('video, audio').forEach(m => m.pause());", completionHandler: nil)
        }
    }

    public func openInSystemBrowser() {
        guard let url = URL(string: currentURLString), !currentURLString.isEmpty else { return }
        UIApplication.shared.open(url)
    }

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
            publicationIconUrl: PrismSearchEngine.faviconURLString(for: targetUrl)
        )

        Task {
            let full = await NewsService.shared.fetchFullArticle(article: baseArticle)
            self.extractedReaderArticle = full
            self.isExtractingReader = false
        }
    }

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
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.85))
            }
        }
    }

    public func showToast(_ message: String) {
        if SettingsService.shared.settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = message
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

    // MARK: - OAuth & Link Detection Helpers

    private func isOAuthOrAuthenticationRequest(url: URL, windowFeatures: WKWindowFeatures) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = (url.query ?? "").lowercased()

        let authDomains = [
            "instagram.com", "threads.net", "threads.com", "facebook.com", "meta.com",
            "accounts.google.com", "appleid.apple.com", "github.com",
            "twitter.com", "x.com", "linkedin.com", "discord.com",
            "login.microsoftonline.com", "login.live.com", "auth0.com", "okta.com"
        ]

        if authDomains.contains(where: { host.contains($0) }) {
            if path.contains("login") || path.contains("auth") || path.contains("oauth") ||
               path.contains("signin") || path.contains("checkpoint") || path.contains("two_factor") ||
               query.contains("client_id") || query.contains("redirect_uri") || query.contains("response_type") {
                return true
            }
        }

        if path.contains("/oauth") || path.contains("/auth/") || path.contains("/login") || path.contains("/signin") {
            return true
        }

        if query.contains("client_id=") || query.contains("redirect_uri=") || query.contains("response_type=") {
            return true
        }

        if windowFeatures.width != nil || windowFeatures.height != nil {
            return true
        }

        return false
    }

    private func isOAuthCompletionRedirect(url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let query = (url.query ?? "").lowercased()

        if let activeUrl = URL(string: currentURLString), let activeHost = activeUrl.host?.lowercased() {
            let cleanActive = PrismSearchEngine.extractCleanDomain(from: activeHost)
            let cleanPopup = PrismSearchEngine.extractCleanDomain(from: host)
            if !cleanActive.isEmpty && (cleanActive == cleanPopup || (cleanActive.contains("threads") && cleanPopup.contains("threads"))) {
                if !path.contains("login") && !path.contains("oauth/authorize") && !path.contains("accounts/login") {
                    return true
                }
                if query.contains("code=") || query.contains("oauth_token=") || query.contains("access_token=") {
                    return true
                }
            }
        }

        if path.hasSuffix("/oauth/callback") || path.hasSuffix("/auth/callback") || path.contains("login/callback") {
            return true
        }

        return false
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

        // Handle app-specific OAuth callback schemes (e.g. threads://, instagram://, barcelona://, fbconnect://)
        let authCallbackSchemes: Set<String> = ["threads", "instagram", "barcelona", "fbconnect"]
        if authCallbackSchemes.contains(scheme) {
            if webView === oauthPopupWebView {
                self.oauthPopupWebView = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.activeWebView.reload()
                }
            }
            decisionHandler(.cancel)
            return
        }

        let allowedSchemes: Set<String> = ["https", "http", "about", "blob"]
        guard allowedSchemes.contains(scheme) else {
            decisionHandler(.cancel)
            return
        }

        // Handle OAuth Popup Completion / Redirect back to target domain
        if webView === oauthPopupWebView {
            if isOAuthCompletionRedirect(url: url) {
                self.oauthPopupWebView = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    self.activeWebView.reload()
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }

        // Target=_blank link clicked in web page: open in new tab!
        if navigationAction.targetFrame == nil {
            if navigationAction.navigationType == .linkActivated {
                PrismStore.shared.openNewTab(url: url.absoluteString, isPrivate: activeIsPrivate)
                decisionHandler(.cancel)
                return
            } else {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
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
            if let u = webView.url, isOAuthCompletionRedirect(url: u) {
                oauthPopupWebView = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    self.activeWebView.reload()
                }
            }
            return
        }
        isLoading = false
        lastScrollY = 0
        if pendingScrollRestoreY > 10 {
            let y = pendingScrollRestoreY
            pendingScrollRestoreY = 0
            webView.evaluateJavaScript("window.scrollTo({ top: \(y), behavior: 'instant' });", completionHandler: nil)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView !== oauthPopupWebView { isLoading = false }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView !== oauthPopupWebView { isLoading = false }
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        // 1. True federated OAuth / SSO popup windows keep window.opener intact inside a modal sub-sheet
        if isOAuthOrAuthenticationRequest(url: url, windowFeatures: windowFeatures) {
            configuration.websiteDataStore = activeWebView.configuration.websiteDataStore
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.customUserAgent = Self.mobileSafariUserAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self
            let host = (url.host ?? "").lowercased()
            self.oauthPopupTitle = host.isEmpty ? "Sign In" : host
            self.oauthPopupWebView = popup
            return popup
        }

        // 2. Normal link or target="_blank" window.open request -> OPEN IN NEW TAB!
        let newTab = PrismStore.shared.openNewTab(url: url.absoluteString, isPrivate: activeIsPrivate)
        let newWv = buildWebView(isPrivate: newTab.isPrivate)
        tabWebViews[newTab.id] = newWv
        return newWv
    }

    public func webViewDidClose(_ webView: WKWebView) {
        if webView === oauthPopupWebView {
            oauthPopupWebView = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.activeWebView.reload()
            }
        }
    }

    // MARK: - Native iOS Long-Press Context Menu (Open in New Tab, Private Tab, Vault, Share)

    public func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let linkUrl = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }

        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let openNewTabAction = UIAction(
                title: "Open in New Tab",
                image: UIImage(systemName: "plus.square.on.square")
            ) { _ in
                PrismStore.shared.openNewTab(url: linkUrl.absoluteString, isPrivate: false)
            }

            let openPrivateTabAction = UIAction(
                title: "Open in Private Tab",
                image: UIImage(systemName: "eyeglasses")
            ) { _ in
                PrismStore.shared.openNewTab(url: linkUrl.absoluteString, isPrivate: true)
            }

            let saveClipAction = UIAction(
                title: "Save Link to Vault",
                image: UIImage(systemName: "bookmark")
            ) { _ in
                PrismStore.shared.saveLinkClip(url: linkUrl.absoluteString, title: "")
                self?.showToast("Saved Link to Vault")
            }

            let copyAction = UIAction(
                title: "Copy Link",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.url = linkUrl
                self?.showToast("Copied Link")
            }

            let shareAction = UIAction(
                title: "Share...",
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                let av = UIActivityViewController(activityItems: [linkUrl], applicationActivities: nil)
                if let topVc = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first {
                    topVc.present(av, animated: true)
                }
            }

            return UIMenu(title: linkUrl.host ?? "Link Options", children: [
                openNewTabAction,
                openPrivateTabAction,
                saveClipAction,
                copyAction,
                shareAction
            ])
        }
        completionHandler(config)
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
                if SettingsService.shared.settings.hapticsEnabled {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
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
                if SettingsService.shared.settings.hapticsEnabled {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    self.imageCandidate = PrismImageCandidate(src: src, alt: alt, width: w, height: h)
                }
            }

        case "scroll":
            if let sy = body["scrollY"] as? Double {
                let delta = sy - lastScrollY
                if sy > 90 && delta > 18 && !isBottomOmniboxCollapsed {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isBottomOmniboxCollapsed = true
                    }
                } else if (delta < -16 || sy <= 40) && isBottomOmniboxCollapsed {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isBottomOmniboxCollapsed = false
                    }
                }
                lastScrollY = sy
                PrismStore.shared.updateActiveTabMetadata(scrollY: sy)
            }

        default:
            break
        }
    }
}

private final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(target: WKScriptMessageHandler) {
        self.target = target
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

public struct PrismHostedWebView: UIViewRepresentable {
    public let webView: WKWebView

    public init(webView: WKWebView) {
        self.webView = webView
    }

    public func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        embed(webView, into: container)
        return container
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        if webView.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            embed(webView, into: uiView)
        }
    }

    private func embed(_ child: WKWebView, into container: UIView) {
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
