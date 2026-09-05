import AppKit

/// Builds the main menu. Everything goes through the responder chain with a
/// `nil` target, so an action lands on whichever object can serve it: the web
/// view, the tab, the tab controller, the window controller, or the app.
enum Menus {
    static let appName = "Google Suite"

    static func build() -> NSMenu {
        let main = NSMenu()
        addAppMenu(to: main)
        addFileManager(to: main)
        addEditMenu(to: main)
        addViewMenu(to: main)
        addTabsMenu(to: main)
        addAccountMenu(to: main)
        addWindowMenu(to: main)
        addHelpMenu(to: main)
        return main
    }

    // MARK: - Helpers

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command,
                             target: AnyObject? = nil, represented: Any? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        if let represented { menuItem.representedObject = represented }
        return menuItem
    }

    private static func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        holder.submenu = menu
        parent.addItem(holder)
        return menu
    }

    // MARK: - Menus

    private static func addAppMenu(to main: NSMenu) {
        let menu = submenu(appName, in: main)
        menu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Open Config File…", #selector(AppDelegate.openConfigFile(_:)), ","))
        menu.addItem(item("Launch at Login", #selector(AppDelegate.toggleLaunchAtLogin(_:)), ""))
        menu.addItem(.separator())
        let services = submenu("Services", in: menu)
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
    }

    private static func addFileManager(to main: NSMenu) {
        let menu = submenu("File", in: main)
        menu.addItem(item("New Calendar Tab", #selector(TabsController.newCalendarTab(_:)), "c", modifiers: [.command, .option]))
        menu.addItem(item("New Gmail Tab", #selector(TabsController.newMailTab(_:)), "m", modifiers: [.command, .option]))
        menu.addItem(item("New Tab from URL…", #selector(TabsController.newTabFromURL(_:)), "t"))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(TabsController.closeTab(_:)), "w"))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", modifiers: [.command, .shift]))
    }

    private static func addEditMenu(to main: NSMenu) {
        let menu = submenu("Edit", in: main)
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", modifiers: [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:)), ""))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = submenu("Find", in: menu)
        find.addItem(item("Find…", #selector(NSResponder.performTextFinderAction(_:)), "f"))
        find.addItem(item("Find Next", #selector(NSResponder.performTextFinderAction(_:)), "g"))
        find.addItem(item("Find Previous", #selector(NSResponder.performTextFinderAction(_:)), "g", modifiers: [.command, .shift]))
        find.addItem(item("Use Selection for Find", #selector(NSResponder.performTextFinderAction(_:)), "e"))
        for entry in find.items { entry.tag = 1 }  // NSTextFinder.Action.showFindInterface == 1

        let speech = submenu("Speech", in: menu)
        speech.addItem(item("Start Speaking", #selector(NSTextView.startSpeaking(_:)), ""))
        speech.addItem(item("Stop Speaking", #selector(NSTextView.stopSpeaking(_:)), ""))
        menu.addItem(.separator())
        let substitutions = submenu("Substitutions", in: menu)
        substitutions.addItem(item("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)), ""))
    }

    private static func addViewMenu(to main: NSMenu) {
        let menu = submenu("View", in: main)
        menu.addItem(item("Reload", #selector(WebTab.reload(_:)), "r"))
        menu.addItem(item("Force Reload", #selector(WebTab.forceReload(_:)), "r", modifiers: [.command, .shift]))
        menu.addItem(item("Stop", #selector(WebTab.stopLoading(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item("Back", #selector(WebTab.goBack(_:)), "["))
        menu.addItem(item("Forward", #selector(WebTab.goForward(_:)), "]"))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(WebTab.zoomIn(_:)), "+"))
        menu.addItem(item("Zoom Out", #selector(WebTab.zoomOut(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(WebTab.zoomActual(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]))
        menu.addItem(item("Open This Page in Browser", #selector(WebTab.openInBrowser(_:)), "o", modifiers: [.command, .option]))
    }

    private static func addTabsMenu(to main: NSMenu) {
        let menu = submenu("Tabs", in: main)
        menu.addItem(item("Show Next Tab", #selector(TabsController.nextTab(_:)), "\u{9}", modifiers: [.command, .control]))
        menu.addItem(item("Show Previous Tab", #selector(TabsController.previousTab(_:)), "\u{9}", modifiers: [.command, .control, .shift]))
        menu.addItem(.separator())
        for index in 0..<9 {
            menu.addItem(item("Show Tab \(index + 1)", #selector(TabsController.selectTab(_:)), "\(index + 1)", represented: index))
        }
    }

    private static func addAccountMenu(to main: NSMenu) {
        let menu = submenu("Account", in: main)
        menu.addItem(item("Account Chooser…", #selector(WebTab.accountChooser(_:)), ""))
        menu.addItem(item("Apply Current Account to All Tabs", #selector(TabsController.applyAccountToAllTabs(_:)), ""))
        menu.addItem(.separator())
        let switcher = submenu("Switch Account", in: menu)
        for account in 0..<Accounts.maxAccounts {
            let key = account < 9 ? "\(account + 1)" : ""
            switcher.addItem(item("Account \(account + 1)", #selector(WebTab.switchAccount(_:)), key,
                                 modifiers: [.command, .option], represented: account))
        }
        menu.addItem(.separator())
        menu.addItem(item("Clear Sign-In…", #selector(WebTab.clearSignIn(_:)), ""))
    }

    private static func addWindowMenu(to main: NSMenu) {
        let menu = submenu("Window", in: main)
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""))
        NSApp.windowsMenu = menu
    }

    private static func addHelpMenu(to main: NSMenu) {
        let menu = submenu("Help", in: main)
        let help = item("Google Calendar Help", #selector(AppDelegate.openHelp(_:)), "?")
        help.representedObject = "https://support.google.com/calendar/"
        menu.addItem(help)
        let mailHelp = item("Gmail Help", #selector(AppDelegate.openHelp(_:)), "")
        mailHelp.representedObject = "https://support.google.com/mail/"
        menu.addItem(mailHelp)
        menu.addItem(.separator())
        menu.addItem(item("README on Disk", #selector(AppDelegate.openConfigFile(_:)), "", represented: "readme"))
        NSApp.helpMenu = menu
    }
}
