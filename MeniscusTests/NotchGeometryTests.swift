import CoreGraphics
import Testing
@testable import Meniscus

struct NotchGeometryTests {
    // A 14-inch MacBook Pro at its default scaled resolution.
    private let laptopFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func hardwareNotchSitsBetweenAuxiliaryAreas() {
        let geometry = NotchGeometry.compute(
            screenFrame: laptopFrame,
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 661, height: 32),
            auxiliaryTopRight: CGRect(x: 851, y: 950, width: 661, height: 32),
            menuBarHeight: 32,
            backingScale: 2
        )
        #expect(geometry.kind == .hardware)
        #expect(geometry.notchRect == CGRect(x: 661, y: 950, width: 190, height: 32))
    }

    @Test func notchOnSecondaryScreenUsesScreenOrigin() {
        let frame = CGRect(x: -1512, y: 300, width: 1512, height: 982)
        let geometry = NotchGeometry.compute(
            screenFrame: frame,
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 661, height: 32),
            auxiliaryTopRight: CGRect(x: 851, y: 950, width: 661, height: 32),
            menuBarHeight: 32,
            backingScale: 2
        )
        #expect(geometry.notchRect == CGRect(x: -851, y: 1250, width: 190, height: 32))
    }

    @Test func edgesSnapToBackingPixels() {
        let geometry = NotchGeometry.compute(
            screenFrame: laptopFrame,
            safeAreaTop: 32.3,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 661.3, height: 32),
            auxiliaryTopRight: CGRect(x: 851, y: 950, width: 660.8, height: 32),
            menuBarHeight: 32,
            backingScale: 2
        )
        #expect(geometry.notchRect.minX == 661.5)
        #expect(geometry.notchRect.maxX == 851)
        #expect(geometry.notchRect.height == 32.5)
        #expect(geometry.notchRect.maxY == laptopFrame.maxY)
    }

    @Test func screenWithoutHousingGetsCenteredVirtualNotch() {
        let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let geometry = NotchGeometry.compute(
            screenFrame: frame,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            menuBarHeight: 25,
            backingScale: 2
        )
        #expect(geometry.kind == .virtual)
        #expect(geometry.notchRect.width == NotchGeometry.virtualNotchWidth)
        #expect(geometry.notchRect.height == 25)
        #expect(geometry.notchRect.midX == frame.midX)
        #expect(geometry.notchRect.maxY == frame.maxY)
    }

    @Test func hiddenMenuBarFallsBackToDefaultHeight() {
        let geometry = NotchGeometry.compute(
            screenFrame: laptopFrame,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            menuBarHeight: 0,
            backingScale: 1
        )
        #expect(geometry.notchRect.height == NotchGeometry.fallbackMenuBarHeight)
    }

    @Test func safeAreaWithoutAuxiliaryAreasIsTreatedAsVirtual() {
        let geometry = NotchGeometry.compute(
            screenFrame: laptopFrame,
            safeAreaTop: 32,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: CGRect(x: 851, y: 950, width: 661, height: 32),
            menuBarHeight: 32,
            backingScale: 2
        )
        #expect(geometry.kind == .virtual)
    }
}
