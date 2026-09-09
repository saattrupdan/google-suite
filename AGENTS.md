# Google Suite

Google Suite is a native macOS AppKit/WebKit wrapper for Google Mail and Google
Calendar. It presents the two Google surfaces in one window and is intentionally not a
general-purpose browser: do not add tabs, an address bar, or generic new-tab behavior.

## Stack

- Swift 5, compiled directly with `swiftc` from the macOS Command Line Tools.
- AppKit, WebKit, UserNotifications, and ServiceManagement system frameworks.
- Bash scripts for building, installing, and smoke testing.
- Dependency-free JavaScript fixtures run with Node in CI.
- Arm64 macOS 13 or newer. There is no Xcode project, Swift package, or external
  package dependency.

## Layout

- `Sources/main.swift`: entry point and command-line argument parsing.
- `Sources/AppDelegate.swift`: lifecycle and diagnostic runners.
- `Sources/RootController.swift`: source rail, page layout, and popup panels.
- `Sources/WebPage.swift`: WKWebView setup, navigation, popups, and downloads.
- `Sources/GmailChrome.swift`: injected chrome-trimming code and live checks.
- `Sources/Config.swift`: persisted settings, host policy, and user agent.
- `Sources/MailWatcher.swift`: multi-account unread polling.
- `Sources/SelfTest.swift`: offline regression checks.
- `tests/chrome-fixtures.js`: dependency-free DOM fixtures for injected JavaScript.
- `build.sh`, `install.sh`, `smoke.sh`: build, installation, and test entry points.

See the README's **What is where** section for the remaining source-file ownership.

## Build and install

Run from the repository root on macOS:

```sh
./build.sh
./install.sh
open "/Applications/Google Suite.app"
```

Use `./build.sh --clean` when stale output is suspected. The build creates and
ad-hoc-signs `Google Suite.app`; signing is required for WebKit's helper processes.
`install.sh` copies the bundle to `/Applications` and registers it with
LaunchServices.

## Testing

For a quick offline check after building:

```sh
./build.sh
SKIP_SMOKE=1 ./smoke.sh
```

For the full local suite:

```sh
./smoke.sh
```

The full suite needs a GUI session, internet access, and a signed-in Google profile. It
runs popup layout, live DOM, and real-page smoke checks. Each stage has its own watchdog
because macOS has no `timeout` command.

CI runs only checks that need neither a window server nor a Google session: the build,
`--selftest`, JavaScript syntax checks, `tests/chrome-fixtures.js`, and bundle linting.
Keep `.github/workflows/ci.yml` authoritative for the exact commands.

After changing `GmailChrome.swift`, run the signed-in `--domcheck`. If Google changed
its markup, use `--domcheck --why`, `--domdump`, and `--domcontrols` to diagnose the
live page before changing selectors.

## Conventions

- Keep the project dependency-free unless the requested feature explicitly requires a
  larger architectural change.
- Use Conventional Commit subjects, matching the existing `fix:`, `feat:`, and
  `chore:` history.
- Put offline Swift regressions in `Sources/SelfTest.swift`; put injected-DOM cases in
  `tests/chrome-fixtures.js`.
- Update `README.md` with user-visible behavior, configuration, or diagnostic changes.
- Keep Markdown prose at no more than 88 characters per line.

## Design invariants

- All pages must share `WKWebsiteDataStore.default()`. Separate or ephemeral stores
  break Google's multi-account `?authuser=N` session.
- A sign-in popup must adopt the exact `WKWebViewConfiguration` supplied to
  `createWebViewWith`. Replacing it loses `window.opener`, so login cannot report back.
- Treat `about:blank` and other hostless popup URLs as in-app placeholders. Never send
  them to `NSWorkspace` or the default browser.
- Construct each page's WKWebView before `loadView`; background pages may be used before
  they have ever been selected.
- Keep popup panels constraint-free. Adding Auto Layout constraints to the live window
  hierarchy can make AppKit resize the window to a web view's zero fitting size.
- `evaluateJavaScript` does not await Promises. Store asynchronous results on a global
  and poll them with a later plain evaluation.
- Gmail enforces Trusted Types. Parse injected HTML/XML with controlled string handling,
  not `DOMParser`.
- A handed-over popup configuration cannot accept a new document-start user script.
  Re-inject required scripts with `evaluateJavaScript` from `didFinish`.

## Generated and local state

- Do not edit `Google Suite.app`, its generated `Info.plist`, or `.build` output.
- `Resources/AppIcon.icns` and `tools/AppIcon.iconset/` are generated but checked in.
  Regenerate them through `tools/make-icon.swift` when changing the source icon.
- User settings live in `~/.config/google-suite/config.json`; WebKit cookies and session
  data live under `~/Library/WebKit/com.saattrupdan.google-suite`. Never add either to
  tests or commits.
- Google markup is not stable. Prefer roles and accessible labels over obfuscated class
  names, and keep the live DOM checks aligned with every selector change.
