import SwiftUI
import AppKit

struct NoteActions {
    var delete: () -> Void
    var toggleCollapse: () -> Void
    var snooze: (Date) -> Void
}

struct NoteView: View {
    @ObservedObject var model: NoteModel
    let actions: NoteActions
    @State private var hovering = false
    @Environment(\.controlActiveState) private var activeState

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.collapsed {
                editor
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(colors: [model.color.top, model.color.bottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(model.color.isDark ? 0.12 : 0.55), lineWidth: 1))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .animation(.easeInOut(duration: 0.25), value: model.color)
    }

    // MARK: Header

    private var showControls: Bool { hovering || activeState == .key }

    private var header: some View {
        HStack(spacing: 6) {
            if model.collapsed {
                Text(model.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.color.ink.opacity(0.75))
                    .lineLimit(1)
                    .allowsHitTesting(false)
            } else if showControls {
                ForEach(NoteColor.allCases) { c in
                    ColorDot(color: c, selected: c == model.color) { model.color = c }
                }
                .transition(.opacity)
            }
            Spacer(minLength: 4)
            if showControls || model.pinned {
                HeaderButton(symbol: model.pinned ? "pin.fill" : "pin",
                             help: model.pinned ? "Unpin (float off)" : "Pin on top of all windows",
                             ink: model.color.ink, active: model.pinned) {
                    model.pinned.toggle()
                }
            }
            if showControls {
                HeaderButton(symbol: "moon.zzz", help: "Snooze: hide until later", ink: model.color.ink) {
                    let menu = NSMenu()
                    menu.addItem(NSMenuItem(title: "Hide Until…", action: nil, keyEquivalent: ""))
                    for o in Snooze.options() {
                        menu.addItem(ClosureMenuItem(o.title) { actions.snooze(o.date) })
                    }
                    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
                }
                HeaderButton(symbol: model.collapsed ? "chevron.down" : "chevron.up",
                             help: model.collapsed ? "Expand" : "Collapse (or double-click the bar)",
                             ink: model.color.ink) { actions.toggleCollapse() }
                HeaderButton(symbol: "xmark", help: "Delete note (⌘⇧T restores it)",
                             ink: model.color.ink) { actions.delete() }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: headerHeight)
        .background(
            ZStack {
                Color.black.opacity(model.color.isDark ? 0.18 : 0.045)
                WindowDragArea(onDoubleClick: actions.toggleCollapse)
            }
        )
    }

    // MARK: Editor

    private var editor: some View {
        NoteTextView(model: model)
            .padding(.horizontal, 2)
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("Write something…")
                        .font(.system(size: model.fontSize, design: .rounded))
                        .foregroundStyle(model.color.ink.opacity(0.35))
                        .padding(.leading, 15)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            HStack {
                Text(relative(model.modified, now: ctx.date))
                Spacer()
                Text(counts)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(model.color.ink.opacity(0.4))
            .padding(.horizontal, 12)
            .padding(.bottom, 7)
            .padding(.top, 2)
            .opacity(showControls ? 1 : 0)
        }
    }

    private var counts: String {
        let words = model.text.split { $0.isWhitespace || $0.isNewline }.count
        return words == 1 ? "1 word" : "\(words) words"
    }

    private func relative(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 45 { return "Edited just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "Edited " + f.localizedString(for: d, relativeTo: now)
    }
}

struct ColorDot: View {
    let color: NoteColor
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(LinearGradient(colors: [color.top, color.bottom], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: selected ? 2 : 0).padding(-1))
                .frame(width: 13, height: 13)
                .scaleEffect(hover ? 1.25 : 1)
                .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { hover = h } }
        .help(color.name)
    }
}

struct HeaderButton: View {
    let symbol: String
    let help: String
    let ink: Color
    var active = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(ink.opacity(active || hover ? 0.9 : 0.5))
                .frame(width: 20, height: 20)
                .background(Circle().fill(ink.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(help)
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { handler() }
}

/// An AppKit view that drags the borderless window and reports double-clicks.
struct WindowDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void

    final class DragView: NSView {
        var onDoubleClick: () -> Void = {}
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onDoubleClick() } else { window?.performDrag(with: event) }
        }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> DragView {
        let v = DragView()
        v.onDoubleClick = onDoubleClick
        return v
    }

    func updateNSView(_ v: DragView, context: Context) { v.onDoubleClick = onDoubleClick }
}
