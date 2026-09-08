import AppKit

// Entry point. Argument parsing happens here and nowhere else.

// Nothing below needs AppKit, so it happens before the application exists:
// printing the JavaScript that goes into Google's pages. `node --check` on the
// output is the only way to catch a syntax error in a string built by
// interpolation, and CI has no window server to launch a window through.
if CommandLine.arguments.contains("--trimhelpers") {
    print(GmailChrome.helperSource)
    exit(0)
}
if CommandLine.arguments.contains("--trimscript") {
    print(GmailChrome.scriptSource(isMail: !CommandLine.arguments.contains("--calendar")))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let arguments = CommandLine.arguments
// A source to jump to. Written to the rendezvous file so the same path works on a
// cold start and when a running instance is merely activated.
if arguments.contains("--mail") { Reveal.request("mail") }
if arguments.contains("--calendar") { Reveal.request("calendar") }
AppRuntime.shared.smokeMode = arguments.contains("--smoke")

if arguments.contains("--selftest") {
    exit(SelfTest.run())
}

AppRuntime.shared.config = Config.load()
// Diagnostic only: compare Google's native DOM without trimming. This is an
// in-memory override and never writes the user's persisted configuration.
if arguments.contains("--no-trim") { AppRuntime.shared.config.trimGmailChrome = false }

let delegate = AppDelegate()
app.delegate = delegate
app.run()
