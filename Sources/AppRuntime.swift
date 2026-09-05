import AppKit

/// Shared, mutable app state that is not owned by any one window.
final class AppRuntime {
    static let shared = AppRuntime()

    /// All tabs share `WKWebsiteDataStore.default()`, which is what makes
    /// Google's `?authuser=N` multi-login work across tabs.
    var config = Config()

    /// Parsed once from the command line in `main.swift`.
    var startURL: String?
    var smokeMode = false

    private init() {}
}
