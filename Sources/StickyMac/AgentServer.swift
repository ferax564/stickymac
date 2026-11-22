import AppKit

/// Local control channel for the CLI / MCP server: newline-delimited JSON over a
/// Unix socket in Application Support (mode 0600, so only this user can connect).
final class AgentServer {
    static var socketPath: String { NoteStore.directory.appendingPathComponent("agent.sock").path }

    private let handle: ([String: Any]) -> [String: Any]

    init(handle: @escaping ([String: Any]) -> [String: Any]) { self.handle = handle }

    func start() {
        let path = Self.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = unixAddress(path) else { return }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return }
        chmod(path, 0o600)
        Thread.detachNewThread { [handle] in
            while true {
                let conn = accept(fd, nil, nil)
                guard conn >= 0 else { continue }
                Thread.detachNewThread {
                    defer { close(conn) }
                    guard let line = readLine(conn),
                          let req = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                    let res = DispatchQueue.main.sync { handle(req) }
                    var out = (try? JSONSerialization.data(withJSONObject: res)) ?? Data()
                    out.append(0x0A)
                    out.withUnsafeBytes { _ = write(conn, $0.baseAddress, out.count) }
                }
            }
        }
    }
}

func unixAddress(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        buf.copyBytes(from: bytes)
        buf[bytes.count] = 0
    }
    return addr
}

/// Reads bytes up to the first newline (or EOF).
func readLine(_ fd: Int32) -> Data? {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        data.append(contentsOf: buf[0..<n])
        if buf[0..<n].contains(0x0A) { break }
    }
    guard let nl = data.firstIndex(of: 0x0A) else { return data.isEmpty ? nil : data }
    return data[..<nl]
}

// MARK: - Request handling (runs on the main thread)

extension AppDelegate {
    func handleAgentRequest(_ req: [String: Any]) -> [String: Any] {
        do {
            return ["ok": true, "result": try perform(req)]
        } catch {
            return ["ok": false, "error": "\(error)"]
        }
    }

    private struct AgentError: Error, CustomStringConvertible { let description: String }

    private func perform(_ req: [String: Any]) throws -> Any {
        let op = req["op"] as? String ?? ""
        switch op {
        case "list":
            return store.notes.sorted { $0.modified > $1.modified }.map(describe)
        case "search":
            let terms = (req["query"] as? String ?? "").lowercased().split(separator: " ")
            return store.notes
                .filter { n in terms.allSatisfy { n.text.lowercased().contains($0) } }
                .sorted { $0.modified > $1.modified }
                .map(describe)
        case "get":
            return describe(try note(req))
        case "create":
            let text = Checklist.fromMarkdown(req["text"] as? String ?? "")
            let size = fittedSize(for: text)
            var frame = CGRect(origin: .zero, size: size)
            if let v = NSScreen.main?.visibleFrame {
                let k = CGFloat(store.notes.count % 6) * 26
                frame.origin = CGPoint(x: v.maxX - size.width - 24 - k, y: v.maxY - size.height - 24 - k)
            }
            let n = addNote(text: text, color: try color(req) ?? nextColor, frame: frame, focus: false)
            n.pinned = req["pinned"] as? Bool ?? false
            return describe(n)
        case "update":
            let n = try note(req)
            if let text = req["text"] as? String { n.text = Checklist.fromMarkdown(text) }
            if let more = req["append"] as? String {
                let sep = n.text.isEmpty || n.text.hasSuffix("\n") ? "" : "\n"
                n.text += sep + Checklist.fromMarkdown(more)
            }
            if let c = try color(req) { n.color = c }
            if let p = req["pinned"] as? Bool { n.pinned = p }
            return describe(n)
        case "delete":
            let n = try note(req)
            guard let c = controllers[n.id] else { throw AgentError(description: "note window missing") }
            c.delete()
            return ["deleted": shortID(n), "restore": "⌘⇧T in StickyMac restores it"]
        default:
            throw AgentError(description: "unknown op '\(op)'")
        }
    }

    private func note(_ req: [String: Any]) throws -> NoteModel {
        let id = (req["id"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        guard id.count >= 4 else { throw AgentError(description: "id must be at least 4 characters") }
        let hits = store.notes.filter { $0.id.uuidString.lowercased().hasPrefix(id) }
        guard hits.count == 1 else {
            throw AgentError(description: hits.isEmpty ? "no note with id '\(id)'" : "id '\(id)' is ambiguous")
        }
        return hits[0]
    }

    private func color(_ req: [String: Any]) throws -> NoteColor? {
        guard let name = req["color"] as? String else { return nil }
        guard let c = NoteColor(rawValue: name.lowercased()) else {
            throw AgentError(description: "color must be one of: " + NoteColor.allCases.map(\.rawValue).joined(separator: ", "))
        }
        return c
    }

    private func shortID(_ n: NoteModel) -> String { String(n.id.uuidString.prefix(8)).lowercased() }

    private func describe(_ n: NoteModel) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var d: [String: Any] = [
            "id": shortID(n), "title": n.title, "text": Checklist.toMarkdown(n.text),
            "color": n.color.rawValue, "pinned": n.pinned, "modified": iso.string(from: n.modified),
        ]
        let lines = n.text.components(separatedBy: "\n")
        let done = lines.filter { $0.hasPrefix(Checklist.done) }.count
        let total = done + lines.filter { $0.hasPrefix(Checklist.open) }.count
        if total > 0 { d["checklist"] = "\(done)/\(total) done" }
        if n.isSnoozed, let u = n.snoozedUntil { d["snoozed_until"] = iso.string(from: u) }
        return d
    }
}
