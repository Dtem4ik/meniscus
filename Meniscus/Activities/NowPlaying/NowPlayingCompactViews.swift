import SwiftUI

/// Left of the notch: a small copy of the artwork.
struct CompactArtwork: View {
    let service: NowPlayingService

    var body: some View {
        Group {
            if let artwork = service.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.fill.tertiary)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Right of the notch: bars that move while music plays, in the artwork's color.
///
/// The bars don't measure audio (that would need access to system audio); they suggest playback.
/// They only animate while something is playing and the compact island is on screen, because the
/// view exists only then; paused, they rest low.
struct Equalizer: View {
    let isPlaying: Bool
    let tint: Color

    private static let barCount = 4
    private static let interval: TimeInterval = 0.18

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.interval, paused: !isPlaying)) { context in
            let tick = isPlaying ? Int(context.date.timeIntervalSinceReferenceDate / Self.interval) : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<Self.barCount, id: \.self) { bar in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: isPlaying ? Self.height(bar: bar, tick: tick) : 3)
                }
            }
            .frame(height: 16)
            .animation(.spring(duration: Self.interval * 1.4, bounce: 0.3), value: tick)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Now playing"))
    }

    /// Pseudo-random but deterministic heights between 4 and 16 points.
    static func height(bar: Int, tick: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: tick &* 31 &+ bar &* 7_919)
        value ^= value >> 33
        value &*= 0xff51_afd7_ed55_8ccd
        value ^= value >> 33
        return 4 + CGFloat(value % 13)
    }
}
