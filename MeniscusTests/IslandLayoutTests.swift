import CoreGraphics
import Testing
@testable import Meniscus

struct IslandLayoutTests {
    private func layout(notchMinX: CGFloat = 661, notchWidth: CGFloat = 190) -> IslandLayout {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(
            kind: .hardware,
            screenFrame: screen,
            notchRect: CGRect(x: notchMinX, y: 950, width: notchWidth, height: 32),
            backingScale: 2
        )
        return IslandLayout(geometry: geometry)
    }

    @Test(arguments: [IslandPhase.collapsed, .compact, .expanded])
    func windowFrameIsWholePointsAndTouchesTopOfScreen(phase: IslandPhase) {
        // A notch on a half point, to check the window still lands on whole points.
        let layout = layout(notchMinX: 661.5, notchWidth: 189.5)
        let frame = layout.windowFrame(for: phase)
        #expect(frame.minX == frame.minX.rounded())
        #expect(frame.width == frame.width.rounded())
        #expect(frame.height == frame.height.rounded())
        #expect(frame.maxY == layout.geometry.screenFrame.maxY)
    }

    @Test(arguments: [IslandPhase.collapsed, .compact, .expanded])
    func windowContainsIslandWithShoulders(phase: IslandPhase) {
        let layout = layout(notchMinX: 661.5, notchWidth: 189.5)
        let window = layout.windowFrame(for: phase)
        let island = layout.interactiveScreenRect(for: phase)
        #expect(window.contains(island))
    }

    @Test(arguments: [
        IslandContent.nowPlaying,
        .home(nil),
        .home(CGSize(width: 120, height: 60)),
        .home(CGSize(width: 2000, height: 500)),
    ])
    func expandedIsWiderThanCompactOnBothSides(content: IslandContent) {
        for notchWidth: CGFloat in [160, 190, 260] {
            let layout = layout(notchWidth: notchWidth)
            let extra = layout.shape(for: .expanded, content: content).width - layout.compactWidth
            #expect(extra >= 2 * layout.metrics.minimumExpansionPerSide)
            #expect(extra >= layout.compactWidth * layout.metrics.expansionRatio - 0.01)
            #expect(layout.windowFrame(for: .expanded).contains(layout.interactiveScreenRect(for: .expanded, content: content)))
        }
    }

    @Test func playerIsAsNarrowAsTheRuleAllows() {
        let layout = layout()
        let player = layout.contentSize(for: .nowPlaying)
        #expect(player.width == layout.minimumExpandedWidth)
        #expect(player.height == layout.metrics.nowPlayingContentHeight)
    }

    @Test func homeTakesItsMeasuredSize() {
        let layout = layout()
        let size = layout.contentSize(for: .home(CGSize(width: 480.3, height: 77.2)))
        #expect(size == CGSize(width: 481, height: 78))
    }

    @Test func homeStaysWithinTheMaximums() {
        let layout = layout()
        let size = layout.contentSize(for: .home(CGSize(width: 2000, height: 500)))
        #expect(size.width == layout.maximumExpandedWidth)
        #expect(size.height == layout.metrics.maximumContentHeight)
    }

    @Test func collapsedIslandCoversNotchExactly() {
        let layout = layout()
        let spec = layout.shape(for: .collapsed)
        #expect(spec.width == layout.geometry.notchRect.width + 2 * layout.metrics.collapsedOutset)
        #expect(spec.height == layout.geometry.notchRect.height + layout.metrics.collapsedOutset)
        #expect(layout.interactiveScreenRect(for: .collapsed).midX == layout.geometry.notchRect.midX)
    }

    @Test func compactIslandWidensTheNotchSymmetrically() {
        let layout = layout()
        let notch = layout.geometry.notchRect
        let compact = layout.interactiveScreenRect(for: .compact)
        #expect(compact.midX == notch.midX)
        #expect(compact.height == notch.height)
        #expect(compact.width > notch.width + 2 * layout.metrics.compactWingWidth - 0.01)
        #expect(layout.windowFrame(for: .expanded).contains(compact))
    }

    @Test func expandedIslandIsNeverNarrowerThanNotch() {
        let layout = layout(notchMinX: 400, notchWidth: 700)
        #expect(layout.minimumExpandedWidth >= 700 + 2 * layout.metrics.expandedBottomRadius)
        #expect(layout.maximumExpandedWidth >= layout.minimumExpandedWidth)
    }

    @Test func centerOffsetIsTheSubPointRemainder() {
        #expect(layout(notchMinX: 661, notchWidth: 190).centerOffset == 0)
        #expect(layout(notchMinX: 661.5, notchWidth: 189.5).centerOffset == 0.25)
    }
}
