import AppKit
import WebKit

/// One browser tab's worth of web content, hosted as a child view controller of
/// `TabsController`. Owns its `WKWebView`, its navigation policy, its downloads
/// and the JS notification shim.
final class WebTab: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let spec: TabSpec

    private let notifyHandler: NotifyHandler
    /// True when the web view came from WebKit's popup callback.
    private let isAdopted: Bool
    /// The tab that opened this one; refreshed when this popup closes.
    weak var openerTab: WebTab?
    /// The tab this one opened, if any, so closing it can unblock the opener.
    weak var openedTab: WebTab?
    private var titleObservation: NSKeyValueObservation?
    private var downloads: Set<WKDownload> = []
    private var popups: [WKWebView] = []
    private(set) var lastError: Error?
    private(set) var didLoad = false

    /// Set when the popup/tab was opened by page JS (`window.open`); such tabs
    /// are removed when the page calls `window.close()`.
    var isPopupTab = false

    let webView: WKWebView

    /// Called when the page title changes so the tab bar / window title updates.
    var onTitleChanged: ((WebTab) -> Void)?

    /// The web view is built here rather than in `loadView()` on purpose: a tab
    /// that has never been selected still has to be able to navigate, and
    /// background tabs are exactly what makes the tab bar feel instant.
    /// `adopted` is a web view WebKit created for us in
    /// `createWebViewWithConfiguration:`. It has to be used as-is: it is the
    /// only web view WebKit will link to the calling page, and a popup built
    /// from a configuration of our own gets `window.opener === null`, which
    /// silently breaks Google sign-in (the popup finishes, the opener never
    /// hears about it and stays on the login screen).
    init(spec: TabSpec, adopted: WKWebView? = nil) {
        self.spec = spec
        let handler = NotifyHandler()
        self.notifyHandler = handler
        self.isAdopted = adopted != nil
        if let adopted {
            self.webView = adopted
        } else {
            self.webView = WebTab.makeWebView(handler: handler)
        }
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
            guard let self else { return }
            self.onTitleChanged?(self)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeWebView(handler: NotifyHandler) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let ucc = config.userContentController
        ucc.addUserScript(Notifier.makeUserScript(enabled: AppRuntime.shared.config.notificationsShim))
        ucc.add(handler, name: Notifier.handlerName)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        web.customUserAgent = AppRuntime.shared.config.effectiveUserAgent
        web.autoresizingMask = [.width, .height]
        web.allowsBackForwardNavigationGestures = true
        web.allowsLinkPreview = false
        if #available(macOS 13.3, *) { web.isInspectable = true }
        return web
    }

    // MARK: - View

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        view.addSubview(webView)
        webView.frame = view.bounds
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Keep the web view pinned to the container in every swap of tabs.
        webView.frame = view.bounds
    }

    // MARK: - Loading

    var currentURL: URL? { webView.url }

    /// The URL to treat as "this tab's address": what is showing now, falling
    /// back to the configured URL before the first navigation completes.
    var currentURLString: String { webView.url?.absoluteString ?? spec.url }

    func load(_ string: String) {
        guard let url = URL(string: string) else {
            FileHandle.standardError.write("gcal: bad URL in config: \(string)\n".data(using: .utf8)!)
            return
        }
        webView.load(URLRequest(url: url))
    }

    @objc func reload(_ sender: Any?) { webView.reload() }

    @objc func forceReload(_ sender: Any?) { webView.reloadFromOrigin() }

    var canGoBack: Bool { webView.canGoBack }
    var canGoForward: Bool { webView.canGoForward }

    // MARK: - Menu actions

    @objc func goBack(_ sender: Any?) { webView.goBack() }
    @objc func goForward(_ sender: Any?) { webView.goForward() }
    @objc func stopLoading(_ sender: Any?) { webView.stopLoading() }
    @objc func zoomIn(_ sender: Any?) { webView.pageZoom *= 1.1 }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom /= 1.1 }
    @objc func zoomActual(_ sender: Any?) { webView.pageZoom = 1.0 }

    @objc func openInBrowser(_ sender: Any?) {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    /// `Account ▸ Switch Account` menu items carry the index in `representedObject`.
    @objc func switchAccount(_ sender: Any?) {
        guard let account = (sender as? NSMenuItem)?.representedObject as? Int else { return }
        load(Accounts.url(currentURLString, account: account))
    }

    /// True when this tab is already showing `account` (or Google has not put a
    /// number in the URL yet, which reads as account 0).
    func showingAccount(_ account: Int) -> Bool {
        Accounts.account(of: webView.url?.absoluteString ?? spec.url) ?? 0 == account
    }

    @objc func accountChooser(_ sender: Any?) {
        let base = currentURLString
        let host = URLComponents(string: base)?.host ?? "calendar.google.com"
        load("https://accounts.google.com/AccountChooser?continue=\(base.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host)&service=\(Self.service(for: host))")
    }

    @objc func clearSignIn(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear all Google sign-in data?"
        alert.informativeText = """
        This removes every cookie this app stored, so you will have to sign in \
        again in every tab. It does not touch Safari, Chrome, or Apple's apps.
        """
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        let done: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let store = WKWebsiteDataStore.default()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
                self.webView.reloadFromOrigin()
            }
        }
        if let window = view.window {
            alert.beginSheetModal(for: window) { done($0) }
        } else {
            done(alert.runModal())
        }
    }

    private static func service(for host: String) -> String {
        if host.contains("calendar") { return "cl" }
        if host.contains("mail") { return "mail" }
        return "wise"
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }

        // about:blank is not a destination, it is a placeholder for a window
        // that script is about to navigate. Handing it to LaunchServices is how
        // you end up with "no application set to open the URL about:blank".
        if Self.isBlank(url) {
            if navigationAction.targetFrame == nil {
                TabsController.current?.openPopup(url.absoluteString, opener: self, configuration: nil)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }

        // Other non-web schemes (mailto:, tel:, obsidian:, vscode…) belong to the OS.
        let scheme = url.scheme?.lowercased() ?? ""
        if !scheme.hasPrefix("http") {
            if scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel); return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download); return
        }

        // Meet links: join in the browser (reliable) unless the user opts in.
        if AppRuntime.shared.config.isMeet(url) && !AppRuntime.shared.config.openMeetInApp {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel); return
        }

        let host = url.host ?? ""
        let isTargetless = navigationAction.targetFrame == nil
        _ = isTargetless

        if AppRuntime.shared.config.isAllowed(host: host) {
            // `target="_blank"` on a Google host: open a tab here instead of a
            // stray popup window. OAuth popups need this to be a real window-ish
            // context, which a tab is.
            if isTargetless {
                TabsController.current?.openPopup(url.absoluteString, opener: self, configuration: nil)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }

        // Everything else leaves for the default browser.
        if isTargetless || navigationAction.modifierFlags.contains(.command) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel); return
        }
        // A plain top-level navigation to a non-Google site: keep it in-app so
        // that links inside Docs/Calendar do not eject you into Chrome mid-edit.
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationResponse response: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
        downloads.insert(download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
        downloads.insert(download)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoad = true
        // A web view WebKit created for a popup already has its configuration,
        // so the notification shim could not be injected at document start.
        if isAdopted, AppRuntime.shared.config.notificationsShim {
            webView.evaluateJavaScript(Notifier.installScript, completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        lastError = error
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        lastError = error
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let fm = FileManager.default
        let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser
        var target = dir.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)
        if fm.fileExists(atPath: target.path) {
            let base = target.deletingPathExtension().lastPathComponent
            let ext = target.pathExtension
            var n = 1
            while fm.fileExists(atPath: target.path), n < 1000 {
                let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
                target = dir.appendingPathComponent(name)
                n += 1
            }
        }
        completionHandler(target)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        lastError = error
        downloads.remove(download)
    }

    func downloadDidFinish(_ download: WKDownload) {
        downloads.remove(download)
    }

    // MARK: - WKUIDelegate

    /// Google's sign-in flow calls `window.open(...)`. Route it into a tab so
    /// the whole flow stays inside one window; `webViewDidClose` tidies up.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures)
        -> WKWebView? {
        // No URL or a blank one: create the window and let the opener navigate
        // it. Loading anything here would replace the document WebKit just set up.
        guard let url = navigationAction.request.url, !Self.isBlank(url) else {
            return TabsController.current?.openPopup("about:blank", opener: self, configuration: configuration)
        }
        if !AppRuntime.shared.config.isAllowed(host: url.host ?? ""), !AppRuntime.shared.config.isMeet(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return TabsController.current?.openPopup(url.absoluteString, opener: self, configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        TabsController.current?.closePopup(for: webView)
    }

    /// Same test, for the string form used in configuration.
    static func isBlankString(_ string: String) -> Bool {
        URL(string: string).map(isBlank) ?? string.isEmpty
    }

    /// True when this tab is sitting on a Google sign-in page, i.e. waiting for
    /// a popup to finish authenticating.
    var isWaitingAtSignIn: Bool {
        let url = currentURLString.lowercased()
        return url.contains("accounts.google.") || url.contains("/signin") || url.contains("service=cl")
    }

    /// `about:blank`, `about:srcdoc`, and any scheme-less empty URL.
    static func isBlank(_ url: URL) -> Bool {
        if url.host != nil { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" { return true }
        return url.absoluteString.isEmpty
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        presentAlert(text: message, informative: nil, buttons: ["OK"]) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        presentAlert(text: message, informative: nil, buttons: ["Cancel", "OK"]) {
            completionHandler($0 == .alertSecondButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let host = origin.host.lowercased()
        decisionHandler(AppRuntime.shared.config.isAllowed(host: host) ? .grant : .prompt)
    }

    private func presentAlert(text: String, informative: String?, buttons: [String],
                              completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let alert = NSAlert()
        alert.messageText = text
        if let informative { alert.informativeText = informative }
        buttons.forEach { alert.addButton(withTitle: $0) }
        if let window = webView.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}


