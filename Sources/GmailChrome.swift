import WebKit

/// Trimming Gmail's own interface, for a window that should show mail and
/// nothing else.
///
/// This is CSS injected into Google's page, so it is written against what the
/// page actually renders — the selectors below come from measuring a live
/// mailbox (`--domdump`), not from remembered class names. Gmail rebuilds those
/// names between releases, so every rule is a best-effort match with several
/// alternatives, the whole thing is one config switch
/// (`trimGmailChrome`), and `--domcheck` reports whether the rules landed.
enum GmailChrome {
    /// What disappears, and what is deliberately left alone.
    static let stylesheet = """
    /* The left rail of labels. role=navigation is the stable part; the class
       names around it are not. */
    div.aeN[role="navigation"],
    div.nH.aqk > div.aeN,
    div[role="navigation"].JZ,
    div[role="navigation"].aii { display: none !important; }

    /* The right rail with Meet / Chat / Keep / Calendar, and its flyout. */
    div.jAmAWb,
    div.dw > div.jAmAWb,
    div.n0.iP9ASd,
    div.n0.Ik .Tq { display: none !important; }

    /* The header keeps: the menu button, the wordmark, search. Everything else
       on the right is Google's own chrome — status chip, Support, the settings
       gear, Gemini, the apps launcher. The account picture stays, because that
       is where "Add another account" lives; hide
       `#gb a[aria-label^="Google Account"]` if you would rather it went. */
    #gb .lJradf,
    #gb a.FH,
    #gb [aria-label="Settings"],
    #gb [aria-label="Support"],
    #gb [aria-label="Google apps"],
    #gb #gbwa,
    #gb .gb_L,
    #gb [aria-label^="Ask Gemini"] { display: none !important; }
    """

    /// Injected before the page runs, so the rails are hidden from the first
    /// paint instead of flashing and collapsing.
    static func makeUserScript(enabled: Bool) -> WKUserScript {
        guard enabled else { return blankScript }
        let source = """
        (() => {
          const css = \(jsString(stylesheet));
          const add = () => {
            if (!document.head || document.getElementById('gcal-chrome')) return;
            const style = document.createElement('style');
            style.id = 'gcal-chrome';
            style.textContent = css;
            document.head.appendChild(style);
          };
          add();
          // Gmail rewrites its toolbar on navigation, which can drop the node.
          new MutationObserver(add).observe(document.documentElement, {childList: true, subtree: true});
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    private static let blankScript = WKUserScript(source: "", injectionTime: .atDocumentStart, forMainFrameOnly: true)

    /// Measures the things the stylesheet targets, so "it applied" is a fact
    /// rather than a hope: each selector reports how many nodes it matched and
    /// how much of them is still visible.
    static let auditScript = """
    (() => {
      const groups = {
        leftRail: ['div.aeN[role="navigation"]', 'div.nH.aqk > div.aeN', 'div[role="navigation"].JZ'],
        rightRail: ['div.jAmAWb', 'div.dw > div.jAmAWb'],
        headerExtras: ['#gb .lJradf', '#gb a.FH', '#gb [aria-label="Settings"]',
                       '#gb [aria-label="Support"]', '#gb [aria-label="Google apps"]',
                       '#gb [aria-label^="Ask Gemini"]'],
        account: ['#gb a[aria-label^="Google Account"]'],
        hamburger: ['#gb [aria-label="Main menu"]'],
        wordmark: ['#gb a[aria-label="Gmail"]'],
        search: ['#gb form[role="search"]'],
      };
      const report = {};
      for (const [name, selectors] of Object.entries(groups)) {
        let matched = 0, visible = 0, widest = 0;
        for (const sel of selectors) {
          for (const el of document.querySelectorAll(sel)) {
            matched++;
            const r = el.getBoundingClientRect();
            if (r.width > 1 && r.height > 1 && getComputedStyle(el).display !== 'none') visible++;
            widest = Math.max(widest, Math.round(r.width));
          }
        }
        report[name] = {matched, visible, widest};
      }
      // Does the message area actually take the space the rails left, or is
      // there a dead strip where they used to be?
      const boxes = {};
      for (const [name, sel] of Object.entries({
          navContainer: 'div.nH.aqk', navColumn: 'div.nH.ao9s',
          listArea: 'div.aO7', listPane: 'div.PQ', threadTable: 'table.L9', bodyPane: 'div.Bk',
      })) {
        const el = document.querySelector(sel);
        if (!el) continue;
        const r = el.getBoundingClientRect();
        boxes[name] = [Math.round(r.x), Math.round(r.width)];
      }
      report.boxes = boxes;
      const style = document.getElementById('gcal-chrome');
      report.sheet = style ? 'installed' : 'missing';
      const list = document.querySelector('div.aO7') || document.querySelector('table.L9');
      report.messageList = list ? (() => { const r = list.getBoundingClientRect();
        return [Math.round(r.x), Math.round(r.width)]; })() : null;
      return JSON.stringify(report);
    })();
    """

    /// A JS string literal for arbitrary text.
    private static func jsString(_ text: String) -> String {
        var out = "\""
        for ch in text.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": break
            case "\t": out += "\\t"
            default: out.append(Character(ch))
            }
        }
        return out + "\""
    }
}
