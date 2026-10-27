import Foundation

/// The parts of a calendar event the island shows. Decoupled from EventKit so the selection
/// rules are unit tested.
nonisolated struct CalendarEventSnapshot: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    /// sRGB components of the calendar color, for a small dot next to the title.
    var calendarColor: RGBColor?

    func isOngoing(at date: Date) -> Bool { start <= date && date < end }
}

nonisolated struct RGBColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

nonisolated enum UpcomingEventSelector {
    /// How far ahead the island looks for the next event.
    static let lookahead: TimeInterval = 24 * 60 * 60

    /// Picks the event to show: an ongoing timed event, otherwise the next timed event that
    /// starts within the lookahead. All-day events are shown only when there's no timed event.
    static func select(from events: [CalendarEventSnapshot], at date: Date) -> CalendarEventSnapshot? {
        let relevant = events.filter { $0.end > date && $0.start < date.addingTimeInterval(lookahead) }
        let timed = relevant.filter { !$0.isAllDay }

        if let ongoing = timed.filter({ $0.isOngoing(at: date) }).min(by: { $0.end < $1.end }) {
            return ongoing
        }
        if let next = timed.min(by: { ($0.start, $0.title) < ($1.start, $1.title) }) {
            return next
        }
        return relevant.filter(\.isAllDay).min { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// When `select(from:at:)` can next return something different, if nothing in the calendar
    /// changes: the end of an ongoing event or the start of an upcoming one.
    static func nextChange(in events: [CalendarEventSnapshot], after date: Date) -> Date? {
        events.flatMap { [$0.start, $0.end] }.filter { $0 > date }.min()
    }
}
