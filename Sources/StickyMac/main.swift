import AppKit

// `StickyMac <command>` runs the CLI / MCP server; no arguments starts the app.
let args = Array(CommandLine.arguments.dropFirst())
if let cmd = args.first, CLI.commands.contains(cmd) {
    exit(CLI.run(args))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
