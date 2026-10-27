import CoreGraphics

nonisolated enum IslandPhase: Equatable, Sendable {
    case collapsed
    /// A live activity (like charging) widens the notch with content left and right of it.
    case compact
    case expanded
}

/// What the expanded island shows; each has its own size.
nonisolated enum IslandContent: Equatable, Sendable {
    /// Time, date and the next event.
    case home
    /// The player: denser, sized to its content like the system's own.
    case nowPlaying
}

/// The animatable parameters of `NotchShape`.
nonisolated struct IslandShapeSpec: Equatable, Sendable {
    /// Width of the body, without the shoulders.
    var width: CGFloat
    var height: CGFloat
    var bottomRadius: CGFloat
    /// Radius of the concave fillets where the top corners meet the top edge of the screen.
    var shoulderRadius: CGFloat

    var totalWidth: CGFloat { width + 2 * shoulderRadius }
}

/// Sizes of the island. Tune the look here; tune the motion in `Motion.swift`.
nonisolated struct IslandMetrics: Equatable, Sendable {
    /// Extra black around the hardware notch to hide anti-aliasing seams at its edges.
    var collapsedOutset: CGFloat = 0
    var collapsedBottomRadius: CGFloat = 9
    var collapsedShoulderRadius: CGFloat = 4

    var expandedWidth: CGFloat = 560
    /// Height of the area below the notch when expanded.
    var expandedContentHeight: CGFloat = 132
    var expandedBottomRadius: CGFloat = 30
    var expandedShoulderRadius: CGFloat = 12

    /// The player's area below the notch.
    var nowPlayingContentWidth: CGFloat = 344
    var nowPlayingContentHeight: CGFloat = 120

    /// Width of each side of the compact island, left and right of the notch.
    var compactWingWidth: CGFloat = 64

    /// Transparent room around the expanded island for spring overshoot and the shadow.
    var windowMargin: CGFloat = 28

    static let standard = IslandMetrics()
}

/// Where the island and its window go for a given notch. Pure, so it is unit tested.
nonisolated struct IslandLayout: Equatable, Sendable {
    var geometry: NotchGeometry
    var metrics: IslandMetrics = .standard

    var notchHeight: CGFloat { geometry.notchRect.height }
    var contentHeight: CGFloat { metrics.expandedContentHeight }
    var expandedWidth: CGFloat {
        max(metrics.expandedWidth, geometry.notchRect.width + 2 * metrics.expandedBottomRadius)
    }

    /// Size of the expanded area below the notch for the given content. The panel is sized for the
    /// largest content, so switching content only animates the shape.
    func contentSize(for content: IslandContent) -> CGSize {
        switch content {
        case .home:
            CGSize(width: expandedWidth, height: contentHeight)
        case .nowPlaying:
            CGSize(
                width: min(max(metrics.nowPlayingContentWidth, geometry.notchRect.width + 2 * metrics.expandedBottomRadius), expandedWidth),
                height: min(metrics.nowPlayingContentHeight, contentHeight)
            )
        }
    }

    func shape(for phase: IslandPhase, content: IslandContent = .home) -> IslandShapeSpec {
        switch phase {
        case .collapsed:
            IslandShapeSpec(
                width: geometry.notchRect.width + 2 * metrics.collapsedOutset,
                height: notchHeight + metrics.collapsedOutset,
                bottomRadius: metrics.collapsedBottomRadius,
                shoulderRadius: metrics.collapsedShoulderRadius
            )
        case .compact:
            IslandShapeSpec(
                width: geometry.notchRect.width + 2 * metrics.compactWingWidth,
                height: notchHeight + metrics.collapsedOutset,
                bottomRadius: metrics.collapsedBottomRadius + 4,
                shoulderRadius: metrics.collapsedShoulderRadius
            )
        case .expanded:
            IslandShapeSpec(
                width: contentSize(for: content).width,
                height: notchHeight + contentSize(for: content).height,
                bottomRadius: metrics.expandedBottomRadius,
                shoulderRadius: metrics.expandedShoulderRadius
            )
        }
    }

    /// The window is centered on a whole point so its frame stays pixel aligned. The notch can sit
    /// on a half point, so views shift their drawing by this amount.
    var centerOffset: CGFloat { geometry.notchRect.midX - windowCenterX }

    private var windowCenterX: CGFloat { geometry.notchRect.midX.rounded(.down) }

    /// Frame of the panel in screen coordinates. Its top edge is the top of the screen.
    func windowFrame(for phase: IslandPhase) -> CGRect {
        let spec = shape(for: phase)
        let margin = phase == .expanded ? metrics.windowMargin : 1
        let halfWidth = (spec.totalWidth / 2 + abs(centerOffset) + margin).rounded(.up)
        let height = (spec.height + margin).rounded(.up)
        return CGRect(
            x: windowCenterX - halfWidth,
            y: geometry.screenFrame.maxY - height,
            width: 2 * halfWidth,
            height: height
        )
    }

    /// The area that reacts to the pointer, in screen coordinates.
    func interactiveScreenRect(for phase: IslandPhase, content: IslandContent = .home) -> CGRect {
        let spec = shape(for: phase, content: content)
        return CGRect(
            x: geometry.notchRect.midX - spec.totalWidth / 2,
            y: geometry.screenFrame.maxY - spec.height,
            width: spec.totalWidth,
            height: spec.height
        )
    }
}
