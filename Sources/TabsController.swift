import AppKit
import WebKit

/// The window's content and its toolbar tab strip.
///
/// Deliberately *not* an `NSTabViewController`: with `.toolbar` style AppKit
/// quietly falls back to a segmented control on top of the content (and it did
/// exactly that here), so the tab bar is built directly as a segmented control
/// inside the toolbar. Same look, no heuristic to lose.
final class TabsController: NSViewController, NSToolbarDelegate,
                            NSMenuItemValidation {
    static weak var current: TabsController?

    private(set) var tabs: [WebTab] = []

    /// False only for `--selftest`, which must not touch the network.
    private let loadsPages: Bool

    let segmented = NSSegmentedControl()
    private let host = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 800))

    var selectedTab: WebTab? {
        guard selectedIndex >= 0, selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    var selectedIndex: Int {
        didSet {
            guard oldValue != selectedIndex, selectedIndex >= 0, selectedIndex < tabs.count else { return }
            applySelection()
        }
    }

    var tabCount: Int { tabs.count }

    // MARK: - Toolbar identifiers

    private static let tabsItemID = NSToolbarItem.Identifier("gcal.tabs")
    private static let openItemID = NSToolbarItem.Identifier("gcal.openInBrowser")
    private static let newItemID = NSToolbarItem.Identifier("gcal.newTab")

    // MARK: - Setup

    init(specs: [TabSpec], loadPages: Bool = true) {
        self.loadsPages = loadPages
        self.selectedIndex = 0
        super.init(nibName: nil, bundle: nil)
        TabsController.current = self

        segmented.segmentStyle = .separated
        segmented.trackingMode = .selectOne
        segmented.target = self
        segmented.action = #selector(segmentChanged(_:))
        segmented.setToolTip("Tabs (⌘1…⌘9)", forSegment: 0)

        for spec in specs { append(spec: spec, popup: false) }
        if !tabs.isEmpty { select(0) }
        syncSegments()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        host.autoresizingMask = [.width, .height]
        view = host
        for tab in tabs {
            host.addSubview(tab.view)
            tab.view.frame = host.bounds
            tab.view.autoresizingMask = [.width, .height]
        }
        applySelection()
    }

    private func applySelection() {
        for (index, tab) in tabs.enumerated() {
            tab.view.isHidden = index != selectedIndex
        }
        if segmented.segmentCount > selectedIndex, segmented.selectedSegment != selectedIndex {
            segmented.selectedSegment = selectedIndex
        }
        if let window = view.window, let tab = selectedTab { setWindowTitle(tab, in: window) }
    }

    private func setWindowTitle(_ tab: WebTab, in window: NSWindow) {
        let pageTitle = tab.webView.title ?? ""
        window.title = pageTitle.isEmpty ? tab.spec.label : pageTitle
    }

    // MARK: - Tab lifecycle

    @discardableResult
    private func append(spec: TabSpec, popup: Bool, activate: Bool = true) -> WebTab {
        let tab = WebTab(spec: spec)
        tab.isPopupTab = popup
        tab.onTitleChanged = { [weak self] updated in self?.titleChanged(for: updated) }
        tabs.append(tab)
        if isViewLoaded {
            host.addSubview(tab.view)
            tab.view.frame = host.bounds
            tab.view.autoresizingMask = [.width, .height]
        }
        if loadsPages { tab.load(spec.url) }
        syncSegments()
        if activate { select(tabs.count - 1) }
        return tab
    }

    func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
        applySelection()
        if isViewLoaded { view.window?.makeFirstResponder(selectedTab?.webView) }
    }

    /// `window.open` from a Google page lands here.
    @discardableResult
    func openPopupTab(_ urlString: String, opener: WKWebView?) -> WKWebView? {
        let spec = TabSpec(label: "Loading…", url: urlString, symbol: "safari")
        return append(spec: spec, popup: true).webView
    }

    func closePopup(for webView: WKWebView) {
        guard let tab = tabs.first(where: { $0.webView === webView }) else { return }
        remove(tab)
    }

    private func remove(_ tab: WebTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tab.view.removeFromSuperview()
        tabs.remove(at: index)
        selectedIndex = tabs.isEmpty ? -1 : min(index, tabs.count - 1)
        syncSegments()
        if !tabs.isEmpty { applySelection() }
        NSApp.mainMenu?.update()
    }

    func loadInSelectedTab(_ urlString: String) {
        if let tab = selectedTab { tab.load(urlString) }
        else if !tabs.isEmpty { tabs[0].load(urlString); select(0) }
    }

    private func titleChanged(for tab: WebTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        guard index < segmented.segmentCount else {
            if index == selectedIndex, let window = view.window { setWindowTitle(tab, in: window) }
            return
        }
        if tab.isPopupTab {
            let pageTitle = tab.webView.title ?? ""
            if !pageTitle.isEmpty { segmented.setLabel(pageTitle, forSegment: index) }
        }
        if index == selectedIndex {
            segmented.setWidth(-1, forSegment: index)
            if let window = self.view.window { setWindowTitle(tab, in: window) }
        }
        segmented.sizeToFit()
    }

    private func syncSegments() {
        segmented.segmentCount = tabs.count
        for (index, tab) in tabs.enumerated() {
            segmented.setLabel(tab.spec.label, forSegment: index)
            segmented.setToolTip(tab.spec.url, forSegment: index)
            if let symbol = tab.spec.symbol,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tab.spec.label) {
                segmented.setImage(image, forSegment: index)
                segmented.setImageScaling(.scaleProportionallyDown, forSegment: index)
            } else {
                segmented.setImage(nil, forSegment: index)
            }
            segmented.setWidth(-1, forSegment: index)
        }
        if tabs.indices.contains(selectedIndex) { segmented.selectedSegment = selectedIndex }
        segmented.isEnabled = tabs.count > 1
        segmented.sizeToFit()
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        select(sender.selectedSegment)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.tabsItemID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = segmented
            item.label = "Tabs"
            return item
        case Self.openItemID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Open in Browser"
            item.paletteLabel = "Open this page in your browser"
            item.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "Open in browser")
            item.target = nil
            item.action = #selector(WebTab.openInBrowser(_:))
            return item
        case Self.newItemID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "New Tab"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")
            item.target = self
            item.action = #selector(newTabFromURL(_:))
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.tabsItemID, .flexibleSpace, Self.openItemID, Self.newItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
    }

    // MARK: - Menu actions

    @objc func newCalendarTab(_ sender: Any?) {
        _ = append(spec: TabSpec(label: "Calendar", url: "https://calendar.google.com/calendar/u/0/r/month",
                                 symbol: "calendar"), popup: false)
    }

    @objc func newMailTab(_ sender: Any?) {
        _ = append(spec: TabSpec(label: "Mail", url: "https://mail.google.com/mail/u/0/",
                                 symbol: "envelope"), popup: false)
    }

    @objc func newTabFromURL(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Open a tab at this URL"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://docs.google.com/document/d/…"
        field.stringValue = "https://"
        alert.accessoryView = field

        var response: NSApplication.ModalResponse
        if let window = view.window {
            var result: NSApplication.ModalResponse = .abort
            let gate = RunLoopGate()
            alert.beginSheetModal(for: window) { reply in result = reply; gate.signal() }
            gate.wait()
            response = result
        } else {
            response = alert.runModal()
        }
        guard response == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme?.hasPrefix("http") == true else {
            NSSound.beep(); return
        }
        _ = append(spec: TabSpec(label: url.host ?? "Tab", url: url.absoluteString, symbol: "safari"), popup: false)
    }

    @objc func closeTab(_ sender: Any?) {
        guard let tab = selectedTab else {
            view.window?.performClose(sender); return
        }
        guard tabCount > 1 else {
            // With one tab left, "close" means the window — what ⌘W means
            // everywhere else on the Mac.
            view.window?.performClose(sender)
            return
        }
        remove(tab)
    }

    @objc func selectTab(_ sender: Any?) {
        guard let index = (sender as? NSMenuItem)?.representedObject as? Int else { return }
        select(index)
    }

    @objc func nextTab(_ sender: Any?) { shift(1) }
    @objc func previousTab(_ sender: Any?) { shift(-1) }

    private func shift(_ delta: Int) {
        guard tabCount > 1 else { return }
        select((selectedIndex + delta + tabCount) % tabCount)
    }

    /// Applies the selected tab's account number to every other tab, so
    /// Calendar and Gmail stop drifting onto different logins.
    @objc func applyAccountToAllTabs(_ sender: Any?) {
        guard let selected = selectedTab else { return }
        let account = Accounts.account(of: selected.currentURLString) ?? 0
        for tab in tabs where tab !== selected {
            tab.load(Accounts.url(tab.currentURLString, account: account))
        }
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(selectTab(_:)):
            return ((menuItem.representedObject as? Int) ?? -1) < tabCount
        case #selector(nextTab(_:)), #selector(previousTab(_:)):
            return tabCount > 1
        case #selector(applyAccountToAllTabs(_:)):
            return tabs.count > 1
        default:
            return true
        }
    }

    // MARK: - Smoke reporting

    func smokeReport() -> [(label: String, url: String, ok: Bool, detail: String)] {
        tabs.map { tab in
            let url = tab.currentURLString
            if let error = tab.lastError {
                return (tab.spec.label, url, false, (error as NSError).localizedDescription)
            }
            return (tab.spec.label, url, tab.didLoad, tab.didLoad ? (tab.webView.title ?? "") : "no load event")
        }
    }

    /// Layout evidence for `--smoke`: the tab strip must have real width and
    /// every tab must be attached to the host view, or the UI is silently wrong.
    func layoutSummary() -> String {
        let attached = tabs.filter { $0.view.superview != nil }.count
        let visible = tabs.filter { !$0.view.isHidden }.count
        let strip = segmented.frame
        return "tabsAttached=\(attached)/\(tabs.count) visible=\(visible) strip=\(Int(strip.width))x\(Int(strip.height)) segments=\(segmented.segmentCount)"
    }

    var allTabsSettled: Bool { !tabs.isEmpty && tabs.allSatisfy { $0.didLoad || $0.lastError != nil } }
}

/// Waits for a sheet from a non-modal code path without nesting `NSApp.run`.
final class RunLoopGate {
    private var signalled = false

    func signal() { signalled = true }

    func wait(timeout: TimeInterval = 120) {
        let deadline = Date().addingTimeInterval(timeout)
        while !signalled, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}
