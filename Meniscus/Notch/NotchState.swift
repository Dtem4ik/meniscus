import Observation

/// What the island views render. Owned and mutated by `NotchWindowController`.
@Observable
final class NotchState {
    var phase: IslandPhase = .collapsed
    /// Content is shown after the shape opens and hidden before it closes, so it has its own flag.
    var isContentVisible = false
    var layout: IslandLayout

    init(layout: IslandLayout) {
        self.layout = layout
    }

    var isExpanded: Bool { phase == .expanded }
    var currentShape: IslandShapeSpec { layout.shape(for: phase) }
}

/// What views inside the island can ask the controller to do.
struct NotchActions {
    var expand: () -> Void = {}
    var openSettings: () -> Void = {}
}
