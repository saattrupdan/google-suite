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

        window.contentViewController = content
        window.setContentSize(contentSize)
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
