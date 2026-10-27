import AppKit
import Observation
import OSLog

/// System-wide Now Playing for any app, read through the bundled adapter.
///
/// Event driven: the adapter process pushes a line whenever the system's Now Playing changes and
/// sleeps otherwise. If the adapter stops working (for example after a macOS update), the
/// activity simply doesn't appear and `availability` explains why in Settings.
@Observable
final class NowPlayingService {
    nonisolated enum Availability: Equatable, Sendable {
        case off
        case checking
        case available
        case unavailable(NowPlayingUnavailableReason)
    }

    private(set) var availability: Availability = .off
    private(set) var current: NowPlayingInfo?
    private(set) var artwork: NSImage?

    /// Called whenever `current` changes, to drive the live activity.
    @ObservationIgnored var onChange: ((NowPlayingInfo?) -> Void)?

    @ObservationIgnored private var adapter: MediaRemoteAdapter?
    @ObservationIgnored private var stream: AdapterStream?
    /// Identifies the current stream, so messages and exits of a stopped one are ignored.
    @ObservationIgnored private var streamID = UUID()
    @ObservationIgnored private var state = NowPlayingStreamState()
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private let logger = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "now-playing")

    /// Restarts after unexpected exits wait 1, 2, 4… seconds; after this many in a row the
    /// adapter is checked again and given up on if the check fails.
    static let failuresBeforeRecheck = 3
    static let failuresBeforeGivingUp = 6

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        consecutiveFailures = 0
        availability = .checking
        switch MediaRemoteAdapter.bundled() {
        case .failure(let reason):
            markUnavailable(reason)
        case .success(let adapter):
            self.adapter = adapter
            Task {
                let permitted = await adapter.selfTest()
                guard isRunning else { return }
                if permitted {
                    availability = .available
                    launchStream()
                } else {
                    markUnavailable(.notPermitted)
                }
            }
        }
    }

    func stop() {
        isRunning = false
        streamID = UUID()
        restartTask?.cancel()
        stream?.stop()
        stream = nil
        availability = .off
        update(NowPlayingStreamState())
    }

    // MARK: Controls

    func togglePlayPause() { send(.togglePlayPause) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    private func send(_ command: MediaRemoteAdapter.Command) {
        guard let adapter, availability == .available else { return }
        Task { await adapter.send(command) }
    }

    /// The playing app, to show its icon and bring it forward on click.
    var sourceApplicationURL: URL? {
        guard let bundleID = current?.sourceBundleIdentifier else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func openSourceApplication() {
        guard let url = sourceApplicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Stream

    private func launchStream() {
        guard isRunning, let adapter else { return }
        let id = UUID()
        streamID = id
        let stream = AdapterStream(
            adapter: adapter,
            onMessage: { [weak self] message in
                guard let service = self else { return }
                Task { @MainActor in service.receive(message, from: id) }
            },
            onExit: { [weak self] status in
                guard let service = self else { return }
                Task { @MainActor in service.streamDidExit(status: status, from: id) }
            }
        )
        do {
            try stream.start()
            self.stream = stream
        } catch {
            logger.error("Adapter stream failed to start: \(error.localizedDescription, privacy: .public)")
            streamDidExit(status: -1, from: id)
        }
    }

    private func receive(_ message: AdapterMessage, from id: UUID) {
        guard isRunning, id == streamID else { return }
        consecutiveFailures = 0
        var next = state
        next.apply(message)
        update(next)
    }

    private func streamDidExit(status: Int32, from id: UUID) {
        guard isRunning, id == streamID else { return }
        stream = nil
        consecutiveFailures += 1
        logger.error("Adapter stream exited with status \(status), failure \(self.consecutiveFailures)")
        update(NowPlayingStreamState())

        if consecutiveFailures >= Self.failuresBeforeGivingUp {
            markUnavailable(.keepsStopping)
            return
        }
        let delay = Duration.seconds(1 << min(consecutiveFailures - 1, 5))
        let recheck = consecutiveFailures >= Self.failuresBeforeRecheck
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isRunning, let adapter = self.adapter else { return }
            if recheck, !(await adapter.selfTest()) {
                self.markUnavailable(.notPermitted)
                return
            }
            self.launchStream()
        }
    }

    private func markUnavailable(_ reason: NowPlayingUnavailableReason) {
        streamID = UUID()
        logger.notice("Now Playing unavailable: \(String(describing: reason), privacy: .public)")
        stream?.stop()
        stream = nil
        availability = .unavailable(reason)
        update(NowPlayingStreamState())
    }

    private func update(_ next: NowPlayingStreamState) {
        let artworkChanged = next.artworkData != state.artworkData
        state = next
        if artworkChanged {
            artwork = next.artworkData.flatMap(NSImage.init(data:))
        }
        let info = next.info
        if info != current {
            current = info
            onChange?(info)
        }
    }
}
