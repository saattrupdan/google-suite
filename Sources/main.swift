import AppKit

// Entry point. Argument parsing happens here and nowhere else.
let app = NSApplication.shared
app.setActivationPolicy(.regular)

let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--url"), index + 1 < arguments.count {
    AppRuntime.shared.startURL = arguments[index + 1]
}
AppRuntime.shared.smokeMode = arguments.contains("--smoke")

if arguments.contains("--selftest") {
    exit(SelfTest.run())
}

AppRuntime.shared.config = Config.load()

let delegate = AppDelegate()
app.delegate = delegate
app.run()
