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
    /// A Zoom, Google Meet or Microsoft Teams link found in the event, for Join.
    var meetingURL: URL?

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

/// Finds the link to join an online meeting in an event's URL, location or notes.
nonisolated enum MeetingLink {
    static func find(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, isMeeting(url) { return url }
            }
        }
        return nil
    }

    /// Zoom (any company subdomain), Google Meet and Microsoft Teams join links.
    static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return url.scheme?.lowercased() == "zoommtg" }
        let path = url.path().lowercased()
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return ["/j/", "/my/", "/w/", "/s/"].contains { path.hasPrefix($0) }
        }
        if host == "meet.google.com" { return path.count > 1 }
        if host == "teams.microsoft.com" { return path.contains("meetup-join") }
        if host == "teams.live.com" { return path.hasPrefix("/meet/") }
        return false
    }
}

/// When to remind of an event: from a few minutes before it starts until shortly after.
nonisolated enum MeetingReminder {
    static let lead: TimeInterval = 5 * 60
    /// Keeps saying "now" for a moment after the start.
    static let afterStart: TimeInterval = 60

    /// The timed event to remind of at `date`: the soonest one starting within the lead time.
    static func select(from events: [CalendarEventSnapshot], at date: Date) -> CalendarEventSnapshot? {
        events
            .filter { !$0.isAllDay && $0.start - lead <= date && date < $0.start + afterStart }
            .min { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// The moments the reminder can change by itself.
    static func boundaries(of events: [CalendarEventSnapshot]) -> [Date] {
        events.filter { !$0.isAllDay }.flatMap { [$0.start - lead, $0.start + afterStart] }
    }

    /// Whole minutes until the start, rounded up; 0 once it started.
    static func minutesUntil(_ start: Date, from date: Date) -> Int {
        max(0, Int((start.timeIntervalSince(date) / 60).rounded(.up)))
    }
}
