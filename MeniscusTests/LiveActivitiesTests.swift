import AppKit
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

    @Test func announcesTwiceBrieflyNotContinuously() {
        let meeting = event("call", startsIn: 5)
        // Five minutes ahead: "soon", once.
        let soon = MeetingReminder.dueMoments(in: [meeting], at: now, announced: [])
        #expect(soon.map(\.moment) == [.soon])
        let announced: Set<String> = [MeetingReminder.key(meeting, .soon)]
        #expect(MeetingReminder.dueMoments(in: [meeting], at: now.addingTimeInterval(30), announced: announced).isEmpty)
        // Nothing in between.
        #expect(MeetingReminder.dueMoments(in: [meeting], at: now.addingTimeInterval(120), announced: announced).isEmpty)
        // At the start: "starting", once.
        #expect(MeetingReminder.dueMoments(in: [meeting], at: meeting.start, announced: announced).map(\.moment) == [.starting])
        // A moment missed by more than the window isn't shown late.
        #expect(MeetingReminder.dueMoments(in: [meeting], at: meeting.start.addingTimeInterval(120), announced: announced).isEmpty)
    }

    @Test func compactTextIsShort() {
        let start = now.addingTimeInterval(5 * 60 + 10)
        #expect(CompactText.meeting(start: start, moment: .soon, at: now).hasPrefix("6"))
        #expect(CompactText.meeting(start: now, moment: .starting, at: now) == String(localized: "now"))
        #expect(CompactText.percent(20).hasPrefix("20"))
    }

    @Test func countdownRoundsUp() {
        #expect(MeetingReminder.minutesUntil(now.addingTimeInterval(4 * 60 + 1), from: now) == 5)
        #expect(MeetingReminder.minutesUntil(now.addingTimeInterval(60), from: now) == 1)
        #expect(MeetingReminder.minutesUntil(now.addingTimeInterval(-10), from: now) == 0)
    }

    @Test func wakesUpAtTheReminderBoundaries() {
        let soon = event("soon", startsIn: 20)
        #expect(MeetingReminder.boundaries(of: [soon]) == [soon.start - 300, soon.start, soon.start + 60])
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

struct InputSourceChangeFilterTests {
    @Test func showsOnlyRealChanges() {
        var filter = InputSourceChangeFilter()
        // The baseline at start is not shown.
        _ = filter.accept("com.apple.keylayout.Russian")
        let notifications = [
            "com.apple.keylayout.ABC", "com.apple.keylayout.ABC",
            "com.apple.keylayout.Russian",
            "com.apple.keylayout.Russian",
        ]
        let shown = notifications.filter { filter.accept($0) }
        // РУ → EN → РУ: each change once, always the layout switched to.
        #expect(shown == ["com.apple.keylayout.ABC", "com.apple.keylayout.Russian"])
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
        #expect(settings.showHeadphones)
        #expect(settings.hideFromScreenCapture)
    }
}

struct CompactWingTests {
    private func layout() -> IslandLayout {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        return IslandLayout(geometry: NotchGeometry(
            kind: .hardware,
            screenFrame: screen,
            notchRect: CGRect(x: 661, y: 950, width: 190, height: 32),
            backingScale: 2
        ))
    }

    private func width(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: CompactText.fontSize, weight: .semibold)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The longest value each activity shows, in English and Russian, and its symbol.
    @Test(arguments: [
        "6 min", "6 мин", "88 мин", "now", "сейчас",   // meeting
        "100%", "20%", "10%",                          // charging, low battery
        "EN", "РУ", "УК", "DE",                        // keyboard layout
        "Saved", "Сохранено",                          // quick capture
        "12",                                          // shelf
        "Off", "Откл.", "On", "Вкл.", "AirPods",       // headphones
    ])
    func valueFitsItsSide(text: String) {
        let layout = layout()
        let content = max(width(text), 16)
        let wing = layout.compactWing(contentWidth: content)
        let slot = wing - 2 * layout.metrics.compactSlotPadding
        #expect(slot >= content, "\(text) is \(content) pt, the side holds \(slot) pt")
    }

    @Test func sidesAreSymmetricAndTheNotchCentered() {
        let layout = layout()
        for content: CGFloat in [10, 30, 60, 200] {
            let wing = layout.compactWing(contentWidth: content)
            let spec = layout.shape(for: .compact, compactWing: wing)
            #expect(spec.width == layout.geometry.notchRect.width + 2 * wing)
            let rect = layout.interactiveScreenRect(for: .compact, compactWing: wing)
            #expect(abs(rect.midX - layout.geometry.notchRect.midX) < 0.01)
            #expect(wing >= layout.metrics.compactMinWingWidth && wing <= layout.metrics.compactMaxWingWidth)
        }
    }

    @Test func widerContentWidensTheSides() {
        let layout = layout()
        #expect(layout.compactWing(contentWidth: 50) > layout.compactWing(contentWidth: 20))
    }
}

@MainActor
struct NoActivityHangsTests {
    @Test func everySimulationEndsByItself() {
        let services = ActivityServices.shared
        services.simulateLowBattery()
        #expect(services.center.current?.kind == .lowBattery)
        #expect(services.center.current?.expiresAt != nil)
        services.calendar.simulateStartingSoon()
        let meeting = services.center.current
        #expect(meeting?.kind == .meeting)
        if let expiresAt = meeting?.expiresAt {
            #expect(expiresAt.timeIntervalSinceNow <= ActivityServices.meetingActivityDuration + 1)
        } else {
            Issue.record("The meeting reminder never ends")
        }
    }

    @Test func headphonesSimulationEndsByItself() {
        let services = ActivityServices()
        services.simulateHeadphones()
        #expect(services.center.current?.kind == .headphones)
        #expect(services.center.current?.expiresAt != nil)
        #expect(services.headphonesEvent?.symbol == "airpodspro")
    }

    @Test func lowerActivitiesShowAfterAHigherOneEnds() async throws {
        let center = ActivityCenter()
        center.post(LiveActivity(id: "music", kind: .nowPlaying, priority: .ongoing, updatedAt: .now, expiresAt: nil))
        center.postTransient(id: "meeting", kind: .meeting, duration: 0.2, priority: .meeting)
        center.postTransient(id: "battery", kind: .lowBattery, duration: 0.5, priority: .lowBattery)
        #expect(center.current?.id == "meeting")
        try await Task.sleep(for: .milliseconds(350))
        #expect(center.current?.id == "battery")
        try await Task.sleep(for: .milliseconds(400))
        #expect(center.current?.id == "music")
    }
}
