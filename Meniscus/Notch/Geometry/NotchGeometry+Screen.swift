import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    var hasCameraHousing: Bool { safeAreaInsets.top > 0 }

    /// Height of the menu bar on this screen, or 0 if it is hidden.
    var menuBarHeight: CGFloat { max(frame.maxY - visibleFrame.maxY, 0) }
}

extension NotchGeometry {
    @MainActor
    init(screen: NSScreen, forceVirtual: Bool = false) {
        self = NotchGeometry.compute(
            screenFrame: screen.frame,
            safeAreaTop: forceVirtual ? 0 : screen.safeAreaInsets.top,
            auxiliaryTopLeft: forceVirtual ? nil : screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: forceVirtual ? nil : screen.auxiliaryTopRightArea,
            menuBarHeight: screen.menuBarHeight,
            backingScale: screen.backingScaleFactor
        )
    }
}

enum ScreenLocator {
    static func screen(for preference: DisplayPreference) -> NSScreen? {
        let screens = NSScreen.screens
        switch preference {
        case .notched:
            return screens.first(where: { $0.hasCameraHousing })
                ?? screens.first(where: { $0.isBuiltIn })
                ?? screens.first
        case .main:
            // The first screen is the one with the menu bar, unlike `NSScreen.main`,
            // which follows keyboard focus.
            return screens.first
        }
    }
}

/// A plain-text dump of the numbers behind the notch geometry, for bug reports.
enum ScreenDiagnostics {
    static func report(screen: NSScreen, geometry: NotchGeometry, layout: IslandLayout) -> String {
        func describe(_ rect: CGRect?) -> String {
            guard let rect else { return "nil" }
            return "(x: \(rect.origin.x), y: \(rect.origin.y), w: \(rect.width), h: \(rect.height))"
        }
        let insets = screen.safeAreaInsets
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return """
        Meniscus \(version) (\(build)) geometry report
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        screen: \(screen.localizedName), built-in: \(screen.isBuiltIn), screens: \(NSScreen.screens.count)
        frame: \(describe(screen.frame))
        visibleFrame: \(describe(screen.visibleFrame))
        backingScaleFactor: \(screen.backingScaleFactor)
        safeAreaInsets: top \(insets.top), left \(insets.left), bottom \(insets.bottom), right \(insets.right)
        auxiliaryTopLeftArea: \(describe(screen.auxiliaryTopLeftArea))
        auxiliaryTopRightArea: \(describe(screen.auxiliaryTopRightArea))
        notch (\(geometry.kind.rawValue)): \(describe(geometry.notchRect))
        collapsed window: \(describe(layout.windowFrame(for: .collapsed)))
        expanded window: \(describe(layout.windowFrame(for: .expanded)))
        center offset: \(layout.centerOffset)
        """
    }
}
