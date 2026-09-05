import Foundation

/// Handing a "show me Mail / Calendar" request from the CLI to a running instance.
///
/// `open --args` only reaches a cold start, so the request travels through a small
/// rendezvous file instead: the CLI writes it, the app reads and deletes it when it
/// next becomes active. That makes `gcal --mail` work whether or not the app was
/// already open, which `--args` alone could never do.
enum Reveal {
    private static var file: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".config/gcal-app/reveal", isDirectory: false)
        ?? URL(fileURLWithPath: "/tmp/gcal-reveal")

    /// Test seam: keep the CLI handshake out of the real config directory.
    static func use(path: URL?) {
        file = path ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("gcal-reveal-\(UUID().uuidString)")
    }

    static func request(_ id: String) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? id.data(using: .utf8)?.write(to: file, options: .atomic)
    }

    /// The pending request, if any. Consumed: one request, one jump.
    static func take() -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: file)
        let id = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }
}
