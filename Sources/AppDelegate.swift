import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var window: AppWindow!
    /// Held strongly: the smoke runner re-arms itself across run-loop turns.
    private var smoke: SmokeRunner?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = AppRuntime.shared
        NSApp.mainMenu = Menus.build()

        var specs = runtime.config.tabs
        if let url = runtime.startURL, var first = specs.first {
            first.url = url
            specs[0] = first
        } else if let url = runtime.startURL {
            specs = [TabSpec(label: "Google", url: url, symbol: nil)]
        }

        window = AppWindow(tabs: TabsController(specs: specs))
        // Smoke drives the same path as normal use, including putting the
        // window on screen: the toolbar tab bar only resolves once the window
        // is real, so testing without it would test a different layout.
        window.show()
        if runtime.smokeMode {
            smoke = SmokeRunner(tabs: window.tabController, window: window.window)
            smoke?.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { window?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// opts into secure state restoration (silences the macOS 14+ warning).
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

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

    @objc func openHelp(_ sender: NSMenuItem?) {
        guard let string = sender?.representedObject as? String, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleLaunchAtLogin(_:)) {
            menuItem.state = LaunchItems.isEnabled ? .on : .off
            return LaunchItems.isSupported
        }
        return true
    }
}

/// `--smoke`: prove the real UI pipeline works end to end — window, toolbar tab
/// bar, two web views, navigation policy, load events — without a browser
/// extension, a testing framework, or any TCC permission.
final class SmokeRunner {
    private let tabs: TabsController
    private let window: NSWindow?
    private let deadline = Date().addingTimeInterval(25)

    init(tabs: TabsController, window: NSWindow?) {
        self.tabs = tabs
        self.window = window
    }

    func start() { tick() }

    private func tick() {
        if tabs.allTabsSettled || Date() > deadline {
            finish()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.tick() }
    }

    private func finish() {
        let report = tabs.smokeReport()
        // What Google sees us as. Worth printing because Google refuses
        // sign-in on user agents it classifies as embedded web views.
        var identity = "unknown"
        let gate = RunLoopGate()
        tabs.selectedTab?.webView.evaluateJavaScript("navigator.userAgent") { value, _ in
            identity = (value as? String) ?? "unknown"
            gate.signal()
        }
        gate.wait(timeout: 3)
        print("  identity \(identity)")
        let items = (window?.toolbar?.items ?? []).map { $0.itemIdentifier.rawValue }.joined(separator: ",")
        let frame = window?.frame ?? .zero
        print("SMOKE tabs=\(report.count) window=\(window != nil) frame=\(Int(frame.width))x\(Int(frame.height)) toolbar=[\(items)] selected=\(tabs.selectedIndex)")
        print("  layout \(tabs.layoutSummary())")
        var allOK = true
        for entry in report {
            allOK = allOK && entry.ok
            let mark = entry.ok ? "ok  " : "fail"
            print("  \(mark) \(entry.label.padding(toLength: 12, withPad: " ", startingAt: 0)) title=\(entry.detail.prefix(60)) url=\(entry.url.prefix(90))")
        }
        print(allOK ? "SMOKE ok" : "SMOKE fail")
        fflush(stdout)
        exit(allOK ? 0 : 1)
    }
}
