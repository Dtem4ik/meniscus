import Foundation
import Observation
import OSLog

/// Loads, saves and watches `config.json`. Edits made by hand in any editor are picked up within
/// a moment; a broken file keeps the last good modes and reports the problem.
@Observable
final class ModesStore {
    static let shared = ModesStore(fileURL: ModesStore.defaultFileURL)

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Meniscus", directoryHint: .isDirectory)
            .appending(path: "config.json", directoryHint: .notDirectory)
    }

    private(set) var config = ModesConfig()
    /// The problem with the file on disk, if the last load failed.
    private(set) var loadError: ModesConfigError?

    var modes: [Mode] { config.modes }

    let fileURL: URL
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "modes")
    @ObservationIgnored private var directoryWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    /// Contents last written by `save`, so our own writes don't trigger a reload.
    @ObservationIgnored private var lastWrittenData: Data?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func start() {
        reload()
        watchDirectory()
        watchFile()
    }

    func stop() {
        directoryWatcher?.cancel()
        fileWatcher?.cancel()
        directoryWatcher = nil
        fileWatcher = nil
    }

    // MARK: Reading

    func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            // No file yet: no modes, and nothing to report.
            config = ModesConfig()
            loadError = nil
            return
        }
        if data == lastWrittenData { return }
        do throws(ModesConfigError) {
            config = try ModesConfigCoder.decode(data)
            loadError = nil
        } catch {
            loadError = error
            logger.error("config.json: \(error.description)")
        }
    }

    // MARK: Writing

    func save(_ newConfig: ModesConfig) throws(ModesConfigError) {
        let issues = ModesConfigValidator.issues(in: newConfig)
        guard issues.isEmpty else { throw .invalidContent(issues) }
        do {
            let data = try ModesConfigCoder.encode(newConfig)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            lastWrittenData = data
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .io(error.localizedDescription)
        }
        config = newConfig
        loadError = nil
        watchFile()
    }

    /// Writes the bundled example if there is no config yet.
    func installExampleIfMissing() throws(ModesConfigError) {
        guard !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        guard let exampleURL = Bundle.main.url(forResource: "config.example", withExtension: "json"),
              let data = try? Data(contentsOf: exampleURL)
        else { throw .io(String(localized: "The example config is missing from the app bundle.")) }
        try save(ModesConfigCoder.decode(data))
    }

    // MARK: Watching

    /// Editors often save by replacing the file, which only the directory sees.
    private func watchDirectory() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directoryWatcher?.cancel()
        directoryWatcher = makeWatcher(for: directory, events: .write)
    }

    /// In-place edits change the file without touching the directory.
    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = makeWatcher(for: fileURL, events: [.write, .extend, .delete, .rename])
    }

    private func makeWatcher(for url: URL, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainThread.run { self?.scheduleReload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    /// Editors write in bursts; reload once things settle.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.reload()
            // The file may have been replaced; watch the new one.
            self.watchFile()
        }
    }
}
