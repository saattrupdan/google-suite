import WebKit

/// Trimming Google's own interface, for a window that should show mail and
/// calendars and nothing else.
///
/// Two things make this harder than writing CSS, and both are handled here:
///
/// * **Class names.** Gmail and Calendar ship obfuscated, release-specific
///   classes, so every rule is written against `role` and `aria-label` where
///   Google exposes them, with class selectors only as extra catches. The
///   selectors below were measured from live pages (`--domdump`).
/// * **Content Security Policy.** Google's pages forbid inline `<style>`
///   elements, so a stylesheet injects fine into Gmail and is dropped without a
///   word on Calendar. The reliable route is the CSSOM: setting
///   `element.style.display` from script is not an "inline style" for CSP and
///   works everywhere. Both are installed — the stylesheet where it is allowed,
///   the CSSOM pass always.
enum GmailChrome {
    // MARK: - Selectors

    /// Both surfaces.
    static let sharedSelectors: [String] = [
        // The right-hand rail with Keep / Tasks / Contacts / Clock. In both
        // products it is the same thing: role=complementary labelled
        // "Side panel", its icons being role=tab children. Targeting only an
        // inner wrapper leaves the 56 pt strip standing.
        "div[role=\"complementary\"][aria-label=\"Side panel\"]",
        "div[role=\"tab\"][aria-label=\"Keep\"]",
        "div[role=\"tab\"][aria-label=\"Tasks\"]",
        "div[role=\"tab\"][aria-label=\"Contacts\"]",
        "div[role=\"tab\"][aria-label=\"Clock\"]",
        "[aria-label=\"Hide side panel\"]",
        "[aria-label=\"Expand side panel\"]",
        "#apps-dock", ".NaccSe", ".lRwCV",

        // The account picture. Inside an embedded web view it only reports
        // "Something went wrong.", so it is gone and the Account menu does its
        // job — see Account ▸ Add Another Account… and Switch Account.
        "#gb a[aria-label^=\"Google Account\"]",
        "#gb .gb_C",
    ]

    /// Gmail. The header keeps the menu button, the wordmark and search.
    static let mailSelectors: [String] = [
        "div.aeN[role=\"navigation\"]",
        "div.nH.aqk > div.aeN",
        "div[role=\"navigation\"].JZ",
        "div.jAmAWb",
        "div.dw > div.jAmAWb",
        "div.n0.iP9ASd",
        "#gb .lJradf",
        "#gb a.FH",
        "#gb [aria-label=\"Settings\"]",
        "#gb [aria-label=\"Support\"]",
        "#gb [aria-label=\"Google apps\"]",
        "#gb #gbwa",
        "#gb .gb_L",
        "[aria-label=\"Ask Gemini\"]",
        "[aria-label^=\"Try Gemini\"]",
        "[aria-label=\"Gemini\"]",
        "[aria-label=\"Gemini search settings\"]",
        ".MxSLJe",
        ".Pv5YRd",
    ]

    /// Calendar. The drawer button stays — that is how you reach the list of
    /// calendars — and so does the week grid.
    static let calendarSelectors: [String] = [
        "#gb [aria-label=\"Search\"]",
        "[aria-label=\"Search calendars\"]",
        "[aria-label=\"Support\"]",
        "[aria-label=\"Settings menu\"]",
        "[aria-label=\"Switch to Calendar\"]",
        "[aria-label=\"Switch to Tasks\"]",
        "[aria-label=\"Google apps\"]",
        "[aria-label=\"Create\"]",
    ]

    static func selectors(isMail: Bool) -> [String] { sharedSelectors + (isMail ? mailSelectors : calendarSelectors) }

    /// A stylesheet for the pages whose CSP permits it.
    static func stylesheet(isMail: Bool) -> String {
        selectors(isMail: isMail).map { "\($0) { display: none !important; }" }.joined(separator: "\n")
    }

    // MARK: - Injection

    static func makeUserScript(enabled: Bool, isMail: Bool) -> WKUserScript {
        guard enabled else { return blankScript }
        return WKUserScript(source: scriptSource(isMail: isMail), injectionTime: .atDocumentEnd,
                            forMainFrameOnly: true)
    }

