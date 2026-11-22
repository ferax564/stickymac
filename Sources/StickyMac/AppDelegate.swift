import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = NoteStore()
    private(set) var controllers: [UUID: NoteWindowController] = [:]
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var notesHidden = false
    private let mirror = MarkdownMirror()
    private lazy var search = SearchController(store: store) { [weak self] id in self?.reveal(id) }
    private lazy var agentServer = AgentServer { [weak self] req in
        self?.handleAgentRequest(req) ?? ["ok": false, "error": "app is shutting down"]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyDefaults()
        buildMainMenu()
        buildStatusItem()
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey, id: 1) { [weak self] in
                self?.newNote(atMouse: true)
            },
            HotKey(keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey, id: 2) { [weak self] in
                self?.newNoteFromClipboard(atMouse: true)
            },
            HotKey(keyCode: kVK_ANSI_F, modifiers: controlKey | optionKey, id: 3) { [weak self] in
                self?.search.toggle()
            },
        ].compactMap { $0 }

        store.onSave = { [weak self] notes in self?.mirror.sync(notes) }
        store.load()
        store.notes.forEach { open($0, focus: false) }
        if store.notes.isEmpty { createWelcomeNote() }
        agentServer.start()

        RunLoop.main.add(Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.wakeDueNotes() }, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wakeDueNotes), name: NSWorkspace.didWakeNotification, object: nil)
    }

    /// 1.0.0 shipped with the bundle ID local.stickymac. Copy its settings to the new ID once.
    private func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard
        let doneKey = "migratedLegacyDefaults"
        guard !defaults.bool(forKey: doneKey), let legacy = UserDefaults(suiteName: "local.stickymac") else { return }
        for key in ["markdownFolder", "markdownManifest"] where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: doneKey)
    }

    @objc func wakeDueNotes() {
        for c in controllers.values where c.model.snoozedUntil != nil && !c.model.isSnoozed {
            c.wake(focus: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { store.saveNow() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showAll()
        return true
    }

    // MARK: Notes

    private func open(_ model: NoteModel, focus: Bool) {
        let c = NoteWindowController(model: model) { [weak self] c in
            self?.controllers[c.model.id] = nil
            self?.store.delete(c.model)
        }
        controllers[model.id] = c
        if model.snoozedUntil != nil && !model.isSnoozed { model.snoozedUntil = nil }
        if !model.isSnoozed { c.show(focus: focus) }
    }

    @objc func newNoteAction(_ sender: Any?) { newNote(atMouse: false) }

    @objc func newNoteFromClipboardAction(_ sender: Any?) { newNoteFromClipboard(atMouse: false) }

    /// ⌃⌥V: drop whatever text is on the clipboard into a fresh note.
    func newNoteFromClipboard(atMouse: Bool) {
        guard let raw = NSPasteboard.general.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        let text = Checklist.fromMarkdown(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        newNote(atMouse: atMouse, text: text, size: fittedSize(for: text))
    }

    /// A note size that roughly fits the text.
    func fittedSize(for text: String) -> CGSize {
        let lines = text.components(separatedBy: "\n").count + text.count / 34
        return CGSize(width: 280, height: CGFloat(min(max(160, lines * 21 + 80), 440)))
    }

    /// New notes cycle through colors so a wall of notes looks lively.
    var nextColor: NoteColor {
        let colors = NoteColor.allCases.filter { $0 != .graphite }
        return colors[store.notes.count % colors.count]
    }

    @discardableResult
    func addNote(text: String, color: NoteColor, frame: CGRect, focus: Bool) -> NoteModel {
        let model = NoteModel(text: text, color: color, frame: frame)
        model.wantsFocus = focus
        store.add(model)
        notesHidden = false
        open(model, focus: focus)
        if !focus { controllers[model.id]?.window.orderFrontRegardless() }
        return model
    }

    func newNote(atMouse: Bool, text: String = "", size: CGSize = CGSize(width: 260, height: 240)) {
        var origin: CGPoint
        if !atMouse, let key = focusedController {
            origin = CGPoint(x: key.window.frame.minX + 28, y: key.window.frame.maxY - 28 - size.height)
        } else {
            let m = NSEvent.mouseLocation
            origin = CGPoint(x: m.x - size.width / 2, y: m.y - size.height + 20)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let v = screen.visibleFrame
            origin.x = min(max(origin.x, v.minX + 8), v.maxX - size.width - 8)
            origin.y = min(max(origin.y, v.minY + 8), v.maxY - size.height - 8)
        }
        addNote(text: text, color: nextColor, frame: CGRect(origin: origin, size: size), focus: true)
    }

    private func createWelcomeNote() {
        guard let v = NSScreen.main?.visibleFrame else { return }
        let text = """
        👋 Welcome to StickyMac!

        • ⌃⌥N anywhere → new note at your cursor
        • ⌃⌥V → new note from the clipboard
        • ⌃⌥F → search all notes
        ☐ Type [] and a space for a checklist
        ☑ Click a box to tick it off
        • 💤 in the bar snoozes a note until later
        • Drag the top bar to move, edges to resize
        • Double-click the bar to collapse
        • Hover for colors · 📌 floats on top
        • ⌘= / ⌘- change text size
        • ⌘W deletes, ⌘⇧T brings it back

        Everything saves automatically.
        """
        let model = NoteModel(text: text, color: .lemon,
                              frame: CGRect(x: v.maxX - 340, y: v.maxY - 420, width: 300, height: 380))
        store.add(model)
        open(model, focus: false)
    }

    private var focusedController: NoteWindowController? {
        (NSApp.keyWindow as? NoteWindow)?.controller
    }

    @objc func deleteFocused(_ sender: Any?) { focusedController?.delete() }

    @objc func restoreDeleted(_ sender: Any?) {
        guard let m = store.popTrash() else { NSSound.beep(); return }
        notesHidden = false
        open(m, focus: true)
    }

    @objc func setColor(_ sender: NSMenuItem) {
        guard let c = focusedController else { return }
        c.model.color = NoteColor.allCases[sender.tag]
    }

    @objc func snoozeFocused(_ sender: NSMenuItem) {
        guard let c = focusedController else { return }
        c.snooze(until: Snooze.options()[sender.tag].date)
    }

    @objc func exportFocused(_ sender: Any?) {
        guard let note = focusedController?.model else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MarkdownMirror.fileName(for: note, unique: false)
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try MarkdownMirror.markdown(for: note).write(to: url, atomically: true, encoding: .utf8) }
        catch { NSAlert(error: error).runModal() }
    }

    @objc func chooseMarkdownFolder(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Notes Here"
        panel.message = "StickyMac will keep a Markdown (.md) copy of every note in this folder. Pick a folder in iCloud Drive to have them on all your devices."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mirror.folder = url
        mirror.sync(store.notes)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc func stopMarkdownFolder(_ sender: Any?) { mirror.folder = nil }

    @objc func togglePin(_ sender: Any?) { focusedController?.model.pinned.toggle() }
    @objc func toggleCollapse(_ sender: Any?) { focusedController?.toggleCollapse() }
    @objc func biggerText(_ sender: Any?) { adjustFont(by: 1) }
    @objc func smallerText(_ sender: Any?) { adjustFont(by: -1) }
    @objc func resetText(_ sender: Any?) { focusedController?.model.fontSize = 15 }

    private func adjustFont(by d: Double) {
        guard let m = focusedController?.model else { return }
        m.fontSize = min(max(m.fontSize + d, 10), 36)
    }

    @objc func showAll() {
        notesHidden = false
        NSApp.activate(ignoringOtherApps: true)
        controllers.values.filter { !$0.model.isSnoozed }.forEach { $0.window.orderFront(nil) }
    }

    @objc func hideAll() {
        notesHidden = true
        controllers.values.forEach { $0.window.orderOut(nil) }
    }

    @objc func toggleHidden() { notesHidden ? showAll() : hideAll() }

    @objc func arrangeAll() {
        guard let v = NSScreen.main?.visibleFrame else { return }
        let ordered = store.notes.filter { !$0.isSnoozed }.compactMap { controllers[$0.id] }
        var x = v.minX + 20, y = v.maxY - 20, rowH: CGFloat = 0
        for c in ordered {
            let f = c.window.frame
            if x + f.width > v.maxX - 20 { x = v.minX + 20; y -= rowH + 16; rowH = 0 }
            let nf = CGRect(x: x, y: y - f.height, width: f.width, height: f.height)
            c.window.animator().setFrame(nf, display: true)
            c.window.orderFront(nil)
            x += f.width + 16
            rowH = max(rowH, f.height)
        }
        notesHidden = false
    }

    @objc func focusNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        reveal(id)
    }

    @objc func searchAction(_ sender: Any?) { search.show() }

    func reveal(_ id: UUID) {
        guard let c = controllers[id] else { return }
        notesHidden = false
        if c.model.collapsed { c.toggleCollapse() }
        if c.model.snoozedUntil != nil { c.wake(focus: true) } else { c.show(focus: true) }
    }

    @objc func toggleLoginItem(_ sender: Any?) {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change Launch at Login"
            a.informativeText = error.localizedDescription + "\n\nTip: move StickyMac.app to /Applications first."
            a.runModal()
        }
    }

    @objc func revealData(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    // MARK: Menus

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "StickyMac")
            b.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt every time it opens so the note list and toggles are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        menu.removeAllItems()
        let new = item("New Note", #selector(newNoteAction(_:)), "")
        new.toolTip = "Global shortcut: ⌃⌥N"
        menu.addItem(new)
        let clip = item("New Note from Clipboard", #selector(newNoteFromClipboardAction(_:)), "")
        clip.toolTip = "Global shortcut: ⌃⌥V"
        menu.addItem(clip)
        let find = item("Search Notes…", #selector(searchAction(_:)), "")
        find.toolTip = "Global shortcut: ⌃⌥F"
        menu.addItem(find)
        menu.addItem(item(notesHidden ? "Show Notes" : "Hide Notes", #selector(toggleHidden), ""))
        menu.addItem(item("Arrange Notes", #selector(arrangeAll), ""))
        let restore = item("Restore Deleted Note", #selector(restoreDeleted(_:)), "")
        restore.isEnabled = !store.trash.isEmpty
        menu.addItem(restore)

        if !store.notes.isEmpty {
            menu.addItem(.separator())
            for n in store.notes.sorted(by: { $0.modified > $1.modified }).prefix(12) {
                let title = n.isSnoozed ? "💤 \(n.title) — until \(Snooze.describe(n.snoozedUntil!))" : n.title
                let mi = item(title, #selector(focusNote(_:)), "")
                mi.representedObject = n.id
                mi.image = swatch(n.color)
                menu.addItem(mi)
            }
        }

        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLoginItem(_:)), "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if let folder = mirror.folder {
            let md = item("Markdown Copies: \(folder.lastPathComponent)", #selector(chooseMarkdownFolder(_:)), "")
            md.state = .on
            md.toolTip = folder.path + " (click to change)"
            menu.addItem(md)
            menu.addItem(item("Stop Saving Markdown Copies", #selector(stopMarkdownFolder(_:)), ""))
        } else {
            menu.addItem(item("Save Markdown Copies to Folder…", #selector(chooseMarkdownFolder(_:)), ""))
        }
        menu.addItem(item("Show Notes File in Finder", #selector(revealData(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit StickyMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func swatch(_ c: NoteColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            NSColor(c.bottom).setFill()
            NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()
            return true
        }
    }

    private func item(_ title: String, _ sel: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = self
        return i
    }

    /// Accessory apps show no menu bar, but key equivalents still route through
    /// the main menu — that's what makes ⌘C/⌘V/⌘Z work inside notes.
    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Hide Notes", action: #selector(hideAll), keyEquivalent: "h"))
        appMenu.items.last?.target = self
        appMenu.addItem(NSMenuItem(title: "Quit StickyMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        addSubmenu(appMenu, "StickyMac", to: main)

        let file = NSMenu(title: "File")
        file.addItem(item("New Note", #selector(newNoteAction(_:)), "n"))
        file.addItem(item("New Note from Clipboard", #selector(newNoteFromClipboardAction(_:)), "v", [.command, .shift]))
        file.addItem(item("Search Notes…", #selector(searchAction(_:)), "k"))
        file.addItem(item("Export Note as Markdown…", #selector(exportFocused(_:)), "e"))
        file.addItem(item("Delete Note", #selector(deleteFocused(_:)), "w"))
        file.addItem(item("Restore Deleted Note", #selector(restoreDeleted(_:)), "t", [.command, .shift]))
        addSubmenu(file, "File", to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f"))
        edit.items.last?.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        addSubmenu(edit, "Edit", to: main)

        let note = NSMenu(title: "Note")
        for (i, c) in NoteColor.allCases.enumerated() {
            let mi = item(c.name, #selector(setColor(_:)), "\(i + 1)")
            mi.tag = i
            note.addItem(mi)
        }
        note.addItem(.separator())
        let checklist = NSMenuItem(title: "Checklist", action: #selector(NoteNSTextView.toggleChecklist(_:)), keyEquivalent: "l")
        checklist.keyEquivalentModifierMask = [.command, .shift]
        note.addItem(checklist)
        let done = NSMenuItem(title: "Check / Uncheck", action: #selector(NoteNSTextView.toggleDone(_:)), keyEquivalent: "u")
        done.keyEquivalentModifierMask = [.command, .shift]
        note.addItem(done)
        note.addItem(.separator())
        note.addItem(item("Pin on Top", #selector(togglePin(_:)), "p", [.command, .shift]))
        note.addItem(item("Collapse / Expand", #selector(toggleCollapse(_:)), "m"))
        let snoozeMenu = NSMenu(title: "Snooze")
        for (i, o) in Snooze.options().enumerated() {
            let mi = item(o.title, #selector(snoozeFocused(_:)), "")
            mi.tag = i
            snoozeMenu.addItem(mi)
        }
        addSubmenu(snoozeMenu, "Snooze", to: note)
        note.addItem(.separator())
        note.addItem(item("Bigger Text", #selector(biggerText(_:)), "="))
        note.addItem(item("Smaller Text", #selector(smallerText(_:)), "-"))
        note.addItem(item("Actual Size", #selector(resetText(_:)), "0"))
        addSubmenu(note, "Note", to: main)

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ menu: NSMenu, _ title: String, to main: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }
}
