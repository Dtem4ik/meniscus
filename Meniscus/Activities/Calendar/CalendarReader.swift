import AppKit
import EventKit

/// A calendar the user can show or hide, from any account set up in System Settings →
/// Internet Accounts (iCloud, Google, Exchange, CalDAV) or on this Mac.
nonisolated struct CalendarInfo: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    /// The account, for example "iCloud" or the Google account's address.
    var sourceTitle: String
    var color: RGBColor?
}

nonisolated enum CalendarGrouping {
    /// Calendars grouped by account, accounts and calendars sorted by name.
    static func bySource(_ calendars: [CalendarInfo]) -> [(source: String, calendars: [CalendarInfo])] {
        Dictionary(grouping: calendars, by: \.sourceTitle)
            .map { source, calendars in
                (source: source, calendars: calendars.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.source.localizedStandardCompare($1.source) == .orderedAscending }
    }

    /// The identifiers to query: every calendar except the hidden ones. Calendars added later
    /// are shown until hidden.
    static func included(_ calendars: [CalendarInfo], hiding hidden: Set<String>) -> Set<String> {
        Set(calendars.map(\.id)).subtracting(hidden)
    }
}

/// Owns the one EventKit store and runs its queries off the main actor.
actor CalendarReader {
    private let store = EKEventStore()

    /// Every event calendar of every account.
    func calendars() -> [CalendarInfo] {
        store.calendars(for: .event).map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: calendar.source?.title ?? "",
                color: calendar.color.flatMap(RGBColor.init)
            )
        }
    }

    /// Events from `date` through the lookahead in the given calendars; all of them for `nil`.
    func events(from date: Date, calendarIDs: Set<String>?) -> [CalendarEventSnapshot] {
        var calendars: [EKCalendar]?
        if let calendarIDs {
            calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
            // An empty list would mean "all calendars" to EventKit.
            if calendars?.isEmpty == true { return [] }
        }
        let end = date.addingTimeInterval(UpcomingEventSelector.lookahead)
        // Starts a day back so events that began earlier but are still running are included.
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-86_400), end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap { event in
            guard event.status != .canceled, let start = event.startDate, let end = event.endDate else { return nil }
            return CalendarEventSnapshot(
                id: event.calendarItemIdentifier + "|\(start.timeIntervalSince1970)",
                title: event.title ?? "",
                start: start,
                end: end,
                isAllDay: event.isAllDay,
                location: event.location,
                calendarColor: event.calendar?.color.flatMap(RGBColor.init),
                meetingURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
            )
        }
    }
}

extension RGBColor {
    nonisolated init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }
}
