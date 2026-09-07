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
///   1. Gmail's Atom feed per signed-in account — sender and subject.
///   2. Gmail's page title ("Inbox (3) - …") — count only, no permissions.
///
/// Every signed-in Google account (`u/0`, `u/1`, …) is polled, so the badge and
/// the notifications behave like a merged inbox: one number, one stream, however
/// many accounts the page is logged into. Gmail itself cannot present a single
/// merged inbox across two Google accounts; this is the closest a wrapper can get
/// without asking the user to set up forwarding.
final class MailWatcher {
    static let shared = MailWatcher()

    weak var page: WebPage?
    var isEnabled = true
    var interval: TimeInterval = 60

    /// True while the per-message feed is answering; the in-page notification
    /// shim defers to us while it is, so nothing arrives twice.
    private(set) var feedIsWorking = false
    /// Why the feed tier is or is not usable, straight from the page, per account.
    private(set) var lastFeedStatus = "never polled"
    /// Set when the injected script itself was refused — the reason a probe would
    /// never resolve, and easy to mistake for a network failure.
    private var lastStartError: String?
    /// How many Google accounts to try (`u/0` … `u/\(accounts - 1)`). Slots that
    /// are not signed in answer 404 and are ignored.
    var accounts = 3

    /// Which Google account sits in which `u/N` slot, learned from the feeds.
    /// The account picture is broken inside an embedded web view, so this is
    /// how the Account menu can say who is signed in.
    struct Mailbox: Equatable {
        let email: String
        let slot: Int
    }

    private(set) var mailboxes: [Mailbox] = []

    private var timer: Timer?
    private var seen: Set<String> = []
    private var primed = false
    private var lastCount: Int?

    private init() {}

    var isRunning: Bool { timer != nil }

    /// Which tier is currently delivering, for `--smoke` and for any future UI.
    var modeDescription: String {
        if !isEnabled { return "off" }
        return feedIsWorking ? "per-message feed (\(lastFeedStatus))"
                             : "unread count only (feed: \(lastFeedStatus))"
    }

