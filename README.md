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

* **Left rail** — Mail, then Calendar. Icon only; unread mail shows as a red badge on the
  envelope. `⌘1` / `⌘2`, or `⌃⇥` to cycle.
* **Toolbar** — Reload, and *Open in Browser* for when you need the real thing.
* No tabs, no address bar, no history menu. Two surfaces, not a browser.

Sign-in popups (`window.open`) appear as a panel over the content and close themselves
when the flow finishes; the page that opened them keeps its `window.opener` link, so
Google's popup can report back.

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
  "allowHosts": ["calendar.google.com", "mail.google.com", "google.com", "gstatic.com"],
  "openMeetInApp": false,
  "notificationsShim": true,
  "mailNotifications": true,
  "mailPollSeconds": 60,
  "userAgent": null
}
```

* **sources** — what the rail shows. An unknown host goes to your browser unless you list
  it in `allowHosts`.
* **openMeetInApp** — `false` (default) sends genuine Meet links to your browser. Google's
  silent warm-up requests to `meet.google.com/` and `/_meet/*` are never opened anywhere;
  they stay in-page. `true` joins calls inside the window and asks for camera/mic.
* **notificationsShim** — bridges in-page `Notification` calls (see limits). `false` to disable.
* **mailPollSeconds** — floored at 15.
* **userAgent** — override if Google complains about the browser at sign-in.

## Keyboard

| Keys | Action |
| --- | --- |
| `⌘1` / `⌘2` | Mail / Calendar |
| `⌃⇥` / `⌃⇧⇥` | next / previous source |
| `⌘R` / `⌥⌘⇧R` | reload this source / reload both |
| `⌥⌘K` | check mail now |
| `⌥⌘1`…`⌥⌘9` | this source onto Google account N |
| `⌥⌘O` | open this page in your browser |
| `⌘,` | open the config file |

## Tests

```sh
./smoke.sh          # SELFTEST (offline) then SMOKE (live), each with a watchdog
```

* `--selftest` — 77 offline checks: source order, config recovery from malformed and
  legacy files, host allow-list against look-alike domains, **Meet join-vs-warm-up
  classification**, account URL rewriting, blank-popup handling, unread-count parsing, rail
  selection and badges, watcher gating, menu shape.
* `--smoke` — builds the real window and prints what it became: layout (rail width, pages
  attached/visible, popups), notification authorization, which mail tier is live, the user
  agent Google saw, and each source's final URL and title. A run that reaches
  `Inbox (1) - you@corp - Mail` is proof of a working session, not just a loaded page.

Both need a logged-in GUI session.

## What is where

```
Sources/main.swift          entry point, argument parsing
Sources/AppDelegate.swift   lifecycle, notification delegate, smoke runner
Sources/AppWindow.swift     the window and its toolbar
Sources/RootController.swift rail + content, popup panels, account-wide reload
Sources/Sidebar.swift       icon rail and unread badge
Sources/WebPage.swift       one WKWebView: navigation policy, popups, downloads, JS panels
Sources/MailWatcher.swift   new-mail polling, both tiers
Sources/Config.swift        config, host policy, Meet classification, user agent
Sources/Accounts.swift      ?authuser=N / /u/N/ rewriting for Google multi-login
Sources/Menus.swift         the menu bar
Sources/Notifier.swift      in-page Notification → native notification bridge
Sources/LaunchItems.swift   SMAppService login item
Sources/SelfTest.swift      offline checks
build.sh install.sh smoke.sh bin/gcal
```

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
