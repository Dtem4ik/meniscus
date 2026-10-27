import Foundation
import OSLog

/// The long-lived sources of live data. Created once by the app delegate.
final class ActivityServices {
    static let shared = ActivityServices()

    let center = ActivityCenter()
    let power = PowerSourceMonitor()
    let calendar = CalendarService()

    /// How long the charging activity stays in the notch after the charger is connected.
    static let chargingActivityDuration: TimeInterval = 4

    private let logger = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "activities")

    func start(settings: AppSettings) {
        power.onEvent = { [weak self] event in self?.handle(event) }
        power.start()
        if settings.showCalendar { calendar.start() }
    }

    private func handle(_ event: PowerEvent) {
        logger.debug("Power event: \(String(describing: event))")
        switch event {
        case .connected, .fullyCharged:
            center.postTransient(id: "charging", kind: .charging, duration: Self.chargingActivityDuration)
        case .disconnected:
            center.remove(id: "charging")
        }
    }
}
