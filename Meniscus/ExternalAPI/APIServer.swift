import Darwin
import Foundation
import OSLog

/// The CLI's way in: a Unix domain socket in a folder only the user can open. Browsers can't
/// reach Unix sockets, so web pages can't use this channel. One JSON object per line in, one
/// answer per line out.
///
/// All work here happens on the server's own queue; requests go to the main actor through
/// `onRequest`. The answer doesn't wait for the main actor: it only says whether the request was
/// valid.
nonisolated final class APIServer: @unchecked Sendable {
    enum Incoming: Sendable {
        case request(APIRequest)
        case hook(client: String, ClaudeCodeAdapter.HookEvent, at: Date?)
    }

    static var socketURL: URL {
        URL.applicationSupportDirectory.appending(path: "Meniscus", directoryHint: .isDirectory).appending(path: "api.sock")
    }

    /// Called on the main actor for each valid request, with its verified source.
    var onRequest: (@MainActor @Sendable (Incoming, APISource) -> Void)?

    private let queue = DispatchQueue(label: "io.github.dtem4ik.meniscus.api", attributes: .concurrent)
    private let lock = NSLock()
    private var listener: DispatchSourceRead?
    private var listeningSocket: Int32 = -1

    var isRunning: Bool { lock.withLock { listeningSocket >= 0 } }

    func start() {
        guard !isRunning else { return }
        let url = Self.socketURL
        let folder = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            chmod(folder.path(percentEncoded: false), 0o700)
        } catch {
            Logger.api.error("Couldn't create the API folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        let path = url.path(percentEncoded: false)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            Logger.api.error("The API socket path is too long")
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            Logger.api.error("Couldn't open the API socket: \(String(cString: strerror(errno)), privacy: .public)")
            close(fd)
            unlink(path)
            return
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptClients(on: fd) }
        source.setCancelHandler {
            close(fd)
            unlink(path)
        }
        lock.withLock {
            listeningSocket = fd
            listener = source
        }
        source.resume()
        Logger.api.notice("API socket open")
    }

    func stop() {
        let source = lock.withLock {
            let source = listener
            listener = nil
            listeningSocket = -1
            return source
        }
        source?.cancel()
    }

    private func acceptClients(on fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            queue.async { [weak self] in
                self?.serve(client)
                close(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Only the logged-in user.
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        var pid: pid_t = 0
        var pidSize = socklen_t(MemoryLayout<pid_t>.size)
        let hasPID = getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidSize) == 0

        guard let line = readLine(from: client) else { return }
        // Resolved now, while the CLI waits for the answer and its parents still exist.
        let source = hasPID ? SourceResolver.source(forPeer: pid) : .unknown
        let answer: [String: Any]
        do {
            let incoming = try Self.decode(line)
            if case .request(let request) = incoming, request.operation == .status {
                answer = Self.status()
            } else {
                answer = ["ok": true, "v": 1]
                if let onRequest {
                    MainThread.run { onRequest(incoming, source) }
                }
            }
        } catch {
            answer = ["ok": false, "v": 1, "error": error.message]
        }
        if var data = try? JSONSerialization.data(withJSONObject: answer) {
            data.append(0x0A)
            _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        }
    }

    static func decode(_ line: Data) throws(APIError) -> Incoming {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            throw .invalid("not a JSON object")
        }
        if object["op"] as? String == "hook" {
            let version = (object["v"] as? NSNumber)?.intValue ?? 1
            guard APILimits.versions.contains(version) else { throw .unsupportedVersion(version) }
            guard let client = object["client"] as? String, client == "claude-code" else { throw .invalid("unknown hook client") }
            guard let event = (object["event"] as? [String: Any]).flatMap(ClaudeCodeAdapter.HookEvent.init) else {
                throw .invalid("hook event missing")
            }
            let at = (object["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            return .hook(client: client, event, at: at)
        }
        return .request(try APIRequest.decode(object, trusted: true))
    }

    /// Versions and channel switches, read from the defaults (safe off the main actor).
    static func status() -> [String: Any] {
        let defaults = UserDefaults.standard
        return [
            "ok": true, "v": 1,
            "versions": APILimits.versions,
            "cli": defaults.object(forKey: SettingsKey.externalCLI) as? Bool ?? true,
            "links": defaults.object(forKey: SettingsKey.externalLinks) as? Bool ?? false,
        ]
    }

    private func readLine(from client: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= APILimits.messageSize {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
            if let newline = data.firstIndex(of: 0x0A) { return data[data.startIndex..<newline] }
        }
        return data.isEmpty || data.count > APILimits.messageSize ? nil : data
    }
}

extension Logger {
    /// External API requests. In Console, filter by subsystem `io.github.dtem4ik.meniscus` and
    /// category `api`.
    nonisolated static let api = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "api")
}
