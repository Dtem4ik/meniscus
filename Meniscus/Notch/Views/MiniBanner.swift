import AppKit
import SwiftUI

/// A short notice the island shows for a few seconds below the notch: a symbol or picture on the
/// left, a title and an optional second line in the middle, an optional indicator on the right.
/// Device connections use it today; track changes and other events can describe themselves the
/// same way.
struct MiniBanner: Equatable {
    var leading: Leading
    var title: String
    var subtitle: String?
    var trailing: Trailing?

    enum Leading: Equatable {
        /// A symbol on a soft tile.
        case symbol(String, color: Color = .white)
        /// An album cover; a note on the same tile until it arrives.
        case artwork(NSImage?)
        /// An app's own icon, which has its own shape: no tile behind it.
        case appIcon(NSImage)
    }

    enum Trailing: Equatable {
        /// A battery ring with the percent inside.
        case battery(Int)
        /// A notice's state: a check mark for success, the attention glyph in the system orange
        /// (the island's only accent).
        case state(NoticeState)
    }
}

/// Lays out a `MiniBanner` in the area below the notch. Sizes come from `IslandMetrics`.
struct MiniBannerView: View {
    let banner: MiniBanner
    let metrics: IslandMetrics
    private var leadingSize: CGFloat { metrics.bannerLeadingSize }

    var body: some View {
        HStack(spacing: metrics.bannerSpacing) {
            leadingTile

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: banner.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle = banner.subtitle {
                    Text(verbatim: subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)

            switch banner.trailing {
            case .battery(let level):
                BatteryRing(level: level, diameter: metrics.bannerRingDiameter, lineWidth: metrics.bannerRingLineWidth)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            case .state(let state):
                NoticeStateGlyph(state: state, size: 17)
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, metrics.bannerHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A battery that arrives while the banner is up fades in.
        .animation(Motion.bannerUpdate, value: banner.trailing)
        .accessibilityElement(children: .combine)
    }

    /// One square tile for every kind of leading content, framed before it is clipped (artwork
    /// fills past its frame), with its corner concentric with the island's (`bannerCorner`):
    /// artwork and the placeholder note are rounded alike.
    @ViewBuilder
    private var leadingTile: some View {
        if case .appIcon(let icon) = banner.leading {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: leadingSize, height: leadingSize)
                .accessibilityHidden(true)
        } else {
            tile
        }
    }

    private var tile: some View {
        ZStack {
            Color.white.opacity(0.1)
            switch banner.leading {
            case .symbol(let name, let color):
                Image(systemName: name)
                    .font(.system(size: leadingSize * 0.5, weight: .medium))
                    .foregroundStyle(color)
            case .artwork(let image?):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .artwork(nil):
                Image(systemName: "music.note")
                    .font(.system(size: leadingSize * 0.45, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .transition(.opacity)
            case .appIcon:
                EmptyView()
            }
        }
        .frame(width: leadingSize, height: leadingSize)
        .clipShape(RoundedRectangle(cornerRadius: metrics.bannerCorner.radius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// `success`: a white check mark; `attention`: an exclamation mark in the system orange;
/// `info`: nothing.
struct NoticeStateGlyph: View {
    let state: NoticeState
    let size: CGFloat

    var body: some View {
        switch state {
        case .info:
            EmptyView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityLabel(Text("Done"))
        case .attention:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .accessibilityLabel(Text("Needs attention"))
        }
    }
}

/// A small ring that fills with the battery level, the percent inside.
struct BatteryRing: View {
    let level: Int
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let color = BatteryRingStyle.color(level: level)
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(level, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(level)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(Text(CompactText.percent(level)))
    }
}

/// Green, yellow below 20%, red below 10%.
nonisolated enum BatteryRingStyle {
    enum Tone: Equatable { case normal, low, critical }

    static func tone(level: Int) -> Tone {
        level < 10 ? .critical : level < 20 ? .low : .normal
    }

    static func color(level: Int) -> Color {
        switch tone(level: level) {
        case .normal: .green
        case .low: .yellow
        case .critical: .red
        }
    }
}
