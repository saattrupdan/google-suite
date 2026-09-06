import Foundation

/// One destination in the sidebar. These are fixed product surfaces — Mail and
/// Calendar — not browser tabs, so the list is config, not something the UI
/// offers to grow.
struct Source: Codable, Equatable {
    var id: String
    var label: String
    var url: String
    var symbol: String

    static let defaults: [Source] = [
        // Mail first: it is the noisier of the two and the one that badges.
        Source(id: "mail", label: "Mail", url: "https://mail.google.com/mail/u/0/", symbol: "envelope"),
        Source(id: "calendar", label: "Calendar", url: "https://calendar.google.com/calendar/u/0/r/month",
               symbol: "calendar"),
    ]
}

/// Everything the app reads from `~/.config/gcal-app/config.json`.
///
/// A missing or malformed file is never fatal: `load()` falls back to defaults,
/// because this is the kind of app you want working even after a fat-fingered
/// comma.
struct Config: Codable {
    var sources: [Source] = Source.defaults
    var allowHosts: [String] = Config.defaultAllowHosts
    var openMeetInApp: Bool = false
    var notificationsShim: Bool = true
    var mailNotifications: Bool = true
    var mailPollSeconds: Double = 60
    /// How many Google accounts to poll for mail: `u/0` … `u/(n-1)`. Slots that
    /// are not signed in answer 404 and are skipped, so a higher number costs a
    /// few extra requests and nothing else.
    var mailAccountSlots = 3
    var userAgent: String? = nil

    static let defaultAllowHosts: [String] = [
        "calendar.google.com", "mail.google.com", "accounts.google.com", "www.google.com",
        "google.com", "docs.google.com", "drive.google.com", "keep.google.com",
        "contacts.google.com", "meet.google.com", "googleusercontent.com", "gstatic.com",
        "googleapis.com", "gmail.com",
    ]

    static let defaults = Config()

    enum CodingKeys: String, CodingKey {
        case sources, allowHosts, openMeetInApp, notificationsShim, mailNotifications
        case mailPollSeconds
        case mailAccountSlots, userAgent
        // Read-only aliases, so an older config still loads.
        case tabs
    }

    init() {}

    /// Lenient decoding: unknown keys are ignored and a wrong-typed value falls
    /// back to its default instead of sinking the whole file.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let legacy = try? c.decode([TabSpec].self, forKey: .tabs),
           try c.decodeIfPresent([Source].self, forKey: .sources) == nil {
            // An old "tabs" list becomes sources, keeping the requested order.
            sources = Self.sortedMailFirst(legacy.map {
                Source(id: $0.label.lowercased(), label: $0.label, url: $0.url, symbol: $0.symbol ?? "globe")
            })
        } else {
            sources = (try? c.decode([Source].self, forKey: .sources)) ?? Source.defaults
        }
        allowHosts = (try? c.decode([String].self, forKey: .allowHosts)) ?? Self.defaultAllowHosts
        openMeetInApp = (try? c.decode(Bool.self, forKey: .openMeetInApp)) ?? false
        notificationsShim = (try? c.decode(Bool.self, forKey: .notificationsShim)) ?? true
        mailNotifications = (try? c.decode(Bool.self, forKey: .mailNotifications)) ?? true
        mailPollSeconds = max(15, (try? c.decode(Double.self, forKey: .mailPollSeconds)) ?? 60)
        mailAccountSlots = max(1, (try? c.decode(Int.self, forKey: .mailAccountSlots)) ?? 3)
        userAgent = (try? c.decode(String.self, forKey: .userAgent)) ?? nil
        if sources.isEmpty { sources = Source.defaults }
    }

    /// Encoding never emits the legacy `tabs` key, only the current shape.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sources, forKey: .sources)
        try c.encode(allowHosts, forKey: .allowHosts)
        try c.encode(openMeetInApp, forKey: .openMeetInApp)
        try c.encode(notificationsShim, forKey: .notificationsShim)
        try c.encode(mailNotifications, forKey: .mailNotifications)
        try c.encode(mailPollSeconds, forKey: .mailPollSeconds)
        try c.encode(mailAccountSlots, forKey: .mailAccountSlots)
        try c.encode(mailAccountSlots, forKey: .mailAccountSlots)
        try c.encodeIfPresent(userAgent, forKey: .userAgent)
    }

    // MARK: - Location

    /// `~/.config/gcal-app/config.json`
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gcal-app/config.json")
    }

    /// Reads the config, writing a default file first if none exists.
    static func load(createIfMissing: Bool = true, at url: URL? = nil) -> Config {
        let location = url ?? fileURL
        guard let data = FileManager.default.contents(atPath: location.path) else {
            if createIfMissing { writeDefaults(to: location) }
            return Config()
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            FileHandle.standardError.write(
                "gcal: ignoring unreadable config at \(location.path): \(error)\n".data(using: .utf8)!)
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

    /// Mail leads the rail no matter what order an old config listed.
    static func sortedMailFirst(_ sources: [Source]) -> [Source] {
        let isMail = { (source: Source) in
            source.id.contains("mail") || source.url.lowercased().contains("mail.google.com")
        }
        return sources.enumerated()
            .sorted { (a, b) in
                let (am, bm) = (isMail(a.element), isMail(b.element))
                if am != bm { return am }
                return a.offset < b.offset
            }
            .map { $0.element }
    }

    // MARK: - Policy helpers

    /// True when `host` is an allow-listed domain or a subdomain of one.
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

    /// True only for a URL that actually joins something: a room code or a
    /// "new meeting" entry point.
    ///
    /// Google's pages hit `meet.google.com/` and `/_meet/*` for warm-up and
    /// error paths. Those must never be handed to a browser — that is how a
    /// stack of `_meet/whoops` tabs appears.
    func isJoinableMeet(_ url: URL) -> Bool {
        guard isMeet(url) else { return false }
        let path = url.path
        if path.hasPrefix("/new") || path.hasPrefix("/d/") { return true }
        let code = path.dropFirst()
        if code.isEmpty { return false }
        if code.hasPrefix("_meet") { return false }
        return code.range(of: #"^[a-z]{3}-[a-z]{4}-[a-z]{3}$"#, options: .regularExpression) != nil
    }

    /// A Safari-shaped user agent.
    ///
    /// `WKWebView`'s own default ends at "(KHTML, like Gecko)" with no browser
    /// and no version, and Google's sign-in treats an unversioned client as an
    /// embedded web view — the classic "This browser or app may not be secure".
    static func suggestedUserAgent() -> String {
        let version = Bundle(url: URL(fileURLWithPath: "/Applications/Safari.app"))?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "17.0"
        let major = version.split(separator: ".").first.map(String.init) ?? version
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major) Safari/605.1.15"
    }

    var effectiveUserAgent: String { userAgent ?? Config.suggestedUserAgent() }
}

/// A tab entry from an older config file, still decoded so upgrades are kind.
struct TabSpec: Codable, Equatable {
    var label: String
    var url: String
    var symbol: String?
}
