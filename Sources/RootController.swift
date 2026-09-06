import AppKit
import WebKit

/// The window's whole content: the icon rail plus one web view per source.
///
/// This replaced a tab bar. Two fixed surfaces do not need tabs, and the tab
/// machinery (segmented control, add/close, `⌘T`) was both the source of a
/// crash and the wrong mental model — this is not a browser.
final class RootController: NSViewController, NSMenuItemValidation {
    static weak var current: RootController?

    private(set) var sources: [Source] = []
    private var pages: [String: WebPage] = [:]
    private let content = NSView()
    private var sidebar: Sidebar!

    /// Popup web views we are holding open, keyed by the page that opened them.
    private var popups: [ObjectIdentifier: PopupPanel] = [:]

    private(set) var selectedID: String

    /// False only for `--selftest`, which must not touch the network.
    private let loadsPages: Bool

    var selectedPage: WebPage? { pages[selectedID] }

    var pagesByOrder: [WebPage] { sources.compactMap { pages[$0.id] } }

    var popupsCount: Int { popups.count }

    // Layout read-outs for --popupprobe.
    var sidebarFrame: NSRect { sidebar.frame }
    var contentFrame: NSRect { content.frame }
    var popupPanelFrame: NSRect? { popups.values.first?.view.frame }
    var popupWebFrame: NSRect? { popups.values.first.map { $0.webView.frame } }

