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
        expect(config.sources[0].symbol == "envelope" && config.sources[1].symbol == "calendar",
               "rail icons are envelope and calendar")
    }

    private static func testConfigIsLenient() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcal-selftest-\(UUID().uuidString)", isDirectory: true)
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
        let config = Config()
        expect(config.isAllowed(host: "calendar.google.com"), "calendar.google.com allowed")
        expect(config.isAllowed(host: "MAIL.GOOGLE.COM"), "host matching ignores case")
        expect(!config.isAllowed(host: "evil.com"), "evil.com not allowed")
        expect(!config.isAllowed(host: "evil-google.com"), "hyphen look-alike rejected")
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
        expectEqual(WebPage.unreadCount(inTitle: "Inbox (3) - dan@syv.ai - Mail") ?? -1, 3, "unread from title")
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
        expectEqual(sidebar.items.count, 2, "one rail button per source")
        expect(sidebar.items.allSatisfy { $0.button.imagePosition == .imageOnly }, "the rail is icon-only")
        expect(sidebar.items.allSatisfy { $0.badge.isHidden }, "badges start hidden")
        sidebar.setBadge(7, id: "mail")
        expectEqual(sidebar.items[0].badge.stringValue, "7", "badge shows the count")
        expect(!sidebar.items[0].badge.isHidden, "badge becomes visible")
        sidebar.setBadge(250, id: "mail")
        expectEqual(sidebar.items[0].badge.stringValue, "99+", "badge caps at 99+")
        sidebar.setBadge(0, id: "mail")
        expect(sidebar.items[0].badge.isHidden, "zero hides the badge")
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
    }
}
