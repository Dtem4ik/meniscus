import SwiftUI

/// The island outline: a body hanging from the top edge with rounded bottom corners and concave
/// "shoulders" where it meets the top of the screen, like the hardware notch.
///
/// The shape is drawn top-centered inside whatever rect it gets, so the view that hosts it keeps a
/// fixed size and only the path animates. All four dimensions are in `animatableData`, so going
/// from the notch to the expanded island is one continuous morph.
nonisolated struct NotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var bottomRadius: CGFloat
    var shoulderRadius: CGFloat
    /// Horizontal offset of the center from `rect.midX` (see `IslandLayout.centerOffset`).
    var centerOffset: CGFloat = 0

    init(_ spec: IslandShapeSpec, centerOffset: CGFloat = 0) {
        width = spec.width
        height = spec.height
        bottomRadius = spec.bottomRadius
        shoulderRadius = spec.shoulderRadius
        self.centerOffset = centerOffset
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(width, height), AnimatablePair(bottomRadius, shoulderRadius)) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            bottomRadius = newValue.second.first
            shoulderRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let width = max(width, 0)
        let height = max(height, 0)
        guard width > 0, height > 0 else { return Path() }

        let shoulder = min(max(shoulderRadius, 0), height / 2)
        let radius = min(max(bottomRadius, 0), width / 2, height - shoulder)

        let midX = rect.midX + centerOffset
        let left = midX - width / 2
        let right = midX + width / 2
        let top = rect.minY
        let bottom = rect.minY + height

        var path = Path()
        path.move(to: CGPoint(x: left - shoulder, y: top))
        // Left shoulder: concave fillet from the top edge down into the left side.
        path.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left, y: bottom), radius: shoulder)
        path.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: right, y: bottom), radius: radius)
        path.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right, y: top), radius: radius)
        // Right shoulder.
        path.addArc(tangent1End: CGPoint(x: right, y: top), tangent2End: CGPoint(x: right + shoulder, y: top), radius: shoulder)
        path.closeSubpath()
        return path
    }
}
