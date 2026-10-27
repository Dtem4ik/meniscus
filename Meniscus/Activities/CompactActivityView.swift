import SwiftUI

/// What a live activity shows left and right of the notch in the compact island.
struct CompactActivityView: View {
    let activity: LiveActivity
    let layout: IslandLayout

    var body: some View {
        let wing = layout.metrics.compactWingWidth
        HStack(spacing: 0) {
            leading
                .frame(width: wing)
            // The camera housing: nothing can be seen here.
            Color.clear
                .frame(width: layout.geometry.notchRect.width)
            trailing
                .frame(width: wing)
        }
        .frame(height: layout.notchHeight)
        .offset(x: layout.centerOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var leading: some View {
        switch activity.kind {
        case .charging:
            ChargingBolt()
        case .nowPlaying:
            CompactArtwork(service: ActivityServices.shared.nowPlaying)
        case .shelf:
            CompactShelfPreview(shelf: .shared)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch activity.kind {
        case .charging:
            if let level = ActivityServices.shared.chargingLevel {
                Text((Double(level) / 100).formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }
        case .nowPlaying:
            let nowPlaying = ActivityServices.shared.nowPlaying
            let shelfCount = ShelfController.shared.items.count
            HStack(spacing: 5) {
                Equalizer(
                    isPlaying: nowPlaying.current?.isPlaying ?? false,
                    tint: nowPlaying.artworkTint.map(Color.init(nsColor:)) ?? .primary
                )
                // Music comes first; a small count reminds of files on the shelf.
                if shelfCount > 0 {
                    ShelfCountBadge(count: shelfCount)
                }
            }
        case .shelf:
            let count = ShelfController.shared.items.count
            Text(count.formatted())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityLabel(Text("Files on the shelf: \(count)"))
        }
    }
}

/// The newest file on the shelf, small, left of the notch.
private struct CompactShelfPreview: View {
    let shelf: ShelfController

    var body: some View {
        if let item = shelf.items.last {
            Image(nsImage: shelf.image(for: item))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(.rect(cornerRadius: shelf.hasThumbnail(item) ? 4 : 0, style: .continuous))
                .onAppear { shelf.loadThumbnails() }
        }
    }
}

/// How many files wait on the shelf, next to the equalizer.
private struct ShelfCountBadge: View {
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.black)
            .padding(.horizontal, 4)
            .frame(minWidth: 14, minHeight: 14)
            .background(.white.opacity(0.85), in: .capsule)
            .accessibilityLabel(Text("Files on the shelf: \(count)"))
    }
}

/// The bolt bounces once when the activity appears.
private struct ChargingBolt: View {
    @State private var didAppear = false

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.green)
            .symbolEffect(.bounce, value: didAppear)
            .onAppear { didAppear = true }
            .accessibilityLabel(Text("Charging"))
    }
}
