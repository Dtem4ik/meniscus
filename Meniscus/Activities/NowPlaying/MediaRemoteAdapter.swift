import Foundation

/// Why system-wide Now Playing isn't available. Shown in Settings.
nonisolated enum NowPlayingUnavailableReason: Error, Equatable, Sendable {
    /// macOS no longer ships `/usr/bin/perl`, which the adapter runs in.
    case perlMissing
    /// This build doesn't contain the adapter (built without CMake or the submodule).
    case adapterNotBundled
    /// The self-test failed: macOS no longer lets the adapter read Now Playing.
    case notPermitted
    /// The adapter keeps stopping unexpectedly.
    case keepsStopping

    var explanation: String {
        switch self {
        case .perlMissing:
            String(localized: "This version of macOS no longer includes the system component Meniscus uses to read what's playing.")
        case .adapterNotBundled:
            String(localized: "This build of Meniscus was made without its Now Playing component. Build it with CMake installed.")
        case .notPermitted:
            String(localized: "This version of macOS doesn't let Meniscus read what's playing anymore.")
        case .keepsStopping:
            String(localized: "Reading what's playing keeps failing. Meniscus stopped trying until it's relaunched.")
        }
    }
}

/// Runs the bundled mediaremote-adapter (BSD 3-Clause, by Jonas van den Berg and contributors).
///
/// Since macOS 15.4 only Apple-signed processes may read the system's Now Playing information.
/// The adapter is a small framework loaded into `/usr/bin/perl`, which is Apple-signed, and
/// prints Now Playing as JSON lines. See docs/now-playing.md.
nonisolated struct MediaRemoteAdapter: Sendable {
    static let perlURL = URL(filePath: "/usr/bin/perl")

    let scriptURL: URL
    let frameworkURL: URL
    let testClientURL: URL

    /// MRCommand ids understood by `send`.
    nonisolated enum Command: Int, Sendable {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    /// Finds the adapter inside the app bundle, or says why it can't be used.
    static func bundled(in bundle: Bundle = .main) -> Result<MediaRemoteAdapter, NowPlayingUnavailableReason> {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: perlURL.path(percentEncoded: false)) else {
            return .failure(.perlMissing)
        }
        let contents = bundle.bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let adapter = MediaRemoteAdapter(
            scriptURL: contents.appending(path: "Resources/mediaremote-adapter.pl"),
            frameworkURL: contents.appending(path: "Frameworks/MediaRemoteAdapter.framework", directoryHint: .isDirectory),
            testClientURL: contents.appending(path: "Helpers/MediaRemoteAdapterTestClient")
        )
        let required = [adapter.scriptURL, adapter.frameworkURL, adapter.testClientURL]
        guard required.allSatisfy({ fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }) else {
            return .failure(.adapterNotBundled)
        }
        return .success(adapter)
    }

    func arguments(_ function: [String], withTestClient: Bool = false) -> [String] {
        var arguments = [scriptURL.path(percentEncoded: false), frameworkURL.path(percentEncoded: false)]
        if withTestClient { arguments.append(testClientURL.path(percentEncoded: false)) }
        return arguments + function
    }

    /// The adapter's own check that it may read Now Playing on this macOS. Takes about half a
    /// second; run once at start and after repeated stream failures.
    @concurrent
    func selfTest() async -> Bool {
        await selfTestReport().passed
    }

    /// The self-test with the adapter's output, for logs and tests.
    @concurrent
    func selfTestReport() async -> (passed: Bool, output: String) {
        let result = await Self.run(arguments(["test"], withTestClient: true), timeout: 10)
        return (result.status == 0, result.output)
    }

    @concurrent
    func send(_ command: Command) async {
        _ = await Self.run(arguments(["send", String(command.rawValue)]), timeout: 5)
    }

    /// Children get a minimal environment: nothing of Meniscus's own environment (for example
    /// `DYLD_*` variables injected by a debugger or test runner) leaks into the adapter.
    static var childEnvironment: [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": "en_US.UTF-8",
        ]
    }

    /// Arguments for the long-running stream: full payloads with microsecond times, diffs for
    /// changes, and a short debounce so a burst of changes becomes one message.
    var streamArguments: [String] {
        arguments(["stream", "--micros", "--debounce=50"])
    }

    /// Runs perl and returns its exit status (`nil` if it couldn't start or timed out) and output.
    private static func run(_ arguments: [String], timeout: TimeInterval) async -> (status: Int32?, output: String) {
        await OneShotProcess(executable: perlURL, arguments: arguments).run(timeout: timeout)
    }
}

/// A short-lived process with a timeout, resumed exactly once by whichever of exit and timeout
/// comes first.
private nonisolated final class OneShotProcess: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(status: Int32?, output: String), Never>?
    private var output = Data()
    /// Keeps logs small; the adapter's messages are short.
    private static let outputLimit = 16 * 1024

    init(executable: URL, arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = MediaRemoteAdapter.childEnvironment
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.lock.withLock {
                if self.output.count < Self.outputLimit { self.output.append(data) }
            }
        }
    }

    func run(timeout: TimeInterval) async -> (status: Int32?, output: String) {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            process.terminationHandler = { [self] finished in finish(finished.terminationStatus) }
            do {
                try process.run()
            } catch {
                finish(nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                if process.isRunning { process.terminate() }
                finish(nil)
            }
        }
    }

    private func finish(_ status: Int32?) {
        let (continuation, output) = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return (continuation, String(decoding: self.output, as: UTF8.self))
        }
        continuation?.resume(returning: (status, output))
    }
}

/// The long-running `stream` process. Reads its output as it arrives and hands complete,
/// decoded lines to `onMessage` on a background queue.
nonisolated final class AdapterStream: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private var buffer = Data()

    init(
        adapter: MediaRemoteAdapter,
        onMessage: @escaping @Sendable (AdapterMessage) -> Void,
        onExit: @escaping @Sendable (Int32) -> Void
    ) {
        process.executableURL = MediaRemoteAdapter.perlURL
        process.arguments = adapter.streamArguments
        process.environment = MediaRemoteAdapter.childEnvironment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { onExit($0.terminationStatus) }
        // The handler runs on one background queue at a time, so `buffer` needs no lock.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[self.buffer.startIndex..<newline]
                self.buffer.removeSubrange(self.buffer.startIndex...newline)
                if let message = AdapterMessage.decode(Data(line)) { onMessage(message) }
            }
        }
    }

    func start() throws {
        try process.run()
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
    }
}