    init(sources: [Source], loadPages: Bool = true) {
        self.sources = sources
        self.loadsPages = loadPages
        self.selectedID = sources.first?.id ?? ""
        super.init(nibName: nil, bundle: nil)
        RootController.current = self

        sidebar = Sidebar(sources: sources)
        sidebar.onSelect = { [weak self] id in self?.select(id: id) }

        for source in sources {
            let page = WebPage(source: source)
            page.onTitleChanged = { [weak self] updated in self?.titleChanged(for: updated) }
            page.onLoaded = { loaded in
                if loaded.source.id == "mail" { MailWatcher.shared.poll() }
            }
            pages[source.id] = page
            content.addSubview(page.view)
            page.view.frame = content.bounds
            page.view.autoresizingMask = [.width, .height]
            page.view.isHidden = source.id != selectedID
            if loadsPages { page.load(source.url) }
        }
        sidebar.setSelected(id: selectedID)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Window-sized layout

    /// Low-priority size constraints that mirror the window's content size.
    ///
    /// Without them the constraint graph defines no size at all — a web view has
    /// no intrinsic size — and AppKit then satisfies the window from the *fitting
    /// size* it can derive, which is just the rail's 56 pt and a zero-height body.
    /// It does this the moment the graph is dirtied, i.e. the first time a popup
    /// panel is attached, collapsing the window to a title bar and a close button.
    /// Mirroring the window's size makes that derived size equal the real one, so
    /// the pass becomes a no-op while the window and the user stay in charge.
    private var sizeFollowers: (width: NSLayoutConstraint, height: NSLayoutConstraint)?
    private var resizeObserver: NSObjectProtocol?

    func followWindowSize(of window: NSWindow) {
        resizeObserver.map(NotificationCenter.default.removeObserver)
        resizeObserver = nil
        view.layoutSubtreeIfNeeded()

        let body = window.contentView?.bounds ?? view.bounds
        let width = view.widthAnchor.constraint(equalToConstant: body.width)
        let height = view.heightAnchor.constraint(equalToConstant: body.height)
        width.priority = .defaultLow
        height.priority = .defaultLow
        NSLayoutConstraint.activate([width, height])
        sizeFollowers = (width, height)

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                guard let self, let body = window.contentView?.bounds else { return }
                self.sizeFollowers?.width.constant = body.width
                self.sizeFollowers?.height.constant = body.height
            }
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        root.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    // MARK: - Selection

    func select(id: String) {
        guard pages[id] != nil, id != selectedID else { return }
        pages[selectedID]?.view.isHidden = true
        selectedID = id
        let page = pages[id]
        page?.view.isHidden = false
        sidebar.setSelected(id: id)
        if let page { titleChanged(for: page) }
        view.window?.makeFirstResponder(page?.firstResponderTarget)
        NSApp.mainMenu?.update()
    }

    @objc func selectMail(_ sender: Any?) { select(id: "mail") }
    @objc func selectCalendar(_ sender: Any?) { select(id: "calendar") }

    @objc func nextSource(_ sender: Any?) { shift(1) }
    @objc func previousSource(_ sender: Any?) { shift(-1) }

    private func shift(_ delta: Int) {
        guard sources.count > 1, let index = sources.firstIndex(where: { $0.id == selectedID }) else { return }
        select(id: sources[(index + delta + sources.count) % sources.count].id)
    }

    // MARK: - Titles and badges

    private func titleChanged(for page: WebPage) {
        if page.source.id == selectedID, let window = view.window {
            let pageTitle = page.pageTitle ?? ""
            window.title = pageTitle.isEmpty ? page.source.label : pageTitle
        }
        // Gmail puts the unread count in its title ("Inbox (3) - …"), which is
        // the one signal that needs no polling and no permissions.
        if page.source.id == "mail" {
            sidebar.setBadge(page.unreadCountFromTitle, id: "mail")
        }
    }

    func setBadge(_ count: Int?, for id: String) { sidebar.setBadge(count, id: id) }

    /// The most recent unread count Gmail's own title advertised, if any.
    var mailUnreadFromTitle: Int? { pages["mail"]?.unreadCountFromTitle }

    // MARK: - Popups (sign-in windows and the like)

    /// `window.open` lands here. Using the configuration WebKit hands over is
    /// what keeps `window.opener` alive, so a finished sign-in can report back.
    @discardableResult
    func showPopup(_ urlString: String, opener: WebPage?, configuration: WKWebViewConfiguration?) -> WKWebView? {
        let adopted = configuration.map {
            WKWebView(frame: NSRect(x: 0, y: 32, width: 940, height: 620), configuration: $0)
        }
        let panel = PopupPanel(urlString: urlString, opener: opener, adopted: adopted,
                               loadsPages: loadsPages)
        panel.onDismiss = { [weak self] key in self?.popups[key] = nil }
        panel.attach(to: content)
        popups[ObjectIdentifier(panel)] = panel
        if let opener { opener.openedPopup = panel.webView }
        return panel.webView
    }

    func closePopup(for webView: WKWebView) {
        for (key, panel) in popups where panel.contains(webView) {
            panel.dismiss()
            popups.removeValue(forKey: key)
        }
    }

    // MARK: - Menu actions

    @objc func applyAccountToAllSources(_ sender: Any?) {
        guard let selected = selectedPage else { return }
        let account = Accounts.account(of: selected.currentURLString) ?? 0
        for page in pagesByOrder where page !== selected {
            page.load(Accounts.url(page.currentURLString, account: account))
        }
    }

    @objc func reloadAllSources(_ sender: Any?) {
        pagesByOrder.forEach { $0.reloadFromOrigin() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectMail(_:)), #selector(selectCalendar(_:)):
            return pages.keys.contains(where: { page in
                (menuItem.action == #selector(selectMail(_:)) && page == "mail")
                    || (menuItem.action == #selector(selectCalendar(_:)) && page == "calendar")
            })
        case #selector(nextSource(_:)), #selector(previousSource(_:)):
            return sources.count > 1
        case #selector(applyAccountToAllSources(_:)):
            return pages.count > 1
        default:
            return true
        }
    }

    // MARK: - Smoke reporting

    func smokeReport() -> [(label: String, url: String, ok: Bool, detail: String)] {
        pagesByOrder.map { page in
            let url = page.currentURLString
            if let error = page.lastError {
                return (page.source.label, url, false, (error as NSError).localizedDescription)
            }
            return (page.source.label, url, page.didLoad, page.didLoad ? (page.pageTitle ?? "") : "no load event")
        }
    }

    var allSourcesSettled: Bool {
        !pagesByOrder.isEmpty && pagesByOrder.allSatisfy { $0.didLoad || $0.lastError != nil }
    }

    func layoutSummary() -> String {
        let attached = pagesByOrder.filter { $0.view.superview != nil }.count
        let visible = pagesByOrder.filter { !$0.view.isHidden }.count
        let railWidth = sidebar.frame.width
        return "pagesAttached=\(attached)/\(pagesByOrder.count) visible=\(visible) rail=\(Int(railWidth)) popups=\(popups.count)"
    }
}

/// A modal-ish panel over the content area for a `window.open` result. Sign-in
/// is the case that matters, and it needs to feel like part of the app rather
/// than a stray window.
/// A `window.open` result: shown as a panel over the content, never as a tab.
///
/// Laid out with frames, not constraints, on purpose. Inserting constraints into
/// the graph after the window is on screen makes AppKit re-derive the window's
/// frame from the content view's fitting size, and nothing in this hierarchy
/// implies a size (a web view has none) — the window collapsed to 56x66, a title
/// bar and a close button, which is what "add another account" used to do.
final class PopupPanel {
    let view = PanelView()
    let webView: WKWebView
    weak var opener: WebPage?
    var onDismiss: ((ObjectIdentifier) -> Void)?

    private let urlString: String
    private let loadsPages: Bool

    /// The panel body: a title bar on top, the web view below it.
    final class PanelView: NSVisualEffectView {
        let bar = NSView()
        let slot = NSView()

        override init(frame: NSRect) {
            super.init(frame: frame)
            material = .contentBackground
            blendingMode = .withinWindow
            state = .active
            wantsLayer = true
            layer?.cornerRadius = 10
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.cgColor
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            addSubview(bar)
            addSubview(slot)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            let barHeight: CGFloat = 30
            bar.frame = NSRect(x: 0, y: bounds.height - barHeight, width: bounds.width, height: barHeight)
            slot.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - barHeight))
        }
    }

