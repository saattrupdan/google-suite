import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation,
                         UNUserNotificationCenterDelegate {
    var window: AppWindow!
    /// Retained: the window holds the view, not the controller.
    private var root: RootController?
    private var probe: PopupProbe?
    private var domDump: DomDump?
    private var domCheck: DomCheck?
    /// Held strongly: the smoke runner re-arms itself across run-loop turns.
    private var smoke: SmokeRunner?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = AppRuntime.shared
        NSApp.mainMenu = Menus.build()
        applyDockIcon()

        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            // Ask now rather than mid-stream, so the first new-mail banner is
            // not also the first time the system asks.
            center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .notDetermined else { return }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
            }
        }

        let root = RootController(sources: runtime.config.sources)
        root.layout = runtime.config.splitLayout ? .split : .single
        root.splitRatio = CGFloat(runtime.config.splitRatio)
        self.root = root
        window = AppWindow(content: root)
        MailWatcher.shared.page = root.pagesByOrder.first { $0.source.id == "mail" }
        MailWatcher.shared.start(interval: runtime.config.mailPollSeconds,
                                 enabled: runtime.config.mailNotifications,
                                 accounts: runtime.config.mailAccountSlots)

        applyRevealRequest()

        // Smoke drives the same path as normal use, window on screen included.
        window.show()
        if arguments.contains("--domcheck") {
            let probe = DomCheck(page: root.pagesByOrder.first { $0.source.id == "mail" })
            self.domCheck = probe
            probe.start()
        }
        if arguments.contains("--domdump") {
            let probe = DomDump(page: root.pagesByOrder.first { $0.source.id == "mail" })
            self.domDump = probe
            probe.start()
        }
        if arguments.contains("--popupprobe") {
            // Retained: an unretained probe would vanish before its own timers.
            let probe = PopupProbe(root: root, window: window.window)
            self.probe = probe
            probe.start()
        }
        if runtime.smokeMode {
            smoke = SmokeRunner(root: root, window: window.window, chrome: window.chromeSummary)
            smoke?.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { window?.show() }
        return true
    }

    /// Sets the icon the Dock and the app switcher show, straight from the
    /// bundle.
    ///
    /// `CFBundleIconFile` alone is not enough on a machine that has already
    /// cached an icon for this bundle id: Spotlight read the new `.icns` while
    /// cmd-tab kept drawing the generic one. Assigning `applicationIconImage`
    /// makes the running process carry its own icon, so neither cache decides.
    private func applyDockIcon() {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = icon
    }

    /// Acts on a `gcal --mail` / `--calendar` request — on a cold start, and on a
    /// re-activation of an instance that is already running (which is the case
    /// `open --args` cannot reach).
    private func applyRevealRequest() {
        guard let id = Reveal.take() else { return }
        root?.select(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyRevealRequest()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - UNUserNotificationCenterDelegate

    /// Banner while the app is frontmost, and jump to the right source on click.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        window?.show()
        if let target = response.notification.request.content.userInfo["goto"] as? String {
            RootController.current?.select(id: target)
        }
    }

    // MARK: - Actions

    @objc func openConfigFile(_ sender: NSMenuItem?) {
        let url: URL
        if (sender?.representedObject as? String) == "readme",
           let resource = Bundle.main.url(forResource: "README", withExtension: "md") {
            url = resource
        } else {
            url = Config.fileURL
            if !FileManager.default.fileExists(atPath: url.path) { Config.writeDefaults(to: url) }
        }
        NSWorkspace.shared.open(url)
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        let target = !LaunchItems.isEnabled
        if let error = LaunchItems.setEnabled(target) {
            let alert = NSAlert()
            alert.messageText = "Could not change launch-at-login"
            alert.informativeText = error
            alert.runModal()
        }
        NSApp.mainMenu?.update()
    }

    @objc func toggleMailNotifications(_ sender: Any?) {
        let config = AppRuntime.shared.config
        MailWatcher.shared.start(interval: config.mailPollSeconds, enabled: !MailWatcher.shared.isEnabled)
    }

    @objc func checkMailNow(_ sender: Any?) { MailWatcher.shared.poll() }

    @objc func openHelp(_ sender: NSMenuItem?) {
        guard let string = sender?.representedObject as? String, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleLaunchAtLogin(_:)):
            menuItem.state = LaunchItems.isEnabled ? .on : .off
            return LaunchItems.isSupported
        case #selector(toggleMailNotifications(_:)):
            menuItem.state = MailWatcher.shared.isEnabled ? .on : .off
            return true
        default:
            return true
        }
    }
}

/// `--smoke`: builds the real window and reports what it became, so a silent
/// layout or identity regression shows up as text instead of a shrug.
final class SmokeRunner {
    private let root: RootController
    private let window: NSWindow?
    private let chrome: String
    private let deadline = Date().addingTimeInterval(30)

    init(root: RootController, window: NSWindow?, chrome: String = "n/a") {
        self.root = root
        self.window = window
        self.chrome = chrome
    }

