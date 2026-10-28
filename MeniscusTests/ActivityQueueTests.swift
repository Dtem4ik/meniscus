import Foundation
import Testing
@testable import Meniscus

struct ActivityQueueTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func activity(
        _ id: String,
        _ priority: LiveActivity.Priority,
        updated: TimeInterval = 0,
        expires: TimeInterval? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: id,
            kind: .charging,
            priority: priority,
            updatedAt: t0.addingTimeInterval(updated),
            expiresAt: expires.map { t0.addingTimeInterval($0) }
        )
    }

    @Test func emptyQueueShowsNothing() {
        #expect(ActivityQueue().current(at: t0) == nil)
    }

    @Test func higherPriorityWins() {
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing, updated: 10))
        queue.post(activity("charging", .charging, updated: 0, expires: 5))
        #expect(queue.current(at: t0)?.id == "charging")
    }

    @Test func musicOutranksTheShelfReminder() {
        var queue = ActivityQueue()
        queue.post(activity("now-playing", .ongoing, updated: 0))
        queue.post(activity("shelf", .background, updated: 10))
        #expect(queue.current(at: t0.addingTimeInterval(20))?.id == "now-playing")
        queue.remove(id: "now-playing")
        #expect(queue.current(at: t0.addingTimeInterval(20))?.id == "shelf")
    }

    @Test func newestWinsWithinSamePriority() {
        var queue = ActivityQueue()
        queue.post(activity("a", .ongoing, updated: 1))
        queue.post(activity("b", .ongoing, updated: 2))
        #expect(queue.current(at: t0)?.id == "b")
    }

    @Test func expiredActivityFallsBackToTheNextOne() {
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing))
        queue.post(activity("charging", .charging, expires: 4))
        #expect(queue.current(at: t0.addingTimeInterval(3.9))?.id == "charging")
        #expect(queue.current(at: t0.addingTimeInterval(4))?.id == "music")
        queue.removeExpired(at: t0.addingTimeInterval(4))
        #expect(queue.activities.map(\.id) == ["music"])
    }

    @Test func postingSameIdReplacesInPlace() {
        var queue = ActivityQueue()
        queue.post(activity("charging", .charging, expires: 4))
        queue.post(activity("charging", .charging, updated: 2, expires: 6))
        #expect(queue.activities.count == 1)
        #expect(queue.activities.first?.expiresAt == t0.addingTimeInterval(6))
    }

    @Test func removeDropsActivity() {
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing))
        queue.remove(id: "music")
        #expect(queue.current(at: t0) == nil)
    }

    @Test func priorityOrderOfLiveActivities() {
        // docs/external-api.md, section 6.
        let order: [LiveActivity.Priority] = [
            .background, .externalActivity, .external, .ongoing, .confirmation, .charging,
            .externalAttention, .directFeedback, .deviceLowBattery, .lowBattery, .meeting, .interaction,
        ]
        #expect(order == order.sorted())
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing))
        queue.post(activity("layout", .directFeedback, updated: 5, expires: 1))
        queue.post(activity("battery", .lowBattery, updated: 1, expires: 4))
        queue.post(activity("meeting", .meeting, updated: 0, expires: 300))
        #expect(queue.current(at: t0)?.id == "meeting")
        queue.remove(id: "meeting")
        #expect(queue.current(at: t0)?.id == "battery")
        // Short activities show over music and give it back when they end.
        #expect(queue.current(at: t0.addingTimeInterval(4))?.id == "music")
    }

    @Test func nextExpirationIsTheEarliestFutureOne() {
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing))
        queue.post(activity("a", .charging, expires: 8))
        queue.post(activity("b", .charging, expires: 3))
        #expect(queue.nextExpiration(after: t0) == t0.addingTimeInterval(3))
        #expect(queue.nextExpiration(after: t0.addingTimeInterval(3)) == t0.addingTimeInterval(8))
        #expect(queue.nextExpiration(after: t0.addingTimeInterval(8)) == nil)
    }
    @Test func aWaitingNoticeGetsItsFullTimeOnceShown() {
        var queue = ActivityQueue()
        queue.post(activity("meeting", .meeting, expires: 5))
        var banner = activity("banner", .external, updated: 1)
        banner.displayDuration = 3
        banner.showBy = t0.addingTimeInterval(15)
        queue.post(banner)
        #expect(queue.current(at: t0.addingTimeInterval(4))?.id == "meeting")
        // The meeting ends at 5; the banner starts its 3 s then, not when it was posted.
        let shownAt = t0.addingTimeInterval(5)
        #expect(queue.current(at: shownAt)?.id == "banner")
        queue.startClock(of: "banner", at: shownAt)
        #expect(queue.current(at: t0.addingTimeInterval(7.5))?.id == "banner")
        #expect(queue.current(at: t0.addingTimeInterval(8)) == nil)
    }

    @Test func aNoticeNeverShownByItsDeadlineIsDropped() {
        var queue = ActivityQueue()
        queue.post(activity("meeting", .meeting, expires: 60))
        var banner = activity("banner", .external, updated: 1)
        banner.displayDuration = 3
        banner.showBy = t0.addingTimeInterval(15)
        queue.post(banner)
        #expect(queue.nextExpiration(after: t0) == t0.addingTimeInterval(15))
        queue.removeExpired(at: t0.addingTimeInterval(16))
        #expect(!queue.contains(id: "banner"))
    }

    @Test func noticesThatWaitInLineShowOldestFirst() {
        var queue = ActivityQueue()
        for (index, id) in ["first", "second", "third"].enumerated() {
            var banner = activity(id, .external, updated: Double(index))
            banner.waitsInLine = true
            queue.post(banner)
        }
        #expect(queue.current(at: t0)?.id == "first")
        queue.remove(id: "first")
        #expect(queue.current(at: t0)?.id == "second")
    }
}

@MainActor
struct ActivityCenterTests {
    @Test func transientActivityIsCurrentUntilItExpires() async throws {
        let center = ActivityCenter()
        center.post(LiveActivity(id: "music", kind: .nowPlaying, priority: .ongoing, updatedAt: .now, expiresAt: nil))
        center.postTransient(id: "charging", kind: .charging, duration: 0.2, priority: .charging)
        #expect(center.current?.id == "charging")
        try await Task.sleep(for: .milliseconds(600))
        #expect(center.current?.id == "music")
    }
}
