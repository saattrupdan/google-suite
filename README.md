# gcal-app — "Google Suite" for Mac

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
cd ~/gitsky/gcal-app
./build.sh && ./install.sh
open "/Applications/Google Suite.app"     # or: bin/gcal
```

Sign in on first launch. Those cookies belong to this app
(`~/Library/WebKit/com.saattrupdan.google-suite`), not to Safari or Chrome — one sign-in,
then it persists. The web view identifies itself as Safari (`Config.suggestedUserAgent()`)
so Google does not reject it as an embedded web view.

## Interface

* **No title bar.** The content runs to the top of the window and the traffic lights float
  over the rail; drag the window by the rail or the divider. There is no toolbar either —
  everything it could have held is in the menu bar, or gone.
* **Left rail** — Mail, then Calendar. Icon only; the source you are looking at is
  **blue**, the other one grey, and unread mail shows as a red badge on the envelope.
  `⌘1` / `⌘2`, or `⌃⇥` to cycle.
* **Side by side** (`⌘\`) — Mail and Calendar split the window evenly, both live at once.
  Worth it on a large monitor; off by default. In split view both rail icons are blue,
  because both are shown.
* No tabs, no address bar, no back/forward. Two surfaces, not a browser.

Sign-in popups (`window.open`) appear as a panel over the content and close themselves
when the flow finishes; the page that opened them keeps its `window.opener` link, so
Google's popup can report back.

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

`~/.config/gcal-app/config.json`, created on first launch:

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
| `⌥⌘O` | open this page in your browser |
| `⌘,` | open the config file |

## Tests

```sh
./smoke.sh          # SELFTEST, then the popup layout stage, then SMOKE — each with a watchdog
```

* `--selftest` — 116 offline checks: source order, config recovery from malformed and
  legacy files, host allow-list against look-alike domains, **Meet join-vs-warm-up
  classification**, account URL rewriting, blank-popup handling, unread-count parsing,
  **account-merge dedup** (three slots, one mailbox, one badge), rail selection, tint and
  badges, watcher gating, menu shape, and that the popup panel stays constraint-free.
* `--smoke` — builds the real window and prints what it became: layout (rail width, pages
  attached/visible, popups), notification authorization, which mail tier is live, the user
  the window chrome (`titlebar=hidden fullSize=true toolbar=none`) and the icon the
  switcher will draw, then each source's final URL and title. A run that reaches
  `Inbox (1) - you@corp - Mail` is proof of a working session, not just a loaded page.
* `--popupprobe` — attaches a popup panel to the live window and fails if the window
  shrinks. It exists because *"add another account"* once collapsed the window to a title
  bar and a close button: adding constraints after the window is on screen makes AppKit
  re-derive the window frame from the content view's fitting size, and a web view has no
  intrinsic size to derive one from.

Both need a logged-in GUI session.

## What is where

```
Sources/main.swift          entry point, argument parsing
Sources/AppDelegate.swift   lifecycle, notification delegate, smoke runner
Sources/AppWindow.swift     the window and its toolbar
Sources/RootController.swift rail + content, popup panels, account-wide reload
Sources/Sidebar.swift       icon rail and unread badge
Sources/WebPage.swift       one WKWebView: navigation policy, popups, downloads, JS panels
Sources/MailWatcher.swift   new-mail polling, both tiers, merged across accounts
Sources/Config.swift        config, host policy, Meet classification, user agent
Sources/Accounts.swift      ?authuser=N / /u/N/ rewriting for Google multi-login
Sources/Menus.swift         the menu bar
Sources/Notifier.swift      in-page Notification → native notification bridge
Sources/LaunchItems.swift   SMAppService login item
Sources/SelfTest.swift      offline checks
build.sh install.sh smoke.sh bin/gcal
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
