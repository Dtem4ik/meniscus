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
        .capture,
        .shelf(itemCount: 0),
        .shelf(itemCount: 3),
        .shelf(itemCount: 40),
        .dropZone,
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

    @Test func dropTargetOpensNearTheTopBeforeTheEdge() {
        let layout = layout()
        let top = layout.geometry.screenFrame.maxY
        let x = layout.geometry.notchRect.midX
        #expect(layout.isNearDropZone(CGPoint(x: x, y: top - 50), isOpen: false))
        #expect(layout.isNearDropZone(CGPoint(x: x + 300, y: top - 80), isOpen: false))
        #expect(!layout.isNearDropZone(CGPoint(x: x, y: top - 150), isOpen: false))
        #expect(!layout.isNearDropZone(CGPoint(x: 20, y: top - 10), isOpen: false))
    }

    @Test func dropTargetClosesOnlyFurtherAway() {
        let layout = layout()
        let top = layout.geometry.screenFrame.maxY
        let x = layout.geometry.notchRect.midX
        #expect(layout.isNearDropZone(CGPoint(x: x, y: top - 150), isOpen: true))
        #expect(!layout.isNearDropZone(CGPoint(x: x, y: top - 220), isOpen: true))
    }

    @Test func dropHintWidensTheCompactIsland() {
        let layout = layout()
        let plain = layout.shape(for: .compact, activity: .nowPlaying)
        let hint = layout.shape(for: .compact, activity: .dropHint)
        #expect(plain.width == layout.compactWidth)
        #expect(hint.width == layout.geometry.notchRect.width + 2 * layout.metrics.dropHintWingWidth)
        #expect(layout.windowFrame(for: .expanded).width >= hint.totalWidth)
    }

    @Test func dropTargetTakesTheFullWidth() {
        let layout = layout()
        #expect(layout.contentSize(for: .dropZone).width == layout.maximumExpandedWidth)
    }

    @Test func shelfGrowsWithItsFilesUpToTheMaximum() {
        let layout = layout()
        let empty = layout.contentSize(for: .shelf(itemCount: 0)).width
        let few = layout.contentSize(for: .shelf(itemCount: 4)).width
        let many = layout.contentSize(for: .shelf(itemCount: 40)).width
        #expect(empty == layout.minimumExpandedWidth)
        #expect(few > empty)
        #expect(many == layout.maximumExpandedWidth)
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
