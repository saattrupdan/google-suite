import AppKit

/// The one window this app has: a left rail plus whichever source is selected.
final class AppWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    init(content: RootController, contentSize: NSSize = NSSize(width: 1280, height: 800)) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
            backing: .buffered,
            defer: false)
        window.tabbingMode = .disallowed
        // Insurance: AppKit can resize a window to the size its content view's
        // constraints imply. Nothing here implies a size, so without a floor a
        // constraint-graph update could shrink the window to a title bar.
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.setFrameAutosaveName("MainWindow")
        window.title = Menus.appName
        window.toolbarStyle = .unified
        window.center()
        super.init(window: window)
        window.delegate = self

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        window.toolbar = toolbar
        toolbar.isVisible = true

        // A view controller's root view comes out of Auto Layout with
        // `translatesAutoresizingMaskIntoConstraints == false`, which makes the
        // window adopt that view's *fitting size* the next time the constraint
        // graph is touched (`-[NSWindow _changeWindowFrameFromConstraintsIfNecessary]`).
        // Nothing in this hierarchy defines a size — a web view has no intrinsic
        // size — so attaching a popup panel collapsed the window to the rail's
        // 56 pt width: a title bar and a close button, nothing else. The content
        // view must resize with the window, not define it.
        window.contentViewController = content
        window.setContentSize(contentSize)
        content.followWindowSize(of: window)
        window.makeFirstResponder(content.selectedPage?.webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static let reloadID = NSToolbarItem.Identifier("gcal.reload")
    private static let browserID = NSToolbarItem.Identifier("gcal.openInBrowser")

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.reloadID: return Self.makeReloadItem()
        case Self.browserID: return Self.makeBrowserItem()
        default: return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.reloadID, .flexibleSpace, Self.browserID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
    }

    private static func makeReloadItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: reloadID)
        item.label = "Reload"
        item.paletteLabel = "Reload this source"
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        item.action = #selector(WebPage.reload(_:))
        return item
    }

    private static func makeBrowserItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: browserID)
        item.label = "Open in Browser"
        item.paletteLabel = "Open this page in your default browser"
        item.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "Open in browser")
        item.action = #selector(WebPage.openInBrowser(_:))
        return item
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var root: RootController? { contentViewController as? RootController }
}
