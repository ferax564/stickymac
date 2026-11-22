import SwiftUI
import AppKit

/// Checklists are stored as plain Unicode so notes stay plain text.
enum Checklist {
    static let open = "☐ "
    static let done = "☑ "
    static let bullet = "• "
    static let markers = [open, done, bullet]
    static let openChar: unichar = 0x2610
    static let doneChar: unichar = 0x2611

    /// Typed at the start of a line and followed by a space, these become list markers.
    static let shortcuts: [String: String] = [
        "[]": open, "[ ]": open, "-[]": open, "- []": open, "- [ ]": open,
        "[x]": done, "- [x]": done,
        "-": bullet, "*": bullet,
    ]

    static func isCheck(_ line: String) -> Bool { line.hasPrefix(open) || line.hasPrefix(done) }

    /// Markdown task lists and bullets → our markers (used for pasted/captured text).
    static func fromMarkdown(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            for (md, mark) in [("- [ ] ", open), ("* [ ] ", open), ("- [x] ", done), ("- [X] ", done), ("* [x] ", done)]
            where line.hasPrefix(md) { return mark + line.dropFirst(md.count) }
            return line
        }.joined(separator: "\n")
    }

    /// Our markers → Markdown.
    static func toMarkdown(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line -> String in
            if line.hasPrefix(open) { return "- [ ] " + line.dropFirst(2) }
            if line.hasPrefix(done) { return "- [x] " + line.dropFirst(2) }
            if line.hasPrefix(bullet) { return "- " + line.dropFirst(2) }
            return line
        }.joined(separator: "\n")
    }
}

final class NoteNSTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let idx = checkboxIndex(at: p) {
            let s = string as NSString
            let toggled = s.character(at: idx) == Checklist.openChar ? "☑" : "☐"
            replace(NSRange(location: idx, length: 1), with: toggled)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let lm = layoutManager, let tc = textContainer else { return }
        let s = string as NSString
        s.enumerateSubstrings(in: NSRange(location: 0, length: s.length), options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
            guard r.length > 0 else { return }
            let c = s.character(at: r.location)
            guard c == Checklist.openChar || c == Checklist.doneChar else { return }
            let g = lm.glyphRange(forCharacterRange: NSRange(location: r.location, length: 1), actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: g, in: tc)
            rect.origin.x += self.textContainerOrigin.x
            rect.origin.y += self.textContainerOrigin.y
            self.addCursorRect(rect, cursor: .pointingHand)
        }
    }

    /// Index of a ☐/☑ at the start of a line under the point, if any.
    private func checkboxIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let pt = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let g = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: nil)
        guard g < lm.numberOfGlyphs else { return nil }
        let rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).insetBy(dx: -3, dy: -2)
        guard rect.contains(pt) else { return nil }
        let ci = lm.characterIndexForGlyph(at: g)
        let s = string as NSString
        guard ci < s.length else { return nil }
        let c = s.character(at: ci)
        guard c == Checklist.openChar || c == Checklist.doneChar else { return nil }
        return s.lineRange(for: NSRange(location: ci, length: 0)).location == ci ? ci : nil
    }

    /// Undoable replacement that notifies the delegate like typing does.
    func replace(_ range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    private func transformSelectedLines(_ f: ([String]) -> [String]) {
        let s = string as NSString
        let block = s.lineRange(for: selectedRange())
        var text = s.substring(with: block)
        let endsNL = text.hasSuffix("\n")
        if endsNL { text.removeLast() }
        var out = f(text.components(separatedBy: "\n")).joined(separator: "\n")
        if endsNL { out += "\n" }
        replace(block, with: out)
        setSelectedRange(NSRange(location: block.location + (out as NSString).length - (endsNL ? 1 : 0), length: 0))
    }

    /// ⌘⇧L: turn the selected lines into a checklist, or back into plain lines.
    @objc func toggleChecklist(_ sender: Any?) {
        transformSelectedLines { lines in
            if lines.allSatisfy(Checklist.isCheck) { return lines.map { String($0.dropFirst(2)) } }
            return lines.map { line in
                if Checklist.isCheck(line) { return line }
                let body = line.hasPrefix(Checklist.bullet) ? String(line.dropFirst(2)) : line
                return Checklist.open + body
            }
        }
    }

    /// ⌘⇧U: check or uncheck the selected checklist items.
    @objc func toggleDone(_ sender: Any?) {
        transformSelectedLines { lines in
            lines.map { line in
                if line.hasPrefix(Checklist.open) { return Checklist.done + line.dropFirst(2) }
                if line.hasPrefix(Checklist.done) { return Checklist.open + line.dropFirst(2) }
                return line
            }
        }
    }
}

