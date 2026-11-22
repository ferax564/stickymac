import Foundation

/// `StickyMac <command>`: talk to the running app (launching it if needed).
enum CLI {
    static let commands: Set<String> = ["mcp", "new", "list", "append", "help", "--help"]

    static let usage = """
    StickyMac command line

      stickymac new [text]        create a note (text from args or stdin); prints its id
      stickymac append <id> text  add lines to a note
      stickymac list              list notes as "id  title"
      stickymac mcp               run as an MCP server on stdio (for Claude Code & other agents)

    Checklists use Markdown: "- [ ] todo" / "- [x] done".
    """

    static func run(_ args: [String]) -> Int32 {
        do {
            switch args[0] {
            case "mcp":
                MCPServer.run()
            case "new":
                var text = args.dropFirst().joined(separator: " ")
                if text.isEmpty, isatty(STDIN_FILENO) == 0 {
                    text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
                }
                let n = try call(["op": "create", "text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
                print((n as? [String: Any])?["id"] ?? "")
            case "append":
                guard args.count >= 3 else { throw ClientError.message(usage) }
                _ = try call(["op": "update", "id": args[1], "append": args.dropFirst(2).joined(separator: " ")])
            case "list":
                for n in (try call(["op": "list"]) as? [[String: Any]]) ?? [] {
                    print("\(n["id"] ?? "")  \(n["title"] ?? "")")
                }
            default:
                print(usage)
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("stickymac: \(error)\n".utf8))
            return 1
        }
    }

    enum ClientError: Error, CustomStringConvertible {
        case message(String)
        var description: String { if case .message(let m) = self { return m }; return "" }
    }

    /// Sends one request to the app; starts the app in the background if it isn't running.
    static func call(_ req: [String: Any]) throws -> Any {
        var fd = connectSocket()
        if fd < 0 {
            launchApp()
            for _ in 0..<60 where fd < 0 {
                usleep(100_000)
                fd = connectSocket()
            }
        }
        guard fd >= 0 else { throw ClientError.message("could not reach StickyMac (is it installed?)") }
        defer { close(fd) }
        var tv = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = try JSONSerialization.data(withJSONObject: req)
        data.append(0x0A)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard let line = readLine(fd),
              let res = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ClientError.message("no response from StickyMac")
        }
        guard res["ok"] as? Bool == true else { throw ClientError.message(res["error"] as? String ?? "unknown error") }
        return res["result"] ?? NSNull()
    }

    private static func connectSocket() -> Int32 {
        guard var addr = unixAddress(AgentServer.socketPath) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { close(fd); return -1 }
        return fd
    }

    /// Opens the .app this binary lives in (or the installed one), without stealing focus.
    private static func launchApp() {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = bundle.pathExtension == "app" ? ["-g", bundle.path] : ["-g", "-b", "local.stickymac"]
        try? p.run()
        p.waitUntilExit()
    }
}

/// Minimal MCP server (JSON-RPC 2.0, one message per line on stdin/stdout).
enum MCPServer {
    private static let colors = ["lemon", "peach", "rose", "mint", "sky", "lavender", "graphite"]

    private static let tools: [[String: Any]] = [
        tool("list_notes", "List every sticky note on the user's Mac, newest first. Returns id, title, text (Markdown), color, pinned, checklist progress.", [:]),
        tool("search_notes", "Find notes whose text contains all the given words.", ["query": str("Words to search for")], required: ["query"]),
        tool("read_note", "Read one note by id.", ["id": str("Note id (8 characters from list_notes)")], required: ["id"]),
        tool("create_note", "Create a sticky note on the user's screen. Use Markdown checklists ('- [ ] item') for to-do lists. Returns the new note's id.", [
            "text": str("Note content. First line becomes the title."),
            "color": ["type": "string", "enum": colors, "description": "Optional note color"],
            "pinned": ["type": "boolean", "description": "Keep the note floating above all windows"],
        ], required: ["text"]),
        tool("update_note", "Change a note: replace its text, append lines, tick checklist items (rewrite '- [ ]' as '- [x]'), recolor or pin it.", [
            "id": str("Note id"),
            "text": str("New full text (replaces everything)"),
            "append": str("Lines to add at the end"),
            "color": ["type": "string", "enum": colors],
            "pinned": ["type": "boolean"],
        ], required: ["id"]),
        tool("delete_note", "Delete a note. The user can restore it with ⌘⇧T.", ["id": str("Note id")], required: ["id"]),
    ]

    private static let opFor = [
        "list_notes": "list", "search_notes": "search", "read_note": "get",
        "create_note": "create", "update_note": "update", "delete_note": "delete",
    ]

    static func run() {
        while let line = Swift.readLine() {
            guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            guard let id = msg["id"] else { continue }  // notifications need no reply
            let params = msg["params"] as? [String: Any] ?? [:]
            switch msg["method"] as? String ?? "" {
            case "initialize":
                reply(id, [
                    "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "stickymac", "version": "1.1.0"],
                    "instructions": "Sticky notes on the user's Mac desktop. Good for leaving the user visible reminders, to-do checklists you tick off as you work, or summaries. Notes appear on screen immediately.",
                ])
            case "ping":
                reply(id, [:])
            case "tools/list":
                reply(id, ["tools": tools])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                var req = params["arguments"] as? [String: Any] ?? [:]
                guard let op = opFor[name] else { reply(id, error: -32602, "unknown tool \(name)"); continue }
                req["op"] = op
                do {
                    let result = try CLI.call(req)
                    let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                    reply(id, ["content": [["type": "text", "text": String(decoding: json, as: UTF8.self)]]])
                } catch {
                    reply(id, ["content": [["type": "text", "text": "\(error)"]], "isError": true])
                }
            default:
                reply(id, error: -32601, "method not found")
            }
        }
    }

    private static func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
        ["name": name, "description": desc,
         "inputSchema": ["type": "object", "properties": props, "required": required]]
    }

    private static func str(_ d: String) -> [String: Any] { ["type": "string", "description": d] }

    private static func reply(_ id: Any, _ result: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": result]) }

    private static func reply(_ id: Any, error code: Int, _ message: String) {
        send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private static func send(_ msg: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: msg, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data([0x0A]))
    }
}
