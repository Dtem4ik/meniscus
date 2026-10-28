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
        case symbol(String, color: Color = .white)
        /// A picture, like an album cover, with rounded corners.
        case image(NSImage)
    }

    enum Trailing: Equatable {
        /// A battery ring with the percent inside.
        case battery(Int)
    }
}

/// Lays out a `MiniBanner` in the area below the notch. Sizes come from `IslandMetrics`.
struct MiniBannerView: View {
    let banner: MiniBanner
    let metrics: IslandMetrics

    var body: some View {
        HStack(spacing: metrics.bannerSpacing) {
            leading
                .frame(width: metrics.bannerLeadingSize, height: metrics.bannerLeadingSize)

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

            if case .battery(let level) = banner.trailing {
                BatteryRing(level: level, diameter: metrics.bannerRingDiameter, lineWidth: metrics.bannerRingLineWidth)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, metrics.bannerHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A battery that arrives while the banner is up fades in.
        .animation(Motion.bannerUpdate, value: banner.trailing)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leading: some View {
        switch banner.leading {
        case .symbol(let name, let color):
            Image(systemName: name)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .accessibilityHidden(true)
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: metrics.bannerLeadingCornerRadius, style: .continuous))
                .accessibilityHidden(true)
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
