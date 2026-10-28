import CoreGraphics

nonisolated enum IslandPhase: Equatable, Sendable {
    case collapsed
    /// A live activity (like charging) widens the notch with content left and right of it.
    case compact
    /// A short notice: the island opens a little way down for a few seconds (see `MiniBanner`).
    case banner
    case expanded
}

/// What the expanded island shows; each has its own size.
nonisolated enum IslandContent: Equatable, Sendable {
    /// Time, date and the next event, at the size they measure (padding included); `nil` until
    /// measured.
    case home(CGSize?)
    /// The player: denser, sized to its content like the system's own.
    case nowPlaying
    /// The quick capture field.
    case capture
    /// The file shelf with this many files.
    case shelf(itemCount: Int)
    /// A large target while files are dragged toward the notch.
    case dropZone
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

    /// Width of each side of the compact island, left and right of the notch, until its content
    /// is measured.
    var compactWingWidth: CGFloat = 64
    /// Room around the content on each side of the compact island.
    var compactSlotPadding: CGFloat = 10
    /// Each side is as wide as its content needs, within these bounds.
    var compactMinWingWidth: CGFloat = 36
    var compactMaxWingWidth: CGFloat = 104

    /// The mini banner: a short notice below the notch, smaller than the expanded island. As
    /// wide as its content needs, up to this; longer titles end in an ellipsis.
    var bannerMaximumWidth: CGFloat = 360
    /// At least this much wider than the notch on each side.
    var bannerMinimumWingWidth: CGFloat = 36
    var bannerContentHeight: CGFloat = 46
    var bannerBottomRadius: CGFloat = 22
    var bannerShoulderRadius: CGFloat = 8
    var bannerHorizontalPadding: CGFloat = 14
    var bannerSpacing: CGFloat = 10
    /// The tile on the left (artwork, or a symbol) is as tall as both lines of text; this is
    /// its size until the text has been measured.
    var bannerLeadingFallbackSize: CGFloat = 30
    /// The battery ring on the right.
    var bannerRingDiameter: CGFloat = 26
    var bannerRingLineWidth: CGFloat = 2.5

    /// The expanded island is always wider than the compact one, so opening grows it sideways as
    /// well as down: by this share of the compact width…
    var expansionRatio: CGFloat = 0.18
    /// …but by at least this much on each side.
    var minimumExpansionPerSide: CGFloat = 40

    /// Upper bounds of the expanded island; the window is sized for them.
    var maximumExpandedWidth: CGFloat = 560
    /// Height of the area below the notch.
    var maximumContentHeight: CGFloat = 132
    var expandedBottomRadius: CGFloat = 30
    var expandedShoulderRadius: CGFloat = 12

    /// The artwork in the open player, and the player's distance from the island's sides.
    var playerArtworkSize: CGFloat = 44
    var playerHorizontalPadding: CGFloat = 18

    /// The player's area below the notch. Its width follows the rule above.
    var nowPlayingContentHeight: CGFloat = 126
    /// The quick capture field below the notch.
    var captureContentWidth: CGFloat = 420
    var captureContentHeight: CGFloat = 56
    /// The file shelf: one tile per file, then the shelf's own buttons.
    var shelfTileWidth: CGFloat = 72
    var shelfTileSpacing: CGFloat = 8
    var shelfHorizontalPadding: CGFloat = 20
    var shelfControlsWidth: CGFloat = 40
    var shelfContentHeight: CGFloat = 96
    /// The drop target's height below the notch; it takes the full expanded width.
    var dropZoneHeight: CGFloat = 120
    /// A file drag this close to the top of the screen, near the notch, opens the drop target,
    /// well before the pointer reaches the edge where macOS opens Mission Control.
    var dropZoneApproachDistance: CGFloat = 90
    /// It closes again once the drag moves this far from the top.
    var dropZoneLeaveDistance: CGFloat = 180
    /// How far to either side of the expanded island a drag still counts as near.
    var dropZoneSideMargin: CGFloat = 120
    /// Home content before it has been measured.
    var homeFallbackSize = CGSize(width: 420, height: 80)
    /// Room around the home content (time, date, event).
    var homeHorizontalPadding: CGFloat = 24
    var homeTopPadding: CGFloat = 6
    var homeBottomPadding: CGFloat = 18

    /// Transparent room around the expanded island for spring overshoot and the shadow.
    var windowMargin: CGFloat = 28

    static let standard = IslandMetrics()

    // MARK: Concentric corners

    /// The radius of a corner set `inset` in from a corner of radius `outer`, so both curves
    /// share a center, as macOS draws nested corners. Every rounded element that sits near the
    /// island's edge takes its radius from here.
    static func concentricRadius(outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat {
        max(outer - inset, minimum)
    }

    /// The tile on the left of a mini banner (artwork, a placeholder or a symbol).
    var bannerLeadingCornerRadius: CGFloat {
        Self.concentricRadius(outer: bannerBottomRadius, inset: bannerHorizontalPadding)
    }

    /// The artwork in the open player.
    var playerArtworkCornerRadius: CGFloat {
        Self.concentricRadius(outer: expandedBottomRadius, inset: playerHorizontalPadding)
    }
}

/// Where the island and its window go for a given notch. Pure, so it is unit tested.
nonisolated struct IslandLayout: Equatable, Sendable {
    var geometry: NotchGeometry
    var metrics: IslandMetrics = .standard

    var notchHeight: CGFloat { geometry.notchRect.height }

    var compactWidth: CGFloat { geometry.notchRect.width + 2 * metrics.compactWingWidth }

    /// The narrowest expanded island: the compact width plus `expansionRatio`, at least
    /// `minimumExpansionPerSide` on each side.
    var minimumExpandedWidth: CGFloat {
        let extra = max(compactWidth * metrics.expansionRatio, 2 * metrics.minimumExpansionPerSide)
        return max(compactWidth + extra, geometry.notchRect.width + 2 * metrics.expandedBottomRadius)
    }

    var maximumExpandedWidth: CGFloat { max(metrics.maximumExpandedWidth, minimumExpandedWidth) }

    /// Size of the expanded area below the notch: the content's own size, at least
    /// `minimumExpandedWidth` wide and within the maximums.
    func contentSize(for content: IslandContent) -> CGSize {
        let natural = switch content {
        case .home(let measured): measured ?? metrics.homeFallbackSize
        case .nowPlaying: CGSize(width: 0, height: metrics.nowPlayingContentHeight)
        case .capture: CGSize(width: metrics.captureContentWidth, height: metrics.captureContentHeight)
        case .shelf(let count): CGSize(width: shelfWidth(itemCount: count), height: metrics.shelfContentHeight)
        case .dropZone: CGSize(width: maximumExpandedWidth, height: metrics.dropZoneHeight)
        }
        return CGSize(
            width: min(max(natural.width.rounded(.up), minimumExpandedWidth), maximumExpandedWidth),
            height: min(natural.height.rounded(.up), metrics.maximumContentHeight)
        )
    }

    /// Whether a file drag at `point` (screen coordinates) is near enough to the notch for the
    /// drop target. `isOpen` widens the area, so the target doesn't flicker at its edge.
    func isNearDropZone(_ point: CGPoint, isOpen: Bool) -> Bool {
        let screen = geometry.screenFrame
        guard point.x >= screen.minX, point.x <= screen.maxX, point.y <= screen.maxY + 1 else { return false }
        let fromTop = screen.maxY - point.y
        let sideways = abs(point.x - geometry.notchRect.midX)
        let halfWidth = maximumExpandedWidth / 2 + metrics.dropZoneSideMargin
        let distance = isOpen ? metrics.dropZoneLeaveDistance : metrics.dropZoneApproachDistance
        return fromTop <= distance && sideways <= halfWidth + (isOpen ? 40 : 0)
    }

    /// The shelf's natural width; scrolls once it reaches the maximum.
    private func shelfWidth(itemCount: Int) -> CGFloat {
        guard itemCount > 0 else { return 0 }
        let tiles = CGFloat(itemCount) * metrics.shelfTileWidth + CGFloat(itemCount - 1) * metrics.shelfTileSpacing
        return 2 * metrics.shelfHorizontalPadding + tiles + metrics.shelfTileSpacing + metrics.shelfControlsWidth
    }

    /// Each side of the compact island for content this wide: both sides the same, so the notch
    /// stays centered.
    func compactWing(contentWidth: CGFloat) -> CGFloat {
        min(max((contentWidth + 2 * metrics.compactSlotPadding).rounded(.up), metrics.compactMinWingWidth), metrics.compactMaxWingWidth)
    }

    func shape(for phase: IslandPhase, content: IslandContent = .home(nil), compactWing: CGFloat? = nil, bannerWidth: CGFloat? = nil) -> IslandShapeSpec {
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
                width: geometry.notchRect.width + 2 * (compactWing ?? metrics.compactWingWidth),
                height: notchHeight + metrics.collapsedOutset,
                bottomRadius: metrics.collapsedBottomRadius + 4,
                shoulderRadius: metrics.collapsedShoulderRadius
            )
        case .banner:
            IslandShapeSpec(
                width: bannerWidth ?? minimumBannerWidth,
                height: notchHeight + metrics.bannerContentHeight,
                bottomRadius: metrics.bannerBottomRadius,
                shoulderRadius: metrics.bannerShoulderRadius
            )
        case .expanded:
            expandedShape(contentSize(for: content))
        }
    }

    /// The banner is always clear of the notch on both sides.
    var minimumBannerWidth: CGFloat { geometry.notchRect.width + 2 * metrics.bannerMinimumWingWidth }

    /// The banner's width for content this wide (padding included).
    func bannerWidth(contentWidth: CGFloat) -> CGFloat {
        min(max(contentWidth.rounded(.up), minimumBannerWidth), max(metrics.bannerMaximumWidth, minimumBannerWidth))
    }

    private func expandedShape(_ contentSize: CGSize) -> IslandShapeSpec {
        IslandShapeSpec(
            width: contentSize.width,
            height: notchHeight + contentSize.height,
            bottomRadius: metrics.expandedBottomRadius,
            shoulderRadius: metrics.expandedShoulderRadius
        )
    }

    /// The window is centered on a whole point so its frame stays pixel aligned. The notch can sit
    /// on a half point, so views shift their drawing by this amount.
    var centerOffset: CGFloat { geometry.notchRect.midX - windowCenterX }

    private var windowCenterX: CGFloat { geometry.notchRect.midX.rounded(.down) }

    /// Frame of the panel in screen coordinates. Its top edge is the top of the screen. Expanded,
    /// it fits the largest island, so switching content only animates the shape.
    func windowFrame(for phase: IslandPhase) -> CGRect {
        let spec = phase == .expanded
            ? expandedShape(CGSize(width: maximumExpandedWidth, height: metrics.maximumContentHeight))
            : shape(for: phase)
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
    func interactiveScreenRect(for phase: IslandPhase, content: IslandContent = .home(nil), compactWing: CGFloat? = nil, bannerWidth: CGFloat? = nil) -> CGRect {
        let spec = shape(for: phase, content: content, compactWing: compactWing, bannerWidth: bannerWidth)
        return CGRect(
            x: geometry.notchRect.midX - spec.totalWidth / 2,
            y: geometry.screenFrame.maxY - spec.height,
            width: spec.totalWidth,
            height: spec.height
        )
    }
}
