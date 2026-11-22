import Foundation

/// Optionally keeps a plain .md copy of every note in a folder the user picks.
/// One-way: the app writes the files; edits made to them are not read back.
/// Only files this mirror created (tracked in a manifest) are ever renamed or removed.
final class MarkdownMirror {
    private let defaults = UserDefaults.standard
    private let folderKey = "markdownFolder"
    private let manifestKey = "markdownManifest"

    var folder: URL? {
        get { defaults.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set {
            defaults.set(newValue?.path, forKey: folderKey)
            defaults.removeObject(forKey: manifestKey)  // a new folder starts a new manifest
        }
    }

    private var manifest: [String: String] {
        get { defaults.dictionary(forKey: manifestKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: manifestKey) }
    }

    static func markdown(for note: NoteModel) -> String {
        Checklist.toMarkdown(note.text).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func fileName(for note: NoteModel) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var t = note.title.components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-*#>"))
        if t.isEmpty || t == "Empty note" { t = "Note" }
        return String(t.prefix(48)) + " " + note.id.uuidString.prefix(6) + ".md"
    }

    func sync(_ notes: [NoteModel]) {
        guard let folder else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var old = manifest
        var new: [String: String] = [:]

        for note in notes where !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let id = note.id.uuidString
            let name = Self.fileName(for: note)
            let url = folder.appendingPathComponent(name)
            // Title changed → rename our existing file instead of leaving a stale copy.
            if let prev = old[id], prev != name {
                let prevURL = folder.appendingPathComponent(prev)
                if fm.fileExists(atPath: prevURL.path), !fm.fileExists(atPath: url.path) {
                    try? fm.moveItem(at: prevURL, to: url)
                }
            }
            old[id] = nil
            let data = Data(Self.markdown(for: note).utf8)
            if (try? Data(contentsOf: url)) != data { try? data.write(to: url, options: .atomic) }
            new[id] = name
        }
        // Notes that were deleted (or emptied): remove only the files we wrote.
        for (_, name) in old {
            let url = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
        }
        manifest = new
    }
}
