import Foundation
import Testing
@testable import Meniscus

struct UpcomingEventSelectorTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ title: String, start: TimeInterval, end: TimeInterval, allDay: Bool = false) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            id: title,
            title: title,
            start: now.addingTimeInterval(start),
            end: now.addingTimeInterval(end),
            isAllDay: allDay,
            location: nil,
            calendarColor: nil
        )
    }

    @Test func nothingToShow() {
        #expect(UpcomingEventSelector.select(from: [], at: now) == nil)
    }

    @Test func ongoingEventBeatsUpcoming() {
        let events = [event("Next", start: 600, end: 1_200), event("Now", start: -600, end: 600)]
        #expect(UpcomingEventSelector.select(from: events, at: now)?.title == "Now")
    }

    @Test func ongoingEventEndingFirstWins() {
        let events = [event("Long", start: -3_600, end: 3_600), event("Short", start: -60, end: 300)]
        #expect(UpcomingEventSelector.select(from: events, at: now)?.title == "Short")
    }

    @Test func earliestUpcomingEvent() {
        let events = [event("Later", start: 7_200, end: 9_000), event("Soon", start: 900, end: 1_800)]
        #expect(UpcomingEventSelector.select(from: events, at: now)?.title == "Soon")
    }

    @Test func endedAndFarFutureEventsAreIgnored() {
        let events = [event("Ended", start: -3_600, end: -60), event("Next week", start: 7 * 86_400, end: 7 * 86_400 + 3_600)]
        #expect(UpcomingEventSelector.select(from: events, at: now) == nil)
    }

    @Test func allDayEventOnlyWhenNoTimedEvent() {
        let allDay = event("Holiday", start: -3_600, end: 80_000, allDay: true)
        #expect(UpcomingEventSelector.select(from: [allDay], at: now)?.title == "Holiday")
        #expect(UpcomingEventSelector.select(from: [allDay, event("Call", start: 600, end: 1_200)], at: now)?.title == "Call")
    }

    @Test func nextChangeIsTheNearestBoundary() {
        let events = [event("Now", start: -600, end: 600), event("Next", start: 300, end: 900)]
        #expect(UpcomingEventSelector.nextChange(in: events, after: now) == now.addingTimeInterval(300))
    }
}
