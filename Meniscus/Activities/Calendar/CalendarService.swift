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
    /// An event starting within a few minutes, for the meeting reminder.
    private(set) var startingSoon: CalendarEventSnapshot?
    /// Called when `startingSoon` changes.
    @ObservationIgnored var onStartingSoonChange: ((CalendarEventSnapshot?) -> Void)?
    /// Every calendar of every account, for the selection in Settings.
    private(set) var calendars: [CalendarInfo] = []

    /// Calendars the user chose not to show.
    @ObservationIgnored var hiddenCalendarIDs: () -> Set<String> = { [] }

    /// Created once access is granted, so it sees every calendar from the start.
    @ObservationIgnored private var reader: CalendarReader?
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
            _ = try await EKEventStore().requestFullAccessToEvents()
        } catch {
            // Treated like a denial below.
        }
        access = Self.currentAccess()
        if access == .granted { start() }
    }

    /// Starts listening for changes. Does nothing until access is granted.
    func start() {
        guard access == .granted, changeObserver == nil else { return }
        if reader == nil { reader = CalendarReader() }
        // Posted when any account syncs or calendars change.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
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
        setStartingSoon(nil)
    }

    /// Developer menu: a reminder for a made-up meeting with a Meet link, starting in 5 minutes.
    func simulateStartingSoon() {
        let start = Date().addingTimeInterval(MeetingReminder.lead)
        setStartingSoon(CalendarEventSnapshot(
            id: "simulated-\(start.timeIntervalSince1970)",
            title: String(localized: "Sample meeting"),
            start: start,
            end: start.addingTimeInterval(30 * 60),
            isAllDay: false,
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        ))
    }

    private func setStartingSoon(_ event: CalendarEventSnapshot?) {
        guard event != startingSoon else { return }
        startingSoon = event
        onStartingSoonChange?(event)
    }

    /// Opens Privacy & Security → Calendars, for when access was denied.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Re-reads calendars and events, for example after the selection changed in Settings.
    func refresh() {
        guard let reader else { return }
        refreshTask?.cancel()
        let hidden = hiddenCalendarIDs()
        refreshTask = Task { [weak self] in
            // EventKit queries can take a moment with many calendars; the reader runs them off the
            // main actor.
            let calendars = await reader.calendars()
            let included = CalendarGrouping.included(calendars, hiding: hidden)
            let events = await reader.events(from: Date(), calendarIDs: hidden.isEmpty ? nil : included)
            guard !Task.isCancelled, let self else { return }
            if calendars != self.calendars { self.calendars = calendars }
            self.apply(events)
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
        setStartingSoon(MeetingReminder.select(from: events, at: now))

        nextChangeTask?.cancel()
        let changes = [UpcomingEventSelector.nextChange(in: events, after: now)].compactMap { $0 }
            + MeetingReminder.boundaries(of: events).filter { $0 > now }
        guard let next = changes.min() else { return }
        nextChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow + 0.5))
            guard !Task.isCancelled else { return }
            self?.reselect()
        }
    }
}
