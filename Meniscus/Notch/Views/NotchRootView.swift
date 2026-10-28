import SwiftUI

/// Everything an island style needs to draw one phase.
struct IslandContext {
    var layout: IslandLayout
    var phase: IslandPhase
    var isContentVisible: Bool
    var reduceMotion: Bool
    var compactActivity: LiveActivity?
    var compactWing: CGFloat
    var bannerWidth: CGFloat
    var content: IslandContent
    var pages: [IslandPage]
    var page: IslandPage
    var pageMovesForward: Bool
    var actions: NotchActions

    var isExpanded: Bool { phase == .expanded }
    var contentSize: CGSize { layout.contentSize(for: content) }
    var shape: NotchShape {
        NotchShape(layout.shape(for: phase, content: content, compactWing: compactWing, bannerWidth: bannerWidth), centerOffset: layout.centerOffset)
    }
}

/// Fills the whole panel. The island is drawn top-centered; the rest stays transparent.
struct NotchRootView: View {
    let state: NotchState
    let settings: AppSettings
    let actions: NotchActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The home content at its own size, never shown. The island opens straight to this size
    /// instead of measuring the visible content, which only appears once the shape is open.
    private var homeContentMeasure: some View {
        HomeIslandContent(metrics: state.layout.metrics)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                state.homeContentSize = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
            }
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// The compact activity's two sides at their natural width, never shown. The island's sides
    /// follow the wider one with the same spring as the rest of the morph.
    @ViewBuilder
    private var compactMeasure: some View {
        if let activity = state.compactActivity {
            CompactSlotMeasure(activity: activity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    let wing = state.layout.compactWing(contentWidth: width)
                    guard wing != state.compactWing else { return }
                    withAnimation(reduceMotion ? Motion.reducedMotionFade : Motion.expand) { state.compactWing = wing }
                }
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    /// The mini banner at its natural width, never shown: the island is as wide as it needs.
    @ViewBuilder
    private var bannerMeasure: some View {
        if let activity = state.compactActivity, activity.kind.isBanner, let banner = MiniBanner.for(activity) {
            MiniBannerView(banner: banner, metrics: state.layout.metrics)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                    let bannerWidth = state.layout.bannerWidth(contentWidth: width)
                    guard bannerWidth != state.bannerWidth else { return }
                    withAnimation(reduceMotion ? Motion.reducedMotionFade : Motion.expand) { state.bannerWidth = bannerWidth }
                }
                .hidden()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            if reduceMotion {
                // No morphing: the compact or expanded island cross-fades over the notch.
                island(phase: .collapsed, isContentVisible: false)
                if state.phase != .collapsed {
                    island(phase: state.phase, isContentVisible: state.isContentVisible)
                        .transition(.opacity)
                }
            } else {
                island(phase: state.phase, isContentVisible: state.isContentVisible)
            }

            if settings.showGeometryOverlay {
                GeometryOverlay(layout: state.layout)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .top) { homeContentMeasure }
        .background(alignment: .top) { compactMeasure }
        .background(alignment: .top) { bannerMeasure }
        // The panel is never the key window; keep glass in its active look anyway.
        .environment(\.materialActiveAppearance, .active)
    }

    @ViewBuilder
    private func island(phase: IslandPhase, isContentVisible: Bool) -> some View {
        let context = IslandContext(
            layout: state.layout,
            phase: phase,
            isContentVisible: isContentVisible,
            reduceMotion: reduceMotion,
            compactActivity: state.compactActivity,
            compactWing: state.compactWing ?? state.layout.metrics.compactWingWidth,
            bannerWidth: state.bannerWidth ?? state.layout.minimumBannerWidth,
            content: state.content,
            pages: state.pages,
            page: state.page,
            pageMovesForward: state.pageMovesForward,
            actions: actions
        )
        IslandView(context: context)
    }
}

/// Holds island content at its expanded size and reveals it blur-to-sharp.
struct IslandContentLayer<Content: View>: View {
    let context: IslandContext
    var topInset: CGFloat
    var height: CGFloat
    var horizontalOffset: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            if context.isContentVisible {
                content
                    .frame(width: context.contentSize.width, height: height)
                    .padding(.top, topInset)
                    .offset(x: horizontalOffset)
                    .transition(context.reduceMotion ? .opacity : .contentReveal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Outlines the computed notch 1 pt outside its edges. On a correct geometry the red line hugs
/// the hardware notch evenly on all three sides.
struct GeometryOverlay: View {
    let layout: IslandLayout

    var body: some View {
        let notch = layout.geometry.notchRect
        Rectangle()
            .strokeBorder(.red, lineWidth: 1)
            .frame(width: notch.width + 2, height: notch.height + 1)
            .offset(x: layout.centerOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
