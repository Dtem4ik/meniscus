import CoreGraphics
import SwiftUI
import Testing
@testable import Meniscus

struct NotchShapeTests {
    private let canvas = CGRect(x: 0, y: 0, width: 400, height: 200)

    private func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    @Test func pathIsTopCenteredAndIncludesShoulders() {
        let spec = IslandShapeSpec(width: 200, height: 32, bottomRadius: 9, shoulderRadius: 4)
        let bounds = NotchShape(spec).path(in: canvas).boundingRect
        #expect(isClose(bounds, CGRect(x: 96, y: 0, width: 208, height: 32)))
    }

    @Test func centerOffsetShiftsPath() {
        let spec = IslandShapeSpec(width: 200, height: 32, bottomRadius: 9, shoulderRadius: 0)
        let bounds = NotchShape(spec, centerOffset: 0.25).path(in: canvas).boundingRect
        #expect(isClose(bounds, CGRect(x: 100.25, y: 0, width: 200, height: 32)))
    }

    @Test func oversizedRadiiStayInsideBody() {
        let spec = IslandShapeSpec(width: 40, height: 20, bottomRadius: 500, shoulderRadius: 500)
        let bounds = NotchShape(spec).path(in: canvas).boundingRect
        // Shoulders are clamped to half the height, so the path is at most 40 + 2 × 10 wide.
        #expect(bounds.width <= 60.01)
        #expect(bounds.height <= 20.01)
    }

    @Test func emptySpecDrawsNothing() {
        let spec = IslandShapeSpec(width: 0, height: 0, bottomRadius: 0, shoulderRadius: 0)
        #expect(NotchShape(spec).path(in: canvas).isEmpty)
    }

    @Test func animatableDataRoundTrips() {
        var shape = NotchShape(IslandShapeSpec(width: 1, height: 2, bottomRadius: 3, shoulderRadius: 4))
        let data = shape.animatableData
        shape.animatableData = data
        #expect(shape.width == 1 && shape.height == 2 && shape.bottomRadius == 3 && shape.shoulderRadius == 4)
    }
}
