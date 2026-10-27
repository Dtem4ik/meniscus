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
        queue.post(activity("charging", .alert, updated: 0, expires: 5))
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
        queue.post(activity("charging", .alert, expires: 4))
        #expect(queue.current(at: t0.addingTimeInterval(3.9))?.id == "charging")
        #expect(queue.current(at: t0.addingTimeInterval(4))?.id == "music")
        queue.removeExpired(at: t0.addingTimeInterval(4))
        #expect(queue.activities.map(\.id) == ["music"])
    }

    @Test func postingSameIdReplacesInPlace() {
        var queue = ActivityQueue()
        queue.post(activity("charging", .alert, expires: 4))
        queue.post(activity("charging", .alert, updated: 2, expires: 6))
        #expect(queue.activities.count == 1)
        #expect(queue.activities.first?.expiresAt == t0.addingTimeInterval(6))
    }

    @Test func removeDropsActivity() {
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing))
        queue.remove(id: "music")
        #expect(queue.current(at: t0) == nil)
    }

    @Test func nextExpirationIsTheEarliestFutureOne() {
        var queue = ActivityQueue()
        queue.post(activity("music", .ongoing))
        queue.post(activity("a", .alert, expires: 8))
        queue.post(activity("b", .alert, expires: 3))
        #expect(queue.nextExpiration(after: t0) == t0.addingTimeInterval(3))
        #expect(queue.nextExpiration(after: t0.addingTimeInterval(3)) == t0.addingTimeInterval(8))
        #expect(queue.nextExpiration(after: t0.addingTimeInterval(8)) == nil)
    }
}

@MainActor
struct ActivityCenterTests {
    @Test func transientActivityIsCurrentUntilItExpires() async throws {
        let center = ActivityCenter()
        center.post(LiveActivity(id: "music", kind: .nowPlaying, priority: .ongoing, updatedAt: .now, expiresAt: nil))
        center.postTransient(id: "charging", kind: .charging, duration: 0.2)
        #expect(center.current?.id == "charging")
        try await Task.sleep(for: .milliseconds(600))
        #expect(center.current?.id == "music")
    }
}