    /// The JavaScript as it goes into the page — exposed so it can be printed
    /// (`--trimscript`) and syntax-checked outside the app.
    static func scriptSource(isMail: Bool) -> String {
        let list = selectors(isMail: isMail).map(jsString).joined(separator: ", ")
        let css = jsString(stylesheet(isMail: isMail))
        let source = """
        (() => {
          const selectors = [\(list)];
          const styleCSS = \(css);

          // Fast path, where inline styles are permitted. Written through a text
          // node because assigning to `textContent` is a Trusted Types sink on
          // Google's pages and throws.
          const addSheet = () => {
            if (!document.head || document.getElementById('suite-chrome')) return;
            const style = document.createElement('style');
            style.id = 'suite-chrome';
            style.appendChild(document.createTextNode(styleCSS));
            document.head.appendChild(style);
          };

          // The path that actually works on Google's strict CSP: assigning
          // through the CSSOM is not an inline style, so it is not blocked.
          const hide = (el) => {
            if (el.dataset.suiteHidden === '1') return;
            try {
              el.dataset.suiteHidden = '1';
              el.style.setProperty('display', 'none', 'important');
              window.__gcalChromeHidden = (window.__gcalChromeHidden || 0) + 1;
            } catch (e) { window.__gcalChromeError = String(e); }
          };

          // A rail is often a column holding one panel. Hiding the panel leaves
          // the column standing — 56 pt of empty strip where the rail was — so
          // an ancestor that has nothing visible left goes too. Only narrow
          // ancestors, so the actual content area is never in play.
          const collapse = (el) => {
            let parent = el.parentElement;
            for (let depth = 0; parent && parent.tagName !== 'BODY' && depth < 4; depth++) {
              const box = parent.getBoundingClientRect();
              if (box.width > 160) break;
              let anyVisible = false;
              for (const child of parent.children) {
                if (child.dataset.suiteHidden === '1') continue;
                const b = child.getBoundingClientRect();
                if (b.width > 1 && b.height > 1) { anyVisible = true; break; }
              }
              if (anyVisible) break;
              hide(parent);
              parent = parent.parentElement;
            }
          };

          const applyDirect = () => {
            for (const sel of selectors) {
              let nodes;
              try { nodes = document.querySelectorAll(sel); } catch (e) { continue; }
              for (const el of nodes) {
                if (el.dataset.suiteHidden === '1') continue;
                hide(el);
                collapse(el);
              }
            }
          };

          /* The header's right-hand cluster. Google parks its own controls
             there — support, settings, the apps launcher, the account picture —
             and several of them carry no accessible name at all: the account
             button is an <img> of a logo gif, and Gmail's support button is an
             <img> of a question mark. No selector can name those reliably, so
             the rule is positional: inside the top bar, within HEADER_ZONE of
             its right edge, anything that is not part of the search box is
             chrome. The menu/drawer button, the wordmark and search sit left of
             that line and stay. */
          const HEADER_ZONE = 360;
          const hideHeaderRight = () => {
            const bar = document.getElementById('gb') || document.querySelector('header[role="banner"]');
            if (!bar) return;
            const keep = new Set();
            for (const form of bar.querySelectorAll('form[role="search"], [role="search"]')) {
              keep.add(form);
              for (const el of form.querySelectorAll('*')) keep.add(el);
            }
            const limit = bar.getBoundingClientRect().right - HEADER_ZONE;
            for (const el of bar.querySelectorAll('a, button, [role="button"], img')) {
              if (el.dataset.suiteHidden === '1' || keep.has(el)) continue;
              const r = el.getBoundingClientRect();
              if (r.width < 8 || r.height < 8 || r.top > 56 || r.x < limit) continue;
              const target = el.closest('a, button, [role="button"]') || el;
              hide(target);
              collapse(target);
            }
          };

          let queued = false;
          const run = () => {
            window.__gcalChromeRuns++;
            // The CSSOM first: it is the part that works under a strict CSP.
            try { applyDirect(); hideHeaderRight(); } catch (e) { window.__gcalChromeError = String(e); }
            try { addSheet(); } catch (e) { window.__gcalChromeSheetError = String(e); }
          };
          // A web view that is not on screen yet freezes requestAnimationFrame,
          // which is exactly the state a second surface is in while it loads, so
          // never make the trimming depend on a frame arriving.
          const schedule = () => {
            if (queued) return;
            queued = true;
            const go = () => { queued = false; run(); };
            if (document.visibilityState === 'visible') requestAnimationFrame(go);
            else setTimeout(go, 250);
          };

          window.__gcalChromeLoaded = true;
          window.__gcalChromeHidden = 0;
          window.__gcalChromeRuns = 0;
          run();
          schedule();
          for (const delay of [400, 1200, 3000, 8000]) setTimeout(run, delay);
          // Both apps rebuild their toolbar and rails on every navigation, so
          // this has to keep running, not just run once.
          new MutationObserver(schedule).observe(document.documentElement,
              {childList: true, subtree: true});
          return 'ok';
        })();
        """
        return source
    }

    private static let blankScript = WKUserScript(source: "", injectionTime: .atDocumentEnd, forMainFrameOnly: true)

    // MARK: - Audit