    init(urlString: String, opener: WebPage?, adopted: WKWebView?, loadsPages: Bool) {
        self.urlString = urlString
        self.opener = opener
        self.loadsPages = loadsPages
        self.webView = adopted
            ?? WKWebView(frame: .zero, configuration: WebPage.defaultConfiguration())

        let label = NSTextField(labelWithString: "Google sign-in")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.sizeToFit()
        label.frame = NSRect(x: 10, y: (30 - label.frame.height) / 2,
                             width: label.frame.width, height: label.frame.height)
        label.autoresizingMask = [.maxXMargin, .minYMargin]
        let close = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        close.bezelStyle = .rounded
        close.controlSize = .small
        close.keyEquivalent = "\u{1b}"
        close.sizeToFit()
        close.frame = NSRect(x: 0, y: (30 - close.frame.height) / 2,
                             width: max(52, close.frame.width), height: close.frame.height)
        close.autoresizingMask = [.minXMargin, .minYMargin]
        view.bar.addSubview(label)
        view.bar.addSubview(close)

        webView.frame = view.slot.bounds
        webView.autoresizingMask = [.width, .height]
        view.slot.addSubview(webView)
    }

    func attach(to container: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        if loadsPages, !WebPage.isBlankString(urlString), let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }

    func contains(_ webView: WKWebView) -> Bool { self.webView === webView }

    @objc private func closeTapped(_ sender: Any?) { dismiss() }

    func dismiss() {
        // A popup that finishes usually just closes. If its opener is still
        // parked on Google's login page, nudge it: it may be waiting for a
        // callback that will not arrive.
        if let opener, opener.isWaitingAtSignIn { opener.reloadFromOrigin() }
        view.removeFromSuperview()
        onDismiss?(ObjectIdentifier(self))
    }
}
