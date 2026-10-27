import Testing
@testable import Meniscus

struct CalendarGroupingTests {
    private let calendars = [
        CalendarInfo(id: "w", title: "Work", sourceTitle: "Google", color: nil),
        CalendarInfo(id: "b", title: "Birthdays", sourceTitle: "Other", color: nil),
        CalendarInfo(id: "h", title: "Home", sourceTitle: "iCloud", color: nil),
        CalendarInfo(id: "f", title: "Family", sourceTitle: "Google", color: nil),
    ]

    @Test func groupsByAccountInNameOrder() {
        let groups = CalendarGrouping.bySource(calendars)
        #expect(groups.map(\.source) == ["Google", "iCloud", "Other"])
        #expect(groups.first?.calendars.map(\.title) == ["Family", "Work"])
    }

    @Test func everyCalendarIsIncludedUntilHidden() {
        #expect(CalendarGrouping.included(calendars, hiding: []) == ["w", "b", "h", "f"])
        #expect(CalendarGrouping.included(calendars, hiding: ["w", "gone"]) == ["b", "h", "f"])
    }
}
