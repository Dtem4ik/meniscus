import AppKit

/// Decides when a new track deserves the mini banner: a different track that is playing. The
/// same track resuming after a pause, or coming back after the player briefly reported nothing,
/// isn't news. Pure, so it is unit tested.
nonisolated struct TrackChangeDetector: Equatable, Sendable {
    /// Title, artist and album of the last track announced or seen at start.
    private(set) var last: String?
    private var hasBaseline = false

    static func identity(of info: NowPlayingInfo) -> String {
        [info.title, info.artist ?? "", info.album ?? ""].joined(separator: "\u{1F}")
    }

    /// Whether this report is a track change to announce. The first track seen is the baseline:
    /// music that was already playing when Meniscus started isn't a change.
    mutating func check(_ info: NowPlayingInfo?) -> Bool {
        guard let info, !info.title.isEmpty else { return false }
        let identity = Self.identity(of: info)
        guard hasBaseline else {
            hasBaseline = true
            last = identity
            return false
        }
        // A new track picked while paused is announced once it plays.
        guard identity != last, info.isPlaying else { return false }
        last = identity
        return true
    }
}

/// What the track change banner shows: taken when the track changes, so quick skips each show
/// their own track, and filled in when the artwork arrives.
struct TrackBanner: Equatable {
    var title: String
    var artist: String?
    var artwork: NSImage?
}

extension MiniBanner {
    /// The artwork on the left (a note until it arrives), title and artist; nothing on the right.
    static func track(_ track: TrackBanner) -> MiniBanner {
        MiniBanner(
            leading: .artwork(track.artwork),
            title: track.title,
            subtitle: track.artist.flatMap { $0.isEmpty ? nil : $0 },
            trailing: nil
        )
    }
}
