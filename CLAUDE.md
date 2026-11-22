# StickyMac

Native macOS sticky notes app (AppKit + SwiftUI, SwiftPM, no dependencies, macOS 14+).

## Commands

- Build: `swift build -c release`
- Build the .app: `./build.sh` (output: `build/StickyMac.app`)
- Install + relaunch: `./build.sh --install` (copies to /Applications)
- There is no test suite or linter; "verified" means it builds with no warnings and the behavior was exercised.

## Verifying changes

Drive the running app through its own API instead of synthesizing keystrokes
(simulated keys go to whatever app the user has focused):

```sh
BIN=/Applications/StickyMac.app/Contents/MacOS/StickyMac
$BIN new "test"; $BIN list; $BIN append <id> "- [ ] x"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | $BIN mcp
```

Notes live in `~/Library/Application Support/StickyMac/notes.json` — that is the user's real data.
Back it up before experiments and remove test notes afterwards.

## Architecture

- One binary: no args → menu bar app; `mcp|new|list|append` → CLI (`main.swift`).
- The app serves newline-delimited JSON on `~/Library/Application Support/StickyMac/agent.sock`
  (`AgentServer.swift`); requests run on the main thread against live `NoteModel`s, so
  the CLI/MCP never writes `notes.json` directly.
- Checklists are stored as plain text with `☐ ` / `☑ ` / `• ` prefixes
  (`Checklist` in `NoteTextView.swift`); the agent API and Markdown export convert to/from `- [ ]`.
- New `NoteRecord` fields must be optional so old `notes.json` files still decode.
- Bump the version in both `build.sh` (Info.plist) and `CLI.swift` (MCP serverInfo).
