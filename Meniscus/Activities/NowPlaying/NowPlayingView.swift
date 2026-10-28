import AppKit
import SwiftUI

/// Expanded Now Playing, dense like the system's own player: artwork, title and artist with the
/// playing app's icon in the corner, then the progress, then the controls.
struct NowPlayingView: View {
    let service: NowPlayingService
    private let metrics = IslandMetrics.standard

    var body: some View {
        if let info = service.current {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    PlayerArtwork(image: service.artwork)
                        .frame(width: metrics.playerArtworkSize, height: metrics.playerArtworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: metrics.playerArtworkCornerRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(info.artist ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity, minHeight: metrics.playerArtworkSize, alignment: .leading)

                    sourceApplication
                }
                .animation(Motion.trackChange, value: info.title)
                .animation(Motion.trackChange, value: info.artist)

                PlaybackProgress(info: info)
                    .padding(.top, 10)

                controls(isPlaying: info.isPlaying)
                    .padding(.top, 2)
            }
            .padding(.horizontal, metrics.playerHorizontalPadding)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func controls(isPlaying: Bool) -> some View {
        HStack(spacing: 18) {
            Button(action: service.previousTrack) {
                Label("Previous", systemImage: "backward.fill")
            }
            .buttonStyle(IslandControlStyle(size: 15))

            Button(action: service.togglePlayPause) {
                Label(
                    isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IslandControlStyle(size: 22))

            Button(action: service.nextTrack) {
                Label("Next", systemImage: "forward.fill")
            }
            .buttonStyle(IslandControlStyle(size: 15))
        }
    }

    /// The playing app's own icon, small in the corner; clicking it brings the app forward.
    @ViewBuilder
    private var sourceApplication: some View {
        if let url = service.sourceApplicationURL {
            let path = url.path(percentEncoded: false)
            Button(action: service.openSourceApplication) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(FileManager.default.displayName(atPath: path))
            .transition(.opacity)
        }
    }
}

/// The artwork, cross-fading when the track changes.
private struct PlayerArtwork: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.1))
                    .transition(.opacity)
            }
        }
        .animation(Motion.trackChange, value: image.map(ObjectIdentifier.init))
    }
}

/// Elapsed time, the bar and the time left. Moves once a second while playing and the island is
/// open; static otherwise.
private struct PlaybackProgress: View {
    let info: NowPlayingInfo

    var body: some View {
        if info.duration != nil, info.elapsed != nil {
            if info.isPlaying {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    row(at: context.date)
                }
            } else {
                row(at: info.timestamp ?? .now)
            }
        }
    }

    private func row(at date: Date) -> some View {
        let elapsed = info.elapsed(at: date) ?? 0
        return HStack(spacing: 8) {
            Text(PlaybackTime.elapsed(elapsed))
                .frame(minWidth: 34, alignment: .leading)
            ProgressBar(value: info.progress(at: date) ?? 0)
            Text(PlaybackTime.remaining(duration: info.duration ?? 0, elapsed: elapsed))
                .frame(minWidth: 34, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
    }
}

private struct ProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

/// "1:23" and "−2:05", through the system's duration formatter.
nonisolated enum PlaybackTime {
    static func elapsed(_ seconds: TimeInterval) -> String {
        format(seconds)
    }

    /// Time left, with a minus sign (U+2212) like the system player.
    static func remaining(duration: TimeInterval, elapsed: TimeInterval) -> String {
        "\u{2212}" + format(duration - elapsed)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 0).rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
