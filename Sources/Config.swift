import Foundation

/// One tab in the window: a label and the URL it shows.
struct TabSpec: Codable, Equatable {
    var label: String
    var url: String
    var symbol: String?

    static let defaults: [TabSpec] = [
        TabSpec(label: "Calendar", url: "https://calendar.google.com/calendar/u/0/r/month", symbol: "calendar"),
        TabSpec(label: "Mail", url: "https://mail.google.com/mail/u/0/", symbol: "envelope"),
    ]
}

/// Everything the app reads from `~/.config/gcal-app/config.json`.
///
/// A missing or malformed file is never fatal: `load()` falls back to
/// `defaults` and keeps going, because this app is the kind of thing you want
/// working even when you fat-fingered a comma at 2am.
struct Config: Codable {
    var tabs: [TabSpec] = TabSpec.defaults
    var allowHosts: [String] = Config.defaultAllowHosts
    var openMeetInApp: Bool = false
    var notificationsShim: Bool = true
    var startURL: String? = nil
    /// Sent as `WKWebView.customUserAgent`. `nil` means "use
    /// `suggestedUserAgent()`". Override this if Google complains about the
    /// browser while you sign in.
    var userAgent: String? = nil

    static let defaultAllowHosts: [String] = [
        "calendar.google.com",
        "mail.google.com",
        "accounts.google.com",
        "www.google.com",
        "google.com",
        "docs.google.com",
        "drive.google.com",
        "keep.google.com",
        "contacts.google.com",
        "meet.google.com",
        "googleusercontent.com",
        "gstatic.com",
        "googleapis.com",
        "gmail.com",
    ]

    static let defaults = Config()

    enum CodingKeys: String, CodingKey {
        case tabs
        case allowHosts
        case openMeetInApp
        case notificationsShim
        case startURL
        case userAgent
    }

    init() {}

    /// Lenient decoding: unknown keys are ignored, and a key with the wrong
    /// type falls back to its default instead of sinking the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabs = (try? c.decode([TabSpec].self, forKey: .tabs)) ?? TabSpec.defaults
        allowHosts = (try? c.decode([String].self, forKey: .allowHosts)) ?? Self.defaultAllowHosts
        openMeetInApp = (try? c.decode(Bool.self, forKey: .openMeetInApp)) ?? false
        notificationsShim = (try? c.decode(Bool.self, forKey: .notificationsShim)) ?? true
        startURL = (try? c.decode(String.self, forKey: .startURL)) ?? nil
        userAgent = (try? c.decode(String.self, forKey: .userAgent)) ?? nil
        if tabs.isEmpty { tabs = TabSpec.defaults }
    }

    // MARK: - Location

    /// `~/.config/gcal-app/config.json`
    static var fileURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("gcal-app", isDirectory: true)
        return base.appendingPathComponent("config.json")
    }

    /// Reads the config, writing a default file first if none exists.
    static func load(createIfMissing: Bool = true, at url: URL? = nil) -> Config {
        let where_ = url ?? fileURL
        let fm = FileManager.default
        guard let data = fm.contents(atPath: where_.path) else {
            if createIfMissing { writeDefaults(to: where_) }
            return Config()
        }
        do {
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            return decoded
        } catch {
            FileHandle.standardError.write(
                "gcal: ignoring unreadable config at \(where_.path): \(error)\n".data(using: .utf8)!)
            return Config()
        }
    }

    static func writeDefaults(to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(Config()) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// A Safari-shaped user agent.
    ///
    /// `WKWebView`'s own default ends after "(KHTML, like Gecko)" with no
    /// browser and no version, and Google's sign-in treats an unversioned
    /// client as an embedded web view — the classic "This browser or app may
    /// not be secure" dead end. Advertising as Safari avoids that; the version
    /// comes from the installed Safari so the string stays honest-ish.
    static func suggestedUserAgent() -> String {
        let version = Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app"))?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "17.0"
        let major = version.split(separator: ".").first.map(String.init) ?? version
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major) Safari/605.1.15"
    }

    /// The agent actually used: explicit config wins, else the suggestion.
    var effectiveUserAgent: String { userAgent ?? Config.suggestedUserAgent() }

    // MARK: - Policy helpers

    /// True when `host` is the allow-listed domain itself or a subdomain of it.
    func isAllowed(host: String) -> Bool {
        let h = host.lowercased()
        return allowHosts.contains { entry in
            let e = entry.lowercased()
            return h == e || h.hasSuffix("." + e)
        }
    }

    func isMeet(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "meet.google.com" || host.hasSuffix(".meet.google.com")
    }
}
