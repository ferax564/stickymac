Native macOS sticky notes that Claude Code and other MCP agents can read and write.

**Install:** download `StickyMac.zip`, unzip, and move `StickyMac.app` to Applications.
The app is not notarized, so the first time **right-click → Open** (or run `xattr -dr com.apple.quarantine /Applications/StickyMac.app`).
Or build from source: `git clone https://github.com/ferax564/stickymac && cd stickymac && ./build.sh --install`.

Requires macOS 14 Sonoma or later.

**Highlights**
- Global hotkeys: ⌃⌥N new note, ⌃⌥V note from clipboard, ⌃⌥F search
- Checklists, bullets, snooze, pin above full-screen apps, seven colors
- Optional Markdown copies in a folder of your choice
- Built-in MCP server and `stickymac` CLI for AI agents

See the [README](https://github.com/ferax564/stickymac#readme) for shortcuts and agent setup.
