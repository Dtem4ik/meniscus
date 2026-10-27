import AppKit
import EventKit
import Observation

/// Reads the next calendar event with EventKit.
///
/// Access is requested only when the user turns the feature on, never at launch. Updates come
/// from `EKEventStoreChanged` and from one timer set to the next start or end of an event.
@Observable
final class CalendarService {
    nonisolated enum Access: Equatable, Sendable {
        case notDetermined
        case granted
        /// Denied, restricted or write-only; the user must change it in System Settings.
        case denied
    }

    private(set) var access: Access
    private(set) var upcoming: CalendarEventSnapshot?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var events: [CalendarEventSnapshot] = []
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var nextChangeTask: Task<Void, Never>?

    init() {
        access = Self.currentAccess()
    }

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Asks for full calendar access (reading events needs full access, not write-only).
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            // Treated like a denial below.
        }
        access = Self.currentAccess()
        if access == .granted { start() }
    }

    /// Starts listening for changes. Does nothing until access is granted.
    func start() {
        guard access == .granted, changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func stop() {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        refreshTask?.cancel()
        nextChangeTask?.cancel()
        upcoming = nil
    }

    /// Opens Privacy & Security → Calendars, for when access was denied.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            // EventKit queries can take a moment with many calendars; keep them off the main actor.
            let events = await Self.fetchEvents(from: Date())
            guard !Task.isCancelled else { return }
            self?.apply(events)
        }
    }

    private func apply(_ newEvents: [CalendarEventSnapshot]) {
        events = newEvents
        reselect()
    }

    private func reselect() {
        let now = Date()
        let selected = UpcomingEventSelector.select(from: events, at: now)
        if selected != upcoming { upcoming = selected }

        nextChangeTask?.cancel()
        guard let next = UpcomingEventSelector.nextChange(in: events, after: now) else { return }
        nextChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow + 0.5))
            guard !Task.isCancelled else { return }
            self?.reselect()
        }
    }

    @concurrent
    private nonisolated static func fetchEvents(from date: Date) async -> [CalendarEventSnapshot] {
        // A store of its own: EKEventStore is not Sendable, and this runs off the main actor.
        let store = EKEventStore()
        let end = date.addingTimeInterval(UpcomingEventSelector.lookahead)
        // Starts a day back so events that began earlier but are still running are included.
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-86_400), end: end, calendars: nil)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled, let start = event.startDate, let end = event.endDate else { return nil }
            let color = event.calendar?.color?.usingColorSpace(.sRGB)
            return CalendarEventSnapshot(
                id: event.calendarItemIdentifier + "|\(start.timeIntervalSince1970)",
                title: event.title ?? "",
                start: start,
                end: end,
                isAllDay: event.isAllDay,
                location: event.location,
                calendarColor: color.map { RGBColor(red: $0.redComponent, green: $0.greenComponent, blue: $0.blueComponent) }
            )
        }
    }
}
