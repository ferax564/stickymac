import AppKit
import SwiftUI

final class SearchState: ObservableObject {
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0
    @Published var notes: [NoteModel] = []

    var results: [NoteModel] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        let sorted = notes.sorted { $0.modified > $1.modified }
        guard !terms.isEmpty else { return Array(sorted.prefix(50)) }
        return Array(sorted.filter { n in
            let t = n.text.lowercased()
            return terms.allSatisfy { t.contains($0) }
        }.prefix(50))
    }
}

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// ⌃⌥F / ⌘K: a Spotlight-style finder across every note, including snoozed ones.
final class SearchController: NSObject, NSWindowDelegate {
    private let panel: SearchPanel
    private let state = SearchState()
    private let store: NoteStore
    private let reveal: (UUID) -> Void
    static let width: CGFloat = 560

    init(store: NoteStore, reveal: @escaping (UUID) -> Void) {
        self.store = store
        self.reveal = reveal
        panel = SearchPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                            styleMask: [.borderless], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let view = SearchView(state: state,
                              open: { [weak self] n in self?.open(n) },
                              close: { [weak self] in self?.hide() },
                              resize: { [weak self] rows in self?.resize(rows: rows) })
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        state.notes = store.notes
        state.query = ""
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: v.midX - Self.width / 2, y: v.maxY - v.height * 0.18))
        }
        resize(rows: state.results.count)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }

    private func open(_ note: NoteModel) {
        hide()
        reveal(note.id)
    }

    private func resize(rows: Int) {
        let h = 58 + (rows == 0 ? 44 : CGFloat(min(rows, 7)) * 50 + 8) + 26
        var f = panel.frame
        let top = f.maxY
        f.size = NSSize(width: Self.width, height: h)
        f.origin.y = top - h
        panel.setFrame(f, display: true)
        panel.invalidateShadow()
    }

    func windowDidResignKey(_ notification: Notification) { hide() }
}

struct SearchView: View {
    @ObservedObject var state: SearchState
    let open: (NoteModel) -> Void
    let close: () -> Void
    let resize: (Int) -> Void

    var body: some View {
        let results = state.results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                SearchField(text: $state.query,
                            onMove: { d in
                                guard !results.isEmpty else { return }
                                state.selection = (state.selection + d + results.count) % results.count
                            },
                            onSubmit: { if results.indices.contains(state.selection) { open(results[state.selection]) } },
                            onCancel: close)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            Divider().opacity(0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if results.isEmpty {
                            Text(state.notes.isEmpty ? "No notes yet" : "No notes match “\(state.query)”")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(height: 44)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, n in
                            SearchRow(note: n, query: state.query, selected: i == state.selection)
                                .id(n.id)
                                .contentShape(Rectangle())
                                .onTapGesture { open(n) }
                                .onHover { if $0 { state.selection = i } }
                        }
                    }
                    .padding(4)
                }
                .onChange(of: state.selection) { _, s in
                    if results.indices.contains(s) { proxy.scrollTo(results[s].id) }
                }
            }
            HStack(spacing: 14) {
                Text("↑↓ select")
                Text("↩ open")
                Text("esc close")
                Spacer()
                Text("\(results.count) note\(results.count == 1 ? "" : "s")")
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .frame(height: 26)
        }
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .onChange(of: results.count, initial: true) { _, c in resize(c) }
    }
}

struct SearchRow: View {
    @ObservedObject var note: NoteModel
    let query: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [note.color.top, note.color.bottom], startPoint: .top, endPoint: .bottom))
                .frame(width: 18, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 13.5, weight: .semibold, design: .rounded)).lineLimit(1)
                Text(snippet).font(.system(size: 11.5, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let until = note.snoozedUntil, note.isSnoozed {
                Label(Snooze.describe(until), systemImage: "moon.zzz")
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(.secondary)
            } else if note.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.25) : .clear))
    }

    /// The line that matches the query, or the second line of the note.
    private var snippet: String {
        let lines = note.text.split(whereSeparator: \.isNewline).map(String.init)
        let first = query.lowercased().split(separator: " ").first.map(String.init) ?? ""
        let hit = first.isEmpty ? nil : lines.dropFirst().first { $0.lowercased().contains(first) }
        return (hit ?? (lines.count > 1 ? lines[1] : "")).trimmingCharacters(in: .whitespaces)
    }
}

/// Plain NSTextField so arrow keys, Return and Esc can drive the result list.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.placeholderString = "Search notes"
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 20, weight: .regular)
        f.delegate = context.coordinator
        f.cell?.lineBreakMode = .byTruncatingTail
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text { f.stringValue = text }
        if f.window?.isKeyWindow == true, f.currentEditor() == nil {
            DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ p: SearchField) { parent = p }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1); return true
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
