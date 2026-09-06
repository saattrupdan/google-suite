import AppKit

/// The one window this app has: a left rail plus whichever source is selected.
final class AppWindow: NSWindowController, NSWindowDelegate {
    init(content: RootController, contentSize: NSSize = NSSize(width: 1280, height: 800)) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            // No title bar: the content runs to the top of the window and the
            // traffic lights float over the rail. Everything else a title bar
            // would hold — reload, open-in-browser — is in the menu bar or gone.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .disallowed
        // Insurance: AppKit can resize a window to the size its content view's
        // constraints imply. Nothing here implies a size, so without a floor a
        // constraint-graph update could shrink the window to a title bar.
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.setFrameAutosaveName("MainWindow")
        window.title = Menus.appName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // With no title bar, the rail and the divider are what you drag
        // the window by.
        window.isMovableByWindowBackground = true
        window.center()
        super.init(window: window)
        window.delegate = self

                window.contentViewController = content
        window.setContentSize(contentSize)
        content.followWindowSize(of: window)
        window.makeFirstResponder(content.selectedPage?.webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var root: RootController? { contentViewController as? RootController }

    /// What the smoke report should say about the chrome.
    var chromeSummary: String {
        guard let window else { return "no window" }
        let fullSize = window.styleMask.contains(.fullSizeContentView)
        return "titlebar=\(window.titleVisibility == .hidden ? "hidden" : "visible")"
            + " fullSize=\(fullSize) toolbar=\(window.toolbar == nil ? "none" : "present")"
            + " buttons=\(window.standardWindowButton(.closeButton) != nil ? "close" : "none")"
    }
}
