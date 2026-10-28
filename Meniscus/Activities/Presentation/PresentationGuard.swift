import AppKit
import Observation

/// Whether the frontmost app is in full screen on the island's screen, when live activities
/// stay hidden. Checked when the active app or Space changes, so nothing polls.
///
/// The window list gives every app's window frames without any permission (only window titles
/// need Screen Recording access, and they aren't read).
@Observable
final class PresentationGuard {
    private(set) var isFullScreen = false

    /// The island's screen; set by the window controller.
    @ObservationIgnored var screenFrame: () -> CGRect? = { nil }

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        guard let screen = screenFrame(),
              let app = NSWorkspace.shared.frontmostApplication,
              let primary = NSScreen.screens.first?.frame,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            set(false)
            return
        }
        let windows = list.compactMap(WindowInfo.init)
        set(FullScreenDetector.isFullScreen(
            windows: windows,
            frontmostPID: app.processIdentifier,
            screenFrame: FullScreenDetector.windowListFrame(of: screen, primaryHeight: primary.height)
        ))
    }

    private func set(_ value: Bool) {
        if value != isFullScreen { isFullScreen = value }
    }
}

/// A window from `CGWindowListCopyWindowInfo`.
nonisolated struct WindowInfo: Equatable, Sendable {
    var ownerPID: pid_t
    var layer: Int
    /// In window list coordinates: origin at the top left of the primary screen.
    var bounds: CGRect

    init(ownerPID: pid_t, layer: Int, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
    }

    init?(_ entry: [String: Any]) {
        guard let pid = entry[kCGWindowOwnerPID as String] as? Int,
              let layer = entry[kCGWindowLayer as String] as? Int,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        else { return nil }
        self.init(ownerPID: pid_t(pid), layer: layer, bounds: bounds)
    }
}

/// Pure rules, unit tested.
nonisolated enum FullScreenDetector {
    /// A normal-level window of the frontmost app covers the whole screen.
    static func isFullScreen(windows: [WindowInfo], frontmostPID: pid_t, screenFrame: CGRect) -> Bool {
        windows.contains { window in
            window.ownerPID == frontmostPID && window.layer == 0 && window.bounds.equalTo(screenFrame)
        }
    }

    /// AppKit's screen frame (origin at the bottom left) in window list coordinates.
    static func windowListFrame(of screen: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: screen.minX, y: primaryHeight - screen.maxY, width: screen.width, height: screen.height)
    }
}
