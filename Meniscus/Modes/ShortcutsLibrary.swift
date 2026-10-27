import Foundation
import Observation

/// The user's shortcuts from the Shortcuts app, for the shortcut picker in Settings. Read with
/// the system's `shortcuts list` command when Settings first needs them; nothing else runs.
@Observable
final class ShortcutsLibrary {
    static let shared = ShortcutsLibrary()

    nonisolated enum State: Equatable, Sendable {
        case notLoaded
        case loading
        case loaded([String])
        /// The command failed; Settings falls back to typing the name.
        case unavailable
    }

    private(set) var state: State = .notLoaded

    func loadIfNeeded() {
        guard state == .notLoaded else { return }
        reload()
    }

    func reload() {
        state = .loading
        Task {
            let names = await Self.fetchNames()
            state = names.map(State.loaded) ?? .unavailable
        }
    }

    nonisolated static let commandURL = URL(filePath: "/usr/bin/shortcuts")

    @concurrent
    nonisolated static func fetchNames() async -> [String]? {
        let box = ProcessBox()
        let process = box.process
        let pipe = Pipe()
        process.executableURL = commandURL
        process.arguments = ["list"]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LANG": "en_US.UTF-8"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // A hung command must not keep Settings waiting forever.
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if box.process.isRunning { box.process.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// One name per line; blank lines and repeats dropped, sorted like Finder sorts names.
    nonisolated static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Lets the timeout reach the process from another queue.
private nonisolated final class ProcessBox: @unchecked Sendable {
    let process = Process()
}
