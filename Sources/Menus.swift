import AppKit

/// The menu bar. Built for a two-surface utility, not a browser: there is no
/// new-tab, close-tab or history menu, because there is nothing to create.
enum Menus {
    static let appName = "Google Suite"

    static func build() -> NSMenu {
        let main = NSMenu()
        addAppMenu(to: main)
        addFileMenu(to: main)
        addEditMenu(to: main)
        addViewMenu(to: main)
        addGoMenu(to: main)
        addAccountMenu(to: main)
        addWindowMenu(to: main)
        addHelpMenu(to: main)
        return main
    }

    // MARK: - Helpers

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             modifiers: NSEvent.ModifierFlags = .command,
                             represented: Any? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
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
        menu.addItem(item("New Mail Notifications", #selector(AppDelegate.toggleMailNotifications(_:)), ""))
        menu.addItem(.separator())
        NSApp.servicesMenu = submenu("Services", in: menu)
        menu.addItem(.separator())
        menu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                         modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
    }

    private static func addFileMenu(to main: NSMenu) {
        let menu = submenu("File", in: main)
        menu.addItem(item("Check Mail Now", #selector(AppDelegate.checkMailNow(_:)), "k",
                         modifiers: [.command, .option]))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w"))
    }

    private static func addEditMenu(to main: NSMenu) {
        let menu = submenu("Edit", in: main)
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v",
                         modifiers: [.command, .option, .shift]))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())

        let find = submenu("Find", in: menu)
        find.addItem(item("Find…", #selector(NSResponder.performTextFinderAction(_:)), "f"))
        find.addItem(item("Find Next", #selector(NSResponder.performTextFinderAction(_:)), "g"))
        find.addItem(item("Find Previous", #selector(NSResponder.performTextFinderAction(_:)), "g",
                         modifiers: [.command, .shift]))
        // All of these resolve through NSTextFinder, whose action tag selects the
        // operation; 1 is "show find interface".
        for entry in find.items { entry.tag = 1 }

        let speech = submenu("Speech", in: menu)
        speech.addItem(item("Start Speaking", #selector(NSTextView.startSpeaking(_:)), ""))
        speech.addItem(item("Stop Speaking", #selector(NSTextView.stopSpeaking(_:)), ""))
    }

    private static func addViewMenu(to main: NSMenu) {
        let menu = submenu("View", in: main)
        menu.addItem(item("Reload", #selector(WebPage.reload(_:)), "r"))
        menu.addItem(item("Reload Both Sources", #selector(RootController.reloadAllSources(_:)), "r",
                         modifiers: [.command, .shift, .option]))
        menu.addItem(item("Stop", #selector(WebPage.stopLoading(_:)), "."))
        menu.addItem(.separator())
        // No Back/Forward: this shows two surfaces, it does not browse.
        menu.addItem(item("Side by Side", #selector(RootController.toggleSplit(_:)), "\\"))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(WebPage.zoomIn(_:)), "+"))
        menu.addItem(item("Zoom Out", #selector(WebPage.zoomOut(_:)), "-"))
        menu.addItem(item("Actual Size", #selector(WebPage.zoomActual(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
                         modifiers: [.command, .control]))
        menu.addItem(item("Open This Page in Browser", #selector(WebPage.openInBrowser(_:)), "o",
                         modifiers: [.command, .option]))
    }

    private static func addGoMenu(to main: NSMenu) {
        let menu = submenu("Go", in: main)
        for (index, source) in Source.defaults.enumerated() {
            menu.addItem(item(source.label, source.id == "mail" ? #selector(RootController.selectMail(_:))
                                                                       : #selector(RootController.selectCalendar(_:)),
                              "\(index + 1)"))
        }
        menu.addItem(.separator())
        menu.addItem(item("Next Source", #selector(RootController.nextSource(_:)), "\u{9}",
                         modifiers: [.command, .control]))
        menu.addItem(item("Previous Source", #selector(RootController.previousSource(_:)), "\u{9}",
                         modifiers: [.command, .control, .shift]))
    }

    private static func addAccountMenu(to main: NSMenu) {
        let menu = submenu("Account", in: main)
        menu.addItem(item("Account Chooser…", #selector(WebPage.accountChooser(_:)), ""))
        menu.addItem(item("Apply Current Account to Both Sources",
                          #selector(RootController.applyAccountToAllSources(_:)), ""))
        menu.addItem(.separator())
        let switcher = submenu("Switch Account", in: menu)
        for account in 0..<Accounts.maxAccounts {
            switcher.addItem(item("Account \(account + 1)", #selector(WebPage.switchAccount(_:)), "\(account + 1)",
                                  modifiers: [.command, .option], represented: account))
        }
        menu.addItem(.separator())
        menu.addItem(item("Clear Sign-In…", #selector(WebPage.clearSignIn(_:)), ""))
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
        let calendar = item("Google Calendar Help", #selector(AppDelegate.openHelp(_:)), "")
        calendar.representedObject = "https://support.google.com/calendar/"
        menu.addItem(calendar)
        let gmail = item("Gmail Help", #selector(AppDelegate.openHelp(_:)), "")
        gmail.representedObject = "https://support.google.com/mail/"
        menu.addItem(gmail)
        menu.addItem(.separator())
        let readme = item("README on Disk", #selector(AppDelegate.openConfigFile(_:)), "", represented: "readme")
        menu.addItem(readme)
        NSApp.helpMenu = menu
    }
}
