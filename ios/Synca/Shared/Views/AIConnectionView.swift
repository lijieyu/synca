import SwiftUI
import WebKit

/// A temporary, authenticated AI guide; shares neither cookies nor storage with browsers.
struct AIConnectionView: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var browser = AIConnectionBrowser()
    @State private var initialToken: String?

    #if os(macOS)
    private var macSheetSize: CGSize {
        let parent = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow
        let screen = parent?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let availableWidth = min(parent?.frame.width ?? 920, screen?.width ?? 920) - 40
        let availableHeight = (screen?.height ?? 800) - 100
        return CGSize(width: min(600, max(320, availableWidth)), height: min(max(320, (browser.contentHeight ?? 404) + 56), min(640, max(320, availableHeight))))
    }
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                MacSheetHeader(title: "message_list.connect_ai")
                if browser.canGoBack {
                    HStack {
                        Button { browser.goBack() } label: {
                            Label("ai_browser.back", systemImage: "chevron.left")
                        }.buttonStyle(.plain)
                        Spacer()
                    }.padding(.horizontal, 24).padding(.bottom, 8)
                }
                browserContent
            }
            .frame(width: macSheetSize.width, height: macSheetSize.height)
            #else
            NavigationStack {
                browserContent
                    .navigationTitle(Text("message_list.connect_ai"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if browser.canGoBack {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { browser.goBack() } label: {
                                    Label("ai_browser.back", systemImage: "chevron.left")
                                }
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("common.close") { dismiss() }
                        }
                    }
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(620), .large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onAppear {
            guard initialToken == nil, let token = api.token else { return }
            initialToken = token
            browser.start(token: token, email: api.currentUserEmail, appearance: resolvedAppearance, language: AppLocalization.identifier) { url in openURL(url) }
        }
        .onChange(of: colorScheme) { _ in
            browser.updatePreferences(appearance: resolvedAppearance, language: AppLocalization.identifier)
        }
        .onChange(of: locale.identifier) { _ in
            browser.updatePreferences(appearance: resolvedAppearance, language: AppLocalization.identifier)
        }
        .onChange(of: api.token) { token in
            guard token != initialToken else { return }
            browser.clearSession()
            dismiss()
        }
        .onDisappear { browser.clearSession() }
    }

    private var resolvedAppearance: String { colorScheme == .dark ? "dark" : "light" }

    private var browserContent: some View {
        ZStack {
            AIWebContainer(browser: browser)
            if browser.isLoading && !browser.hasLoadedDocument && !browser.failed {
                ProgressView("message_list.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                    .allowsHitTesting(false)
            }
            if browser.failed {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark").font(.title)
                        .accessibilityHidden(true)
                    Text("ai_browser.load_failed").multilineTextAlignment(.center)
                    Button("common.retry") { browser.retry() }
                        .buttonStyle(.borderedProminent).tint(.accentColor)
                }
                .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
    }
}

@MainActor
private final class AIConnectionBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var canGoBack = false
    @Published private(set) var isLoading = true
    @Published private(set) var failed = false
    @Published private(set) var hasLoadedDocument = false
    @Published private(set) var contentHeight: CGFloat?
    let webView: WKWebView
    private var externalOpen: ((URL) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var started = false
    private var sessionToken: String?
    private var sessionEmail: String?
    private var appearance = "light"
    private var language = "en"
    private var permittedDocumentOrigins: Set<String> = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        #if os(macOS)
        configuration.userContentController.add(AIContentHeightHandler { [weak self] height, scroll in
            guard let self else { return }
            if abs((self.contentHeight ?? 0) - height) > 1 { self.contentHeight = height }
            if let scroll {
                // Allow SwiftUI to resize the native sheet before positioning the H5 scroller.
                DispatchQueue.main.async { [weak self] in
                    self?.webView.evaluateJavaScript("""
                    requestAnimationFrame(() => requestAnimationFrame(() => {
                      const page = document.querySelector('.ai-page');
                      if (page) page.scrollTo({top: \(scroll == "end" ? "page.scrollHeight" : "0"),
                        behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'});
                    }));
                    """, completionHandler: nil)
                }
            }
        }, name: "syncaAIContentHeight")
        #endif
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

    func start(token: String, email: String?, appearance: String, language: String, externalOpen: @escaping (URL) -> Void) {
        guard !started else { return }
        started = true
        self.externalOpen = externalOpen
        sessionToken = token
        sessionEmail = email
        updatePreferences(appearance: appearance, language: language)
        webView.load(URLRequest(url: AppLinks.aiConnectionURL))
    }
    func updatePreferences(appearance: String, language: String) {
        self.appearance = appearance
        self.language = language
        guard let sessionToken else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: EmbeddedAISession.bootstrap(token: sessionToken, email: sessionEmail, appearance: appearance, language: language),
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
        #if os(macOS)
        controller.addUserScript(WKUserScript(source: Self.contentHeightScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        #endif
        if let url = webView.url, EmbeddedAISession.isTrusted(url) {
            webView.evaluateJavaScript(EmbeddedAISession.preferences(appearance: appearance, language: language), completionHandler: nil)
        }
    }

    #if os(macOS)
    // Measure the content, not the viewport-sized .ai-page: shrinking the window
    // must not feed its own previous height back into the next measurement.
    private static let contentHeightScript = """
    (() => {
      if (window.top !== window || location.origin !== 'https://synca.haerth.cn' ||
          !['/ai', '/ai/'].includes(location.pathname)) return;
      let scheduled = false, observed, expanded = false;
      const report = () => {
        scheduled = false;
        const content = document.querySelector('.ai-content');
        if (!content || !content.querySelector('.ai-tutorial, .ai-connections, .ai-consent')) return;
        if (observed !== content) { if (observed) sizeObserver.unobserve(observed); sizeObserver.observe(content); observed = content; }
        const hasPrompt = !!content.querySelector('#ai-prompt-content');
        const scroll = hasPrompt !== expanded ? (hasPrompt ? 'end' : 'start') : null;
        expanded = hasPrompt;
        window.webkit.messageHandlers.syncaAIContentHeight.postMessage({height: Math.ceil(content.offsetHeight), scroll});
      };
      const schedule = () => { if (!scheduled) { scheduled = true; requestAnimationFrame(report); } };
      const sizeObserver = new ResizeObserver(schedule);
      new MutationObserver(schedule).observe(document.body, {childList:true, subtree:true, attributes:true});
      schedule();
    })();
    """
    #endif

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
        sessionToken = nil
        sessionEmail = nil
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
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedDocument = true
        updatePreferences(appearance: appearance, language: language)
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

#if os(macOS)
/// The controller owns this proxy; its callback captures the browser weakly.
@MainActor
private final class AIContentHeightHandler: NSObject, WKScriptMessageHandler {
    let onHeight: (CGFloat, String?) -> Void
    init(onHeight: @escaping (CGFloat, String?) -> Void) { self.onHeight = onHeight }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url, EmbeddedAISession.isTrusted(url),
              ["/ai", "/ai/"].contains(url.path),
              let body = message.body as? [String: Any],
              let number = body["height"] as? NSNumber else { return }
        let height = CGFloat(number.doubleValue)
        guard height.isFinite, height > 0 else { return }
        let scroll = body["scroll"] as? String
        onHeight(height, ["end", "start"].contains(scroll ?? "") ? scroll : nil)
    }
}
#endif
