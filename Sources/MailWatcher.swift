import AppKit
import UserNotifications

/// New-mail notifications.
///
/// A wrapper cannot receive Gmail push: that goes through a service worker and
/// WebKit gives third-party apps no push provider. So the watcher reads Gmail
/// through the page's own signed-in session instead, on a timer, and posts
/// native notifications for messages it has not seen before.
///
/// Two tiers, because the Atom feed is not guaranteed to exist:
///   1. `mail.google.com/mail/feed/atom` — per-message sender and subject.
///   2. Gmail's page title ("Inbox (3) - …") — count only, no permissions.
final class MailWatcher {
    static let shared = MailWatcher()

    weak var page: WebPage?
    var isEnabled = true
    var interval: TimeInterval = 60

    /// True while the per-message feed is answering; the in-page notification
    /// shim defers to us while it is, so nothing arrives twice.
    private(set) var feedIsWorking = false
    /// Why the feed tier is or is not usable, straight from the page.
    private(set) var lastFeedStatus = "never polled"

    private var timer: Timer?
    private var seen: Set<String> = []
    private var primed = false
    private var lastCount: Int?

    private init() {}

    var isRunning: Bool { timer != nil }

    /// Which tier is currently delivering, for `--smoke` and for any future UI.
    var modeDescription: String {
        if !isEnabled { return "off" }
        return feedIsWorking ? "per-message feed" : "unread count only (feed: \(lastFeedStatus))"
    }

    func start(interval: TimeInterval, enabled: Bool) {
        stop()
        self.interval = max(15, interval)
        self.isEnabled = enabled
        guard enabled else { return }
        let timer = Timer(timeInterval: self.interval, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = min(5, self.interval / 4)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called by the in-page shim. Returns true when the shim's notification was
    /// already covered here, so it should not also be shown.
    func absorbsInPageNotifications(host: String) -> Bool {
        host.contains("mail.google.com") && feedIsWorking && isEnabled
    }

    // MARK: - Polling

    /// Starts the feed read. The result is stashed on the page instead of
    /// returned: `evaluateJavaScript` will not await a Promise here ("result of
    /// an unsupported type"), so the script returns a plain value and the answer
    /// is read back in a second call.
    ///
    /// Raw string on purpose — these are JavaScript regular expressions, and
    /// Swift escaping turned `\\s` into an invalid escape once already.
    private static let startScript = #"""
    (() => {
      window.__gcalMailProbe = {state: 'pending'};
      fetch('/mail/feed/atom?_=' + Date.now(), {credentials: 'same-origin', cache: 'no-store'})
        .then((r) => { if (!r.ok) throw new Error('http ' + r.status); return r.text(); })
        .then((text) => {
          // Parsed with string matching, not DOMParser: Gmail serves a Trusted
          // Types CSP, so building a DOM from XML throws "requires a TrustedHTML".
          const decode = (raw) => (raw || '')
            .replace(/<[^>]*>/g, '')
            .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
            .replace(/&#(\d+);/g, (m, d) => String.fromCharCode(parseInt(d, 10)))
            .replace(/\s+/g, ' ').trim();
          const pick = (block, tag) => {
            const m = block.match(new RegExp('<' + tag + '[^>]*>([\\s\\S]*?)</' + tag + '>'));
            return m ? decode(m[1]) : '';
          };
          const full = (text.match(/<fullcount[^>]*>(\d+)<\/fullcount>/) || [])[1];
          const blocks = text.match(/<entry[\s\S]*?<\/entry>/g) || [];
          const entries = blocks.slice(0, 8).map((block) => {
            const author = (block.match(/<author[\s\S]*?<\/author>/) || [''])[0];
            return {id: pick(block, 'id'), title: pick(block, 'title'), from: pick(author, 'name')};
          });
          if (!full && !blocks.length) throw new Error('no feed elements');
          window.__gcalMailProbe = {state: 'done', payload: JSON.stringify(
            {ok: true, fullcount: full ? parseInt(full, 10) : null, entries})};
        })
        .catch((e) => { window.__gcalMailProbe = {state: 'done', payload: JSON.stringify(
            {ok: false, error: String(e)})}; });
      return 'started';
    })();
    """#

    private static let readScript = "JSON.stringify(window.__gcalMailProbe || {state: 'absent'});"

    func poll() {
        guard isEnabled, let page else { return }
        guard page.didLoad, page.currentURLString.contains("mail.google.com") else { return }
        lastFeedStatus = "polling"
        page.evaluate(json: Self.startScript) { [weak self] _, error in
            if let error { self?.lastFeedStatus = "could not start (\(error))" }
            self?.readProbe(attempt: 0)
        }
    }

    private func readProbe(attempt: Int) {
        guard let page else { return }
        page.evaluate(json: Self.readScript) { [weak self] value, error in
            guard let self else { return }
            let probe = value as? [String: Any]
            let state = probe?["state"] as? String
            if state == "done", let payload = probe?["payload"] as? String,
               let data = payload.data(using: .utf8),
               let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if (result["ok"] as? Bool) == true {
                    self.lastFeedStatus = "ok"
                    self.feedIsWorking = true
                    self.consume(result)
                } else {
                    self.feedIsWorking = false
                    self.lastFeedStatus = (result["error"] as? String) ?? "unavailable"
                    self.fallbackCount()
                }
                return
            }
            if state == "pending", attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.readProbe(attempt: attempt + 1) }
                return
            }
            self.feedIsWorking = false
            self.lastFeedStatus = error ?? "probe never resolved"
            self.fallbackCount()
        }
    }

    private func consume(_ result: [String: Any]) {
        if let count = result["fullcount"] as? Int {
            RootController.current?.setBadge(count, for: "mail")
            lastCount = count
        }
        let entries = (result["entries"] as? [[String: Any]]) ?? []
        let ids = entries.compactMap { $0["id"] as? String }

        guard primed else {
            seen = Set(ids)
            primed = true
            return
        }

        let fresh = entries.filter { ($0["id"] as? String).map { !seen.contains($0) } ?? false }
        seen.formUnion(ids)
        guard !fresh.isEmpty else { return }

        if fresh.count == 1, let entry = fresh.first {
            let from = (entry["from"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "New mail"
            Notifier.deliver(title: from, body: (entry["title"] as? String) ?? "", target: "mail")
            return
        }
        Notifier.deliver(title: "\(fresh.count) new messages",
                         body: fresh.compactMap { $0["from"] as? String }.prefix(3).joined(separator: ", "),
                         target: "mail")
    }

    /// Count-only tier: Gmail's own title, e.g. "Inbox (4) - name - Mail".
    private func fallbackCount() {
        guard let count = page?.unreadCountFromTitle else { return }
        RootController.current?.setBadge(count, for: "mail")
        defer { lastCount = count }
        guard primed else { primed = true; return }
        if let previous = lastCount, count > previous {
            Notifier.deliver(title: "\(count - previous) new messages",
                             body: "\(count) unread in total", target: "mail")
        }
    }
}