    func start() { tick() }

    private func tick() {
        // Settle means: every page resolved *and* the first feed probe answered,
        // otherwise the report describes a watcher that never ran.
        let pagesSettled = root.allSourcesSettled
        let watcherAnswered = MailWatcher.shared.lastFeedStatus != "never polled"
            && MailWatcher.shared.lastFeedStatus != "polling"
        if (pagesSettled && watcherAnswered) || Date() > deadline { finish(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.tick() }
    }

    private func finish() {
        let report = root.smokeReport()
        var identity = "unknown"
        let gate = RunLoopGate()
        root.selectedPage?.webView.evaluateJavaScript("navigator.userAgent") { value, _ in
            identity = (value as? String) ?? "unknown"
            gate.signal()
        }
        gate.wait(timeout: 3)

        var auth = "not-run"
        if Bundle.main.bundleIdentifier != nil {
            let inner = RunLoopGate()
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                auth = "\(settings.authorizationStatus.rawValue)"
                inner.signal()
            }
            inner.wait(timeout: 3)
        }

        print("SMOKE sources=\(report.count) window=\(window != nil) auth=\(auth) watcher=\(MailWatcher.shared.isRunning ? "on" : "off") mailMode=\(MailWatcher.shared.modeDescription)")
        print("  layout \(root.layoutSummary())")
        print("  chrome \(chrome) "
              + "icon=\(NSApp.applicationIconImage?.size ?? .zero)")
        print("  identity \(identity)")
        var allOK = true
        for entry in report {
            allOK = allOK && entry.ok
            let mark = entry.ok ? "ok  " : "fail"
            print("  \(mark) \(entry.label.padding(toLength: 10, withPad: " ", startingAt: 0)) title=\(entry.detail.prefix(58)) url=\(entry.url.prefix(80))")
        }
        print(allOK ? "SMOKE ok" : "SMOKE fail")
        fflush(stdout)
        exit(allOK ? 0 : 1)
    }
}

/// Waits for an asynchronous callback without nesting `NSApp.run`.
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

/// Regression test for the window collapse: attaches a popup panel the way
/// `window.open` does and fails if the window or the web view ends up tiny. The
/// bug was invisible in the selftest because it only happens once the window is
/// on screen and a constraint graph update makes AppKit re-derive the window's
/// frame from the content view's fitting size.
final class PopupProbe {
    private let root: RootController
    private let window: NSWindow?
    private var deadline = Date().addingTimeInterval(15)

    init(root: RootController, window: NSWindow?) {
        self.root = root
        self.window = window
    }

    func start() {
        window?.makeKeyAndOrderFront(nil)
        guard let opener = root.pagesByOrder.first else { print("PROBE fail: no page"); exit(1) }
        baseline = window?.frame ?? .zero
        _ = root.showPopup("about:blank", opener: opener, configuration: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            self.dump("after layout")
            self.finish()
        }
    }

    private var baseline: NSRect = .zero

    private func dump(_ when: String) {
        print("PROBE \(when): window=\(desc(window?.frame)) content=\(desc(root.contentFrame)) "
              + "sidebar=\(desc(root.sidebarFrame)) popups=\(root.popupsCount) "
              + "panel=\(desc(root.popupPanelFrame)) panelWeb=\(desc(root.popupWebFrame))")
    }

    private func desc(_ frame: NSRect?) -> String {
        guard let frame else { return "nil" }
        return "\(Int(frame.width))x\(Int(frame.height))"
    }

    private func finish() {
        let panel = root.popupWebFrame ?? .zero
        let window = window?.frame ?? .zero
        let ok = panel.width > 200 && panel.height > 200
            && abs(window.width - baseline.width) < 2 && abs(window.height - baseline.height) < 2
        print("PROBE \(ok ? "ok" : "FAIL: the popup collapsed the window")")
        exit(ok ? 0 : 1)
    }
}

/// Prints the parts of Gmail's own layout that a stylesheet would target: wide
/// left/right containers, the header, and the hamburger button. Injected CSS has
/// to be written against what the page actually renders, not against remembered
/// class names, and this is the evidence for it.
final class DomDump {
    weak var page: WebPage?

    init(page: WebPage?) { self.page = page }

