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
            Equalizer(
                isPlaying: nowPlaying.current?.isPlaying ?? false,
                tint: nowPlaying.artworkTint.map(Color.init(nsColor:)) ?? .primary
            )
        }
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
