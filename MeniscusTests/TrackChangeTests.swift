import AppKit
import Foundation
import Testing
@testable import Meniscus

struct TrackChangeDetectorTests {
    /// `#expect` can't call a mutating method on a local value, so the tests use a reference.
    private final class Detector {
        var value = TrackChangeDetector()
        func check(_ info: NowPlayingInfo?) -> Bool { value.check(info) }
    }

    private func track(_ title: String, artist: String = "Artist", playing: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, isPlaying: playing)
    }

    @Test func musicAlreadyPlayingAtStartIsNotAChange() {
        let detector = Detector()
        #expect(!detector.check(track("One")))
    }

    @Test func aNewTrackIsAChange() {
        let detector = Detector()
        _ = detector.check(track("One"))
        #expect(detector.check(track("Two")))
        #expect(!detector.check(track("Two")))
    }

    @Test func resumingTheSameTrackIsNot() {
        let detector = Detector()
        _ = detector.check(track("One"))
        #expect(!detector.check(track("One", playing: false)))
        #expect(!detector.check(track("One", playing: true)))
    }

    @Test func aDropoutBetweenReportsIsNot() {
        let detector = Detector()
        _ = detector.check(track("One"))
        #expect(!detector.check(nil))
        #expect(!detector.check(track("One")))
    }

    @Test func aTrackPickedWhilePausedIsAnnouncedWhenItPlays() {
        let detector = Detector()
        _ = detector.check(track("One"))
        #expect(!detector.check(track("Two", playing: false)))
        #expect(detector.check(track("Two", playing: true)))
    }

    @Test func quickSkipsAreEachAChange() {
        let detector = Detector()
        _ = detector.check(track("One"))
        #expect(detector.check(track("Two")))
        #expect(detector.check(track("Three")))
        #expect(detector.check(track("Two")))
    }

    @Test func sameTitleByAnotherArtistIsAChange() {
        let detector = Detector()
        _ = detector.check(track("Intro", artist: "A"))
        #expect(detector.check(track("Intro", artist: "B")))
    }
}

@MainActor
struct TrackBannerTests {
    @Test func showsArtworkTitleAndArtistWithoutAnIndicator() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let banner = MiniBanner.track(TrackBanner(title: "Song", artist: "Band", artwork: image))
        #expect(banner.leading == .artwork(image))
        #expect(banner.title == "Song")
        #expect(banner.subtitle == "Band")
        #expect(banner.trailing == nil)
    }

    @Test func aNoteUntilTheArtworkArrives() {
        let banner = MiniBanner.track(TrackBanner(title: "Song", artist: ""))
        #expect(banner.leading == .artwork(nil))
        #expect(banner.subtitle == nil)
    }

    @Test func quickSkipsUpdateTheBannerInsteadOfReopeningIt() {
        let services = ActivityServices()
        services.simulateTrackChange()
        let first = services.center.current
        #expect(first?.kind == .trackChange)
        #expect(first.flatMap(\.expiresAt).map { $0.timeIntervalSinceNow <= ActivityServices.bannerDuration + 0.1 } == true)
        let firstTitle = services.trackBanner?.title
        services.simulateTrackChange()
        #expect(services.center.current?.id == first?.id)
        #expect(services.trackBanner?.title != firstTitle)
        #expect((services.center.current?.expiresAt ?? .distantPast) >= (first?.expiresAt ?? .distantFuture))
    }

    @Test func cornersAreConcentricWithTheIsland() {
        let metrics = IslandMetrics.standard
        for corner in [metrics.bannerCorner, metrics.playerCorner] {
            // Radius plus inset is the island's radius: the curves share a center.
            #expect(corner.radius > 0)
        }
        #expect(metrics.bannerCorner.radius + metrics.bannerCorner.inset == metrics.bannerBottomRadius)
        #expect(metrics.playerCorner.radius + metrics.playerCorner.inset == metrics.expandedBottomRadius)
        // Never rounder than the cap, never closer than the minimum inset.
        #expect(metrics.bannerCorner.radius <= metrics.bannerLeadingSize * metrics.elementMaximumCornerFraction)
        #expect(metrics.playerCorner.radius <= metrics.playerArtworkSize * metrics.elementMaximumCornerFraction)
        #expect(metrics.bannerCorner.inset >= metrics.bannerMinimumInset)
        #expect(metrics.playerCorner.inset >= metrics.playerMinimumInset)
        // The tile sits as far from the bottom as from the side.
        #expect(abs((metrics.bannerContentHeight - metrics.bannerLeadingSize) / 2 - metrics.bannerCorner.inset) <= 0.5)
    }

    @Test func aCappedRadiusMovesTheElementIn() {
        let small = ConcentricCorner(outer: 30, size: 44, minimumInset: 8, maximumFraction: 0.24)
        #expect(small.inset == 19.5)
        #expect(small.radius == 10.5)
        #expect(small.radius <= 44 * 0.24)
        let uncapped = ConcentricCorner(outer: 12, size: 44, minimumInset: 8, maximumFraction: 0.24)
        #expect(uncapped.radius == 4)
        #expect(uncapped.inset == 8)
    }

    @Test func bannerKindRestsInTheBanner() {
        #expect(LiveActivity.Kind.trackChange.isBanner)
    }
}
