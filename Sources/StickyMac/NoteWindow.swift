import AppKit
import SwiftUI
import Combine

let headerHeight: CGFloat = 34

final class NoteWindow: NSWindow {
    weak var controller: NoteWindowController?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class NoteWindowController: NSObject, NSWindowDelegate {
    let model: NoteModel
    let window: NoteWindow
    private var subs = Set<AnyCancellable>()
    private let onDelete: (NoteWindowController) -> Void
    private var animating = false

    init(model: NoteModel, onDelete: @escaping (NoteWindowController) -> Void) {
        self.model = model
        self.onDelete = onDelete
        let frame = NoteWindowController.visibleFrame(for: model)
        window = NoteWindow(contentRect: frame, styleMask: [.borderless, .resizable],
                            backing: .buffered, defer: false)
        super.init()

        window.controller = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 180, height: model.collapsed ? headerHeight : 120)
        if model.collapsed { window.maxSize = NSSize(width: 4000, height: headerHeight) }

        let actions = NoteActions(
            delete: { [weak self] in self?.delete() },
            toggleCollapse: { [weak self] in self?.toggleCollapse() }
        )
        let host = NSHostingView(rootView: NoteView(model: model, actions: actions))
        host.sizingOptions = []  // the window decides its size, not SwiftUI
        window.contentView = host

        model.$pinned
            .sink { [weak self] pinned in self?.applyPinned(pinned) }
            .store(in: &subs)
    }

    static func visibleFrame(for model: NoteModel) -> CGRect {
        var f = model.frame
        if model.collapsed { f.size.height = headerHeight }
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(f.insetBy(dx: 40, dy: 10)) }
        if !onScreen, let s = NSScreen.main?.visibleFrame {
            f.origin = CGPoint(x: s.midX - f.width / 2, y: s.midY - f.height / 2)
        }
        return f
    }

    func show(focus: Bool) {
        if focus {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        window.invalidateShadow()
    }

    private func applyPinned(_ pinned: Bool) {
        window.level = pinned ? .floating : .normal
        window.collectionBehavior = pinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.managed, .fullScreenAuxiliary]
    }

    func toggleCollapse() {
        var f = window.frame
        let top = f.maxY
        if model.collapsed {
            f.size.height = max(model.expandedHeight, 120)
            window.maxSize = NSSize(width: 4000, height: 4000)
            window.minSize = NSSize(width: 180, height: 120)
        } else {
            model.expandedHeight = f.height
            f.size.height = headerHeight
            window.minSize = NSSize(width: 180, height: headerHeight)
        }
        f.origin.y = top - f.height
        let collapsing = !model.collapsed
        animating = true
        if !collapsing { model.collapsed = false }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(f, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.animating = false
            if collapsing {
                self.model.collapsed = true
                self.window.maxSize = NSSize(width: 4000, height: headerHeight)
            }
            self.model.frame = self.window.frame
            self.window.invalidateShadow()
        })
    }

    func delete() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.window.orderOut(nil)
            self.onDelete(self)
        })
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) { syncFrame() }
    func windowDidResize(_ notification: Notification) {
        syncFrame()
        window.invalidateShadow()
    }

    private func syncFrame() {
        guard !animating else { return }
        model.frame = window.frame
        if !model.collapsed { model.expandedHeight = window.frame.height }
        model.objectWillChange.send()
    }
}