    func start() {
        guard let page else { print("DOM fail: no mail page"); exit(1) }
        guard page.didLoad, page.currentURLString.contains("mail.google.com") else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start() }
            return
        }
        let js = #"""
        (() => {
          const out = {viewport: [innerWidth, innerHeight], panels: [], header: [], hamburger: [], search: []};
          const info = (el) => ({
            tag: el.tagName.toLowerCase(),
            cls: (el.className || '').toString().slice(0, 90),
            id: el.id || '',
            role: el.getAttribute('role') || '',
            aria: el.getAttribute('aria-label') || el.getAttribute('title') || '',
            rect: [Math.round(el.getBoundingClientRect().x), Math.round(el.getBoundingClientRect().y),
                   Math.round(el.getBoundingClientRect().width), Math.round(el.getBoundingClientRect().height)],
            parent: el.parentElement ? el.parentElement.tagName.toLowerCase() + '.' +
                    (el.parentElement.className || '').toString().split(' ').slice(0, 3).join('.') : '',
          });
          for (const el of document.querySelectorAll('body div, body aside, body nav')) {
            const r = el.getBoundingClientRect();
            if (r.width < 60 || r.height < 200) continue;
            if (r.width > innerWidth * 0.55 && r.height > innerHeight * 0.6) continue;   // the message list itself
            if (r.width > 300) continue;
            out.panels.push(info(el));
          }
          for (const el of document.querySelectorAll('#gb, #gb > *, #gb * [id], #gb [aria-label], #gb form')) out.header.push(info(el));
          for (const el of document.querySelectorAll('[aria-label="Main menu"], [aria-label="Main menu"] *, .j6, .aj3')) out.hamburger.push(info(el));
          for (const el of document.querySelectorAll('div[role="search"], form[role="search"], [aria-label="Search the web"], input[name="query"]')) out.search.push(info(el));
          out.panels = out.panels.slice(0, 45);
          window.__gcalDom = JSON.stringify(out);
          return window.__gcalDom;
        })();
        """#
        page.evaluate(json: js) { [weak self] value, error in
            if let error { print("DOM start error: \(error)") }
            guard let self else { return }
            guard let value else { print("DOM fail: no result"); exit(1) }
            // evaluate(json:) already parses a JSON string into a dictionary.
            self.printDump(value as? [String: Any] ?? [:])
        }
    }

    private func printDump(_ obj: [String: Any]) {
        guard !obj.isEmpty else { print("DOM fail: empty result"); exit(1) }
        func rows(_ key: String, _ label: String) {
            print("DOM \(label):")
            for rowValue in (obj[key] as? [Any] ?? []) {
                guard let row = rowValue as? [String: Any] else { continue }
                let rect = (row["rect"] as? [Int]) ?? []
                let bits = rect.map(String.init).joined(separator: ",")
                print("   \(row["tag"] ?? "?")#\(row["id"] ?? "") .\(row["cls"] ?? "") role=\(row["role"] ?? "") aria=\(row["aria"] ?? "") [\(bits)] parent=\(row["parent"] ?? "")")
            }
        }
        print("DOM viewport: \((obj["viewport"] as? [Int] ?? []).map(String.init).joined(separator: "x"))")
        rows("panels", "wide containers")
        rows("header", "header")
        rows("hamburger", "hamburger")
        rows("search", "search")
        exit(0)
    }
}

/// Runs GmailChrome.auditScript and turns the measurements into a verdict: the
/// rails hidden, the header reduced to menu + wordmark + search, and the account
/// button and menu button still reachable.
final class DomCheck {
    weak var page: WebPage?
    private var attempt = 0

    init(page: WebPage?) { self.page = page }

    func start() {
        guard let page else { print("CHECK fail: no mail page"); exit(1) }
        guard page.didLoad, page.currentURLString.contains("mail.google.com") else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.start() }
            return
        }
        page.evaluate(json: GmailChrome.auditScript) { [weak self] value, error in
            if let error { print("CHECK eval error: \(error)") }
            if let report = value as? [String: Any], !report.isEmpty { self?.finish(report); return }
            guard let self else { return }
            self.attempt += 1
            if self.attempt < 15 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.start() }
            } else {
                print("CHECK fail: no report")
                exit(1)
            }
        }
    }

    private func finish(_ report: [String: Any]) {
        var failures: [String] = []
        func group(_ name: String) -> (matched: Int, visible: Int, widest: Int) {
            guard let raw = report[name] as? [String: Any] else { return (-1, -1, -1) }
            return ((raw["matched"] as? Int) ?? -1, (raw["visible"] as? Int) ?? -1,
                    (raw["widest"] as? Int) ?? -1)
        }
        for name in ["leftRail", "rightRail", "headerExtras"] {
            let g = group(name)
            print("CHECK \(name): matched=\(g.matched) visible=\(g.visible) widest=\(g.widest)")
            if g.matched == 0 { failures.append("\(name): nothing matched (Gmail changed its markup)") }
            if g.visible > 0 { failures.append("\(name): \(g.visible) still visible") }
        }
        for name in ["hamburger", "wordmark", "search", "account"] {
            let g = group(name)
            print("CHECK \(name): matched=\(g.matched) visible=\(g.visible) widest=\(g.widest)")
            if g.visible == 0 { failures.append("\(name): should still be visible") }
        }
        print("CHECK stylesheet: \(report["sheet"] ?? "?")")
        for (name, box) in (report["boxes"] as? [String: [Int]] ?? [:]).sorted(by: { $0.key < $1.key }) {
            print("CHECK \(name): x=\(box[0]) width=\(box[1])")
        }
        print(failures.isEmpty ? "CHECK ok" : "CHECK FAIL: " + failures.joined(separator: "; "))
        exit(failures.isEmpty ? 0 : 1)
    }
}
