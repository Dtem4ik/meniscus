import Darwin
import Foundation

// `meniscus`: the command line way to show notices and running tasks in the Meniscus notch.
// It talks to the running app over a Unix socket that only this user can open, and never gets
// in the way of whatever runs it: it answers within half a second, never asks anything, and
// exits 0 whenever the notice was accepted. Design: docs/external-api.md.

/// When the event happened: taken first, before reading any input, so asynchronous callers
/// (like Claude Code hooks) can be put back in order by the app.
let startedAt = Int64(Date().timeIntervalSince1970 * 1000)

let usage = """
usage: meniscus notify TITLE [--subtitle TEXT] [--state info|success|attention] [--open URL|PATH]
       meniscus activity start  --id ID TITLE [--subtitle TEXT] [--state STATE] [--timeout 30m]
       meniscus activity update --id ID [TITLE] [--subtitle TEXT] [--state STATE]
       meniscus activity end    --id ID [TITLE] [--subtitle TEXT] [--state STATE] [--quiet]
       meniscus status
       meniscus hook claude-code    (reads a Claude Code hook's JSON from standard input)

Exit status: 0 accepted (shown, queued or silenced by Settings), 2 invalid input,
3 Meniscus isn't running. Activities can carry --at MILLISECONDS for the event's time.
"""

enum Exit: Int32 {
    case ok = 0, invalid = 2, notRunning = 3
}

func fail(_ message: String, _ code: Exit = .invalid) -> Never {
    FileHandle.standardError.write(Data(("meniscus: " + message + "\n").utf8))
    exit(code.rawValue)
}

/// "90", "90s", "30m", "2h" → seconds.
func seconds(_ text: String) -> Double? {
    let units: [Character: Double] = ["s": 1, "m": 60, "h": 3600]
    if let unit = text.last, let factor = units[unit] { return Double(text.dropLast()).map { $0 * factor } }
    return Double(text)
}

/// Options and positional words, in any order.
func parse(_ arguments: ArraySlice<String>, flags: Set<String>) -> (options: [String: String], words: [String], switches: Set<String>) {
    var options: [String: String] = [:]
    var words: [String] = []
    var switches = Set<String>()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        if argument.hasPrefix("--") {
            let name = String(argument.dropFirst(2))
            if flags.contains(name) {
                switches.insert(name)
            } else if let value = iterator.next() {
                options[name] = value
            } else {
                fail("--\(name) needs a value")
            }
        } else {
            words.append(argument)
        }
    }
    return (options, words, switches)
}

func request(for arguments: [String]) -> [String: Any] {
    guard let command = arguments.first else { fail(usage) }
    var object: [String: Any] = ["v": 1]
    switch command {
    case "notify":
        let parsed = parse(arguments.dropFirst(), flags: [])
        guard let title = parsed.words.first else { fail("notify needs a title") }
        object["op"] = "notify"
        object["title"] = title
        object["subtitle"] = parsed.options["subtitle"]
        object["state"] = parsed.options["state"]
        if let open = parsed.options["open"] {
            // Relative paths are made absolute here, where the working folder is known.
            object["open"] = open.contains("://") || open.hasPrefix("/")
                ? open : FileManager.default.currentDirectoryPath + "/" + open
        }
    case "activity":
        guard arguments.count > 1, ["start", "update", "end"].contains(arguments[1]) else {
            fail("activity needs start, update or end")
        }
        let parsed = parse(arguments.dropFirst(2), flags: ["quiet"])
        guard let id = parsed.options["id"] else { fail("activity needs --id") }
        object["op"] = arguments[1]
        object["id"] = id
        object["title"] = parsed.words.first
        object["subtitle"] = parsed.options["subtitle"]
        object["state"] = parsed.options["state"]
        object["at"] = parsed.options["at"].flatMap { Int64($0) } ?? startedAt
        if let timeout = parsed.options["timeout"] {
            guard let value = seconds(timeout) else { fail("--timeout takes a duration like 90s, 30m or 2h") }
            object["timeout"] = value
        }
        if parsed.switches.contains("quiet") { object["quiet"] = true }
        if arguments[1] == "start", object["title"] == nil { fail("activity start needs a title") }
    case "status":
        object["op"] = "status"
    default:
        fail(usage)
    }
    return object
}

/// `meniscus hook claude-code`: forwards only what the mapping needs, never the prompt, the
/// answer or full paths.
func hookRequest() -> [String: Any]? {
    let input = FileHandle.standardInput.readData(ofLength: 1 << 20)
    guard let hook = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
          let event = hook["hook_event_name"] as? String else { return nil }
    var fields: [String: Any] = ["hook_event_name": event]
    fields["session_id"] = hook["session_id"] as? String
    fields["notification_type"] = hook["notification_type"] as? String
    if let cwd = hook["cwd"] as? String { fields["project"] = URL(filePath: cwd).lastPathComponent }
    return ["v": 1, "op": "hook", "client": "claude-code", "at": startedAt, "event": fields]
}

func socketPath() -> String {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Application Support")
    return support.appending(path: "Meniscus/api.sock").path(percentEncoded: false)
}

/// Sends one line and returns the app's answer, or nil when Meniscus isn't running.
func send(_ object: [String: Any]) -> [String: Any]? {
    guard var data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    data.append(0x0A)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 0, tv_usec: 500_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let path = socketPath()
    guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard connected == 0 else { return nil }
    let written = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    guard written == data.count else { return nil }

    var answer = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while !answer.contains(0x0A) {
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { break }
        answer.append(contentsOf: buffer[0..<count])
    }
    return (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any] ?? ["ok": true]
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case nil, "-h", "--help", "help":
    print(usage)
case "--version", "version":
    print("meniscus 1 (API v1)")
case "hook":
    // Never delay or fail the hook: exit 0, print nothing.
    guard arguments.dropFirst().first == "claude-code", let object = hookRequest() else { exit(0) }
    _ = send(object)
    exit(0)
default:
    let object = request(for: arguments)
    guard let answer = send(object) else { fail("Meniscus isn't running, or its command line tool is turned off in Settings", .notRunning) }
    if answer["ok"] as? Bool == false { fail(answer["error"] as? String ?? "the request was refused") }
    if object["op"] as? String == "status",
       let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys]) {
        print(String(decoding: data, as: UTF8.self))
    }
}
