import CoreGraphics
import Foundation
import Testing
@testable import Meniscus

struct MeetingLinkTests {
    @Test func findsZoomMeetAndTeamsLinks() {
        #expect(MeetingLink.find(in: [nil, "Room 4", "Join: https://acme.zoom.us/j/123456789?pwd=abc"])?.host() == "acme.zoom.us")
        #expect(MeetingLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.path() == "/abc-defg-hij")
        #expect(MeetingLink.find(in: ["<https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0>"]) != nil)
        #expect(MeetingLink.find(in: ["https://teams.live.com/meet/9123456789"]) != nil)
    }

    @Test func ignoresOtherLinks() {
        #expect(MeetingLink.find(in: ["Agenda: https://example.com/doc", "https://zoom.us/pricing", "https://meet.google.com/"]) == nil)
        #expect(MeetingLink.find(in: [nil, ""]) == nil)
    }

    @Test func eventURLComesFirst() {
        let url = MeetingLink.find(in: ["https://meet.google.com/aaa-bbbb-ccc", "https://acme.zoom.us/j/1"])
        #expect(url?.host() == "meet.google.com")
    }
}

struct MeetingReminderTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func event(_ id: String, startsIn minutes: Double, allDay: Bool = false) -> CalendarEventSnapshot {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEventSnapshot(id: id, title: id, start: start, end: start.addingTimeInterval(1800), isAllDay: allDay)
    }

    @Test func remindsFiveMinutesAhead() {
        let events = [event("later", startsIn: 30), event("soon", startsIn: 4.5), event("day", startsIn: 2, allDay: true)]
        #expect(MeetingReminder.select(from: events, at: now)?.id == "soon")
        #expect(MeetingReminder.select(from: [event("six", startsIn: 6)], at: now) == nil)
        // Says "now" for a minute after the start, then stops.
        #expect(MeetingReminder.select(from: [event("started", startsIn: -0.5)], at: now)?.id == "started")
        #expect(MeetingReminder.select(from: [event("over", startsIn: -2)], at: now) == nil)
    }

    @Test func countdownRoundsUp() {
        #expect(MeetingReminder.minutesUntil(now.addingTimeInterval(4 * 60 + 1), from: now) == 5)
        #expect(MeetingReminder.minutesUntil(now.addingTimeInterval(60), from: now) == 1)
        #expect(MeetingReminder.minutesUntil(now.addingTimeInterval(-10), from: now) == 0)
    }

    @Test func wakesUpAtTheReminderBoundaries() {
        let soon = event("soon", startsIn: 20)
        #expect(MeetingReminder.boundaries(of: [soon]) == [soon.start - 300, soon.start + 60])
        #expect(MeetingReminder.boundaries(of: [event("day", startsIn: 20, allDay: true)]).isEmpty)
    }

    @Test func joinShowsAroundTheMeetingOnly() {
        var meeting = event("call", startsIn: 8)
        #expect(!MeetingJoin.isOffered(for: meeting, at: now))
        meeting.meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")
        #expect(MeetingJoin.isOffered(for: meeting, at: now))
        #expect(!MeetingJoin.isOffered(for: meeting, at: now.addingTimeInterval(-3 * 60)))
        #expect(!MeetingJoin.isOffered(for: meeting, at: meeting.end))
    }
}

struct LowBatteryWarningsTests {
    private func battery(_ level: Int, charger: Bool = false) -> PowerState {
        PowerState(level: level, isOnACPower: charger, isCharging: charger)
    }

    @Test func warnsOncePerThresholdPerDischarge() {
        var warnings = LowBatteryWarnings()
        let levels = [25, 21, 20, 19, 15, 11, 10, 9, 5]
        let warned = levels.compactMap { warnings.check(battery($0)) }
        #expect(warned == [20, 10])
    }

    @Test func chargerStartsOver() {
        var warnings = LowBatteryWarnings()
        #expect(warnings.check(battery(19)) == 20)
        #expect(warnings.check(battery(19, charger: true)) == nil)
        #expect(warnings.check(battery(19)) == 20)
    }

    @Test func fallingPastBothWarnsForTheLowest() {
        var warnings = LowBatteryWarnings()
        #expect(warnings.check(battery(8)) == 10)
        #expect(warnings.check(battery(7)) == nil)
    }

    @Test func colorsFollowTheLevel() {
        #expect(BatteryWarningStyle.symbol(level: 10) == "battery.0percent")
        #expect(BatteryWarningStyle.symbol(level: 20) == "battery.25percent")
    }
}

struct InputSourceLabelTests {
    @Test func twoLettersInTheLanguageItself() {
        #expect(InputSourceLabel.shortName(languages: ["en"], localizedName: "ABC") == "EN")
        #expect(InputSourceLabel.shortName(languages: ["ru"], localizedName: "Russian") == "РУ")
        #expect(InputSourceLabel.shortName(languages: ["de"], localizedName: "German") == "DE")
        #expect(InputSourceLabel.shortName(languages: ["uk"], localizedName: "Ukrainian") == "УК")
    }

    @Test func fallsBackToTheName() {
        #expect(InputSourceLabel.shortName(languages: [], localizedName: "Emoji") == "EM")
    }
}

struct FullScreenDetectorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func frontmostWindowCoveringTheScreenIsFullScreen() {
        let windows = [
            WindowInfo(ownerPID: 7, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            WindowInfo(ownerPID: 9, layer: 25, bounds: CGRect(x: 0, y: 0, width: 1512, height: 24)),
        ]
        #expect(FullScreenDetector.isFullScreen(windows: windows, frontmostPID: 7, screenFrame: screen))
        #expect(!FullScreenDetector.isFullScreen(windows: windows, frontmostPID: 9, screenFrame: screen))
    }

    @Test func zoomedWindowIsNotFullScreen() {
        let zoomed = [WindowInfo(ownerPID: 7, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))]
        #expect(!FullScreenDetector.isFullScreen(windows: zoomed, frontmostPID: 7, screenFrame: screen))
    }

    @Test func secondScreenInWindowListCoordinates() {
        // A 1920×1080 screen above-right of a 1512×982 primary, in AppKit coordinates.
        let appKit = CGRect(x: 1512, y: 982, width: 1920, height: 1080)
        #expect(FullScreenDetector.windowListFrame(of: appKit, primaryHeight: 982) == CGRect(x: 1512, y: -1080, width: 1920, height: 1080))
    }
}

@MainActor
struct LiveActivitySettingsTests {
    @Test func everyLiveActivityIsOnByDefault() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "meniscus-live-\(UUID().uuidString)")!)
        #expect(settings.showMeetingReminders)
        #expect(settings.showLowBattery)
        #expect(settings.showCharging)
        #expect(settings.showInputSource)
        #expect(settings.showCaptureConfirmation)
        #expect(settings.hideFromScreenCapture)
    }
}
