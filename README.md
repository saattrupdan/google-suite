# google-suite — Google Mail and Calendar for Mac

Two Google surfaces in one small native window: **Mail** and **Calendar**, a left rail
of icons, and nothing else. Built from `swiftc` and `WKWebView` — no Electron, no Xcode
project, no browser chrome.

It exists because the *Apple* Calendar/Mail path to Google has holes no setting in
Apple's apps can fill:

| | Apple Calendar / Mail | This app |
| --- | --- | --- |
| Add a Google Meet link to an event | ❌ FaceTime only | ✅ the web UI's own button |
| Open a colleague's calendar by typing their name | ❌ only what Google exports over CalDAV | ✅ whatever `calendar.google.com` can see |
| Gmail labels, filters, snooze | partial | ✅ |
| New-mail alerts while the app is in the background | via Apple's account push | ✅ own poller, native banners |

It is not a better calendar. It is Google's calendar and Gmail with a window of their
own.

## Install

```sh
cd ~/gitsky/google-suite
./build.sh && ./install.sh
open "/Applications/Google Suite.app"     # or: bin/gsuite
```

Sign in on first launch. Those cookies belong to this app
(`~/Library/WebKit/com.saattrupdan.google-suite`), not to Safari or Chrome — one sign-in,
then it persists. The web view identifies itself as Safari (`Config.suggestedUserAgent()`)
so Google does not reject it as an embedded web view.

## Interface

* **No traditional title bar.** In single mode the traffic lights float over the 56pt
  rail; in split mode the rail is hidden and a shallow native strip hosts the lights above
  both web panes. Drag the window by the rail, strip, or divider. There is no toolbar either
  — everything it could have held is in the menu bar, or gone.
* **Left rail** — Mail, then Calendar. Icon only; the source you are looking at is
  **blue**, the other one grey, and unread mail shows as a red badge on the envelope.
  `⌘1` / `⌘2`, or `⌃⇥` to cycle.
