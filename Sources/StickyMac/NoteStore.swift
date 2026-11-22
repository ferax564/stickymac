import AppKit
import Combine

/// Live, observable state of one note.
final class NoteModel: ObservableObject, Identifiable {
    let id: UUID
    let created: Date
    @Published var text: String { didSet { modified = Date() } }
    @Published var color: NoteColor
    @Published var pinned: Bool
    @Published var collapsed: Bool
    @Published var fontSize: Double
    @Published var modified: Date
    @Published var snoozedUntil: Date?
    var frame: CGRect
    var expandedHeight: CGFloat
    /// Set for freshly created notes so the editor grabs focus.
    var wantsFocus = false

    init(text: String = "", color: NoteColor, frame: CGRect) {
        self.id = UUID()
        self.created = Date()
        self.text = text
        self.color = color
        self.pinned = false
        self.collapsed = false
        self.fontSize = 15
        self.modified = Date()
        self.frame = frame
        self.expandedHeight = frame.height
    }

    init(record r: NoteRecord) {
        id = r.id; created = r.created; text = r.text; color = r.color
        pinned = r.pinned; collapsed = r.collapsed; fontSize = r.fontSize
        modified = r.modified; frame = r.frame; expandedHeight = r.expandedHeight
        snoozedUntil = r.snoozedUntil
    }

    var record: NoteRecord {
        NoteRecord(id: id, created: created, modified: modified, text: text, color: color,
                   pinned: pinned, collapsed: collapsed, fontSize: fontSize,
                   frame: frame, expandedHeight: expandedHeight, snoozedUntil: snoozedUntil)
    }

    var isSnoozed: Bool { (snoozedUntil ?? .distantPast) > Date() }

    var title: String {
        var first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if Checklist.markers.contains(where: first.hasPrefix) { first.removeFirst(2) }
        let t = first.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Empty note" : String(t.prefix(40))
    }
}

/// On-disk representation.
struct NoteRecord: Codable {
    var id: UUID
    var created: Date
    var modified: Date
    var text: String
    var color: NoteColor
    var pinned: Bool
    var collapsed: Bool
    var fontSize: Double
    var frame: CGRect
    var expandedHeight: CGFloat
    var snoozedUntil: Date?
}

final class NoteStore {
    private(set) var notes: [NoteModel] = []
    private(set) var trash: [NoteRecord] = []
    private var subs: [UUID: AnyCancellable] = [:]
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var saveSub: AnyCancellable?
    /// Called after every save (used for the Markdown folder copy).
    var onSave: (([NoteModel]) -> Void)?

    let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.json")
    }()

    private struct FileFormat: Codable {
        var version = 1
        var notes: [NoteRecord]
        var trash: [NoteRecord]
    }

    init() {
        saveSub = saveSubject
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.saveNow() }
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let f = try? dec.decode(FileFormat.self, from: data) else {
            // Keep a copy of an unreadable file rather than overwriting it.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return
        }
        trash = f.trash
        f.notes.forEach { add(NoteModel(record: $0), save: false) }
    }

    @discardableResult
    func add(_ note: NoteModel, save: Bool = true) -> NoteModel {
        notes.append(note)
        subs[note.id] = note.objectWillChange.sink { [weak self] _ in self?.scheduleSave() }
        if save { scheduleSave() }
        return note
    }

    func delete(_ note: NoteModel) {
        notes.removeAll { $0.id == note.id }
        subs[note.id] = nil
        // Empty notes vanish; anything with content goes to a small undo trash.
        if !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            trash.append(note.record)
            if trash.count > 20 { trash.removeFirst(trash.count - 20) }
        }
        scheduleSave()
    }

    func popTrash() -> NoteModel? {
        guard let r = trash.popLast() else { return nil }
        let n = NoteModel(record: r)
        add(n)
        return n
    }

    func scheduleSave() { saveSubject.send() }

    func saveNow() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let f = FileFormat(notes: notes.map(\.record), trash: trash)
        guard let data = try? enc.encode(f) else { return }
        try? data.write(to: fileURL, options: .atomic)
        onSave?(notes)
    }
}