struct NoteTextView: NSViewRepresentable {
    @ObservedObject var model: NoteModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        let tv = NoteNSTextView(frame: .zero)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 8, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.string = model.text
        tv.delegate = context.coordinator
        scroll.documentView = tv
        context.coordinator.restyle(tv, force: true)

        if model.wantsFocus {
            model.wantsFocus = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NoteNSTextView else { return }
        context.coordinator.model = model
        if tv.string != model.text { tv.string = model.text }
        context.coordinator.restyle(tv)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var model: NoteModel
        private var lastStyleKey = ""

        init(model: NoteModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NoteNSTextView else { return }
            if model.text != tv.string { model.text = tv.string }
            restyle(tv, force: true)
        }

        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            // "[] " / "- [ ] " / "- " at the start of a line become ☐ / •
            guard replacementString == " ", range.length == 0, let tv = tv as? NoteNSTextView else { return true }
            let s = tv.string as NSString
            let line = s.lineRange(for: NSRange(location: range.location, length: 0))
            let before = s.substring(with: NSRange(location: line.location, length: range.location - line.location))
            guard let mark = Checklist.shortcuts[before] else { return true }
            tv.replace(NSRange(location: line.location, length: (before as NSString).length), with: mark)
            return false
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.insertNewline(_:)), let tv = tv as? NoteNSTextView else { return false }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return false }
            let s = tv.string as NSString
            let line = s.lineRange(for: NSRange(location: sel.location, length: 0))
            let text = s.substring(with: line).trimmingCharacters(in: .newlines)
            guard let prefix = Checklist.markers.first(where: { text.hasPrefix($0) }),
                  sel.location >= line.location + 2 else { return false }
            if text.dropFirst(2).trimmingCharacters(in: .whitespaces).isEmpty {
                // Enter on an empty item ends the list.
                tv.replace(NSRange(location: line.location, length: 2), with: "")
            } else {
                tv.insertText("\n" + (prefix == Checklist.bullet ? Checklist.bullet : Checklist.open), replacementRange: sel)
            }
            return true
        }

        func restyle(_ tv: NSTextView, force: Bool = false) {
            let key = "\(model.color.rawValue)|\(model.fontSize)"
            guard force || key != lastStyleKey, !tv.hasMarkedText(), let ts = tv.textStorage else { return }
            lastStyleKey = key

            let ink = NSColor(model.color.ink)
            let size = CGFloat(model.fontSize)
            let base = NSFont.systemFont(ofSize: size)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 2
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: para]

            let s = ts.string as NSString
            let full = NSRange(location: 0, length: s.length)
            ts.beginEditing()
            ts.setAttributes(attrs, range: full)
            s.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in
                guard r.length > 0 else { return }
                let c = s.character(at: r.location)
                let box = NSRange(location: r.location, length: 1)
                if c == Checklist.doneChar {
                    ts.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.55), range: box)
                    if r.length > 2 {
                        ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                          .foregroundColor: ink.withAlphaComponent(0.4)],
                                         range: NSRange(location: r.location + 2, length: r.length - 2))
                    }
                } else if c == Checklist.openChar {
                    ts.addAttribute(.foregroundColor, value: ink.withAlphaComponent(0.75), range: box)
                }
            }
            ts.endEditing()
            tv.typingAttributes = attrs
            tv.insertionPointColor = model.color.isDark ? NSColor(Color(hex: 0xFFE76B)) : ink
            tv.window?.invalidateCursorRects(for: tv)
        }
    }
}
