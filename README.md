# gcal-app — "Google Suite" for Mac

One Dock icon, one window, two tabs: **Calendar** and **Mail**, both showing the real
Google web UI in a `WKWebView`. No Electron, no browser chrome, no Xcode project — one
`swiftc` invocation and a hand-written `Info.plist`.

It exists because the *Apple* Calendar/Mail path to Google leaves two holes that no
setting in Apple's apps can fill:

| | Apple Calendar / Mail | This app |
| --- | --- | --- |
| Add a Google Meet link to an event | ❌ FaceTime only | ✅ the web UI's own button |
| Open a colleague's calendar by typing their name | ❌ only calendars Google exports over CalDAV | ✅ whatever `calendar.google.com` can see |
| Gmail labels, filters, snooze, "Search everything" | partial | ✅ |

That is the whole pitch: it is not a better calendar, it is Google's calendar with a
window of its own.

## Install

```sh
cd ~/gitsky/gcal-app
./build.sh && ./install.sh
open -a 'Google Suite'          # or: bin/gcal
```

First launch asks you to **sign in**. Those cookies live in this app's own store
(`~/Library/WebKit/com.saattrupdan.google-suite`), not in Safari or Chrome, so it is one
sign-in per machine and it persists. The web view advertises itself as Safari
(`Config.suggestedUserAgent()`) precisely so Google does not reject it as an embedded web
view.

## Tests

```sh
./smoke.sh
```

Two stages, both with hard watchdogs so a wedged UI fails instead of hanging:

* `--selftest` — 50 offline checks: config defaults and malformed-file recovery, host
  allow-list (including look-alike domains), account-URL rewriting, tab
  add/close/select/wrap behaviour, the notification shim, menu shape.
* `--smoke` — builds the real window on screen and reports what it ended up as: window
  frame, toolbar item identifiers, tab-strip width, each tab's final URL and title, and
  the user agent Google saw. `SMOKE ok` means both pages navigated and reported a title.

Both stages need a logged-in GUI session, because that is what a window server is.

## What is where

```
Sources/main.swift          entry point, argument parsing
Sources/AppDelegate.swift   app lifecycle + the smoke runner
Sources/AppWindow.swift     the single window and its toolbar
Sources/TabsController.swift tab list, tab strip, toolbar items, tab menu actions
Sources/WebTab.swift        one WKWebView: navigation policy, popups, downloads, JS panels
Sources/Config.swift        ~/.config/gcal-app/config.json, host policy, user agent
Sources/Accounts.swift      ?authuser=N / /u/N/ rewriting for Google multi-login
Sources/Menus.swift         the menu bar
Sources/Notifier.swift      in-page Notification → native notification bridge
Sources/LaunchItems.swift   SMAppService login item
Sources/SelfTest.swift      offline checks
build.sh install.sh smoke.sh bin/gcal
```

## Configuration

`~/.config/gcal-app/config.json`, created on first launch:

```json
{
  "tabs": [
    { "label": "Calendar", "url": "https://calendar.google.com/calendar/u/0/r/month", "symbol": "calendar" },
    { "label": "Mail", "url": "https://mail.google.com/mail/u/0/", "symbol": "envelope" }
  ],
  "allowHosts": ["calendar.google.com", "mail.google.com", "google.com", "gstatic.com"],
  "openMeetInApp": false,
  "notificationsShim": true,
  "userAgent": null
}
```

* **tabs** — any URL, not just Google. An unknown host stays put unless you add it to
  `allowHosts`, in which case it loads in-app instead of bouncing to your browser.
* **openMeetInApp** — `false` (default) sends `meet.google.com` links to your browser,
  where camera permissions are already settled. `true` loads Meet inside a tab; the first
  call then asks for camera and microphone.
* **notificationsShim** — see the caveat below. Set `false` if it ever misbehaves.
* **userAgent** — set a string if Google complains about the browser during sign-in.

## Keyboard

| Keys | Action |
| --- | --- |
| `⌘1`…`⌘9` / `⌃⇥` | switch tab |
| `⌥⌘C` / `⌥⌘M` / `⌘T` | new Calendar tab / new Gmail tab / new tab at a URL |
| `⌘R` / `⇧⌘R` | reload / reload ignoring cache |
| `⌥⌘1`…`⌥⌘9` | this tab onto Google account N |
| `⌥⌘O` | open this page in your browser |
| `⌘W` | close tab (closes the window when one tab is left) |
| `⌘,` | open the config file |

## Limits, honestly

* **Reminders do not fire like Apple Calendar's.** WebKit has no service-worker push, and
  Google delivers Calendar reminders through exactly that. While a tab is open some
  in-page notifications are bridged to native ones (`Notifier.swift`), but nothing arrives
  when the app is closed. For reliable alerts: Google Calendar Settings → General →
  Notification settings → **Email**, and let Mail.app surface them.
* **No offline mode.** No window server, no app — it needs a GUI session.
* **It is not a CalDAV client.** Apple Calendar can stay installed for iCloud or other
  accounts; this window only shows what Google's own pages show.
* **Ad-hoc signed.** Built for one machine. If you copy the `.app` elsewhere and the
  browser quarantines it: `xattr -d com.apple.quarantine "<path>/Google Suite.app"`.
* **Menu-bar calendar, Spotlight, Siri, and widgets keep using Apple Calendar** — this app
  is a window, not a system calendar.
* Not affiliated with Google; trademarks belong to Google LLC.
