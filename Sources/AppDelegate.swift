import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation,
                         UNUserNotificationCenterDelegate {
    var window: AppWindow!
    /// Retained: the window holds the view, not the controller.
    private var root: RootController?
    private var probe: PopupProbe?
    /// Held strongly: the smoke runner re-arms itself across run-loop turns.
    private var smoke: SmokeRunner?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = AppRuntime.shared
        NSApp.mainMenu = Menus.build()
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
        self.root = root
        window = AppWindow(content: root)
        MailWatcher.shared.page = root.pagesByOrder.first { $0.source.id == "mail" }
        MailWatcher.shared.start(interval: runtime.config.mailPollSeconds,
                                 enabled: runtime.config.mailNotifications,
                                 accounts: runtime.config.mailAccountSlots)

        applyRevealRequest()

        // Smoke drives the same path as normal use, window on screen included.
        window.show()
        if arguments.contains("--popupprobe") {
            // Retained: an unretained probe would vanish before its own timers.
            let probe = PopupProbe(root: root, window: window.window)
            self.probe = probe
            probe.start()
        }
        if runtime.smokeMode {
            smoke = SmokeRunner(root: root, window: window.window)
            smoke?.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { window?.show() }
        return true
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
    private let deadline = Date().addingTimeInterval(30)

    init(root: RootController, window: NSWindow?) {
        self.root = root
        self.window = window
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
