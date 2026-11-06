import SwiftUI
import WebKit
import DailyCore

/// Hybrid Supabase Admin authentication sheet for macOS:
/// 1. Primary: Interactive GitHub OAuth via Supabase CLI Login (`P-256 ECDH + AES-256-GCM`) + Dashboard GoTrue session capture.
/// 2. Fallback: Collapsible Personal Access Token (`sbp_...`) bar.
public struct SupabaseAdminLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var adminService = SupabaseAdminService.shared

    @State private var handshake = SupabaseCliLoginHandshake(platformLabel: "macOS")
    @State private var showPatBar = false
    @State private var patInput = ""
    @State private var isLoadingWeb = true
    @State private var statusBanner: String?
    @State private var localError: String?

    public var onAuthenticated: (() -> Void)?

    public init(onAuthenticated: (() -> Void)? = nil) {
        self.onAuthenticated = onAuthenticated
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ThemeColors.bgStop1.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    if showPatBar {
                        patFallbackBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let err = localError ?? adminService.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ThemeColors.error)
                            Text(err)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Spacer()
                            Button("Dismiss") {
                                localError = nil
                                adminService.errorMessage = nil
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(ThemeColors.accentCyan)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ThemeColors.error.opacity(0.16))
                    }

                    Divider().background(Color.white.opacity(0.12))

                    ZStack {
                        SupabaseAdminMacWebView(
                            handshake: handshake,
                            isLoading: $isLoadingWeb,
                            statusBanner: $statusBanner,
                            onHandshakeDetected: { deviceCode, dashboardJson in
                                completeWebHandshake(deviceCode: deviceCode, dashboardJson: dashboardJson)
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if isLoadingWeb || adminService.isAuthenticating {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(ThemeColors.accentCyan)
                                Text(adminService.isAuthenticating
                                     ? "Decrypting ECDH Management Token & verifying project..."
                                     : (statusBanner ?? "Loading Supabase Cloud Login (GitHub OAuth supported)..."))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ThemeColors.fgMutedDark)
                            }
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(ThemeColors.bgStop1.opacity(0.92))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Supabase Admin Login")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(ThemeColors.accentCyan)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 840, maxWidth: 980, minHeight: 680, idealHeight: 780, maxHeight: 920)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(ThemeColors.accentCyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in with GitHub to Supabase Control Plane")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("100% Read-Only telemetry · P-256 ECDH encrypted handshake · Local sandboxed storage")
                    .font(.system(size: 11))
                    .foregroundColor(ThemeColors.fgMutedDark)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPatBar.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 11))
                    Text(showPatBar ? "Hide Token Input" : "Use PAT (sbp_...)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(ThemeColors.accentCyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(ThemeColors.accentCyan.opacity(0.12))
                        .overlay(Capsule().strokeBorder(ThemeColors.accentCyan.opacity(0.3), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.32))
    }

    private var patFallbackBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .foregroundColor(ThemeColors.accentCyan)
                .font(.system(size: 13))

            SecureField("Paste Personal Access Token (sbp_...)", text: $patInput)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundColor(.white)
                .font(.system(size: 13, design: .monospaced))

            Button("Connect Token") {
                connectManualPat()
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(ThemeColors.accentCyan))
            .buttonStyle(.plain)
            .disabled(patInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || adminService.isAuthenticating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
    }

    private func connectManualPat() {
        localError = nil
        let raw = patInput
        Task {
            do {
                try await adminService.connectWithPersonalAccessToken(raw)
                dismiss()
                onAuthenticated?()
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func completeWebHandshake(deviceCode: String, dashboardJson: String?) {
        guard !adminService.isAuthenticating else { return }
        localError = nil
        Task {
            do {
                try await adminService.completeCliHandshake(
                    handshake: handshake,
                    deviceCode: deviceCode,
                    dashboardSessionJson: dashboardJson
                )
                dismiss()
                onAuthenticated?()
            } catch {
                localError = error.localizedDescription
            }
        }
    }
}

// MARK: - macOS WKWebView Representable with SPA History + LocalStorage Bridge

private struct SupabaseAdminMacWebView: NSViewRepresentable {
    let handshake: SupabaseCliLoginHandshake
    @Binding var isLoading: Bool
    @Binding var statusBanner: String?
    let onHandshakeDetected: (String, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.websiteDataStore = WKWebsiteDataStore.default()

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "supabaseCliBridge")

        // Monitor SPA pushState/replaceState + interval check for `device_code` and GoTrue dashboard token
        let bridgeJs = """
        (function() {
          var sentCode = null;
          function checkSupabaseCliState() {
            try {
              var host = (window.location.hostname || '').toLowerCase();
              if (host.indexOf('supabase.com') === -1) return;
              var params = new URLSearchParams(window.location.search || '');
              var code = params.get('device_code');
              if (code && code.length > 0 && code !== sentCode) {
                sentCode = code;
                var dashToken = null;
                try { dashToken = window.localStorage.getItem('supabase.dashboard.auth.token'); } catch (e) {}
                window.webkit.messageHandlers.supabaseCliBridge.postMessage({
                  deviceCode: code,
                  dashboardSession: dashToken || ''
                });
              }
            } catch (err) {}
          }
          var origPush = history.pushState;
          history.pushState = function() {
            var r = origPush.apply(this, arguments);
            setTimeout(checkSupabaseCliState, 50);
            return r;
          };
          var origReplace = history.replaceState;
          history.replaceState = function() {
            var r = origReplace.apply(this, arguments);
            setTimeout(checkSupabaseCliState, 50);
            return r;
          };
          window.addEventListener('popstate', checkSupabaseCliState);
          setInterval(checkSupabaseCliState, 450);
          setTimeout(checkSupabaseCliState, 100);
        })();
        """
        let script = WKUserScript(source: bridgeJs, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContent.addUserScript(script)
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = HeadlessReadabilityParser.mediumSafariUserAgent
        webView.load(URLRequest(url: handshake.loginUrl))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "supabaseCliBridge")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let parent: SupabaseAdminMacWebView
        private var didDeliverCode = false
        private var didRecoverRedirect = false

        init(_ parent: SupabaseAdminMacWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "supabaseCliBridge",
                  !didDeliverCode,
                  let body = message.body as? [String: Any],
                  let code = body["deviceCode"] as? String,
                  !code.isEmpty else {
                return
            }
            didDeliverCode = true
            let dashSession = body["dashboardSession"] as? String
            DispatchQueue.main.async {
                self.parent.onHandshakeDetected(code, dashSession)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            if let urlStr = navigationAction.request.url?.absoluteString,
               !didDeliverCode,
               let code = SupabaseAdminCrypto.extractDeviceCode(from: urlStr) {
                didDeliverCode = true
                webView.evaluateJavaScript("window.localStorage.getItem('supabase.dashboard.auth.token')") { val, _ in
                    let dash = val as? String
                    DispatchQueue.main.async {
                        self.parent.onHandshakeDetected(code, dash)
                    }
                }
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            guard !didDeliverCode, let currentUrl = webView.url?.absoluteString else { return }

            if let code = SupabaseAdminCrypto.extractDeviceCode(from: currentUrl) {
                didDeliverCode = true
                webView.evaluateJavaScript("window.localStorage.getItem('supabase.dashboard.auth.token')") { val, _ in
                    let dash = val as? String
                    DispatchQueue.main.async {
                        self.parent.onHandshakeDetected(code, dash)
                    }
                }
                return
            }

            // If GitHub OAuth sign-in dropped query params and landed on /dashboard/organizations, re-trigger CLI session URL once
            if !didRecoverRedirect && SupabaseAdminCrypto.shouldRecoverCliLoginRedirect(currentUrl: currentUrl) {
                didRecoverRedirect = true
                parent.statusBanner = "GitHub session established — authorizing DayOne Admin Console..."
                webView.load(URLRequest(url: parent.handshake.loginUrl))
            }
        }
    }
}
