import AppKit
import Observation
import OSLog

/// The long-lived sources of live data. Created once by the app delegate.
@Observable
final class ActivityServices {
    static let shared = ActivityServices()

    let center = ActivityCenter()
    let power = PowerSourceMonitor()
    let calendar = CalendarService()
    let nowPlaying = NowPlayingService()

    /// Battery level shown by the charging activity.
    private(set) var chargingLevel: Int?

    /// How long the charging activity stays in the notch after the charger is connected.
    static let chargingActivityDuration: TimeInterval = 4

    @ObservationIgnored private let logger = Logger.power

    func start(settings: AppSettings) {
        power.onEvent = { [weak self] event in self?.handle(event) }
        power.start()
        calendar.hiddenCalendarIDs = { settings.hiddenCalendarIDs }
        if settings.showCalendar { calendar.start() }

        nowPlaying.onChange = { [weak self] info in
            guard let self else { return }
            if let info, info.isPlaying {
                center.post(LiveActivity(id: "now-playing", kind: .nowPlaying, priority: .ongoing, updatedAt: Date(), expiresAt: nil))
            } else {
                center.remove(id: "now-playing")
            }
        }
        if settings.showNowPlaying { nowPlaying.start() }
    }

    /// Developer menu: plays the charging activity without a cable.
    func simulateCharging() {
        let level = power.state?.level ?? 80
        logger.notice("Simulated charger connected at \(level, privacy: .public)%")
        showCharging(level: level)
    }

    private func handle(_ event: PowerEvent) {
        logger.notice("Power event: \(String(describing: event), privacy: .public)")
        switch event {
        case .connected(let level):
            showCharging(level: level)
        case .fullyCharged:
            showCharging(level: 100)
        case .disconnected:
            center.remove(id: "charging")
        }
    }

    private func showCharging(level: Int) {
        chargingLevel = level
        center.postTransient(id: "charging", kind: .charging, duration: Self.chargingActivityDuration)
        if AppSettings.shared.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}

extension Logger {
    /// Power source snapshots and charger events. In Console, filter by subsystem
    /// `io.github.dtem4ik.meniscus` and category `power`.
    nonisolated static let power = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "power")
}
