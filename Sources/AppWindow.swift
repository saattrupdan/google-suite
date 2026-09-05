import AppKit

/// The one window this app has. A toolbar is required before the tab
/// controller is installed, because `NSTabViewController.TabStyle.toolbar`
/// renders its tab bar *inside* the toolbar.
final class AppWindow: NSWindowController, NSWindowDelegate {
    private let tabs: TabsController

    init(tabs: TabsController, contentSize: NSSize = NSSize(width: 1280, height: 800)) {
        self.tabs = tabs
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("MainWindow")
        window.title = "Google"
        window.center()
        super.init(window: window)
        window.delegate = self

        // The tab controller owns the toolbar's content: the tab strip plus two
        // buttons. Assign the delegate before the window takes the toolbar, or
        // the default item set is never instantiated.
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = tabs
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.showsBaselineSeparator = false

        window.contentViewController = tabs
        window.toolbar = toolbar
        toolbar.isVisible = true
        window.setContentSize(contentSize)
        window.makeFirstResponder(tabs.selectedTab?.webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var tabController: TabsController { tabs }

    // MARK: - Menu actions routed here when no web view is first responder

    @objc func newWindow(_ sender: Any?) { show() }
}