    /// Measures the result, so "it applied" is a fact. Groups marked `mustHide`
    /// fail if anything of them is still visible; the rest fail if they
    /// disappear. `rightStrip` catches the case where the rail is hidden but its
    /// column still holds 56 pt of empty space.
    static let auditScript = """
    (() => {
      const groups = {
        leftRail: {mustHide: true, optional: true,
                   selectors: ['div.aeN[role="navigation"]', 'div.nH.aqk > div.aeN',
                               'div[role="navigation"].JZ']},
        rightRail: {mustHide: true, optional: false,
                    selectors: ['div[role="complementary"][aria-label="Side panel"]',
                                'div.jAmAWb', 'div.dw > div.jAmAWb']},
        railTabs: {mustHide: true, optional: true,
                   selectors: ['div[role="tab"][aria-label="Keep"]',
                               'div[role="tab"][aria-label="Tasks"]',
                               'div[role="tab"][aria-label="Contacts"]']},
        headerExtras: {mustHide: true, optional: false,
                       selectors: ['#gb .lJradf', '#gb a.FH', '#gb [aria-label="Settings"]',
                                   '#gb [aria-label="Support"]', '#gb [aria-label="Google apps"]',
                                   '[aria-label="Ask Gemini"]', '[aria-label="Settings menu"]',
                                   '[aria-label="Switch to Tasks"]', '[aria-label="Create"]']},
        account: {mustHide: true, optional: false, selectors: ['#gb a[aria-label^="Google Account"]']},
        gemini: {mustHide: true, optional: true,
                 selectors: ['[aria-label="Ask Gemini"]', '[aria-label="Gemini"]',
                             '[aria-label^="Try Gemini"]', '.MxSLJe', '.Pv5YRd']},
        hamburger: {mustHide: false, optional: true,
                    selectors: ['#gb [aria-label="Main menu"]', '#gb [aria-label="Main drawer"]']},
        wordmark: {mustHide: false, optional: true,
                   selectors: ['#gb a[aria-label="Gmail"]', '#gb a[aria-label="Calendar"]',
                               '#gb span[aria-label="Calendar"]']},
      };
      const report = {};
      for (const [name, group] of Object.entries(groups)) {
        let matched = 0, visible = 0, widest = 0;
        for (const sel of group.selectors) {
          let nodes = [];
          try { nodes = document.querySelectorAll(sel); } catch (e) { continue; }
          for (const el of nodes) {
            matched++;
            const r = el.getBoundingClientRect();
            if (r.width > 1 && r.height > 1 && getComputedStyle(el).display !== 'none') visible++;
            widest = Math.max(widest, Math.round(r.width));
          }
        }
        report[name] = {matched, visible, widest, mustHide: group.mustHide, optional: group.optional};
      }
      report.sheet = document.getElementById('suite-chrome') ? 'installed' : 'not installed';
      report.marked = document.querySelectorAll('[data-suite-hidden]').length;
      report.injected = window.__gcalChromeLoaded ? 'yes' : 'NO SCRIPT';
      report.runs = window.__gcalChromeRuns || 0;
      report.hidden = window.__gcalChromeHidden || 0;
      report.error = String(window.__gcalChromeError || window.__gcalChromeSheetError || 'none');
      // Something tall and narrow still touching the right edge is a rail that
      // survived, or an empty column where one used to be.
      let strip = 0;
      for (const el of document.querySelectorAll('body div, body aside')) {
        const r = el.getBoundingClientRect();
        if (r.width < 20 || r.width > 140 || r.height < innerHeight * 0.5) continue;
        if (Math.abs(r.maxX - innerWidth) > 4) continue;
        if (getComputedStyle(el).display === 'none') continue;
        strip++;
      }
      report.rightStrip = strip;
      // Anything still visible in the header's right-hand cluster is chrome that
      // survived. The account and support buttons are <img> with no accessible
      // name, so no selector can promise they are gone — measure instead.
      let headerRight = 0;
      const bar = document.getElementById('gb') || document.querySelector('header[role="banner"]');
      if (bar) {
        const keep = new Set();
        for (const form of bar.querySelectorAll('form[role="search"], [role="search"]')) {
          keep.add(form);
          for (const el of form.querySelectorAll('*')) keep.add(el);
        }
        const limit = bar.getBoundingClientRect().right - 360;
        const seen = new Set();
        for (const el of bar.querySelectorAll('a, button, [role="button"], img')) {
          if (keep.has(el) || el.dataset.suiteHidden === '1') continue;
          const target = el.closest('a, button, [role="button"]') || el;
          if (seen.has(target)) continue;
          const r = target.getBoundingClientRect();
          if (r.width < 8 || r.height < 8 || r.top > 56 || r.x < limit) continue;
          if (getComputedStyle(target).display === 'none') continue;
          seen.add(target);
          headerRight++;
        }
      }
      report.headerRight = headerRight;
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
