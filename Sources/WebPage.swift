import AppKit
import WebKit

/// One source's web view: navigation policy, popups, downloads, JS panels.
///
/// Named "page" rather than "tab" because there are exactly two of them and the
/// user does not create or close them.
final class WebPage: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let source: Source

    private let notifyHandler: NotifyHandler
    /// True when the web view came from WebKit's popup callback, which cannot
    /// take a document-start script.
    private let isAdopted: Bool
    private var titleObservation: NSKeyValueObservation?
    private var downloads: Set<WKDownload> = []

    weak var openedPopup: WKWebView?
    var onTitleChanged: ((WebPage) -> Void)?
    /// Fired once the first navigation resolves, so a source can start reading
    /// its own data instead of waiting for a timer.
    var onLoaded: ((WebPage) -> Void)?
    private(set) var lastError: Error?
    private(set) var didLoad = false

    let webView: WKWebView

    /// A web view WebKit created in `createWebViewWithConfiguration:` must be
    /// used as-is: it is the only one linked to the calling page, and a popup
    /// built from our own configuration gets `window.opener === null` — which
    /// silently breaks Google sign-in.
    init(source: Source, adopted: WKWebView? = nil) {
        self.source = source
        let handler = NotifyHandler()
        self.notifyHandler = handler
        self.isAdopted = adopted != nil
        self.webView = adopted ?? WebPage.makeWebView(handler: handler)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // No back/forward: swipe should not turn this into a browser.
        webView.allowsBackForwardNavigationGestures = false
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
            guard let self else { return }
            self.onTitleChanged?(self)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Web view construction

    static func defaultConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let handler = NotifyHandler()
        config.userContentController.addUserScript(
            Notifier.makeUserScript(enabled: AppRuntime.shared.config.notificationsShim))
        config.userContentController.add(handler, name: Notifier.handlerName)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        associatedHandlers[prefixKey] = handler
        return config
    }

    /// Keeps the script message handler alive; `WKUserContentController` holds
    /// its handlers strongly, but the object is created in a static function.
    private static var associatedHandlers: [String: NotifyHandler] = [:]
    private static let prefixKey = "default"

    private static func makeWebView(handler: NotifyHandler) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.addUserScript(
            Notifier.makeUserScript(enabled: AppRuntime.shared.config.notificationsShim))
        config.userContentController.add(handler, name: Notifier.handlerName)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsLinkPreview = false
        if #available(macOS 13.3, *) { web.isInspectable = true }
        web.customUserAgent = AppRuntime.shared.config.effectiveUserAgent
        return web
    }

    // MARK: - View

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        view.addSubview(webView)
        webView.frame = view.bounds
        webView.autoresizingMask = [.width, .height]
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        webView.frame = view.bounds
    }

    /// What the window should hand first responder to.
    var firstResponderTarget: NSView { webView }

    /// The document's title. Named to avoid colliding with
    /// `NSViewController.title`, which this class also inherits.
    var pageTitle: String? { webView.title }

    /// Gmail writes its unread count into the page title ("Inbox (3) - …"),
    /// which is the one badge signal that needs no polling or permissions.
    var unreadCountFromTitle: Int? { Self.unreadCount(inTitle: pageTitle) }

    /// Gmail writes its unread count into the title; parsed here so the badge
    /// works even when the Atom feed is gone.
    static func unreadCount(inTitle title: String?) -> Int? {
        guard let title,
              let match = try? NSRegularExpression(pattern: #"[\[(](\d{1,4})[\])]"#)
                .firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else { return nil }
        return Int(title[range])
    }

    var currentURLString: String { webView.url?.absoluteString ?? source.url }

    var isWaitingAtSignIn: Bool {
        let url = currentURLString.lowercased()
        return url.contains("accounts.google.") || url.contains("/signin")
    }

    static func isBlank(_ url: URL) -> Bool {
        if url.host != nil { return false }
        if url.scheme?.lowercased() == "about" { return true }
        return url.absoluteString.isEmpty
    }

    /// Sign-in has to happen inside the window; everything Google calls a link
    /// does not.
    static func isSignIn(_ host: String) -> Bool {
        Config.signInHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    static func isBlankString(_ string: String) -> Bool {
        URL(string: string).map(isBlank) ?? string.isEmpty
    }

    // MARK: - Loading

    func load(_ string: String) {
        guard let url = URL(string: string) else {
            FileHandle.standardError.write("gcal: bad URL in config: \(string)\n".data(using: .utf8)!)
            return
        }
        webView.load(URLRequest(url: url))
    }

    func reloadFromOrigin() { webView.reloadFromOrigin() }

    /// Runs JavaScript and hands back the decoded JSON result. Used by the mail
    /// watcher, which reads Gmail through the page's own authenticated session.
    func evaluate(json js: String, timeout: TimeInterval = 12,
                  completion: @escaping (Any?, String?) -> Void) {
        var delivered = false
        let finish: (Any?, String?) -> Void = { value, error in
            guard !delivered else { return }
            delivered = true
            completion(value, error)
        }
        webView.evaluateJavaScript(js) { result, error in
            if let error {
                let ns = error as NSError
                // A bare "A JavaScript exception occurred" tells us nothing; the
                // message and line live in the userInfo.
                var detail = ns.localizedDescription
                if let message = ns.userInfo["WKJavaScriptExceptionMessage"] as? String {
                    detail += " — \(message)"
                }
                if let line = ns.userInfo["WKJavaScriptExceptionLineNumber"] as? Int {
                    detail += " (line \(line))"
                }
                finish(nil, detail)
                return
            }
            if let text = result as? String, let data = text.data(using: .utf8) {
                finish((try? JSONSerialization.jsonObject(with: data)) as Any?, nil)
            } else {
                finish(result, nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil, "timed out after \(Int(timeout))s") }
    }

    // MARK: - Menu actions

    @objc func reload(_ sender: Any?) { webView.reload() }
    @objc func forceReload(_ sender: Any?) { webView.reloadFromOrigin() }
    @objc func stopLoading(_ sender: Any?) { webView.stopLoading() }
    @objc func goBack(_ sender: Any?) { webView.goBack() }
    @objc func goForward(_ sender: Any?) { webView.goForward() }
    @objc func zoomIn(_ sender: Any?) { webView.pageZoom *= 1.1 }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom /= 1.1 }
    @objc func zoomActual(_ sender: Any?) { webView.pageZoom = 1.0 }

    @objc func openInBrowser(_ sender: Any?) {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    /// `Account ▸ Switch Account` items carry the index in `representedObject`.
    @objc func switchAccount(_ sender: Any?) {
        guard let account = (sender as? NSMenuItem)?.representedObject as? Int else { return }
        load(Accounts.url(currentURLString, account: account))
    }

    @objc func accountChooser(_ sender: Any?) {
        let base = currentURLString
        let host = URLComponents(string: base)?.host ?? "mail.google.com"
        let encoded = base.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? host
        load("https://accounts.google.com/AccountChooser?continue=\(encoded)&service=\(Self.service(for: host))")
    }

    @objc func clearSignIn(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear all Google sign-in data?"
        alert.informativeText = """
        This removes every cookie this app stored, so you will have to sign in again \
        in both sources. It does not touch Safari, Chrome, or Apple's apps.
        """
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        let go: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let store = WKWebsiteDataStore.default()
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                             modifiedSince: Date(timeIntervalSince1970: 0)) {
                self.webView.reloadFromOrigin()
            }
        }
        if let window = view.window { alert.beginSheetModal(for: window) { go($0) } }
        else { go(alert.runModal()) }
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
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true

        // about:blank is a placeholder for a window script is about to
        // navigate, not a destination. Handing it to LaunchServices is how you
        // get "no application set to open the URL about:blank".
        if Self.isBlank(url) {
            if navigationAction.targetFrame == nil {
                RootController.current?.showPopup(url.absoluteString, opener: self, configuration: nil)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if !scheme.hasPrefix("http") {
            if scheme == "blob" || scheme == "data" { decisionHandler(.allow); return }
            NSWorkspace.shared.open(url)   // mailto:, tel:, vscode: and friends
            decisionHandler(.cancel); return
        }

        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }

        // Meet: only a URL that actually joins a call leaves for the browser.
        // Google's warm-up hits on meet.google.com/ and /_meet/* stay in-app,
        // otherwise every page load spawns a "_meet/whoops" browser tab.
        if AppRuntime.shared.config.isMeet(url) {
            let joins = AppRuntime.shared.config.isJoinableMeet(url)
            if AppRuntime.shared.config.openMeetInApp { decisionHandler(.allow); return }
            if joins, isMainFrame, navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }

        // This is not a browser. Only the surface's own pages stay in the
        // window; a link to Drive, Docs or some article in an email belongs in
        // the user's browser, which is also where a popup would go.
        let host = url.host ?? ""
        let inApp = AppRuntime.shared.config.openLinksInBrowser
            ? AppRuntime.shared.config.staysInApp(host: host, for: source)
            : AppRuntime.shared.config.isAllowed(host: host)

        if inApp {
            if navigationAction.targetFrame == nil,
               AppRuntime.shared.config.staysInApp(host: host, for: source) {
                // Only a sign-in popup belongs here; a target=_blank link to the
                // same surface is still a link.
                if Self.isSignIn(host) {
                    RootController.current?.showPopup(url.absoluteString, opener: self, configuration: nil)
                    decisionHandler(.cancel); return
                }
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow); return
        }

        guard isMainFrame else {
            // An iframe pointing elsewhere is not a click; refuse it quietly
            // rather than spawning a browser tab.
            decisionHandler(.cancel); return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
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
        let firstLoad = !didLoad
        didLoad = true
        if firstLoad { onLoaded?(self) }
        // A handed-over configuration cannot accept a new document-start script,
        // so the notification shim goes in afterwards.
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
                target = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                n += 1
            }
        }
        completionHandler(target)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        lastError = error
        downloads.remove(download)
    }

    func downloadDidFinish(_ download: WKDownload) { downloads.remove(download) }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else {
            return RootController.current?.showPopup("about:blank", opener: self, configuration: configuration)
        }
        if Self.isBlank(url) {
            return RootController.current?.showPopup(url.absoluteString, opener: self, configuration: configuration)
        }
        if AppRuntime.shared.config.isMeet(url) {
            // A real call joins in the browser; a warm-up popup is simply
            // blocked. Neither ever spawns a browser tab on its own.
            if AppRuntime.shared.config.isJoinableMeet(url), !AppRuntime.shared.config.openMeetInApp {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
        // A popup is either Google's sign-in flow, which must stay here or the
        // login can never finish, or a link, which belongs in the browser.
        let host = url.host ?? ""
        if Self.isSignIn(host) {
            return RootController.current?.showPopup(url.absoluteString, opener: self, configuration: configuration)
        }
        if AppRuntime.shared.config.openLinksInBrowser
            || !AppRuntime.shared.config.isAllowed(host: host) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return RootController.current?.showPopup(url.absoluteString, opener: self, configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        RootController.current?.closePopup(for: webView)
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
            panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
        } else {
            panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        presentAlert(text: message, buttons: ["OK"]) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        presentAlert(text: message, buttons: ["Cancel", "OK"]) { completionHandler($0 == .alertSecondButtonReturn) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(AppRuntime.shared.config.isAllowed(host: origin.host.lowercased()) ? .grant : .deny)
    }

    private func presentAlert(text: String, buttons: [String],
                              completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let alert = NSAlert()
        alert.messageText = text
        buttons.forEach { alert.addButton(withTitle: $0) }
        if let window = webView.window { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }
}
