import SwiftUI

/// The island: solid black like Dynamic Island, continuous with the hardware notch. Liquid Glass
/// is used only for the controls inside it.
struct IslandView: View {
    let context: IslandContext

    var body: some View {
        let shape = context.shape
        let layout = context.layout
        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .shadow(color: .black.opacity(context.isExpanded ? 0.35 : context.phase == .banner ? 0.25 : 0), radius: 18, y: 8)

            IslandContentLayer(
                context: context,
                topInset: layout.notchHeight,
                height: context.contentSize.height,
                horizontalOffset: layout.centerOffset
            ) {
                IslandContentView(context: context)
                    .overlay(alignment: .bottom) {
                        if context.pages.count > 1, context.content != .capture, context.content != .dropZone {
                            PageDots(pages: context.pages, selected: context.page, select: context.actions.selectPage)
                                .padding(.bottom, 2)
                                .transition(.opacity)
                        }
                    }
            }
            .mask { shape }

            if context.phase == .banner, let activity = context.compactActivity, let banner = MiniBanner.for(activity) {
                MiniBannerView(banner: banner, metrics: layout.metrics)
                    .frame(width: layout.bannerWidth, height: layout.metrics.bannerContentHeight)
                    .padding(.top, layout.notchHeight)
                    .offset(x: layout.centerOffset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(context.reduceMotion ? .opacity : .contentReveal)
                    .mask { shape }
            }

            if context.phase == .compact, let activity = context.compactActivity {
                CompactActivityView(activity: activity, layout: layout, wing: context.compactWing)
                    .transition(context.reduceMotion ? .opacity : .contentReveal)
                    .mask { shape }
            }
        }
        // Black stays black in Light Mode, so the content must use dark-appearance colors.
        .environment(\.colorScheme, .dark)
    }
}

/// The expanded content. Nothing but the content itself: Settings live in the menu bar. A new
/// page slides in from the side it was swiped from.
struct IslandContentView: View {
    let context: IslandContext

    var body: some View {
        let metrics = context.layout.metrics
        ZStack {
            switch context.content {
            case .home:
                HomeIslandContent(metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(pageTransition)
            case .nowPlaying:
                NowPlayingView(service: ActivityServices.shared.nowPlaying)
                    .transition(pageTransition)
            case .capture:
                CaptureField(capture: .shared, onFinish: context.actions.endCapture)
                    .transition(.opacity)
            case .shelf:
                ShelfView(shelf: .shared, metrics: metrics)
                    .transition(pageTransition)
            case .dropZone:
                ShelfDropZone(isTargeted: ShelfController.shared.isDropTargeted)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pageTransition: AnyTransition {
        guard !context.reduceMotion else { return .opacity }
        return .push(from: context.pageMovesForward ? .trailing : .leading).combined(with: .opacity)
    }
}

/// Time, date and the next event, the modes below them, with their padding. The same view is measured off screen
/// (`NotchRootView`) to size the island, so the two always agree.
struct HomeIslandContent: View {
    let metrics: IslandMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeContent(
                calendar: ActivityServices.shared.calendar,
                showCalendar: AppSettings.shared.showCalendar
            )
            ModesBar(store: .shared)
        }
        .padding(.horizontal, metrics.homeHorizontalPadding)
        .padding(.top, metrics.homeTopPadding)
        .padding(.bottom, metrics.homeBottomPadding)
    }
}

/// Buttons inside the island (player controls, modes): white symbols with no background; a soft
/// circle shows only on hover and press.
struct IslandControlStyle: ButtonStyle {
    var size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        IslandControl(configuration: configuration, size: size)
    }

    private struct IslandControl: View {
        let configuration: Configuration
        let size: CGFloat
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + 18, height: size + 18)
                .background {
                    Circle()
                        .fill(.white.opacity(configuration.isPressed ? 0.2 : isHovered ? 0.1 : 0))
                        .animation(Motion.controlHover, value: isHovered)
                }
                .contentShape(.circle)
                .scaleEffect(configuration.isPressed ? Motion.controlPressScale : 1)
                .animation(Motion.controlPress, value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}
