import SwiftUI
import WebKit
import DailyCore

/// Modern authentication sheet for Substack supporting both browser-based sign-in and direct publication/handle configuration.
public struct SubstackLoginSheet: View {
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
                            Image(systemName: "newspaper.fill")
                                .foregroundColor(ThemeColors.accentCyan)
                                .font(.system(size: 14, weight: .bold))
                            
                            TextField("Enter Substack handle or publication", text: $manualUsername)
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
                            .disabled(manualUsername.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n")).isEmpty)
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
                        
                        Text("Or sign in below to automatically connect your Substack account & subscriptions")
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
                        SubstackWebViewRepresentable(
                            initialUrl: URL(string: "https://substack.com/sign-in")!,
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
                                Text("Loading Substack...")
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
            .navigationTitle("Login to Substack")
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
            $0.newsSubstackUsername = clean
        }
        dismiss()
    }
    
    private func handleDetectedUsername(_ username: String) {
        settingsService.update {
            $0.newsSubstackUsername = username
        }
        dismiss()
    }
}

/// WKWebView coordinator monitoring Substack authentication completion on iOS.
private struct SubstackWebViewRepresentable: UIViewRepresentable {
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
                for cookie in cookies where cookie.domain.lowercased().contains("substack.com") {
                    await cookieStore.deleteCookie(cookie)
                }
            }
            webView.load(URLRequest(url: targetUrl))
        }
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: SubstackWebViewRepresentable
        private var detectedCompleted = false
        
        init(_ parent: SubstackWebViewRepresentable) {
            self.parent = parent
        }
        
        // MARK: - WKUIDelegate (Window & Popup Management for OAuth)
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
            
            guard host == "substack.com" || host == "www.substack.com" || host.hasSuffix(".substack.com") else { return }
            
            let path = url.path
            if path.hasPrefix("/sign-in") || path.hasPrefix("/login") {
                return
            }
            
            let preloadsJs = """
            (function() {
                try {
                    var p = window._preloads;
                    if (!p) return null;
                    var user = p.user;
                    if (!user) return null;
                    return JSON.stringify({
                        id: user.id || null,
                        handle: user.handle || null,
                        name: user.name || null
                    });
                } catch(e) {
                    return null;
                }
            })()
            """
            
            var detectedHandle: String?
            if let result = try? await webView.evaluateJavaScript(preloadsJs) as? String,
               let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let handle = json["handle"] as? String, !handle.isEmpty {
                    detectedHandle = handle
                } else if let name = json["name"] as? String, !name.isEmpty {
                    detectedHandle = name
                }
            }
            
            if detectedHandle == nil && path.hasPrefix("/@") {
                let parts = path.dropFirst(2).split(separator: "/")
                if let first = parts.first, !first.isEmpty {
                    detectedHandle = String(first)
                }
            }
            
            // Verify session cookie presence
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let allCookies = await cookieStore.allCookies()
            let hasSessionCookie = allCookies.contains { cookie in
                (cookie.name == "substack.sid" || cookie.name == "connect.sid") &&
                !cookie.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            
            if hasSessionCookie, let finalHandle = detectedHandle ?? (path.contains("inbox") ? "user" : nil) {
                detectedCompleted = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                parent.onUsernameDetected(finalHandle)
            }
        }
    }
}
