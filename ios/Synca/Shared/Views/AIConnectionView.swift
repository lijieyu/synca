import SwiftUI
import WebKit

/// A temporary, authenticated AI guide; shares neither cookies nor storage with browsers.
struct AIConnectionView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var browser = AIConnectionBrowser()
    @State private var initialToken: String?

    #if os(macOS)
    private var macSheetWidth: CGFloat {
        let parent = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow
        return min(880, max(520, (parent?.frame.width ?? 920) - 40))
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { browser.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .disabled(!browser.canGoBack)
                .accessibilityLabel(Text("ai_browser.back"))
                Text("message_list.connect_ai").font(.headline)
                Spacer()
                if browser.isLoading { ProgressView().controlSize(.small) }
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28).background(Color.secondary.opacity(0.1), in: Circle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.close"))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            ZStack {
                AIWebContainer(browser: browser)
                if browser.failed {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark").font(.title)
                        Text("ai_browser.load_failed").multilineTextAlignment(.center)
                        Button("common.retry") { browser.retry() }
                            .buttonStyle(.borderedProminent).tint(.syncaPurple)
                    }
                    .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
        }
        #if os(macOS)
        .frame(width: macSheetWidth, height: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            guard initialToken == nil, let token = api.token else { return }
            initialToken = token
            browser.start(token: token, email: api.currentUserEmail) { url in openURL(url) }
        }
        .onChange(of: api.token) { token in
            guard token != initialToken else { return }
            browser.clearSession()
            dismiss()
        }
        .onDisappear { browser.clearSession() }
    }
}

@MainActor
private final class AIConnectionBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var canGoBack = false
    @Published private(set) var isLoading = true
    @Published private(set) var failed = false
    let webView: WKWebView
    private var externalOpen: ((URL) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var started = false
    private var permittedDocumentOrigins: Set<String> = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.canGoBack = self?.webView.canGoBack ?? false }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.isLoading = self?.webView.isLoading ?? false }
            }
        ]
    }

    func start(token: String, email: String?, externalOpen: @escaping (URL) -> Void) {
        guard !started else { return }
        started = true
        self.externalOpen = externalOpen
        let script = WKUserScript(source: EmbeddedAISession.bootstrap(token: token, email: email), injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        webView.load(URLRequest(url: AppLinks.aiConnectionURL))
    }
    func retry() {
        failed = false
        webView.load(URLRequest(url: webView.url ?? AppLinks.aiConnectionURL))
    }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func clearSession() {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        webView.loadHTMLString("", baseURL: nil)
        permittedDocumentOrigins.removeAll()
        externalOpen = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about", url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        // New third-party document origins require a deliberate top-level link click.
        // Background redirects and subframes cannot extend this browsing boundary.
        // Only the exact Synca origin receives the main-frame session bootstrap.
        // Never load an insecure page or a URL containing credentials in this browser.
        if scheme == "https", url.user == nil, url.password == nil {
            let origin = "\(scheme)://\(url.host?.lowercased() ?? ""):\(url.port ?? 443)"
            let isMainDocument = navigationAction.targetFrame?.isMainFrame ?? true
            if !EmbeddedAISession.isTrusted(url) {
                if isMainDocument && navigationAction.sourceFrame.isMainFrame && navigationAction.navigationType == .linkActivated {
                    permittedDocumentOrigins.insert(origin)
                }
                guard permittedDocumentOrigins.contains(origin) else {
                    decisionHandler(.cancel)
                    return
                }
            }
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: url))
            } else { decisionHandler(.allow) }
            return
        }
        // AI clients use registered URL schemes. Only a user's link click may launch one.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.sourceFrame.isMainFrame,
           !["http", "file", "data", "javascript", "blob", "about"].contains(scheme) {
            externalOpen?(url)
        }
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { failed = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed = true }
    private func handle(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { failed = true }
    }
}

#if os(macOS)
private struct AIWebContainer: NSViewRepresentable {
    let browser: AIConnectionBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
private struct AIWebContainer: UIViewRepresentable {
    let browser: AIConnectionBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
