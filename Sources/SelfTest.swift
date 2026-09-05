import AppKit
import WebKit

/// Offline checks: pure logic plus UI object construction. No network, no
/// TCC prompts, no browser. `--smoke` is the one that needs the internet.
enum SelfTest {
    private static var checks = 0
    private static var failures: [String] = []

    static func run() -> Int32 {
        checks = 0
        failures = []

        testConfigDefaults()
        testConfigIsLenient()
        testHostPolicy()
        testAccountURLs()
        testTabsWithoutLoading()
        testNotificationShim()
        testMenus()

        if failures.isEmpty {
            print("SELFTEST ok (\(checks) checks)")
            return 0
        }
        for failure in failures { print("SELFTEST FAIL: \(failure)") }
        print("SELFTEST failed (\(failures.count)/\(checks) checks)")
        return 1
    }

    // MARK: - Assert helpers

    private static func expect(_ condition: Bool, _ what: String) {
        checks += 1
        if !condition { failures.append(what) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        checks += 1
        if actual != expected { failures.append("\(what): got \(actual), expected \(expected)") }
    }

    // MARK: - Checks

    private static func testConfigDefaults() {
        let config = Config()
        expectEqual(config.tabs.count, 2, "default tab count")
        expect(config.tabs[0].url.contains("calendar.google.com"), "first default tab is Calendar")
        expect(config.tabs[1].url.contains("mail.google.com"), "second default tab is Mail")
        expect(config.notificationsShim, "notification shim defaults on")
        expect(!config.openMeetInApp, "Meet opens in the browser by default")
    }

    private static func testConfigIsLenient() {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gcal-selftest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Wrong types and unknown keys must not sink the file.
        try? "{\"tabs\": 17, \"openMeetInApp\": \"yes\", \"wat\": true}".data(using: .utf8)?.write(to: temp)
        let broken = Config.load(createIfMissing: false, at: temp)
        expectEqual(broken.tabs.count, 2, "malformed tabs falls back to defaults")
        expect(!broken.openMeetInApp, "malformed bool falls back to default")

        // A real file round-trips.
        var good = Config()
        good.openMeetInApp = true
        good.allowHosts = ["calendar.google.com"]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(good).write(to: temp)
        let loaded = Config.load(createIfMissing: false, at: temp)
        expect(loaded.openMeetInApp, "openMeetInApp round-trips")
        expectEqual(loaded.allowHosts, ["calendar.google.com"], "allowHosts round-trips")

        // Missing file yields defaults and creates the file.
        let fresh = temp.deletingLastPathComponent().appendingPathComponent("fresh.json")
        let fromNothing = Config.load(createIfMissing: true, at: fresh)
        expectEqual(fromNothing.tabs.count, 2, "missing file yields defaults")
        expect(FileManager.default.fileExists(atPath: fresh.path), "missing file is written")

        try? FileManager.default.removeItem(at: temp.deletingLastPathComponent())
    }

    private static func testHostPolicy() {
        let config = Config()
        expect(config.isAllowed(host: "calendar.google.com"), "calendar.google.com allowed")
        expect(config.isAllowed(host: "MAIL.GOOGLE.COM"), "host matching is case-insensitive")
        expect(!config.isAllowed(host: "evil.com"), "evil.com not allowed")
        expect(!config.isAllowed(host: "notgoogle.com"), "suffix look-alike rejected")
        expect(!config.isAllowed(host: "evil-google.com"), "hyphen look-alike rejected")
        expect(config.isMeet(URL(string: "https://meet.google.com/abc-defg-hij")!), "meet detected")
        expect(!config.isMeet(URL(string: "https://calendar.google.com/calendar/u/0/r/month")!), "calendar is not meet")
    }

    private static func testAccountURLs() {
        expectEqual(
            Accounts.url("https://calendar.google.com/calendar/u/0/r/month", account: 2),
            "https://calendar.google.com/calendar/u/2/r/month", "rewrites calendar path")
        expectEqual(
            Accounts.url("https://mail.google.com/mail/u/1/", account: 0),
            "https://mail.google.com/mail/u/0/", "rewrites gmail path")
        let appended = Accounts.url("https://drive.google.com/drive/my-drive", account: 3)
        expect(appended.contains("authuser=3"), "adds authuser when no /u/ segment exists")
        let replaced = Accounts.url("https://docs.google.com/document/d/1abc?authuser=1", account: 0)
        expect(replaced.contains("authuser=0") && !replaced.contains("authuser=1"), "replaces existing authuser")
        expectEqual(
            Accounts.url("https://accounts.google.com/AccountChooser", account: 2),
            "https://accounts.google.com/AccountChooser", "account chooser untouched")
        expectEqual(Accounts.url("https://example.com/x", account: 2), "https://example.com/x", "non-Google untouched")
        expectEqual(Accounts.account(of: "https://mail.google.com/mail/u/3/") ?? -1, 3, "reads account from path")
        expectEqual(Accounts.account(of: "https://www.google.com/?authuser=4") ?? -1, 4, "reads account from query")
        expectEqual(Accounts.account(of: "https://example.com/") ?? -99, -99, "unknown account is nil")
    }

    private static func testTabsWithoutLoading() {
        let tabs = TabsController(specs: TabSpec.defaults, loadPages: false)
        expectEqual(tabs.tabs.count, 2, "two tabs built")
        expect(tabs.selectedTab === tabs.tabs[0], "first tab selected")

        tabs.select(1)
        expect(tabs.selectedTab === tabs.tabs[1], "selection follows index")

        let before = tabs.tabs.count
        tabs.newCalendarTab(nil)
        expectEqual(tabs.tabs.count, before + 1, "newCalendarTab appends")
        tabs.closeTab(nil)
        expectEqual(tabs.tabs.count, before, "closeTab removes the newest tab")

        tabs.selectTab(NSMenuItem(title: "x", action: nil, keyEquivalent: "").withRepresented(1))
        expect(tabs.selectedTab === tabs.tabs[1], "selectTab honours representedObject")

        tabs.previousTab(nil)
        expect(tabs.selectedTab === tabs.tabs[0], "previousTab wraps to first")
        tabs.nextTab(nil)
        expect(tabs.selectedTab === tabs.tabs[1], "nextTab wraps forward")

        // The last tab must refuse to close rather than leave an empty window.
        while tabs.tabs.count > 1 { tabs.closeTab(nil) }
        tabs.closeTab(nil)
        expectEqual(tabs.tabs.count, 1, "last tab refuses to close")
    }

    private static func testNotificationShim() {
        expect(Notifier.installScript.contains(Notifier.handlerName), "shim posts to the registered handler")
        expect(Notifier.installScript.contains("class GCalNotification"), "shim defines a Notification replacement")
        expectEqual(Notifier.makeUserScript(enabled: false).source, "", "disabled shim injects nothing")
        expectEqual(Notifier.makeUserScript(enabled: true).injectionTime, .atDocumentStart, "shim runs at document start")
    }

    private static func testMenus() {
        let menu = Menus.build()
        expect(menu.items.count >= 8, "all top-level menus present")
        let titles = menu.items.map { $0.title }
        for required in ["File", "Edit", "View", "Tabs", "Account", "Window", "Help"] {
            expect(titles.contains(required), "menu contains \(required)")
        }
        let tabsMenu = menu.items.first { $0.title == "Tabs" }?.submenu
        expectEqual(tabsMenu?.items.filter { $0.title.hasPrefix("Show Tab ") }.count, 9, "nine tab shortcuts")
        let accountMenu = menu.items.first { $0.title == "Account" }?.submenu
        let switcher = accountMenu?.items.first { $0.title == "Switch Account" }?.submenu
        expectEqual(switcher?.items.count, Accounts.maxAccounts, "account submenu size matches Accounts.maxAccounts")
    }
}

private extension NSMenuItem {
    func withRepresented(_ value: Int) -> NSMenuItem {
        representedObject = value
        return self
    }
}
