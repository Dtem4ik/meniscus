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
                .shadow(color: .black.opacity(context.isExpanded ? 0.35 : 0), radius: 18, y: 8)

            IslandContentLayer(
                context: context,
                topInset: layout.notchHeight,
                height: context.contentSize.height,
                horizontalOffset: layout.centerOffset
            ) {
                IslandContentView(content: context.content, metrics: layout.metrics)
            }
            .mask { shape }

            if context.phase == .compact, let activity = context.compactActivity {
                CompactActivityView(activity: activity, layout: layout)
                    .transition(context.reduceMotion ? .opacity : .contentReveal)
                    .mask { shape }
            }
        }
        // Black stays black in Light Mode, so the content must use dark-appearance colors.
        .environment(\.colorScheme, .dark)
    }
}

/// The expanded content. Nothing but the content itself: Settings live in the menu bar.
struct IslandContentView: View {
    let content: IslandContent
    let metrics: IslandMetrics

    var body: some View {
        ZStack {
            switch content {
            case .home:
                HomeIslandContent(metrics: metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            case .nowPlaying:
                NowPlayingView(service: ActivityServices.shared.nowPlaying)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Time, date and the next event with their padding. The same view is measured off screen
/// (`NotchRootView`) to size the island, so the two always agree.
struct HomeIslandContent: View {
    let metrics: IslandMetrics

    var body: some View {
        HomeContent(
            calendar: ActivityServices.shared.calendar,
            showCalendar: AppSettings.shared.showCalendar
        )
        .padding(.horizontal, metrics.homeHorizontalPadding)
        .padding(.top, metrics.homeTopPadding)
        .padding(.bottom, metrics.homeBottomPadding)
    }
}
