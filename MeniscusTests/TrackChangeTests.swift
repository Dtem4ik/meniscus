import AppKit
import Foundation
import Testing
@testable import Meniscus

struct TrackChangeDetectorTests {
    private func track(_ title: String, artist: String = "Artist", playing: Bool = true) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, isPlaying: playing)
    }

    @Test func musicAlreadyPlayingAtStartIsNotAChange() {
        var detector = TrackChangeDetector()
        #expect(!detector.check(track("One")))
    }

    @Test func aNewTrackIsAChange() {
        var detector = TrackChangeDetector()
        _ = detector.check(track("One"))
        #expect(detector.check(track("Two")))
        #expect(!detector.check(track("Two")))
    }

    @Test func resumingTheSameTrackIsNot() {
        var detector = TrackChangeDetector()
        _ = detector.check(track("One"))
        #expect(!detector.check(track("One", playing: false)))
        #expect(!detector.check(track("One", playing: true)))
    }

    @Test func aDropoutBetweenReportsIsNot() {
        var detector = TrackChangeDetector()
        _ = detector.check(track("One"))
        #expect(!detector.check(nil))
        #expect(!detector.check(track("One")))
    }

    @Test func aTrackPickedWhilePausedIsAnnouncedWhenItPlays() {
        var detector = TrackChangeDetector()
        _ = detector.check(track("One"))
        #expect(!detector.check(track("Two", playing: false)))
        #expect(detector.check(track("Two", playing: true)))
    }

    @Test func quickSkipsAreEachAChange() {
        var detector = TrackChangeDetector()
        _ = detector.check(track("One"))
        #expect(detector.check(track("Two")))
        #expect(detector.check(track("Three")))
        #expect(detector.check(track("Two")))
    }

    @Test func sameTitleByAnotherArtistIsAChange() {
        var detector = TrackChangeDetector()
        _ = detector.check(track("Intro", artist: "A"))
        #expect(detector.check(track("Intro", artist: "B")))
    }
}

@MainActor
struct TrackBannerTests {
    @Test func showsArtworkTitleAndArtistWithoutAnIndicator() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let banner = MiniBanner.track(TrackBanner(title: "Song", artist: "Band", artwork: image))
        #expect(banner.leading == .image(image))
        #expect(banner.title == "Song")
        #expect(banner.subtitle == "Band")
        #expect(banner.trailing == nil)
    }

    @Test func aNoteUntilTheArtworkArrives() {
        let banner = MiniBanner.track(TrackBanner(title: "Song", artist: ""))
        #expect(banner.leading == .symbol("music.note"))
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

    @Test func bannerKindRestsInTheBanner() {
        #expect(LiveActivity.Kind.trackChange.isBanner)
    }
}
