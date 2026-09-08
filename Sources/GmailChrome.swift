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

    /// A JS regex body naming controls that are the product rather than its
    /// decoration. Both apps push their real navigation into the header's
    /// right-hand side when a pane gets narrow, so position alone cannot tell
    /// chrome from navigation and the positional rule needs this exception.
    static let keepPattern = "(search|previous|next|today|change view|change date|"
        + "jump to|date picker|main menu|main drawer|navigation|back|forward)"

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
          const keepPattern = \(jsString(keepPattern));

          const box = (el) => el.getBoundingClientRect();
          const labelOf = (el) => (el.getAttribute &&
              (el.getAttribute('aria-label') || el.getAttribute('title'))) || '';

          const describe = (el) => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
            ' .' + (el.className || '').toString().split(/\\s+/).slice(0, 3).join('.') +
            (labelOf(el) ? ' aria=' + labelOf(el) : '') +
            ' [' + Math.round(box(el).x) + ',' + Math.round(box(el).y) + ',' +
            Math.round(box(el).width) + 'w]';
          // Position rules can take something the user needs, and "hidden=34"
          // says nothing about which of the 34 was the search icon. --domcheck
          // --why prints this.
          const note = (why, el) => {
            const log = window.__gcalChromeLog = window.__gcalChromeLog || [];
            if (log.length < 250) log.push(why + ': ' + describe(el));
          };
          let reason = 'selector';

          /* Whether an element takes up space. Zero size means either it is gone
             or the page has not been laid out yet — and at documentEnd nothing
             has been laid out, which is why an earlier version concluded that
             every container was empty and hid the toolbars inside them. Only a
             measured "no" counts as no; an unmeasurable subtree counts as yes. */
          const occupiesSpace = (el, cap) => {
            if (box(el).width >= 1) return true;
            const kids = el.querySelectorAll('*');
            if (kids.length > cap) return true;
            for (const kid of kids) if (box(kid).width >= 1) return true;
            return false;
          };

          const hide = (el) => {
            if (el.dataset.suiteHidden === '1') return;
            try {
              el.dataset.suiteHidden = '1';
              el.style.setProperty('display', 'none', 'important');
              window.__gcalChromeHidden = (window.__gcalChromeHidden || 0) + 1;
              note(reason, el);
            } catch (e) { window.__gcalChromeError = String(e); }
          };

          /* Controls that happen to sit on the right but are the product, not
             its decoration. Both apps move their real navigation into the
             header's right-hand side when the pane gets narrow — Calendar's
             previous/next arrows and view menu, Gmail's search collapsing to a
             magnifier — so position alone cannot tell chrome from navigation.
             Labels can, and they are the durable handle anyway. */
          const isKept = (el) => {
            for (let node = el, depth = 0; node && depth < 4; node = node.parentElement, depth++) {
              if (node.matches && node.matches('form[role="search"], [role="search"]')) return true;
              const label = labelOf(node);
              if (label && new RegExp(keepPattern, 'i').test(label)) return true;
              if (node === document.body) break;
            }
            return false;
          };

          // A rail is often a column holding one panel. Hiding the panel leaves
          // the column standing, so an ancestor with nothing left in it goes too
          // — narrow ancestors only, so the content area is never in play.
          const collapse = (el) => {
            let parent = el.parentElement;
            for (let depth = 0; parent && parent.tagName !== 'BODY' && depth < 4; depth++) {
              const width = box(parent).width;
              if (width > 160 || width < 1) break;
              if (isKept(parent)) break;
              let occupied = false;
              for (const child of parent.children) {
                if (child.dataset.suiteHidden === '1') continue;
                if (occupiesSpace(child, 200)) { occupied = true; break; }
              }
              if (occupied) break;
              reason = 'collapse';
              hide(parent);
              reason = 'selector';
              parent = parent.parentElement;
            }
          };

          const applyDirect = () => {
            reason = 'selector';
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
             and several carry no accessible name at all: the account button is
             an <img> of a logo gif, Gmail's support button an <img> of a
             question mark. Nothing a selector can name reliably, so the rule is
             positional, with isKept() as the exception that keeps navigation. */
          const HEADER_ZONE = 360;
          const hideHeaderRight = () => {
            const bar = document.getElementById('gb') || document.querySelector('header[role="banner"]');
            if (!bar) return;
            const barBox = box(bar);
            if (barBox.width < 200) return;            // not laid out yet
            const limit = barBox.right - HEADER_ZONE;
            for (const el of bar.querySelectorAll('a, button, [role="button"], img')) {
              if (el.dataset.suiteHidden === '1' || isKept(el)) continue;
              const r = box(el);
              if (r.width < 8 || r.height < 8 || r.top > 56 || r.x < limit) continue;
              const target = el.closest('a, button, [role="button"]') || el;
              if (isKept(target)) continue;
              reason = 'header-zone';
              hide(target);
              collapse(target);
              reason = 'selector';
            }
          };

          const addSheet = () => {
            if (!document.head || document.getElementById('suite-chrome')) return;
            const style = document.createElement('style');
            style.id = 'suite-chrome';
            style.appendChild(document.createTextNode(styleCSS));
            document.head.appendChild(style);
          };

          const applyDirectAll = () => { applyDirect(); hideHeaderRight(); };

          let queued = false;
          const run = () => {
            window.__gcalChromeRuns++;
            try { applyDirectAll(); } catch (e) { window.__gcalChromeError = String(e); }
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
          // Layout, not just markup, decides what is chrome. Re-run once the page
          // is complete so the geometry rules see real boxes.
          if (document.readyState !== 'complete') {
            addEventListener('load', () => { run(); setTimeout(run, 600); });
          }
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
        // Navigation that both apps move into the header's right side when the
        // pane is narrow: Calendar's arrows and view menu, Gmail's collapsed
        // search. Must stay — the bug this group exists to catch is an earlier
        // version of the positional rule hiding them.
        // Navigation that both apps move into the header's right side when the
        // pane is narrow: Calendar's arrows and Today, Gmail's collapsed search.
        // Must stay — the bug this group exists to catch is the positional rule
        // eating them, which an earlier version of it did. Labels are prefixes
        // because the name carries the period ("Previous month") and the date
        // ("Today, Tuesday, 8 September").
        navControls: {mustHide: false, optional: true,
                      selectors: ['[aria-label^="Previous"]', '[aria-label^="Next"]',
                                  '[aria-label^="Today"]', '[aria-label^="Change View"]',
                                  '[aria-label^="Change view"]', '[aria-label="Search mail"]']},
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
        const keepRe = new RegExp(\(jsString(keepPattern)), 'i');
        const kept = (el) => {
          for (let node = el, depth = 0; node && depth < 4; node = node.parentElement, depth++) {
            if (keep.has(node)) return true;
            const label = (node.getAttribute &&
                           (node.getAttribute('aria-label') || node.getAttribute('title'))) || '';
            if (label && keepRe.test(label)) return true;
            if (node === document.body) break;
          }
          return false;
        };
        const limit = bar.getBoundingClientRect().right - 360;
        const seen = new Set();
        for (const el of bar.querySelectorAll('a, button, [role="button"], img')) {
          if (keep.has(el) || kept(el) || el.dataset.suiteHidden === '1') continue;
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
      report.log = (window.__gcalChromeLog || []).slice(0, 40);
      /* The product's own toolbar row, just under the header: Calendar's view
         menu and arrows, Gmail's refresh and page arrows. Nothing of ours is
         supposed to touch it — the header rule is limited to the bar, and the
         ancestor-collapse rule refuses anything wider than 160 pt — so an
         empty toolbar means we over-reached. */
      let toolbar = 0;
      for (const el of document.querySelectorAll('button, div[role="button"], [role="combobox"], [role="menu"], select')) {
        const r = el.getBoundingClientRect();
        if (r.top < 56 || r.top > 130 || r.width < 10 || r.height < 10) continue;
        if (getComputedStyle(el).display === 'none') continue;
        toolbar++;
      }
      report.toolbarControls = toolbar;
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