    func start(interval: TimeInterval, enabled: Bool, accounts: Int = 3) {
        stop()
        self.interval = max(15, interval)
        self.isEnabled = enabled
        self.accounts = max(1, accounts)
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

    /// Starts the feed reads. Results are stashed on the page instead of
    /// returned: `evaluateJavaScript` will not await a Promise here ("result of
    /// an unsupported type"), so the script returns a plain value and the answer
    /// is read back in a second call.
    ///
    /// Raw string on purpose — these are JavaScript regular expressions, and
    /// Swift escaping turned `\\s` into an invalid escape once already.
    private static func startScript(slots: [Int]) -> String {
        let list = slots.map(String.init).joined(separator: ", ")
        return #"""
    (() => {
      try {
      // Interpolation inside a raw string needs the backslash: \#(list).
      const slots = [\#(list)];
      window.__gcalMailProbe = {state: 'pending'};
      // Parsed with string matching, not DOMParser: Gmail serves a Trusted Types
      // CSP, so building a DOM from XML throws "requires a TrustedHTML".
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
      const parse = (text) => {
        const full = (text.match(/<fullcount[^>]*>(\d+)<\/fullcount>/) || [])[1];
        const blocks = text.match(/<entry[\s\S]*?<\/entry>/g) || [];
        const entries = blocks.slice(0, 8).map((block) => {
          const author = (block.match(/<author[\s\S]*?<\/author>/) || [''])[0];
          return {id: pick(block, 'id'), title: pick(block, 'title'), from: pick(author, 'name')};
        });
        if (!full && !blocks.length) throw new Error('no feed elements');
        // The feed has no <email>; the mailbox address is in its title
        // ("Gmail - Inbox for you@example.com"). It is also the only thing that
        // distinguishes one signed-in account from another: an unused u/N slot
        // answers 200 with the *same* mailbox, so counting every slot would
        // multiply the badge by the number of slots polled.
        const feedTitle = pick(text.slice(0, 800), 'title');
        const owner = (feedTitle.match(/for\s+(\S+@\S+)/) || [])[1] || '';
        return {fullcount: full ? parseInt(full, 10) : 0, email: owner, title: feedTitle, entries};
      };
      // Two URL shapes exist across Gmail generations; try the documented
      // per-account one first, then the legacy path form. An async loop rather
      // than a rejected-promise chain: a seed Promise.reject() nobody has
      // attached a handler to yet surfaces to WebKit as a JS exception, and the
      // probe then never resolves.
      const paths = (u) => u === 0 ? ['/mail/feed/u/0/atom', '/mail/u/0/feed/atom', '/mail/feed/atom']
                                   : ['/mail/feed/u/' + u + '/atom', '/mail/u/' + u + '/feed/atom'];
      const readSlot = async (u) => {
        let why = 'unreachable';
        for (const path of paths(u)) {
          try {
            const r = await fetch(path + '?_=' + Date.now(),
                                  {credentials: 'same-origin', cache: 'no-store'});
            if (!r.ok) { why = 'http ' + r.status; continue; }
            const parsed = parse(await r.text());
            return {u, ok: true, ...parsed};
          } catch (e) { why = String(e); }
        }
        return {u, ok: false, error: why};
      };
      Promise.all(slots.map(readSlot))
        .then((results) => {
          window.__gcalMailProbe = {state: 'done', payload: JSON.stringify(
            {ok: results.some((r) => r.ok), accounts: results})};
        })
        .catch((e) => { window.__gcalMailProbe = {state: 'done', payload: JSON.stringify(
            {ok: false, error: String(e)})}; });
      return 'started';
      } catch (e) {
        // Without this, a synchronous failure inside the script reaches
        // Swift only as "A JavaScript exception occurred" — no message, no
        // line, and the probe looks like a timeout.
        window.__gcalMailProbe = {state: 'done', payload: JSON.stringify(
            {ok: false, error: 'script threw: ' + (e && e.message || String(e))})};
        return 'threw';
      }
    })();
    """#
    }

    private static let readScript = "JSON.stringify(window.__gcalMailProbe || {state: 'absent'});"

    func poll() {
        guard isEnabled, let page else { return }
        guard page.didLoad, page.currentURLString.contains("mail.google.com") else { return }
        lastFeedStatus = "polling"
        lastStartError = nil
        page.evaluate(json: Self.startScript(slots: Array(0..<accounts))) { [weak self] _, error in
            if let error { self?.lastStartError = error }
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
            // A failed start (a syntax error in the injected script, say) looks
            // exactly like a probe that never resolved, so keep both reasons.
            var reason = error ?? "probe never resolved"
            if let startError = self.lastStartError { reason += " (script failed: \(startError))" }
            self.lastFeedStatus = reason
            self.fallbackCount()
        }
    }

    /// Merges every signed-in account into one badge and one notification stream.
    private func consume(_ result: [String: Any]) {
        let merged = Self.merge(result, excluding: seen)
        seen.formUnion(merged.allIDs)
        lastFeedStatus = merged.status
        mailboxes = merged.slots

        if merged.countsAsUnread {
            RootController.current?.setBadge(merged.total, for: "mail")
            lastCount = merged.total
        }
        // The first answer only teaches us what already exists; it must never
        // notify about mail that was there before the app started.
        guard primed else { primed = true; return }
        let fresh = merged.fresh
        guard !fresh.isEmpty else { return }

        // With more than one mailbox, say which one the mail landed in.
        let labelMailbox = merged.mailboxes.count > 1
        if fresh.count == 1, let only = fresh.first {
            let sender = only.from.isEmpty ? "New mail" : only.from
            var body = only.subject
            if labelMailbox, let mailbox = only.mailbox { body += " · " + mailbox }
            Notifier.deliver(title: sender, body: body, target: "mail")
            return
        }
        var body = fresh.compactMap { $0.from.isEmpty ? nil : $0.from }.prefix(3).joined(separator: ", ")
        if labelMailbox { body += " · " + merged.mailboxes.sorted().joined(separator: ", ") }
        Notifier.deliver(title: "\(fresh.count) new messages", body: body, target: "mail")
    }

    /// Pure half of `consume`, so the account dedup can be checked offline.
    struct Merged {
        var total = 0
        var status = ""
        var fresh: [MailMessage] = []
        var mailboxes: [String] = []
        var allIDs: [String] = []
        /// False when no slot reported a count, i.e. leave the badge alone.
        var countsAsUnread = false
        /// Slot → mailbox, for the Account menu.
        var slots: [Mailbox] = []
    }

    static func merge(_ result: [String: Any], excluding seen: Set<String>) -> Merged {
        var out = Merged()
        var counted: Set<String> = []
        var status: [String] = []

        for slot in (result["accounts"] as? [[String: Any]]) ?? [] {
            let u = (slot["u"] as? Int) ?? 0
            guard (slot["ok"] as? Bool) == true else {
                status.append("u\(u):\((slot["error"] as? String) ?? "n/a")")
                continue
            }
            let mailbox = (slot["email"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            // Gmail answers an unused u/N slot with the signed-in mailbox, so
            // identity — not the slot number — decides whether it is a new inbox.
            let key = mailbox ?? "u\(u)"
            if !counted.insert(key).inserted {
                status.append("u\(u)=\(mailbox ?? "u\(u)") (again)")
                continue
            }
            status.append("u\(u):\(mailbox ?? "?")")
            out.total += (slot["fullcount"] as? Int) ?? 0
            out.countsAsUnread = true
            if let mailbox {
                out.mailboxes.append(mailbox)
                out.slots.append(Mailbox(email: mailbox, slot: u))
            }
            let entries = (slot["entries"] as? [[String: Any]]) ?? []
            for entry in entries {
                guard let id = entry["id"] as? String else { continue }
                out.allIDs.append(id)
                if seen.contains(id) { continue }
                out.fresh.append(MailMessage(id: id,
                                             from: (entry["from"] as? String) ?? "",
                                             subject: (entry["title"] as? String) ?? "",
                                             mailbox: mailbox))
            }
        }
        out.status = status.joined(separator: ", ")
        return out
    }

    struct MailMessage {
        let id: String
        let from: String
        let subject: String
        let mailbox: String?
    }

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
