import SwiftUI
import WebKit
import DailyCore

/// Modern authentication sheet for Medium supporting both browser-based OAuth/redirect login and direct handle configuration.
public struct MediumLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settingsService = SettingsService.shared
    
    @State private var manualUsername = ""
    @State private var isLoadingWeb = true
    @State private var errorMessage: String?
    
    private let clearExistingSession: Bool
    
    public init(clearExistingSession: Bool = false) {
        self.clearExistingSession = clearExistingSession
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#120D1A").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Quick Direct Handle Setup Bar
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "at")
                                .foregroundColor(ThemeColors.accentCyan)
                                .font(.system(size: 14, weight: .bold))
                            
                            TextField("Enter Medium handle (e.g. johndoe)", text: $manualUsername)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                            
                            Button("Connect") {
                                connectManualUsername()
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(ThemeColors.accentCyan)
                            )
                            .disabled(manualUsername.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).isEmpty)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                        
                        Text("Or sign in below to automatically detect your Medium account & reading list")
                            .font(.system(size: 11))
                            .foregroundColor(ThemeColors.fgMutedDark)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.3))
                    
                    Divider().background(Color.white.opacity(0.12))
                    
                    // WebKit Browser View
                    ZStack {
                        MediumWebViewRepresentable(
                            initialUrl: URL(string: "https://medium.com/m/signin")!,
                            clearExistingSession: clearExistingSession,
                            isLoading: $isLoadingWeb,
                            onUsernameDetected: { username in
                                handleDetectedUsername(username)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if isLoadingWeb {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(ThemeColors.accentCyan)
                                Text("Loading Medium...")
                                    .font(.system(size: 12))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(hex: "#120D1A").opacity(0.85))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Login to Medium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private func connectManualUsername() {
        let clean = manualUsername.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n"))
        guard !clean.isEmpty else { return }
        settingsService.update {
            $0.newsMediumUsername = clean
            if $0.newsMediumReadingListUrl == nil || $0.newsMediumReadingListUrl?.isEmpty == true {
                $0.newsMediumReadingListUrl = "https://medium.com/@\(clean)/list/reading-list"
            }
        }
        dismiss()
    }
    
    private func handleDetectedUsername(_ username: String) {
        settingsService.update {
            $0.newsMediumUsername = username
            $0.newsMediumReadingListUrl = "https://medium.com/@\(username)/list/reading-list"
        }
        dismiss()
    }
}

/// WKWebView coordinator monitoring Medium OAuth completion only after full navigation commit & cookie persistence.
private struct MediumWebViewRepresentable: UIViewRepresentable {
    let initialUrl: URL
    let clearExistingSession: Bool
    @Binding var isLoading: Bool
    let onUsernameDetected: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = HeadlessReadabilityParser.mediumSafariUserAgent
        
        let shouldClear = clearExistingSession
        let targetUrl = initialUrl
        Task { @MainActor in
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            if shouldClear {
                let cookies = await cookieStore.allCookies()
                for cookie in cookies where cookie.domain.lowercased().contains("medium.com") {
                    await cookieStore.deleteCookie(cookie)
                }
            } else {
                await HeadlessReadabilityParser.shared.sanitizeMediumCookies()
                // Remove stale guest `lo_*` uid cookies prior to sign-in so OAuth writes a clean member uid
                let cookies = await cookieStore.allCookies()
                for cookie in cookies where cookie.domain.lowercased().contains("medium.com") &&
                    cookie.name == "uid" && !ArticleExtractor.isAuthenticatedMediumUid(cookie.value) {
                    await cookieStore.deleteCookie(cookie)
                }
            }
            webView.load(URLRequest(url: targetUrl))
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: MediumWebViewRepresentable
        private var detectedCompleted = false
        private var didRequestProfileRedirect = false
        
        private static let ignoredHosts: Set<String> = [
            "help.medium.com",
            "policy.medium.com",
            "status.medium.com",
            "blog.medium.com",
            "cdn-client.medium.com",
            "miro.medium.com",
            "glyph.medium.com",
            "meter.medium.com"
        ]
        
        init(_ parent: MediumWebViewRepresentable) {
            self.parent = parent
        }
        
        // MARK: - WKUIDelegate (Window & Popup Management for OAuth like Facebook / Google)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            Task { @MainActor in
                await self.verifyAuthenticatedSession(in: webView)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Only redirect target="_blank" OAuth popups into the main frame; NEVER cancel normal OAuth redirects!
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        
        @MainActor
        private func verifyAuthenticatedSession(in webView: WKWebView) async {
            guard !detectedCompleted,
                  let url = webView.url,
                  let host = url.host?.lowercased() else { return }
            
            guard host == "medium.com" || host == "www.medium.com" || host.hasSuffix(".medium.com") else { return }
            guard !Self.ignoredHosts.contains(host) else { return }
            
            let path = url.path
            if path.hasPrefix("/m/signin") ||
               path.hasPrefix("/m/connect") ||
               path.hasPrefix("/m/callback") ||
               path.hasPrefix("/m/start-auth") ||
               path.hasPrefix("/m/account") {
                return
            }
            
            let viewerJs = """
            (function() {
                try {
                    var s = window.__APOLLO_STATE__ || {};
                    var rq = s.ROOT_QUERY || {};
                    var v = rq.viewer;
                    if (!v) return null;
                    var ref = v.__ref || (typeof v === 'string' ? v : null);
                    var u = ref ? s[ref] : v;
                    if (u && u.username) return String(u.username);
                } catch (e) {}
                return null;
            })()
            """
            let viewerUsername = (try? await webView.evaluateJavaScript(viewerJs) as? String)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n"))
            
            let cookieStore = WKWebsiteDataStore.default().httpCookieStore
            var hasAuthCookies = ArticleExtractor.hasAuthenticatedMediumCookies(await cookieStore.allCookies())
            
            // If Apollo already shows an authenticated viewer, wait briefly for WebKit's Networking process to sync HttpOnly cookies
            if !hasAuthCookies && (viewerUsername?.isEmpty == false) {
                for _ in 0..<12 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if ArticleExtractor.hasAuthenticatedMediumCookies(await cookieStore.allCookies()) {
                        hasAuthCookies = true
                        break
                    }
                }
            }
            
            guard hasAuthCookies, !detectedCompleted else { return }
            
            var resolvedUsername: String? = nil
            if let vUser = viewerUsername, !vUser.isEmpty {
                resolvedUsername = vUser
            } else if path.hasPrefix("/@") {
                let parts = path.dropFirst(2).split(separator: "/")
                if let first = parts.first, !first.isEmpty {
                    resolvedUsername = String(first)
                }
            } else if host != "medium.com" && host != "www.medium.com" && host != "api.medium.com" && host.hasSuffix(".medium.com") {
                let sub = host.replacingOccurrences(of: ".medium.com", with: "")
                if !sub.isEmpty {
                    resolvedUsername = sub
                }
            }
            
            if let finalUser = resolvedUsername, !finalUser.isEmpty {
                detectedCompleted = true
                await HeadlessReadabilityParser.shared.sanitizeMediumCookies()
                await ArticleExtractor.clearCache()
                // Allow WebKit's cookie store to flush to disk before the sheet tears down its WKWebView
                try? await Task.sleep(nanoseconds: 350_000_000)
                parent.onUsernameDetected(finalUser)
            } else if !didRequestProfileRedirect && (path == "/" || path.isEmpty) {
                didRequestProfileRedirect = true
                webView.load(URLRequest(url: URL(string: "https://medium.com/me")!))
            }
        }
    }
}
