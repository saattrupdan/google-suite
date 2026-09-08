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
    ]

    /// Calendar. The drawer button stays — that is how you reach the list of
    /// calendars — and so does the week grid.
    static let calendarSelectors: [String] = [
        "#gb [aria-label=\"Search\"]",
        "[aria-label=\"Search calendars\"]",
        // This compact icon is not Calendar's view selector. The canonical
        // selector is the text-bearing Month/Week/... dropdown in #gb.
        "[aria-label=\"Filter and view\"]",
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
        + "view switcher|day|week|month|schedule|year|"
        + "jump to|date picker|main menu|main drawer|navigation|back|forward)"

    static func selectors(isMail: Bool) -> [String] { sharedSelectors + (isMail ? mailSelectors : calendarSelectors) }

    /// Pure-ish DOM helpers are kept in one small source block so fixture tests
    /// exercise the same implementation that the page uses. They do not assume
    /// Google's classes, only the live header boundary and inline-style rules.
    static let helperSource = #"""
    window.__gcalChromeHelpers = window.__gcalChromeHelpers || (() => {
      const viewport = () => ({
        width: Math.max(Number(window.innerWidth || globalThis.innerWidth ||
          (document.documentElement && document.documentElement.clientWidth) || 0),
          Number(window.visualViewport && window.visualViewport.width || 0)),
        height: Math.max(Number(window.innerHeight || globalThis.innerHeight ||
          (document.documentElement && document.documentElement.clientHeight) || 0),
          Number(window.visualViewport && window.visualViewport.height || 0))
      });
      const viewportIntersection = (el) => {
        if (!el || !el.getBoundingClientRect) return false;
        const r = el.getBoundingClientRect(), v = viewport();
        return r.right > 0 && r.bottom > 0 && r.left < v.width && r.top < v.height;
      };
      const hitTested = (el) => {
        if (!el || !document.elementFromPoint) return false;
        const r = el.getBoundingClientRect(), v = viewport();
        const x = r.left + r.width / 2, y = r.top + r.height / 2;
        if (!(x >= 0 && y >= 0 && x < v.width && y < v.height)) return false;
        const hit = document.elementFromPoint(x, y);
        for (let node = hit; node; node = node.parentElement) if (node === el) return true;
        return hit === el;
      };
      const laidOut = (el) => {
        if (!el || !el.getBoundingClientRect) return false;
        const r = el.getBoundingClientRect(), s = getComputedStyle(el);
        return r.width > 1 && r.height > 1 && viewportIntersection(el)
          && s.display !== 'none' && s.visibility !== 'hidden' && s.visibility !== 'collapse'
          && Number(s.opacity || 1) > 0;
      };
      const pointVisible = (el) => {
        if (!laidOut(el) || !document.elementFromPoint) return false;
        const r = el.getBoundingClientRect(), v = viewport(), x = r.left + r.width / 2, y = r.top + r.height / 2;
        if (!(x >= 0 && y >= 0 && x < v.width && y < v.height)) return false;
        const stack = document.elementsFromPoint ? document.elementsFromPoint(x, y) : [];
        return hitTested(el) || stack.some(hit => hit === el || (el.contains && el.contains(hit)));
      };
      const visible = (el) => laidOut(el) && hitTested(el);
      const headerOf = (el) => el && el.closest && el.closest('#gb, header[role="banner"]');
      const headerChrome = (el) => {
        const header = headerOf(el);
        if (!header) return false;
        const hr = header.getBoundingClientRect(), r = el.getBoundingClientRect();
        return r.top < hr.bottom + 4 && r.bottom > hr.top - 4
          && r.right >= Math.max(hr.left, hr.right - 560);
      };
      const controlTarget = (el) => el.closest &&
        (el.closest('a,button,[role="button"],[role="menuitem"]') || el);
      const candidateName = (el) => ((el.getAttribute &&
        (el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('data-tooltip') || ''))
        + ' ' + (el.textContent || '')).trim();
      const geminiCandidate = (el) => {
        const target = controlTarget(el), name = candidateName(target);
        if (!headerChrome(target)) return false;
        if (/gemini|studio unavailable/i.test(name)) return true;
        // Gmail has also shipped this launcher as an icon-only control. The
        // class may be on the interactive target or on an icon nested inside
        // it; inspect the original candidate before promoting it to a button.
        const classedIcon = (el.matches && el.matches('.MxSLJe,.Pv5YRd'))
          || !!(el.querySelector && el.querySelector('.MxSLJe,.Pv5YRd'))
          || (target.matches && target.matches('.MxSLJe,.Pv5YRd'));
        return !!classedIcon;
      };
      const scopedGeminiCandidates = () => {
        const header = document.querySelector('#gb, header[role="banner"]');
        if (!header) return [];
        const nodes = header.querySelectorAll('a,button,[role="button"],[role="menuitem"],'
          + '[aria-label],[data-tooltip],.MxSLJe,.Pv5YRd');
        const out = [], seen = new Set();
        for (const node of nodes) {
          const target = controlTarget(node);
          if (geminiCandidate(target) && !seen.has(target)) { seen.add(target); out.push(target); }
        }
        return out;
      };
      const remember = (state, el, property, value, priority = 'important') => {
        if (!state.has(el)) state.set(el, {});
        const saved = state.get(el);
        if (!(property in saved)) saved[property] = {
          value: el.style.getPropertyValue(property), priority: el.style.getPropertyPriority(property)
        };
        el.style.setProperty(property, value, priority);
      };
      const restore = (state) => {
        for (const [el, properties] of state) {
          for (const [property, old] of Object.entries(properties)) {
            if (old.value) el.style.setProperty(property, old.value, old.priority);
            else el.style.removeProperty(property);
          }
        }
        state.clear();
      };
      const normalizeText = (el) => (el && (el.textContent || '') || '')
        .replace(/\s+/g, ' ').trim().toLowerCase();
      // Calendar's canonical view control is an unnamed #gb button. Its live
      // signature is text such as "Montharrow_drop_down": a view name followed
      // by Google's Material icon ligature. Do not generalise this to arbitrary
      // text; Settings and Support also carry icon text in some releases.
      const calendarViewButton = (el) => {
        const target = controlTarget(el);
        if (!target || !target.matches || !target.matches('button')
            || !target.closest || !target.closest('#gb')) return false;
        const text = normalizeText(target);
        const hasViewName = /(day|week|month|year|schedule)/i.test(text);
        const hasDropDownIcon = text.includes('arrow_drop_down')
          || !!(target.querySelector && target.querySelector('[data-icon="arrow_drop_down"],'
            + '.material-icons, .material-symbols-outlined'));
        return hasViewName && hasDropDownIcon;
      };
      const calendarChoicesValid = (choices) => {
        const text = choices.join(' ');
        return /(^|\b)day(\b|[A-Za-z]|$)/i.test(text)
          && /(^|\b)week(\b|[A-Za-z]|$)/i.test(text)
          && /(^|\b)month(\b|[A-Za-z]|$)/i.test(text);
      };
      const menuVisible = (root) => {
        if (!root || root.getAttribute('aria-hidden') === 'true') return false;
        return visible(root);
      };
      const menuChoices = (root) => {
        const choices = [];
        if (!menuVisible(root)) return choices;
        for (const el of root.querySelectorAll('[role="menuitem"],[role="radio"],[role="option"],button')) {
          // A visible menu's text is not evidence that its hidden duplicate is
          // clickable. Every accepted choice passes its own geometry,
          // computed-style, viewport, and center-point hit test.
          const r = el.getBoundingClientRect(), s = getComputedStyle(el), v = {
            width: Math.max(Number(window.innerWidth || 0), Number(document.documentElement && document.documentElement.clientWidth || 0)),
            height: Math.max(Number(window.innerHeight || 0), Number(document.documentElement && document.documentElement.clientHeight || 0))
          };
          const x = r.left + r.width / 2, y = r.top + r.height / 2;
          const hit = document.elementFromPoint && document.elementFromPoint(x, y);
          let ownsHit = false;
          for (let node = hit; node; node = node.parentElement) if (node === el) { ownsHit = true; break; }
          if (!(r.width > 1 && r.height > 1 && r.right > 0 && r.bottom > 0
                && r.left < v.width && r.top < v.height && s.display !== 'none'
                && s.visibility !== 'hidden' && s.visibility !== 'collapse'
                && Number(s.opacity || 1) > 0 && ownsHit)) continue;
          const text = ((el.getAttribute('aria-label') || '') + ' ' + (el.textContent || ''))
            .replace(/\s+/g, ' ').trim();
          if (text && !choices.includes(text)) choices.push(text);
        }
        return choices;
      };
      return {visible, pointVisible, laidOut, viewportIntersection, hitTested, headerChrome, geminiCandidate,
        scopedGeminiCandidates, calendarViewButton, normalizeText, remember, restore,
        calendarChoicesValid, menuVisible, menuChoices};
    })();
    """#

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
        let source = helperSource + """
        (() => {
          const helpers = window.__gcalChromeHelpers;
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
          const hasOwnName = (el) => {
            for (let node = el, depth = 0; node && depth < 2; node = node.parentElement, depth++) {
              if (labelOf(node)) return true;
            }
            const img = node => node.tagName === 'IMG' ? node : (node.querySelector && node.querySelector('img'));
            const picture = img(el);
            // An image only names its button if the image itself is labelled.
            if (picture && (picture.getAttribute('alt') || '').trim()) return true;
            return false;
          };

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

          const mailSearchState = window.__gcalMailSearchState || {styles: new Map(), target: null};
          window.__gcalMailSearchState = mailSearchState;

          // Calendar's compact view control can open its real menu below the
          // viewport when Google leaves the narrow branch's host at the split
          // edge. Repair only the newly opened menu from this exact button;
          // never move an ancestor or another menu, and restore every injected
          // property after close or resize.
          const calendarMenuState = window.__gcalCalendarMenuState || {
            styles: new Map(), button: null, menu: null, parent: null, nextSibling: null,
            before: new Map(), armed: false, bound: null
          };
          window.__gcalCalendarMenuState = calendarMenuState;
          const calendarMenus = () => Array.from(document.querySelectorAll('[role="menu"],[role="listbox"]'));
          const calendarMenuComputedOpen = (menu) => {
            if (!menu) return false;
            const style = getComputedStyle(menu);
            return menu.getAttribute('aria-hidden') !== 'true' && style.display !== 'none'
              && style.visibility !== 'hidden' && style.visibility !== 'collapse'
              && Number(style.opacity || 1) > 0;
          };
          const calendarMenuGeometryOpen = (menu) => {
            if (!calendarMenuComputedOpen(menu)) return false;
            const r = box(menu);
            return r.width > 1 && r.height > 1;
          };
          const restoreCalendarMenu = () => {
            helpers.restore(calendarMenuState.styles);
            if (calendarMenuState.menu && calendarMenuState.parent
                && calendarMenuState.menu.parentElement === document.body) {
              try { calendarMenuState.parent.insertBefore(calendarMenuState.menu,
                calendarMenuState.nextSibling); } catch (e) {}
            }
            calendarMenuState.menu = null;
            calendarMenuState.parent = null;
            calendarMenuState.nextSibling = null;
            calendarMenuState.button = null;
            calendarMenuState.before = new Map();
            calendarMenuState.armed = false;
          };
          const calendarMenuViewport = () => ({
            width: Math.max(Number(innerWidth || 0),
              Number(window.visualViewport && window.visualViewport.width || 0),
              Number(document.documentElement && document.documentElement.clientWidth || 0)),
            height: Math.max(Number(innerHeight || 0),
              Number(window.visualViewport && window.visualViewport.height || 0),
              Number(document.documentElement && document.documentElement.clientHeight || 0))
          });
          const repairCalendarMenu = () => {
            if (\(isMail ? "true" : "false") || !calendarMenuState.armed) return;
            const menu = calendarMenus().filter(candidate => calendarMenuGeometryOpen(candidate)
              && (!calendarMenuState.before.has(candidate) || !calendarMenuState.before.get(candidate)));
            if (menu.length !== 1) return;
            const exact = menu[0];
            calendarMenuState.menu = exact;
            const r = box(exact), v = calendarMenuViewport();
            const inViewport = r.right > 0 && r.bottom > 0 && r.left < v.width && r.top < v.height;
            if (inViewport && helpers.hitTested(exact)) {
              calendarMenuState.armed = false;
              return;
            }
            // The raw diagnostic showed this menu's transformed, overflow:auto
            // host keeps even position:fixed at y=800. Reparent only this exact
            // newly opened menu; no ancestor or other menu is touched.
            calendarMenuState.parent = exact.parentElement;
            calendarMenuState.nextSibling = exact.nextSibling;
            document.body.appendChild(exact);
            helpers.remember(calendarMenuState.styles, exact, 'position', 'fixed');
            helpers.remember(calendarMenuState.styles, exact, 'left', '0px');
            helpers.remember(calendarMenuState.styles, exact, 'top', '0px');
            helpers.remember(calendarMenuState.styles, exact, 'right', 'auto');
            helpers.remember(calendarMenuState.styles, exact, 'bottom', 'auto');
            helpers.remember(calendarMenuState.styles, exact, 'z-index', '2147483647');
            const moved = box(exact), viewport = calendarMenuViewport();
            const anchor = box(calendarMenuState.button);
            // Anchor the popup under the real dropdown, right edges aligned.
            // Google leaves a transform on the portal, so calculate the CSS
            // offset from the rectangle produced at left:0/top:0 rather than
            // assuming those declarations put the box at the origin.
            const targetLeft = Math.max(0, Math.min(viewport.width - moved.width,
              anchor.right - moved.width));
            const targetTop = Math.max(0, Math.min(viewport.height - moved.height,
              anchor.bottom + 4));
            exact.style.setProperty('left', `${targetLeft - moved.left}px`, 'important');
            exact.style.setProperty('top', `${targetTop - moved.top}px`, 'important');
            calendarMenuState.armed = false;
          };
          // Restore the exact portal before a real menu-item pointer or
          // keyboard activation. That lets the subsequent mousedown/click (or
          // keyup) travel through Google's original ownership tree, preserving
          // delegated selection and close handlers.
          const restoreCalendarMenuForChoice = (event) => {
            const menu = calendarMenuState.menu, target = event.target;
            if (!menu || !target || !menu.contains(target)) return;
            if (event.type === 'keydown' && !['Enter', ' '].includes(event.key)) return;
            restoreCalendarMenu();
          };
          document.addEventListener('pointerdown', restoreCalendarMenuForChoice, true);
          document.addEventListener('mousedown', restoreCalendarMenuForChoice, true);
          document.addEventListener('keydown', restoreCalendarMenuForChoice, true);

          const bindCalendarMenuButton = () => {
            if (\(isMail ? "true" : "false")) return;
            const button = Array.from(document.querySelectorAll('#gb button'))
              .find(el => helpers.calendarViewButton(el));
            if (!button || calendarMenuState.bound === button) return;
            calendarMenuState.bound = button;
            button.addEventListener('click', () => {
              // A second activation is Google's native close path. Restore the
              // exact menu before its handler runs so its original ownership
              // and event wiring remain intact. This must also run while the
              // diagnostic is closing; otherwise Google receives the second
              // activation while its menu is still reparented and cannot close it.
              if (calendarMenuState.menu && calendarMenuComputedOpen(calendarMenuState.menu)
                  && button.getAttribute('aria-expanded') === 'true') {
                restoreCalendarMenu();
                return;
              }
              calendarMenuState.button = button;
              // Google retains the closed menu as a sized node at y=viewport.
              // Baseline interactive state, not mere geometry, so the same node
              // remains eligible on every later opening.
              calendarMenuState.before = new Map(calendarMenus()
                .map(menu => [menu, helpers.menuVisible(menu)]));
              calendarMenuState.armed = true;
              setTimeout(repairCalendarMenu, 25);
            }, true);
          };
          const updateCalendarMenu = () => {
            if (\(isMail ? "true" : "false")) return;
            bindCalendarMenuButton();
            if (calendarMenuState.menu && !calendarMenuComputedOpen(calendarMenuState.menu))
              restoreCalendarMenu();
            // The click handler captures the exact newly opened menu after
            // this run-loop turn; do not repair before the probe can record it.
          };

          const keepMailSearchInViewport = () => {
            if (!\(isMail ? "true" : "false")) return;
            const search = document.querySelector('button[aria-label="Search mail"],'
              + '[role="button"][aria-label="Search mail"]');
            if (!search) return;
            helpers.restore(mailSearchState.styles);
            mailSearchState.target = null;
            if (Number(innerWidth || 0) >= 900) return;
            const r = box(search), viewportWidth = Math.max(Number(innerWidth || 0),
              Number(window.visualViewport && window.visualViewport.width || 0));
            if (r.right > viewportWidth || r.left < 0) {
              mailSearchState.target = search;
              helpers.remember(mailSearchState.styles, search, 'position', 'relative');
              helpers.remember(mailSearchState.styles, search, 'left',
                `${Math.max(-r.left, Math.min(0, viewportWidth - r.right))}px`);
            }
          };

          const hideGeminiControls = () => {
            if (!\(isMail ? "true" : "false")) return;
            // Scope removal to the actual Gmail header/right chrome. In
            // particular, never search body text: an email may legitimately
            // mention Gemini.
            for (const target of helpers.scopedGeminiCandidates()) {
              reason = 'gemini';
              hide(target);
              reason = 'selector';
            }
          };

          const applyDirect = () => {
            reason = 'selector';
            hideGeminiControls();
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
              // Calendar's text-bearing view dropdown is unnamed, so the
              // positional rule must spare this exact structural signature.
              // The separate Filter-and-view icon is hidden by selector above.
              if (!\(isMail ? "true" : "false") && helpers.calendarViewButton(target)) continue;
              /* Only nameless controls. Google's own buttons here have no
                 accessible name at all — the account button is an <img> of a
                 logo gif, support an <img> of a question mark — while anything
                 the product wants you to use is named: "Next month", "Today,
                 Tuesday, 8 September", "Change view". Naming is also what
                 survives a UI release or another language, so prev/next is
                 protected by this rather than by a word list matching today.
                 Named chrome we do want gone (the apps launcher, settings,
                 Gemini) is gone by selector, where it can be listed and
                 checked. */
              if (hasOwnName(target)) continue;
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

          const applyDirectAll = () => {
            applyDirect(); hideHeaderRight(); keepMailSearchInViewport(); updateCalendarMenu();
          };

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

          window.__gcalChromeRun = run;
          window.__gcalChromeLoaded = true;
          window.__gcalChromeHidden = 0;
          window.__gcalChromeRuns = 0;
          run();
          schedule();
          for (const delay of [400, 1200, 3000, 8000]) setTimeout(run, delay);
          setInterval(run, 1500);
          // Layout, not just markup, decides what is chrome. Re-run once the page
          // is complete so the geometry rules see real boxes.
          if (document.readyState !== 'complete') {
            addEventListener('load', () => { run(); setTimeout(run, 600); });
          }
          new MutationObserver(schedule).observe(document.documentElement,
              {childList: true, subtree: true});
          addEventListener('resize', () => {
            restoreCalendarMenu();
            schedule();
          }, {passive: true});
          return 'ok';
        })();
        """
        return source
    }

    private static let blankScript = WKUserScript(source: "", injectionTime: .atDocumentEnd, forMainFrameOnly: true)

    // MARK: - Diagnostics

    /// Lists every interactive element in the header or the right-hand area,
    /// including zero-sized candidates. Google often leaves a hidden copy of a
    /// control next to the live one, and the distinction is otherwise invisible
    /// when a class name changes.
    static let controlsScript = #"""
    (() => {
      const controls = 'a,button,input,select,summary,[role="button"],[role="combobox"],'
        + '[role="menuitem"],[role="radio"],[role="tab"],[contenteditable="true"]';
      const text = (el) => Array.from(el.childNodes || [])
        .filter(node => node.nodeType === Node.TEXT_NODE).map(node => node.textContent || '')
        .join(' ').replace(/\s+/g, ' ').trim().slice(0, 120);
      const ancestry = (el) => {
        const out = [];
        for (let node = el, depth = 0; node && depth < 6; node = node.parentElement, depth++) {
          const cls = (node.className || '').toString().split(/\s+/).filter(Boolean).slice(0, 3).join('.');
          const label = node.getAttribute && (node.getAttribute('aria-label') || node.getAttribute('title')) || '';
          out.push(node.tagName.toLowerCase() + (node.id ? '#' + node.id : '')
            + (cls ? '.' + cls : '') + (label ? ' aria=' + label.slice(0, 60) : ''));
        }
        return out;
      };
      const signature = (el) => {
        const img = el.tagName === 'IMG' ? el : el.querySelector && el.querySelector('img');
        const svg = el.tagName === 'SVG' ? el : el.querySelector && el.querySelector('svg');
        const path = svg && svg.querySelector('path');
        return {
          image: img ? {alt: img.alt || '', src: (img.currentSrc || img.src || '').slice(0, 140)} : null,
          svg: svg ? {viewBox: svg.getAttribute('viewBox') || '',
                      text: (svg.outerHTML || '').replace(/\s+/g, ' ').slice(0, 180),
                      path: path ? (path.getAttribute('d') || '').slice(0, 100) : ''} : null
        };
      };
      const rows = [];
      const candidates = document.querySelectorAll('#gb *,#gb,'
        + 'header[role="banner"] a,header[role="banner"] button,header[role="banner"] input,header[role="banner"] select,'
        + 'header[role="banner"] [role],body a,body button,body input,body select,body summary,body [role],body [aria-label]');
      let scanned = 0;
      for (const el of candidates) {
        if (++scanned > 12000 || rows.length >= 500) break;
        const r = el.getBoundingClientRect();
        const inHeader = !!el.closest('#gb, header[role="banner"]');
        const inRight = r.right >= innerWidth - 400 && r.top < 180;
        if (!inHeader && !inRight) continue;
        const style = getComputedStyle(el);
        const centerHit = document.elementFromPoint && r.width > 1 && r.height > 1
          ? document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2) : null;
        const hitSummary = centerHit ? {tag: centerHit.tagName.toLowerCase(), id: centerHit.id || '',
          cls: (centerHit.className || '').toString().split(/\s+/).slice(0, 3).join('.'),
          ancestry: (() => { const a = []; for (let n = centerHit, i = 0; n && i++ < 5; n = n.parentElement) a.push(n.tagName.toLowerCase() + '.' + (n.className || '').toString().split(/\s+/).slice(0, 2).join('.')); return a; })() } : null;
        const visible = r.width > 1 && r.height > 1 && style.display !== 'none'
          && style.visibility !== 'hidden' && style.visibility !== 'collapse'
          && Number(style.opacity || 1) > 0;
        rows.push({tag: el.tagName.toLowerCase(), id: el.id || '', role: el.getAttribute('role') || '',
          aria: el.getAttribute('aria-label') || el.getAttribute('title') || '', ownText: text(el),
          text: (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 160),
          rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
          hit: hitSummary, visible, inHeader, inRight, display: style.display, visibility: style.visibility,
          opacity: style.opacity, hidden: el.hidden, ariaHidden: el.getAttribute('aria-hidden') || '',
          suiteHidden: el.dataset && el.dataset.suiteHidden || '', ancestry: ancestry(el),
          signature: signature(el)});
      }
      return JSON.stringify({viewport: [innerWidth, innerHeight], viewportDetail: {
        inner: [innerWidth, innerHeight], outer: [outerWidth, outerHeight],
        client: [document.documentElement.clientWidth, document.documentElement.clientHeight],
        visual: window.visualViewport ? [visualViewport.width, visualViewport.height, visualViewport.scale] : null
      }, scanned, controls: rows});
    })();
    """#

    // MARK: - Live verification

    /// Starts a real click on Calendar's text-bearing view dropdown. WebKit does
    /// not await Promises returned by evaluateJavaScript, so completion is
    /// stashed on the page and DomCheck polls it with a plain JSON expression.
    static let calendarMenuProbeScript = #"""
    (() => {
      const helpers = window.__gcalChromeHelpers;
      const state = window.__gcalCalendarMenuProbe = {
        status: 'pending', choices: [], closed: false,
        rawMenu: null, openMenu: null, finalMenu: null
      };
      const started = Date.now();
      const allMenus = () => Array.from(document.querySelectorAll('[role="menu"],[role="listbox"]'));
      const choicesFor = menu => helpers && helpers.menuChoices ? helpers.menuChoices(menu) : [];
      const viewport = () => ({
        width: Math.max(Number(window.innerWidth || 0), Number(window.visualViewport && window.visualViewport.width || 0),
          Number(document.documentElement && document.documentElement.clientWidth || 0)),
        height: Math.max(Number(window.innerHeight || 0), Number(window.visualViewport && window.visualViewport.height || 0),
          Number(document.documentElement && document.documentElement.clientHeight || 0))
      });
      const rect = el => {
        const r = el.getBoundingClientRect();
        return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)];
      };
      const ancestry = el => {
        const out = [];
        for (let node = el, depth = 0; node && depth++ < 8; node = node.parentElement) {
          const cls = (node.className || '').toString().split(/\\s+/).filter(Boolean).slice(0, 3).join('.');
          out.push(node.tagName.toLowerCase() + (node.id ? '#' + node.id : '')
            + (cls ? '.' + cls : ''));
        }
        return out;
      };
      const centerHit = el => {
        const r = el.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
        const hit = document.elementFromPoint && document.elementFromPoint(x, y);
        let owns = false;
        for (let node = hit; node; node = node.parentElement) if (node === el) { owns = true; break; }
        return {point: [Math.round(x), Math.round(y)], hit: hit ? ancestry(hit)[0] : null,
          hitAncestry: hit ? ancestry(hit) : [], owns};
      };
      const clippingAncestors = el => {
        const out = [];
        for (let node = el.parentElement, depth = 0; node && node !== document.body && depth++ < 8;
             node = node.parentElement) {
          const s = getComputedStyle(node), r = node.getBoundingClientRect();
          out.push({node: ancestry(node)[0], rect: rect(node), overflow: s.overflow,
            overflowX: s.overflowX, overflowY: s.overflowY});
        }
        return out;
      };
      const menuDiagnostic = (menu, phase) => {
        const r = menu.getBoundingClientRect(), s = getComputedStyle(menu), v = viewport();
        return {phase, rect: rect(menu), viewport: [v.width, v.height],
          parent: ancestry(menu.parentElement),
          computed: {display: s.display, visibility: s.visibility, opacity: s.opacity,
            position: s.position, left: s.left, top: s.top, right: s.right, bottom: s.bottom,
            zIndex: s.zIndex},
          inline: {display: menu.style.display, visibility: menu.style.visibility,
            opacity: menu.style.opacity, position: menu.style.position, left: menu.style.left,
            top: menu.style.top, right: menu.style.right, bottom: menu.style.bottom,
            zIndex: menu.style.zIndex},
          clippingAncestors: clippingAncestors(menu), center: centerHit(menu),
          computedOpen: menu.getAttribute('aria-hidden') !== 'true' && s.display !== 'none'
            && s.visibility !== 'hidden' && s.visibility !== 'collapse' && Number(s.opacity || 1) > 0,
          choices: choicesFor(menu)};
      };
      const computedOpen = menu => {
        if (!menu) return false;
        const s = getComputedStyle(menu);
        return menu.getAttribute('aria-hidden') !== 'true' && s.display !== 'none'
          && s.visibility !== 'hidden' && s.visibility !== 'collapse' && Number(s.opacity || 1) > 0;
      };
      const strictOpen = menu => {
        if (!computedOpen(menu)) return false;
        const r = menu.getBoundingClientRect(), v = viewport();
        return r.width > 1 && r.height > 1 && r.right > 0 && r.bottom > 0
          && r.left < v.width && r.top < v.height && !!helpers.menuVisible(menu);
      };
      const geometryOpen = menu => {
        if (!computedOpen(menu)) return false;
        const r = menu.getBoundingClientRect();
        return r.width > 1 && r.height > 1;
      };
      const activateButton = control => {
        const r = control.getBoundingClientRect();
        const x = r.left + r.width / 2, y = r.top + r.height / 2;
        const init = {bubbles: true, cancelable: true, view: window,
          clientX: x, clientY: y, screenX: x, screenY: y, button: 0};
        const target = control;
        if (typeof PointerEvent === 'function') {
          const pointer = {...init, pointerType: 'mouse', isPrimary: true, buttons: 1};
          target.dispatchEvent(new PointerEvent('pointerdown', pointer));
          target.dispatchEvent(new PointerEvent('pointerup', {...pointer, buttons: 0}));
        }
        target.dispatchEvent(new MouseEvent('mousedown', init));
        target.dispatchEvent(new MouseEvent('mouseup', init));
        target.dispatchEvent(new MouseEvent('click', init));
      };
      let button = null, menuInstance = null, closeRequested = false;
      // A retained closed portal can stay sized off-screen. Record strict,
      // interactive state so a second opening of the same node is still new.
      const before = new Map(allMenus().map(menu => [menu, strictOpen(menu)]));
      const candidates = () => allMenus().filter(menu => {
        if (!geometryOpen(menu)) return false;
        return !before.has(menu) || !before.get(menu);
      });
      const requestNaturalClose = () => {
        if (closeRequested || !menuInstance) return;
        closeRequested = true;
        // Select the already-active Month item first: it changes no user
        // state, exercises the actual item path, and naturally closes the
        // menu. The production pointerdown capture restores Google's original
        // ownership before the remaining activation events are dispatched.
        const event = new KeyboardEvent('keydown', {
          key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true
        });
        const month = Array.from(menuInstance.querySelectorAll(
          '[role="menuitem"],[role="radio"],[role="option"],button')).find(el =>
            /^month(?:\b|[A-Z])/i.test(((el.getAttribute('aria-label') || '') + ' '
              + (el.textContent || '')).trim()) && helpers.pointVisible(el));
        try { if (month) activateButton(month); else if (button) activateButton(button); } catch (e) {}
        setTimeout(() => {
          if (!computedOpen(menuInstance)) return;
          try { button && button.focus(); } catch (e) {}
          for (const target of [menuInstance, button, document.activeElement, document.body, document, window]) {
            if (!target || !target.dispatchEvent) continue;
            try { target.dispatchEvent(event); } catch (e) {}
            try { target.dispatchEvent(new KeyboardEvent('keyup', {
              key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true
            })); } catch (e) {}
          }
        }, 120);
      };
      const finish = (ok, choices, error) => {
        state.status = 'closing'; state.choices = choices;
        requestNaturalClose();
        setTimeout(() => {
          state.finalMenu = menuInstance ? menuDiagnostic(menuInstance, 'after-close') : null;
          state.buttonState = button ? {ariaExpanded: button.getAttribute('aria-expanded'),
            ariaHaspopup: button.getAttribute('aria-haspopup')} : null;
          // Google's native closed representation keeps this portal sized in
          // its off-screen host at y=viewportHeight. Require both semantic
          // closure on the real button and that the exact menu is no longer
          // visible/hittable; off-screen geometry alone is not sufficient.
          const ariaClosed = button && button.getAttribute('aria-expanded') === 'false';
          const closed = !!ariaClosed && !strictOpen(menuInstance);
          state.status = ok && closed ? 'ok' : 'failed';
          state.choices = choices; state.closed = closed;
          if (error) state.error = error;
        }, 600);
      };
      const diagnostics = () => allMenus().map(el => menuDiagnostic(el, 'diagnostic'));
      const poll = () => {
        if (!menuInstance) {
          const appeared = candidates();
          if (appeared.length === 1) {
            menuInstance = appeared[0];
            // This is intentionally before any validation or close request: the
            // record is the unmodified menu Google opened after our click.
            state.rawMenu = menuDiagnostic(menuInstance, 'raw-after-click');
          } else if (appeared.length > 1) {
            finish(false, [], 'more than one newly opened menu: ' + JSON.stringify(diagnostics()));
            return;
          }
        }
        if (menuInstance) {
          const choices = choicesFor(menuInstance);
          if (strictOpen(menuInstance) && choices.length > 0 && helpers.calendarChoicesValid(choices)) {
            const mr = menuInstance.getBoundingClientRect(), br = button.getBoundingClientRect();
            // Production must place the real popup directly under the button,
            // right edges aligned—not merely somewhere inside the viewport.
            const anchored = Math.abs(mr.right - br.right) <= 4
              && mr.top >= br.bottom && mr.top - br.bottom <= 12;
            state.openMenu = menuDiagnostic(menuInstance, 'visible-after-production-repair');
            if (anchored) { finish(true, choices, ''); return; }
          }
        }
        if (Date.now() - started > 4000) {
          finish(false, menuInstance ? choicesFor(menuInstance) : [],
            'actual Montharrow_drop_down click did not reveal one hittable Day/Week/Month menu; '
              + 'button=' + JSON.stringify(button && {text: button.textContent, rect: rect(button)})
              + '; candidates=' + JSON.stringify(diagnostics()));
          return;
        }
        setTimeout(poll, 50);
      };
      const waitForButton = () => {
        button = Array.from(document.querySelectorAll('#gb button')).find(el =>
          helpers && helpers.calendarViewButton(el) && helpers.pointVisible(el));
        if (!button) {
          if (Date.now() - started > 4000) {
            state.status = 'failed'; state.error = 'real Montharrow_drop_down view button did not become visible'; return;
          }
          setTimeout(waitForButton, 50); return;
        }
        try { activateButton(button); }
        catch (e) { finish(false, [], String(e)); return; }
        setTimeout(poll, 0);
      };
      waitForButton();
      return JSON.stringify(state);
    })();
    """#
    static let calendarMenuProbePollScript = "JSON.stringify(window.__gcalCalendarMenuProbe || {status: 'missing'})"

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
        hamburger: {mustHide: false, optional: true,
                    selectors: ['#gb [aria-label="Main menu"]', '#gb [aria-label="Main drawer"]']},
        filterIcon: {mustHide: true, optional: true,
                     selectors: ['[aria-label="Filter and view"]']},
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
      const auditWidth = Math.max(Number(innerWidth || 0),
        Number(window.visualViewport && window.visualViewport.width || 0));
      const auditHeight = Math.max(Number(innerHeight || 0),
        Number(window.visualViewport && window.visualViewport.height || 0));
      const visible = (el) => {
        const r = el.getBoundingClientRect(), style = getComputedStyle(el);
        const inViewport = r.right > 0 && r.bottom > 0 && r.left < auditWidth && r.top < auditHeight;
        const x = r.left + r.width / 2, y = r.top + r.height / 2;
        const hit = document.elementFromPoint && document.elementFromPoint(x, y);
        const stack = document.elementsFromPoint ? document.elementsFromPoint(x, y) : [];
        const pointHit = !!hit && (hit === el || (el.contains && el.contains(hit)))
          || stack.some(target => target === el || (el.contains && el.contains(target)));
        return r.width > 1 && r.height > 1 && inViewport && style.display !== 'none'
          && style.visibility !== 'hidden' && style.visibility !== 'collapse'
          && Number(style.opacity || 1) > 0 && pointHit;
      };
      const gemini = [];
      const helpers = window.__gcalChromeHelpers;
      for (const el of (helpers ? helpers.scopedGeminiCandidates() : [])) {
        const svg = el.querySelector && el.querySelector('svg');
        const path = svg && svg.querySelector('path');
        const r = el.getBoundingClientRect();
        gemini.push({tag: el.tagName.toLowerCase(), cls: (el.className || '').toString().slice(0, 90),
                     aria: el.getAttribute('aria-label') || el.getAttribute('title') || '',
                     visible: visible(el), rect: [Math.round(r.x), Math.round(r.y),
                                                    Math.round(r.width), Math.round(r.height)],
                     ancestry: (() => { const a = []; for (let n = el, i = 0; n && i++ < 6; n = n.parentElement)
                       a.push(n.tagName.toLowerCase() + (n.id ? '#' + n.id : '') + '.' +
                         (n.className || '').toString().split(/\\s+/).slice(0, 2).join('.')); return a; })(),
                     svgPath: path ? (path.getAttribute('d') || '').slice(0, 120) : '',
                     suiteHidden: el.dataset && el.dataset.suiteHidden || ''});
      }
      report.geminiLauncher = {matched: gemini.length,
                               visible: gemini.filter(item => item.visible).length,
                               identities: gemini.slice(0, 12), mustHide: true, optional: true};
      const laidOut = (el) => {
        const r = el.getBoundingClientRect(), style = getComputedStyle(el);
        return r.width > 1 && r.height > 1 && r.right > 0 && r.bottom > 0
          && r.left < auditWidth && r.top < auditHeight && style.display !== 'none'
          && style.visibility !== 'hidden' && style.visibility !== 'collapse'
          && Number(style.opacity || 1) > 0;
      };
      const viewButtons = Array.from(document.querySelectorAll('#gb button'))
        .filter(el => helpers && helpers.calendarViewButton(el));
      const viewButton = viewButtons.find(el => laidOut(el));
      const filterIcon = document.querySelector('[aria-label="Filter and view"]');
      const labelledInteractive = (prefix) => Array.from(document.querySelectorAll(
        'button[aria-label],a[aria-label],[role="button"][aria-label]'))
        .filter(el => (el.getAttribute('aria-label') || '').toLowerCase().startsWith(prefix));
      const controlAudit = (el) => {
        const r = el.getBoundingClientRect();
        const inViewport = r.right > 0 && r.bottom > 0 && r.left < auditWidth && r.top < auditHeight;
        const x = r.left + r.width / 2, y = r.top + r.height / 2;
        const hit = document.elementFromPoint && document.elementFromPoint(x, y);
        const hitTarget = hit && hit.closest && hit.closest('button,a,[role="button"]');
        const aria = el.getAttribute('aria-label') || '';
        const sameLabelTarget = hitTarget && (hitTarget.getAttribute('aria-label') || '') === aria;
        const sameLabelDescendant = hit && hit.querySelector && Array.from(
          hit.querySelectorAll('button,a,[role="button"]')).some(target =>
            (target.getAttribute('aria-label') || '') === aria);
        const stack = document.elementsFromPoint ? document.elementsFromPoint(x, y) : [];
        const stackHit = stack.some(target => target === el || (el.contains && el.contains(target)));
        const hitContains = !!(hit && ((el.contains && el.contains(hit))
          || sameLabelTarget || sameLabelDescendant || stackHit));
        return {tag: el.tagName.toLowerCase(), aria: el.getAttribute('aria-label') || '',
          visible: laidOut(el) && inViewport && hitContains, inViewport, hit: hitContains,
          hitTag: hit ? hit.tagName.toLowerCase() : '', hitContains,
          rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]};
      };
      const controls = {
        viewButton: viewButton ? controlAudit(viewButton) : null,
        filterIcon: filterIcon ? controlAudit(filterIcon) : null,
        previous: labelledInteractive('previous').map(controlAudit),
        next: labelledInteractive('next').map(controlAudit)
      };
      const activeControls = [controls.viewButton, ...controls.previous, ...controls.next]
        .filter(item => item && item.visible);
      const overlaps = [];
      for (let i = 0; i < activeControls.length; i++) for (let j = i + 1; j < activeControls.length; j++) {
        const a = activeControls[i].rect, b = activeControls[j].rect;
        if (a[0] < b[0] + b[2] && a[0] + a[2] > b[0] && a[1] < b[1] + b[3] && a[1] + a[3] > b[1])
          overlaps.push([a, b]);
      }
      report.calendarViewOptions = {
        matched: viewButtons.length,
        visible: !!(controls.viewButton && controls.viewButton.visible),
        kind: 'Montharrow_drop_down menu', options: [],
        viewButton: controls.viewButton, filterIcon: controls.filterIcon,
        noOverlap: overlaps.length === 0, overlaps
      };
      report.calendarNavigation = {
        previous: controls.previous.filter(item => item.visible).length,
        next: controls.next.filter(item => item.visible).length,
        today: labelledInteractive('today').filter(visible).length,
        controls: {previous: controls.previous, next: controls.next}, noOverlap: overlaps.length === 0
      };
      report.gmailControls = {
        askGemini: Array.from(document.querySelectorAll('button[aria-label="Ask Gemini"],[aria-label="Ask Gemini"]'))
          .map(controlAudit),
        searchMail: Array.from(document.querySelectorAll('button[aria-label="Search mail"],a[aria-label="Search mail"],[role="button"][aria-label="Search mail"]')).map(controlAudit)
      };
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
      let headerRight = 0, namedVisible = 0;
      const hiddenNamed = [];
      // A control is "named" when it or its picture carries an accessible name.
      // Google's chrome here has none; the product's navigation always does.
      const named = (el) => {
        const pic = el.tagName === 'IMG' ? el : (el.querySelector && el.querySelector('img'));
        if ((el.getAttribute('aria-label') || el.getAttribute('title') || '').trim()) return true;
        return !!(pic && (pic.getAttribute('alt') || '').trim());
      };
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
          // The unnamed Calendar view dropdown is intentional navigation, not
          // surviving chrome; audit the same structural predicate as trimming.
          if (helpers && helpers.calendarViewButton(target)) continue;
          if (seen.has(target)) continue;
          const r = target.getBoundingClientRect();
          if (r.width < 8 || r.height < 8 || r.top > 56 || r.x < limit) continue;
          if (getComputedStyle(target).display === 'none') {
            if (named(target)) {
              const r2 = target.getBoundingClientRect();
              hiddenNamed.push(target.tagName.toLowerCase() +
                  ' aria=' + ((target.getAttribute('aria-label') || target.getAttribute('title') ||
                                (target.querySelector('img') || {}).alt || '') + '').slice(0, 40) +
                  ' [' + Math.round(r2.x) + ',' + Math.round(r2.y) + ',' + Math.round(r2.width) + 'w]');
            }
            continue;
          }
          if (named(target)) namedVisible++;
          seen.add(target);
          headerRight++;
        }
      }
      report.headerRight = headerRight;
      // Anything named that the product put in the header must still be there:
      // prev/next, Today, the view menu. Nameless leftovers are chrome and are
      // counted by headerRight.
      report.headerNamed = namedVisible;
      report.headerHiddenNamed = hiddenNamed.slice(0, 6);
      report.log = (window.__gcalChromeLog || []).slice(0, 40);
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
