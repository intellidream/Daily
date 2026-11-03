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
    
    public init() {}
    
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 800, maxWidth: 960, minHeight: 680, idealHeight: 780, maxHeight: 920)
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

/// Headless WKWebView coordinator monitoring Medium OAuth redirects and detecting `@username`.
private struct MediumWebViewRepresentable: NSViewRepresentable {
    let initialUrl: URL
    @Binding var isLoading: Bool
    let onUsernameDetected: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
        webView.load(URLRequest(url: initialUrl))
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: MediumWebViewRepresentable
        private var detectedCompleted = false
        
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
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            checkUrl(webView.url, webView: webView)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            checkUrl(webView.url, webView: webView)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            if let url = navigationAction.request.url {
                if checkUrl(url, webView: webView) {
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
        
        @discardableResult
        private func checkUrl(_ url: URL?, webView: WKWebView) -> Bool {
            guard !detectedCompleted, let url = url, let host = url.host?.lowercased() else { return false }
            
            if host.contains("medium.com") {
                let path = url.path
                if path.hasPrefix("/@") {
                    let parts = path.dropFirst(2).split(separator: "/")
                    if let first = parts.first, !first.isEmpty {
                        detectedCompleted = true
                        let detected = String(first)
                        DispatchQueue.main.async {
                            self.parent.onUsernameDetected(detected)
                        }
                        return true
                    }
                } else if host != "medium.com" && host != "www.medium.com" && host != "api.medium.com" && host.hasSuffix(".medium.com") {
                    let sub = host.replacingOccurrences(of: ".medium.com", with: "")
                    if !sub.isEmpty {
                        detectedCompleted = true
                        DispatchQueue.main.async {
                            self.parent.onUsernameDetected(sub)
                        }
                        return true
                    }
                } else if path == "/" || path == "" || path == "/?source=logo" {
                    // Navigate to /me which redirects to /@username
                    DispatchQueue.main.async {
                        webView.load(URLRequest(url: URL(string: "https://medium.com/me")!))
                    }
                }
            }
            return false
        }
    }
}