* **Side by side** (`⌘\`) — Mail and Calendar split the window, both live at once. Worth
  it on a large monitor; off by default. The source rail is hidden so both web panes reclaim
  the full width; the native traffic-light strip remains above them. **Drag the divider** to
  give one side more room; the split is remembered (`splitRatio`), and it never goes past
  80/20 either way.
* **Trimmed Gmail interface** — Gmail's own label rail on the left and its Meet/Chat/Keep
  rail on the right are hidden, and its header is reduced to the menu button, the wordmark,
  search and your account picture. See [Trimming Gmail's interface](#trimming-gmails-interface).
* No tabs, no address bar, no back/forward. Two surfaces, not a browser.

Sign-in popups (`window.open`) appear as a panel over the content and close themselves
when the flow finishes; the page that opened them keeps its `window.opener` link, so
Google's popup can report back.

## Trimming Google's interface

Both surfaces show their product and nothing else. Gone: Gmail's label rail and
right dock, Calendar's search / support / settings buttons, the Calendar↔Tasks
toggle, the **Create** button, Google's apps launcher and the account picture.
Also the right-hand strip with Keep / Tasks / Contacts / Clock — in *both*
products that is the same element, `role="complementary"` labelled *"Side
panel"*; hiding only an inner wrapper leaves a 56 pt empty column standing where
the rail was. The header keeps the **menu button** (the hamburger or, in
Calendar, the drawer — that is how you open the list of inboxes or calendars),
the **wordmark**, and **search**.

Two things make this more than writing CSS, and neither is obvious:

* **Google forbids inline `<style>` elements.** An injected stylesheet is
  applied on Gmail and dropped without a word on Calendar. So the rules are
  *also* applied through the CSSOM — `element.style.setProperty(...)` — which
  CSP does not count as an inline style and which works on both.
* **`requestAnimationFrame` does not run in a web view that is not on screen**,
  which is exactly the state the second surface is in while it loads. A
  frame-scheduled pass silently never executes, so trimming runs immediately,
  again on every DOM mutation, and again at fixed delays.

Selectors are written against `role` and `aria-label`, measured from the live
pages, because the obfuscated classes change every release. Where there is no
label to select, the rule is positional: **the right-hand 360 pt of the top bar
is Google chrome**, hidden whatever it contains. That is not laziness — the
account button is an `<img>` of a logo gif and Gmail's support button is an
`<img>` of a question mark, both with no accessible name at all, which is why
they survived an earlier, label-only pass while still being clickable. The menu
button, the wordmark and search sit left of that line and are untouched.

Two exceptions keep that rule honest, both measured rather than assumed:

* **Navigation is spared by name.** When a pane gets narrow, both products move
  their real controls into the header's right side — Calendar's *Previous
  month* / *Next month* / *Today, Tuesday, 8 September*, and Gmail's search
  collapsing to a magnifier. A positional rule that does not know this eats the
  arrows, which is exactly what an earlier version of it did.
* **Nothing is hidden before it has been laid out.** At `documentEnd` every
  element measures zero, so "this container looks empty" is not evidence — one
  version concluded from that that the toolbars were empty and hid them. An
  unmeasurable subtree now counts as occupied, and the pass runs again on `load`.

`--domcheck` covers both: exact checks fail when Gmail's visible
Gemini/Studio launcher survives, or when Calendar's real text-bearing
`Montharrow_drop_down` view dropdown / previous/next navigation goes missing.
The separate compact `Filter and view` icon is hidden, not used as a substitute.
The audit requires viewport intersection, center-point hit testing, and no pairwise
overlap for visible Calendar controls. The Calendar probe clicks the real dropdown,
requires a newly visible menu whose Day/Week/Month items are all hittable, and
proves that same menu instance was hidden or removed; a zero-sized duplicate cannot
satisfy it. `--domcheck --why` prints what each rule hid and why
(`selector`, `header-zone`, `collapse`) — the only practical way to find out which
of 20 hidden elements was the one you needed. `--domdump` and `--domcheck` show both surfaces while they
measure, because a hidden web view is never laid out and would report zeros;
`--fullwidth` explicitly forces the requested source into a single full-width
surface (even when `splitLayout` is persisted), without saving that temporary
choice. `--no-trim --calendar --fullwidth --domdump` is a safe native-DOM
comparison: trimming is disabled in memory only and the persisted config is untouched. Pass `--calendar` with it to diagnose Calendar. `--domcontrols` prints
every header/right-area interactive control with ancestry, own text,
image/SVG signatures, hidden markers, and computed display/visibility. It is
still surgery
on a page the app does not control: a Google release can rename everything and
the rules will quietly do nothing. `--domcheck` is the guard — it measures each
thing on **every** surface and fails when something that must be gone is visible,
when a rule matched *nothing at all* (the markup moved), when the trimming script
never ran, and when something narrow still holds the right edge:

```sh
"./Google Suite.app/Contents/MacOS/Google Suite" --domcheck
# CHECK Mail:      rightRail: matched=5 visible=0   hidden=20 rightStrip=0 …
# CHECK Calendar:  railTabs:  matched=3 visible=0   hidden=52 rightStrip=0 …
# CHECK ok
```

When it reports `nothing matched`, run `--domdump` to see the current structure
and update `Sources/GmailChrome.swift`. `--domdump --images` adds every image
(avatars are pictures, not labels) and `--domdump --find Gemini` lists everything
whose text, title, alt or label mentions a word — how a control with no name
gets identified. `--trimscript` prints the exact JavaScript that gets injected,
so it can be `node --check`ed when a page starts rejecting it. To stop touching Google's pages: `"trimGmailChrome": false`.

## Accounts

The account picture in Google's header is hidden on purpose: inside an embedded
web view it does nothing useful, reporting *"Something went wrong."* whenever you
click it. Account switching lives in the **Account** menu instead:

* **Add Another Account…** (⇧⌘A) opens Google's add-account page as a panel in
  the window, and the new session lands in the next `u/N` slot.
* **Switch Account** (⌥⌘1…9) lists the addresses Gmail actually reports —
  `MailWatcher` learns which slot is which mailbox from the Atom feeds, so the
  menu says `you@example.com` rather than "Account 1".
* **Apply Current Account to Both Sources** keeps mail and calendar on the same
  account.

A merged *unread badge* across accounts is automatic — counts are summed per
mailbox, so an account appearing in two slots is not counted twice. A merged
*inbox* is not something an app can do: Gmail shows one mailbox at a time. The
Google-side answer is forwarding plus *Send mail as* (Settings → Accounts and
Import), or POP for the second account. Calendars merge the same way — add the
colleague's calendar under Settings → *Add by address* and one month view shows
both.


## Links

Links go to your browser, not into this window. What stays inside is deliberately small:
the surface you are in (`mail.google.com` or `calendar.google.com`), Google's sign-in
pages, and anything you list in `allowHosts`. A Drive file, a Docs link, an article in an
email, a target=`_blank` link — all of that opens in your default browser, which is the
only place it can look right anyway.

Sign-in popups are the exception that must stay: they need to keep the `window.opener`
link, so they open as a panel inside the window and close themselves.

## Several Google accounts

Click your avatar in Gmail or Calendar and choose **Add another account** — the sign-in
popup opens as a panel inside the window, and afterwards both accounts are live in the
same session, exactly as in a browser.

* **Mail notifications and the unread badge already merge across accounts.** The poller
  reads `u/0`, `u/1`, `u/2` and works out which are genuinely different mailboxes (Gmail
  answers an unused slot with the *same* mailbox, so counting slots would multiply the
  badge). One number on the envelope, one stream of banners, however many you are signed
  into. `mailAccountSlots` raises how many are polled.
* **A single merged Gmail inbox is not something a wrapper can do** — Google does not
  present two Google accounts as one inbox. If you want one list, do it Google-side, and
  this app needs no changes at all afterwards:
  * *Settings → Forwarding and POP/IMAP* on account B: **forward** everything to A
    (real-time, keeps labels' history), then on A add **Send mail as** B so replies go out
    from the right address. This is the closest thing to a true merged inbox.
  * Or *Settings → Accounts and Import → Check mail from other accounts* (POP3, pulls
    B's mail into A). A Workspace admin can disable POP, in which case use forwarding.
* **A merged calendar view is easy and real**: open calendar A, *Settings → Add calendar →
  By address* and add B's calendar address (in B: *Settings → [calendar] → Integrate
  calendar → Calendar address*). Both then live in one month view, and B's events behave
  like any other secondary calendar. Sharing B's calendar with A's address makes it appear
  under *Other calendars* without any address. *Settings → Import & Export* only
  handles one-off `.ics` files — imported events do not stay in sync.

## New-mail notifications

Gmail push arrives through a service worker, and WebKit gives third-party apps no push
provider, so the app reads Gmail instead — through the page's own signed-in session, every
60 s (`mailPollSeconds`):

1. **Per message** — `mail.google.com/mail/feed/atom`, giving sender and subject. Parsed
   with string matching, because Gmail's Trusted Types CSP forbids building a DOM.
2. **Count only** — falls back to the unread count Gmail writes in its title
   ("Inbox (3) - …"), so you still get told, just without who it is from.

`--smoke` prints which tier is live (`mailMode=per-message feed`). Toggle with
*Google Suite ▸ New Mail Notifications*; *File ▸ Check Mail Now* forces a poll.

**While the app is closed, nothing arrives.** That part genuinely needs Google's push or
an account in Apple's Mail app.

## Configuration

`~/.config/google-suite/config.json`, created on first launch (settings from the
old `~/.config/gcal-app/` are picked up automatically once):

```json
{
  "sources": [
    { "id": "mail", "label": "Mail", "url": "https://mail.google.com/mail/u/0/", "symbol": "envelope" },
    { "id": "calendar", "label": "Calendar",
      "url": "https://calendar.google.com/calendar/u/0/r/month", "symbol": "calendar" }
  ],
  "allowHosts": [],
  "openMeetInApp": false,
  "openLinksInBrowser": true,
  "splitLayout": false,
  "splitRatio": 0.5,
  "trimGmailChrome": true,
  "notificationsShim": true,
  "mailNotifications": true,
  "mailPollSeconds": 60,
  "mailAccountSlots": 3,
  "userAgent": null
}
```

* **sources** — what the rail shows. Each source carries the hosts that belong to it,
  derived from its URL; `hosts` overrides that.
* **openLinksInBrowser** — `true` (default): everything that is not the current surface or
  sign-in opens in your browser. `false` restores the older behaviour of keeping any host
  listed in `allowHosts` inside the window.
* **splitLayout** — start in split view rather than one surface at a time.
* **splitRatio** — how much of the window Mail gets in split view (0.2 … 0.8). Dragging the
  divider writes it.
* **trimGmailChrome** — inject the Gmail stylesheet described above.
* **allowHosts** — *extra* hosts that may stay in the window. Empty by default; it used to
  list Drive, Docs, Keep and `google.com`, which turned every link into a page in here.
* **openMeetInApp** — `false` (default) sends genuine Meet links to your browser. Google's
  silent warm-up requests to `meet.google.com/` and `/_meet/*` are never opened anywhere;
  they stay in-page. `true` joins calls inside the window and asks for camera/mic.
* **notificationsShim** — bridges in-page `Notification` calls (see limits). `false` to disable.
* **mailPollSeconds** — floored at 15.
* **mailAccountSlots** — how many signed-in Google accounts to poll (`u/0` …). Slots that
  are not signed in are recognised as duplicates of another slot and ignored.
* **userAgent** — override if Google complains about the browser at sign-in.

## Keyboard

| Keys | Action |
| --- | --- |
| `⌘1` / `⌘2` | Mail / Calendar |
| `⌘\` | side-by-side view on or off |
| `⌃⇥` / `⌃⇧⇥` | next / previous source |
| `⌘R` / `⌥⌘⇧R` | reload this source / reload both |
| `⌥⌘K` | check mail now |
| `⌥⌘1`…`⌥⌘9` | this source onto Google account N |
| `⇧⌘A` | add another Google account |
| `⌥⌘O` | open this page in your browser |
| `⌘,` | open the config file |

## Tests

```sh
./smoke.sh    # selftest, popup-layout probe, live chrome verdict, GUI smoke — each with its own watchdog
SKIP_SMOKE=1 ./smoke.sh    # offline half only
```

* `--selftest` — offline checks: source order, config recovery from malformed
  and legacy files, host policy against look-alike domains, Meet join-vs-warm-up
  classification, account URL rewriting, blank-popup handling, unread-count
  parsing, account-merge dedup (three slots, one mailbox, one badge), rail
  selection, tint and badges, watcher gating, menu shape, single/split geometry
  (including the hidden zero-width rail, native split traffic-light strip, full-width
  content with reduced height, restoration to the single-mode rail, and badges updated
  while hidden), the divider's hit strip, the trimming
  selectors and CSSOM/CSP workarounds, and that the popup panel stays
  constraint-free.
* `--domcheck` — the live verdict on both surfaces. It asserts that no visible
  Gemini/Studio launcher remains in Gmail, that the 56px Search mail control
  remains visible and hittable, and that Calendar's real text-bearing
  `Montharrow_drop_down` view button and Previous/Next controls are visible,
  hittable, in the viewport, and non-overlapping. It also clicks the real menu and
  checks Day/Week/Month choices. Needs a signed-in profile.
* `--no-trim` — diagnostic-only native comparison flag. It disables trimming for
  this process without changing the persisted config; combine with
  `--calendar --fullwidth --domdump` to measure Google's native controls.
* `--domcontrols` — diagnostic inventory for one requested surface, including
  computed visibility, signatures, and ancestry for icon-only header controls.
* `--smoke` — builds the real window and prints what it became: layout mode,
  selected source, rail visibility and width, content offset and width, whether
  content reclaims the full window, divider geometry, pages attached and visible,
  popup count, notification authorisation, which mail tier is live, the chrome
  (`titlebar=hidden fullSize=true toolbar=none`) and the icon the switcher draws,
  then each surface's final URL and title. Reaching
  `Inbox (1) - you@corp - Mail` is proof of a working session, not just a loaded
  page.
* `--popupprobe` — forces split mode, attaches a popup panel to the live window,
  prints root-coordinate frames for the actual close/minimize/zoom buttons, and fails
  if those buttons miss the native safe strip or overlap either web pane. It also retains
  the non-collapse check: adding constraints after the window is on screen once made
  AppKit re-derive the frame from the content view's fitting size, and a web view has no
  intrinsic size to derive one from.

CI (`.github/workflows/ci.yml`) runs on `macos-latest` and covers everything that
needs neither a window server nor a Google session: the build, `--selftest`,
`--trimscript | node --check` for both surfaces, the dependency-free DOM fixtures
(`tests/chrome-fixtures.js`, including zero-size menu and nested Gmail icon
adversaries), and a lint of the built bundle.
The live half cannot run there, since it would need your Google login — run
`--domcheck` yourself after a Google release, and `--domdump` when it complains.


## What is where

```
Sources/main.swift          entry point, argument parsing
Sources/AppDelegate.swift   lifecycle, notification delegate, smoke runner
Sources/AppWindow.swift     the window and its toolbar
Sources/RootController.swift rail + content, popup panels, account-wide reload
Sources/Sidebar.swift       icon rail and unread badge
Sources/WebPage.swift       one WKWebView: navigation policy, popups, downloads, JS panels
Sources/MailWatcher.swift   new-mail polling, both tiers, merged across accounts
Sources/GmailChrome.swift   the stylesheet that trims Gmail's rails, and the live check
Sources/Config.swift        config, host policy, Meet classification, user agent
Sources/Accounts.swift      ?authuser=N / /u/N/ rewriting for Google multi-login
Sources/Menus.swift         the menu bar
Sources/Notifier.swift      in-page Notification → native notification bridge
Sources/LaunchItems.swift   SMAppService login item
Sources/SelfTest.swift      offline checks
build.sh install.sh smoke.sh bin/gsuite
tools/make-icon.swift       generates Resources/AppIcon.icns from tools/google-g.png
```

## Icon

A white rounded tile with Google's four-colour **G** — the same shape Google's own app
icons use — generated by `swift tools/make-icon.swift` from the mark at
`ssl.gstatic.com/images/branding/product/1x/googleg_512dp.png`. It is Google's trademark:
fine for a personal build on your own machine, not something to distribute. The app also
sets `NSApp.applicationIconImage` at launch: `CFBundleIconFile` on its own was read by
Spotlight while ⌘-tab kept drawing the cached generic icon, and the running process
carrying its own icon settles that without waiting for any cache to expire.

## Limits, honestly

* **Calendar reminders still don't fire natively.** Same service-worker reason. Gmail is
  covered by the poller; Calendar is not — for reminders use Google Calendar Settings →
  General → Notification settings → **Email** and let Mail.app surface them.
* **Notifications stop when the app quits.** Enable *Launch at Login* to keep it running.
* **No offline mode**, and it needs a GUI session.
* **Not a CalDAV client.** Apple Calendar can stay installed for iCloud and friends.
* **Menu bar calendar, Spotlight, Siri and widgets still read Apple Calendar** — this is a
  window, not a system calendar.
* The in-page notification bridge (`Notifier.swift`) is best-effort: some pages notify
  through JS while open, and it forwards those. Gmail's own alerts are suppressed while the
  poller is working, so you don't get two banners for one message.
* Ad-hoc signed, built for one machine. If a copied bundle is quarantined:
  `xattr -d com.apple.quarantine "<path>/Google Suite.app"`.
* Not affiliated with Google; trademarks belong to Google LLC.
