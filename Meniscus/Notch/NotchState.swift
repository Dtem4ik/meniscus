import CoreGraphics
import Foundation
import Observation

/// What the island views render. Owned and mutated by `NotchWindowController`.
@Observable
final class NotchState {
    var phase: IslandPhase = .collapsed
    /// Content is shown after the shape opens and hidden before it closes, so it has its own flag.
    var isContentVisible = false
    var layout: IslandLayout
    /// What the expanded island shows; decides its size.
    var content: IslandContent = .home(nil)
    /// The pages there is something to show on, and the one shown. Page dots appear when there
    /// is more than one.
    var pages: [IslandPage] = [.home]
    var page: IslandPage = .home
    /// Which way the last page turn went, so content slides in from the right side.
    var pageMovesForward = true
    /// The home content's own size, measured off screen so the island can open to it directly.
    var homeContentSize: CGSize?
    /// The live activity shown while not expanded; `nil` leaves the plain notch.
    var compactActivity: LiveActivity?

    init(layout: IslandLayout) {
        self.layout = layout
    }

    var isExpanded: Bool { phase == .expanded }
    /// Where the island returns when it isn't expanded.
    var restingPhase: IslandPhase { compactActivity == nil ? .collapsed : .compact }
    var currentShape: IslandShapeSpec { layout.shape(for: phase, content: content) }
}

/// What views inside the island can ask the controller to do.
struct NotchActions {
    var expand: () -> Void = {}
    /// Closes the capture field and the island.
    var endCapture: () -> Void = {}
    var selectPage: (IslandPage) -> Void = { _ in }
}
