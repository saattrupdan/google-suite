import AppKit
import WebKit

/// Offline checks: pure logic plus UI construction. No network, no TCC prompts.
/// `--smoke` is the one that needs the internet.
enum SelfTest {
    private static var checks = 0
    private static var failures: [String] = []

    static func run() -> Int32 {
        checks = 0
        failures = []

        testSourceOrder()
        testConfigIsLenient()
        testHostPolicy()
        testMeetPolicy()
        testAccountURLs()
        testBlankAndUnreadParsing()
        testRootControllerWithoutLoading()
        testSidebar()
        testSplitLayout()
        testSplitDivider()
        testGmailChromeCSS()
        testLinkPolicy()
        testMailWatcherGating()
        testMailAccountMerge()
        testNotificationShim()
        testMenus()
        testRevealHandshake()
        testPopupPanelIsFrameBased()

        if failures.isEmpty {
            print("SELFTEST ok (\(checks) checks)")
            return 0
        }
        for failure in failures { print("SELFTEST FAIL: \(failure)") }
        print("SELFTEST failed (\(failures.count)/\(checks) checks)")
        return 1
    }

    // MARK: - Helpers

    private static func expect(_ condition: Bool, _ what: String) {
        checks += 1
        if !condition { failures.append(what) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        checks += 1
        if actual != expected { failures.append("\(what): got \(actual), expected \(expected)") }
    }

    // MARK: - Checks

    private static func testSourceOrder() {
        let config = Config()
        expectEqual(config.sources.count, 2, "two sources configured")
        expectEqual(config.sources[0].id, "mail", "Mail comes before Calendar")
        expectEqual(config.sources[1].id, "calendar", "Calendar is second")
        expectEqual(config.mailPollSeconds, 60, "mail polls once a minute")
        expect(config.mailNotifications, "mail notifications default on")
        expectEqual(config.mailAccountSlots, 3, "three account slots polled by default")
        expect(!config.splitLayout, "one surface at a time by default")
        expect(config.openLinksInBrowser, "links go to the browser by default")
        expect(config.trimGmailChrome, "Gmail's own rails are trimmed by default")
        expectEqual(config.splitRatio, 0.5, "split view starts even")
        expect(config.sources[0].symbol == "envelope" && config.sources[1].symbol == "calendar",
               "rail icons are envelope and calendar")
    }

    private static func testConfigIsLenient() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("google-suite-selftest-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try? "{\"sources\": 12, \"mailNotifications\": \"yes\", \"nope\": 1}".data(using: .utf8)?.write(to: file)
        let broken = Config.load(createIfMissing: false, at: file)
        expectEqual(broken.sources.count, 2, "malformed sources fall back to defaults")
        expect(broken.mailNotifications, "malformed bool falls back to default")

        // An older config with a "tabs" list must still load, Mail first if that
        // is how the user had it.
        try? "{\"tabs\": [{\"label\":\"Mail\",\"url\":\"https://mail.google.com/mail/u/0/\"},{\"label\":\"Calendar\",\"url\":\"https://calendar.google.com/x\"}]}".data(using: .utf8)?.write(to: file)
        let legacy = Config.load(createIfMissing: false, at: file)
        expectEqual(legacy.sources.count, 2, "legacy tabs list converts to sources")
        expectEqual(legacy.sources[0].url, "https://mail.google.com/mail/u/0/", "legacy order preserved")

        var custom = Config()
        custom.mailPollSeconds = 200
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(custom).write(to: file)
        expectEqual(Config.load(createIfMissing: false, at: file).mailPollSeconds, 200, "poll interval round-trips")

        try? "{\"splitLayout\": true, \"openLinksInBrowser\": false}".data(using: .utf8)?.write(to: file)
        let modes = Config.load(createIfMissing: false, at: file)
        expect(modes.splitLayout, "split view is remembered")
        expect(!modes.openLinksInBrowser, "link handling can be turned off")

        // Poll intervals below 15s are refused: that is hammering Google.
        try? "{\"mailPollSeconds\": 1}".data(using: .utf8)?.write(to: file)
        expect(Config.load(createIfMissing: false, at: file).mailPollSeconds >= 15, "poll interval is floored at 15s")

        try? "{\"mailAccountSlots\": 0}".data(using: .utf8)?.write(to: file)
        expect(Config.load(createIfMissing: false, at: file).mailAccountSlots >= 1, "slot count is floored at 1")

        let fresh = dir.appendingPathComponent("fresh.json")
        expectEqual(Config.load(createIfMissing: true, at: fresh).sources.count, 2, "missing file yields defaults")
        expect(FileManager.default.fileExists(atPath: fresh.path), "missing file is written")
        try? FileManager.default.removeItem(at: dir)
    }

    private static func testHostPolicy() {
        var config = Config()
        config.allowHosts = ["calendar.google.com"]
        expect(config.isAllowed(host: "calendar.google.com"), "an allowed host matches exactly")
        expect(config.isAllowed(host: "CALENDAR.GOOGLE.COM"), "host matching ignores case")
        expect(!config.isAllowed(host: "evil.com"), "evil.com not allowed")
        expect(!config.isAllowed(host: "evil-google.com"), "hyphen look-alike rejected")
        expect(config.allowHosts == ["calendar.google.com"], "extras round-trip")
        expect(Config().allowHosts.isEmpty,
               "nothing is privileged by default; each surface carries its own hosts")
    }

    /// The whole point of these: Google's Meet warm-ups must never open a
    /// browser tab, and real room links must still leave for the browser.
    private static func testMeetPolicy() {
        let config = Config()
        func joinable(_ string: String) -> Bool {
            config.isJoinableMeet(URL(string: string)!)
        }
        expect(joinable("https://meet.google.com/abc-defg-hij"), "a room code joins")
        expect(joinable("https://meet.google.com/new"), "\"new meeting\" joins")
        expect(!joinable("https://meet.google.com/"), "the Meet root does not join")
        expect(!joinable("https://meet.google.com/_meet/whoops"), "the whoops page does not join")
        expect(!joinable("https://meet.google.com/_meet/ready"), "the ready warm-up does not join")
        expect(!config.isJoinableMeet(URL(string: "https://calendar.google.com/calendar/u/0/r/month")!),
               "calendar is not Meet")
        expect(config.isMeet(URL(string: "https://meet.google.com/")!), "root is still Meet")
    }

    private static func testAccountURLs() {
        expectEqual(Accounts.url("https://mail.google.com/mail/u/0/", account: 2),
                    "https://mail.google.com/mail/u/2/", "rewrites gmail path")
        expectEqual(Accounts.url("https://calendar.google.com/calendar/u/1/r/month", account: 0),
                    "https://calendar.google.com/calendar/u/0/r/month", "rewrites calendar path")
        expect(Accounts.url("https://drive.google.com/drive", account: 3).contains("authuser=3"),
               "adds authuser when no /u/ segment exists")
        expectEqual(Accounts.url("https://accounts.google.com/x", account: 2),
                    "https://accounts.google.com/x", "account chooser untouched")
        expectEqual(Accounts.account(of: "https://mail.google.com/mail/u/3/") ?? -1, 3, "reads account from path")
        expectEqual(Accounts.account(of: "https://www.google.com/?authuser=4") ?? -1, 4, "reads account from query")
    }

    private static func testBlankAndUnreadParsing() {
        expect(WebPage.isBlank(URL(string: "about:blank")!), "about:blank is blank")
        expect(WebPage.isBlankString("about:blank"), "blank recognised in string form")
        expect(!WebPage.isBlank(URL(string: "https://accounts.google.com/v3/signin")!), "a real URL is not blank")
        expectEqual(WebPage.unreadCount(inTitle: "Inbox (3) - you@example.com - Mail") ?? -1, 3, "unread from title")
        expectEqual(WebPage.unreadCount(inTitle: "(12) Inbox - Mail") ?? -1, 12, "unread in bracket form")
        expect(WebPage.unreadCount(inTitle: "Inbox - Mail") == nil, "no unread count means no badge")
        expect(WebPage.unreadCount(inTitle: nil) == nil, "a nil title parses to nothing")
    }

    private static func testRootControllerWithoutLoading() {
        let root = RootController(sources: Source.defaults, loadPages: false)
        expectEqual(root.pagesByOrder.count, 2, "two pages built")
        expectEqual(root.selectedID, "mail", "Mail is selected at launch")
        expect(!root.pagesByOrder[0].view.isHidden, "Mail view is visible")
        expect(root.pagesByOrder[1].view.isHidden, "Calendar view is hidden")

        root.select(id: "calendar")
        expectEqual(root.selectedID, "calendar", "select(id:) switches source")
        expect(root.pagesByOrder[0].view.isHidden, "Mail view hides after switching")

        root.nextSource(nil)
        expectEqual(root.selectedID, "mail", "nextSource wraps to Mail")
        root.previousSource(nil)
        expectEqual(root.selectedID, "calendar", "previousSource wraps backwards")

        let web = root.showPopup("about:blank", opener: root.selectedPage, configuration: nil)
        expect(web != nil, "window.open yields a web view")
        expectEqual(root.popupsCount, 1, "the popup is tracked")
        root.closePopup(for: web!)
        expectEqual(root.popupsCount, 0, "closing the popup releases it")
    }

    private static func testSidebar() {
        let sidebar = Sidebar(sources: Source.defaults)
        sidebar.frame = NSRect(x: 0, y: 0, width: Sidebar.width, height: 600)
        sidebar.layoutSubtreeIfNeeded()
        expectEqual(sidebar.items.count, 2, "one rail button per source")
        expect(sidebar.items.allSatisfy { $0.button.imagePosition == .imageOnly }, "the rail is icon-only")
        expect(sidebar.items.allSatisfy { $0.badge.isHidden }, "badges start hidden")
        sidebar.setBadge(7, id: "mail")
        sidebar.layoutSubtreeIfNeeded()
        expectEqual(sidebar.items[0].badge.stringValue, "7", "badge shows the count")
        expect(!sidebar.items[0].badge.isHidden, "badge becomes visible")
        sidebar.setBadge(250, id: "mail")
        expectEqual(sidebar.items[0].badge.stringValue, "99+", "badge caps at 99+")
        sidebar.setBadge(0, id: "mail")
        expect(sidebar.items[0].badge.isHidden, "zero hides the badge")
        // A badge hanging over the container's edge is what got clipped by the
        // rail, so it must live inside it.
        sidebar.setBadge(123, id: "mail")
        sidebar.layoutSubtreeIfNeeded()
        let badge = sidebar.items[0].badge.frame
        let holder = sidebar.items[0].container.frame
        expect(badge.maxX <= holder.maxX + 0.5 && badge.maxY <= holder.maxY + 0.5 && badge.minX >= holder.minX,
               "the badge stays inside its icon (\(badge) in \(holder))")
        expect(sidebar.items[0].container.frame.maxY <= sidebar.bounds.height - Sidebar.topInset + 1,
               "the first icon clears the window buttons (top \(sidebar.items[0].container.frame.maxY) of "
               + "\(sidebar.bounds.height))")
        sidebar.setSelected(id: "calendar")
        expect(sidebar.items[1].button.state == .on && sidebar.items[0].button.state == .off,
               "selection highlights one icon")
        expect(sidebar.items[1].button.contentTintColor?.isEqual(to: Sidebar.tint(forSelected: true)) == true,
               "the shown source is tinted blue")
        expect(sidebar.items[0].button.contentTintColor?.isEqual(to: Sidebar.tint(forSelected: false)) == true,
               "the hidden source is grey, not blue")
    }

    /// The dedup that keeps the badge honest: Gmail answers every unused account
    /// slot with the same mailbox, so identity — not the slot number — decides.
    private static func testSplitLayout() {
        let root = RootController(sources: Source.defaults, loadPages: false)
        root.view.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        root.view.layoutSubtreeIfNeeded()
        expect(root.pagesByOrder[1].view.isHidden, "single view hides the other surface")

        root.layout = .split
        let mail = root.pagesByOrder[0].view.frame
        let calendar = root.pagesByOrder[1].view.frame
        expect(!root.pagesByOrder[0].view.isHidden && !root.pagesByOrder[1].view.isHidden,
               "split view shows both surfaces")
        expect(abs(mail.width - calendar.width) < 2 && calendar.minX >= mail.maxX,
               "split view gives each surface half the width (\(mail) / \(calendar))")
        expect(mail.height > 600 && calendar.height > 600, "split surfaces fill the height")
        expect(!root.dividerFrame.isNull && root.dividerFrame.height > 600,
               "the divider spans the height")

        root.layout = .single
        expect(root.pagesByOrder[1].view.isHidden, "going back to one surface hides Calendar")

        // Selecting in split view must not hide the other half.
        root.layout = .split
        root.select(id: "mail")
        expect(!root.pagesByOrder[1].view.isHidden, "selecting one surface keeps both visible")
    }

    /// Links are for the browser; only the two surfaces and sign-in belong in
    /// the window.
    private static func testSplitDivider() {
        let root = RootController(sources: Source.defaults, loadPages: false)
        root.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        root.view.layoutSubtreeIfNeeded()
        root.layout = .split
        root.splitRatio = 0.35
        let mail = root.pagesByOrder[0].view.frame
        let calendar = root.pagesByOrder[1].view.frame
        expect(abs(mail.width - (1144 * 0.35)) < 3, "the ratio sets Mail's width (\(mail.width))")
        expect(abs(calendar.maxX - 1144) < 2, "Calendar still ends at the window edge (\(calendar.maxX))")
        expect(calendar.minX > mail.maxX, "no overlap between the two surfaces")

        root.splitRatio = 0.01
        expect(RootController.splitLimits.contains(root.splitRatio),
               "the ratio is clamped to something usable (\(root.splitRatio))")
        root.splitRatio = 0.99
        expect(RootController.splitLimits.contains(root.splitRatio), "clamped from above too")

        // The strip you grab is wider than the line you see.
        root.splitRatio = 0.5
        let divider = root.dividerFrame
        expect(divider.width >= RootController.dividerHitWidth,
               "the divider strip is grabbable (\(divider.width) wide)")
        expect(divider.width >= 18, "the cursor zone is wide enough to find (\(divider.width))")
        expect(root.dividerHitTest(CGPoint(x: divider.midX, y: divider.midY)),
               "the middle of the strip takes the mouse")
        expect(!root.dividerHitTest(CGPoint(x: divider.minX - 40, y: divider.midY)),
               "clicks well away from the seam go to the page, not the divider")
        expect(abs(divider.midX - (root.contentFrame.midX - 28)) < 3 || abs(divider.midX - 572) < 3,
               "the divider sits between the two surfaces (\(divider))")
    }

    private static func testGmailChromeCSS() {
        // The header rule is positional, because the account and support
        // buttons are <img> elements with no accessible name to select.
        expect(GmailChrome.scriptSource(isMail: true).contains("hideHeaderRight"),
               "the header's right-hand cluster is hidden by position, not by name")
        for selector in ["[aria-label=\"Gemini\"]", ".Pv5YRd"] {
            expect(GmailChrome.mailSelectors.contains(selector), "gmail hides \(selector)")
        }
        expect(GmailChrome.auditScript.contains("headerRight"),
               "the audit measures the header zone, so a surviving avatar is a failure")

        expect(GmailChrome.makeUserScript(enabled: false, isMail: true).source.isEmpty,
               "disabled trimming injects nothing")
        let mailScript = GmailChrome.makeUserScript(enabled: true, isMail: true)
        let calendarScript = GmailChrome.makeUserScript(enabled: true, isMail: false)
        expect(mailScript.source.contains("suite-chrome"), "the stylesheet is installed under a known id")
        expect(mailScript.source.contains("aeN"), "the mail page gets the mail rules")
        expect(calendarScript.source.contains("Switch to Tasks"), "the calendar page gets the calendar rules")
        expect(!calendarScript.source.contains("aeN"), "Calendar is not styled as Gmail")
        for isMail in [true, false] {
            let css = GmailChrome.stylesheet(isMail: isMail)
            expect(css.contains(#"aria-label="Side panel""#),
                   "the right rail is targeted by role and label, not just a class")
            expect(css.contains(#"aria-label^="Google Account""#), "the broken account picture is hidden")
            expect(css.contains(#"[role="complementary"]"#), "the side panel selector uses its role")
            // Google forbids inline <style> elements, so the stylesheet alone is
            // not enough; the CSSOM pass is what makes it stick on Calendar.
            let js = GmailChrome.makeUserScript(enabled: true, isMail: isMail).source
            expect(js.contains("setProperty"), "hiding also happens through the CSSOM (CSP-proof)")
            expect(js.contains("MutationObserver"), "re-rendered chrome is hidden again, not just once")
        }
        // The rules must name what the live page actually renders.
        for selector in ["div.aeN[role=\"navigation\"]", "div.jAmAWb", "#gb a.FH", "#gb .lJradf"] {
            expect(GmailChrome.mailSelectors.contains(selector), "mail selectors target \(selector)")
        }
        expect(GmailChrome.sharedSelectors.contains(#"#gb a[aria-label^="Google Account"]"#),
               "the account picture is hidden (it only errors inside a web view)")
        for selector in ["[aria-label=\"Create\"]", "[aria-label=\"Switch to Tasks\"]",
                         "[aria-label=\"Settings menu\"]", "[aria-label=\"Google apps\"]",
                         "[aria-label=\"Support\"]"] {
            expect(GmailChrome.calendarSelectors.contains(selector), "calendar hides \(selector)")
        }
        expect(GmailChrome.calendarSelectors.allSatisfy { !$0.contains("Main drawer") },
               "the calendar drawer button is left alone")
        let addURL = Accounts.addAccountURL(for: "https://mail.google.com/mail/u/0/")
        expect(addURL.hasPrefix("https://accounts.google.com/AddSession?hl=en&continue="),
               "adding an account goes to Google's AddSession page")
        expect(addURL.contains("mail.google.com") && !addURL.contains(" "),
               "the return address is escaped into the url")
        expect(GmailChrome.auditScript.contains("leftRail"), "the audit measures the rails")
        expect(WebPage.isMail(Source(id: "mail", label: "Mail", url: "https://mail.google.com/mail/u/0/",
                                    symbol: "envelope")), "Mail is recognised as mail")
        expect(!WebPage.isMail(Source(id: "calendar", label: "Calendar",
                                      url: "https://calendar.google.com/calendar/u/0/r/month",
                                      symbol: "calendar")), "Calendar is not trimmed")
        var config = Config()
        config.trimGmailChrome = false
        expect(!config.trimGmailChrome, "trimming can be turned off in config")
    }

    private static func testLinkPolicy() {
        let config = Config()
        let mail = config.sources.first { $0.id == "mail" }!
        let calendar = config.sources.first { $0.id == "calendar" }!
        expect(config.staysInApp(host: "mail.google.com", for: mail), "Mail stays in Mail")
        expect(!config.staysInApp(host: "docs.google.com", for: mail), "a Docs link leaves the app")
        expect(!config.staysInApp(host: "drive.google.com", for: mail), "Drive leaves the app")
        expect(!config.staysInApp(host: "example.com", for: mail), "an article in an email leaves the app")
        expect(config.staysInApp(host: "accounts.google.com", for: mail), "sign-in stays inside")
        expect(config.staysInApp(host: "calendar.google.com", for: calendar), "Calendar stays in Calendar")
        expect(!config.staysInApp(host: "mail.google.com", for: calendar),
               "Calendar does not swallow Mail links")
        expect(mail.inAppHosts == ["mail.google.com"], "hosts derive from the source URL")
        expect(calendar.inAppHosts.contains("www.google.com"), "Calendar also answers to www.google.com")
        expect(config.staysInApp(host: "notion.so", for: mail) == false, "nothing else is privileged")
        var extra = Config()
        extra.allowHosts = ["notion.so"]
        expect(extra.staysInApp(host: "notion.so", for: mail), "an explicitly allowed host may stay")
    }

    private static func testMailAccountMerge() {
        func slot(_ u: Int, _ mailbox: String, _ count: Int, _ ids: [String]) -> [String: Any] {
            ["u": u, "ok": true, "email": mailbox, "fullcount": count,
             "entries": ids.map { ["id": $0, "title": "Subject \($0)", "from": "Someone"] }]
        }
        let one = MailWatcher.merge(["accounts": [slot(0, "a@x.dk", 3, ["i1", "i2"]),
                                                  slot(1, "a@x.dk", 3, ["i1", "i2"]),
                                                  slot(2, "a@x.dk", 3, ["i1", "i2"])]],
                                   excluding: [])
        expectEqual(one.total, 3, "one mailbox seen through three slots counts once")
        expectEqual(one.fresh.count, 2, "duplicate entries collapse to distinct messages")
        expectEqual(one.mailboxes.count, 1, "one mailbox reported")

        let two = MailWatcher.merge(["accounts": [slot(0, "a@x.dk", 3, ["i1"]),
                                                  slot(1, "b@y.dk", 4, ["i9"]),
                                                  slot(2, "a@x.dk", 3, ["i1"])]],
                                    excluding: ["i1"])
        expectEqual(two.total, 7, "two real mailboxes add up")
        expectEqual(two.fresh.map { $0.id }, ["i9"], "already-seen messages are not re-notified")
        expectEqual(two.fresh.first?.mailbox ?? "", "b@y.dk", "a message keeps its mailbox label")

        let dead = MailWatcher.merge(["accounts": [["u": 0, "ok": false, "error": "http 404"]]],
                                     excluding: [])
        expect(!dead.countsAsUnread, "no count means the badge is left alone")
        expect(dead.status.contains("http 404"), "the failure reason survives")
    }

    private static func testMailWatcherGating() {
        let watcher = MailWatcher.shared
        watcher.stop()
        expect(!watcher.isRunning, "watcher is stopped before start")
        expect(!watcher.absorbsInPageNotifications(host: "mail.google.com"),
               "a stopped watcher must not swallow in-page notifications")
        watcher.start(interval: 15, enabled: false)
        expect(!watcher.isRunning, "starting disabled creates no timer")
    }

    /// The window collapse came from constraints being inserted after the window
    /// was on screen, so the panel must stay constraint-free.
    private static func testPopupPanelIsFrameBased() {
        let panel = PopupPanel(urlString: "about:blank", opener: nil, adopted: nil, loadsPages: false)
        expect(panel.view.constraints.isEmpty, "the popup panel adds no constraints")
        expect(panel.view.subviews.count == 2, "panel is bar + web slot, laid out by frames")
    }

    private static func testNotificationShim() {
        expect(Notifier.installScript.contains(Notifier.handlerName), "shim posts to the registered handler")
        expect(Notifier.installScript.contains("class GCalNotification"), "shim replaces Notification")
        expectEqual(Notifier.makeUserScript(enabled: false).source, "", "disabled shim injects nothing")
    }

    private static func testRevealHandshake() {
        Reveal.use(path: nil)  // a temp file, not the real config directory
        expect(Reveal.take() == nil, "no request pending at first")
        Reveal.request("calendar")
        expectEqual(Reveal.take() ?? "", "calendar", "a request survives to the next take")
        expect(Reveal.take() == nil, "a request is consumed once")
        Reveal.use(path: nil)
    }

    private static func testMenus() {
        let menu = Menus.build()
        let titles = menu.items.map { $0.title }
        for required in ["File", "Edit", "View", "Go", "Account", "Window", "Help"] {
            expect(titles.contains(required), "menu contains \(required)")
        }
        let all = menu.items.compactMap { $0.submenu }.flatMap { $0.items }
        expect(!all.contains { $0.title.contains("New Tab") }, "no browser-style New Tab commands")
        expect(!all.contains { $0.title.contains("Close Tab") }, "no browser-style Close Tab command")
        let go = menu.items.first { $0.title == "Go" }?.submenu
        let goTitles = go?.items.map { $0.title } ?? []
        expect(goTitles.first == "Mail" && goTitles.dropFirst().first == "Calendar",
               "Go lists Mail then Calendar, in that order")
        expect(all.contains { $0.title == "New Mail Notifications" }, "notifications can be toggled off")
        let view = menu.items.first { $0.title == "View" }?.submenu
        let viewTitles = view?.items.map { $0.title } ?? []
        expect(viewTitles.contains("Side by Side"), "split view is a menu command")
        expect(!viewTitles.contains("Back") && !viewTitles.contains("Forward"),
               "no browser navigation commands")
    }
}
