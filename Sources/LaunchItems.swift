import AppKit
import ServiceManagement

/// Login-item toggle. `SMAppService` is the only sanctioned way on macOS 13+;
/// on this build (macOS 26) there is no older path to fall back to.
enum LaunchItems {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns an error description when the change did not take.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard #available(macOS 13.0, *) else { return "Launch at login needs macOS 13 or newer." }
        guard Bundle.main.bundleIdentifier != nil else {
            return "Not running from an app bundle; install with ./install.sh first."
        }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
