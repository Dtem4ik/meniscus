import AppKit
import SwiftUI

/// Expanded Now Playing: artwork, title, artist, progress, controls and the playing app.
/// Functional layout; visual polish comes with the rest of the island content.
struct NowPlayingView: View {
    let service: NowPlayingService

    var body: some View {
        if let info = service.current {
            HStack(spacing: 14) {
                artwork
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let artist = info.artist {
                        Text(artist)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    PlaybackProgress(info: info)
                }
                .frame(maxWidth: 240, alignment: .leading)

                controls(isPlaying: info.isPlaying)
                sourceApplication
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = service.artwork {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.fill.tertiary)
        }
    }

    private func controls(isPlaying: Bool) -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: service.previousTrack) {
                    Label("Previous", systemImage: "backward.fill")
                }
                .islandControl()
                Button(action: service.togglePlayPause) {
                    Label(
                        isPlaying ? String(localized: "Pause") : String(localized: "Play"),
                        systemImage: isPlaying ? "pause.fill" : "play.fill"
                    )
                        .contentTransition(.symbolEffect(.replace))
                }
                .islandControl()
                Button(action: service.nextTrack) {
                    Label("Next", systemImage: "forward.fill")
                }
                .islandControl()
            }
        }
    }

    /// The playing app's own icon; clicking it brings the app forward.
    @ViewBuilder
    private var sourceApplication: some View {
        if let url = service.sourceApplicationURL {
            Button(action: service.openSourceApplication) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(FileManager.default.displayName(atPath: url.path(percentEncoded: false)))
        }
    }
}

/// Moves once a second while playing and the island is open; static otherwise.
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
        HStack(spacing: 6) {
            ProgressView(value: info.progress(at: date) ?? 0)
                .progressViewStyle(.linear)
            Text(Duration.seconds(info.elapsed(at: date) ?? 0), format: .time(pattern: .minuteSecond))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
