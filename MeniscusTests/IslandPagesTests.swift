import CoreGraphics
import Testing
@testable import Meniscus

struct IslandPagesTests {
    @Test func pagesFollowWhatThereIsToShow() {
        #expect(IslandPages.available(isPlaying: false, hasShelfItems: false) == [.home])
        #expect(IslandPages.available(isPlaying: true, hasShelfItems: false) == [.nowPlaying, .home])
        #expect(IslandPages.available(isPlaying: true, hasShelfItems: true) == [.nowPlaying, .shelf, .home])
        #expect(IslandPages.available(isPlaying: false, hasShelfItems: true) == [.shelf, .home])
    }

    @Test func islandOpensOnThePlayer() {
        #expect(IslandPages.defaultPage(in: [.nowPlaying, .home]) == .nowPlaying)
        #expect(IslandPages.defaultPage(in: [.nowPlaying, .shelf, .home]) == .nowPlaying)
        #expect(IslandPages.defaultPage(in: [.shelf, .home]) == .home)
    }

    @Test func vanishedPageFallsBackToTheDefault() {
        #expect(IslandPages.resolve(.shelf, in: [.nowPlaying, .home]) == .nowPlaying)
        #expect(IslandPages.resolve(.home, in: [.nowPlaying, .home]) == .home)
    }

    @Test func turningStopsAtTheEnds() {
        let pages: [IslandPage] = [.nowPlaying, .shelf, .home]
        #expect(IslandPages.page(from: .nowPlaying, by: 1, in: pages) == .shelf)
        #expect(IslandPages.page(from: .shelf, by: -1, in: pages) == .nowPlaying)
        #expect(IslandPages.page(from: .nowPlaying, by: -1, in: pages) == nil)
        #expect(IslandPages.page(from: .home, by: 1, in: pages) == nil)
    }
}

struct PageSwipeTrackerTests {
    private func swipe(_ deltas: [CGFloat], deltaY: CGFloat = 0, tracker: inout PageSwipeTracker) -> [PageSwipeTracker.Turn] {
        var turns: [PageSwipeTracker.Turn] = []
        for (index, delta) in deltas.enumerated() {
            let phase: PageSwipeTracker.Phase = index == 0 ? .began : .changed
            if let turn = tracker.handle(phase, fingerDeltaX: delta, deltaY: deltaY) { turns.append(turn) }
        }
        _ = tracker.handle(.ended, fingerDeltaX: 0, deltaY: 0)
        return turns
    }

    @Test func fingersLeftTurnToTheNextPageOnce() {
        var tracker = PageSwipeTracker()
        #expect(swipe([-10, -15, -20, -30, -40], tracker: &tracker) == [.next])
    }

    @Test func fingersRightTurnBack() {
        var tracker = PageSwipeTracker()
        #expect(swipe([12, 12, 12, 12], tracker: &tracker) == [.previous])
    }

    @Test func shortOrVerticalScrollsDoNothing() {
        var tracker = PageSwipeTracker()
        #expect(swipe([-5, -5, -5], tracker: &tracker).isEmpty)
        #expect(swipe([-20, -20, -20], deltaY: 40, tracker: &tracker).isEmpty)
    }

    @Test func eachSwipeTurnsAgain() {
        var tracker = PageSwipeTracker()
        #expect(swipe([-40], tracker: &tracker) == [.next])
        #expect(swipe([-40], tracker: &tracker) == [.next])
    }

    @Test func momentumIsIgnored() {
        var tracker = PageSwipeTracker()
        #expect(tracker.handle(.momentum, fingerDeltaX: -100, deltaY: 0) == nil)
    }
}
