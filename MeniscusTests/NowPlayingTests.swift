import Foundation
import Testing
@testable import Meniscus

struct AdapterMessageTests {
    private func decode(_ json: String) -> AdapterMessage? {
        AdapterMessage.decode(Data(json.utf8))
    }

    private let fullPayload = """
    {"type":"data","diff":false,"payload":{"processIdentifier":4242,"bundleIdentifier":"com.example.player",\
    "playing":true,"title":"Song","artist":"Artist","album":"","durationMicros":200000000,\
    "elapsedTimeMicros":10000000,"timestampEpochMicros":1700000000000000,"playbackRate":1,\
    "artworkMimeType":"image/png","artworkData":"AAEC"}}
    """

    @Test func decodesAFullMessage() throws {
        let message = try #require(decode(fullPayload))
        #expect(!message.isDiff)
        #expect(message.values["playing"] == .bool(true))
        #expect(message.values["processIdentifier"] == .number(4242))
        #expect(message.artwork == .set(Data([0, 1, 2])))
    }

    @Test func ignoresOtherLines() {
        #expect(decode(#"{"type":"error","payload":{}}"#) == nil)
        #expect(decode("not json") == nil)
        #expect(decode("") == nil)
    }

    @Test func derivesInfoFromState() throws {
        var state = NowPlayingStreamState()
        state.apply(try #require(decode(fullPayload)))
        let info = try #require(state.info)
        #expect(info.title == "Song")
        #expect(info.artist == "Artist")
        #expect(info.album == nil)
        #expect(info.isPlaying)
        #expect(info.duration == 200)
        #expect(info.elapsed == 10)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(info.processIdentifier == 4242)
        #expect(state.artworkData == Data([0, 1, 2]))
    }

    @Test func diffsUpdateAndRemoveKeys() throws {
        var state = NowPlayingStreamState()
        state.apply(try #require(decode(fullPayload)))
        state.apply(try #require(decode(#"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#)))
        let info = try #require(state.info)
        #expect(!info.isPlaying)
        #expect(info.artist == nil)
        #expect(info.title == "Song")
        // A diff without artwork keeps the artwork.
        #expect(state.artworkData == Data([0, 1, 2]))
    }

    @Test func emptyFullPayloadMeansNothingIsPlaying() throws {
        var state = NowPlayingStreamState()
        state.apply(try #require(decode(fullPayload)))
        state.apply(try #require(decode(#"{"type":"data","diff":false,"payload":{}}"#)))
        #expect(state.info == nil)
        #expect(state.artworkData == nil)
    }

    @Test func titleIsRequired() throws {
        var state = NowPlayingStreamState()
        state.apply(try #require(decode(#"{"type":"data","diff":false,"payload":{"playing":true,"title":""}}"#)))
        #expect(state.info == nil)
    }
}

struct NowPlayingInfoTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func info(playing: Bool = true, elapsed: TimeInterval? = 10, duration: TimeInterval? = 100, rate: Double? = nil) -> NowPlayingInfo {
        NowPlayingInfo(
            processIdentifier: 1, bundleIdentifier: "com.example.helper", parentBundleIdentifier: nil,
            title: "Song", artist: nil, album: nil, isPlaying: playing,
            duration: duration, elapsed: elapsed, timestamp: t0, playbackRate: rate
        )
    }

    @Test func extrapolatesWhilePlaying() {
        #expect(info().elapsed(at: t0.addingTimeInterval(5)) == 15)
        #expect(info(rate: 2).elapsed(at: t0.addingTimeInterval(5)) == 20)
        #expect(info(playing: false).elapsed(at: t0.addingTimeInterval(5)) == 10)
    }

    @Test func clampsToDuration() {
        #expect(info(elapsed: 95).elapsed(at: t0.addingTimeInterval(60)) == 100)
        #expect(info(elapsed: 95).progress(at: t0.addingTimeInterval(60)) == 1)
    }

    @Test func unknownTimesHaveNoProgress() {
        #expect(info(elapsed: nil).progress(at: t0) == nil)
        #expect(info(duration: nil).progress(at: t0) == nil)
    }

    @Test func parentAppIsTheSource() {
        var value = info()
        #expect(value.sourceBundleIdentifier == "com.example.helper")
        value.parentBundleIdentifier = "com.example.browser"
        #expect(value.sourceBundleIdentifier == "com.example.browser")
    }
}

/// Runs the real adapter from the app bundle. If a macOS update breaks it, this fails in CI
/// before users notice.
struct MediaRemoteAdapterIntegrationTests {
    @Test func adapterIsBundled() throws {
        _ = try MediaRemoteAdapter.bundled().get()
    }

    @Test(.timeLimit(.minutes(1)))
    func adapterSelfTestPasses() async throws {
        let adapter = try MediaRemoteAdapter.bundled().get()
        let report = await adapter.selfTestReport()
        #expect(report.passed, "Adapter output: \(report.output)")
    }
}
