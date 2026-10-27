import CoreGraphics

/// Where the notch is on a screen, in AppKit screen coordinates (origin at the bottom left).
///
/// This is a pure value computed from the numbers `NSScreen` reports, so it can be unit tested
/// without a display. See `NotchGeometry+Screen.swift` for the bridge from `NSScreen`.
nonisolated struct NotchGeometry: Equatable, Sendable {
    nonisolated enum Kind: String, Equatable, Sendable {
        /// The screen has a camera housing; the rect matches it.
        case hardware
        /// No camera housing (external display, older Mac, or forced in the Developer menu).
        case virtual
    }

    var kind: Kind
    /// Full frame of the screen the notch lives on.
    var screenFrame: CGRect
    /// The notch itself, aligned to the screen's backing pixels.
    var notchRect: CGRect
    var backingScale: CGFloat

    /// Width of the virtual notch on screens without a camera housing. Close to the hardware one.
    static let virtualNotchWidth: CGFloat = 190
    /// Height used for a virtual notch when the menu bar is hidden and its height is unknown.
    static let fallbackMenuBarHeight: CGFloat = 24

    /// Computes the notch for one screen.
    ///
    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top`; non-zero only on screens with a camera housing.
    ///   - auxiliaryTopLeft: `NSScreen.auxiliaryTopLeftArea`, the menu bar area left of the housing.
    ///   - auxiliaryTopRight: `NSScreen.auxiliaryTopRightArea`, the menu bar area right of the housing.
    ///   - menuBarHeight: Height of the menu bar on this screen, or 0 if it is hidden.
    ///   - backingScale: `NSScreen.backingScaleFactor`, used to snap edges to whole pixels.
    static func compute(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        menuBarHeight: CGFloat,
        backingScale: CGFloat
    ) -> NotchGeometry {
        let scale = max(backingScale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }

        // Only the widths of the auxiliary areas are used, so the result does not depend on
        // whether AppKit reports them in global or screen-local coordinates.
        if safeAreaTop > 0,
           let left = auxiliaryTopLeft, let right = auxiliaryTopRight,
           left.width > 0, right.width > 0 {
            let minX = snap(screenFrame.minX + left.width)
            let maxX = snap(screenFrame.maxX - right.width)
            let height = snap(safeAreaTop)
            if maxX > minX {
                return NotchGeometry(
                    kind: .hardware,
                    screenFrame: screenFrame,
                    notchRect: CGRect(x: minX, y: screenFrame.maxY - height, width: maxX - minX, height: height),
                    backingScale: scale
                )
            }
        }

        let height = snap(menuBarHeight > 0 ? menuBarHeight : fallbackMenuBarHeight)
        let width = snap(virtualNotchWidth)
        let minX = snap(screenFrame.midX - width / 2)
        return NotchGeometry(
            kind: .virtual,
            screenFrame: screenFrame,
            notchRect: CGRect(x: minX, y: screenFrame.maxY - height, width: width, height: height),
            backingScale: scale
        )
    }
}
