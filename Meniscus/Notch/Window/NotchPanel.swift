import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space,
/// including next to full-screen apps. It never takes focus from the frontmost app.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar (24) and status items, below pop-up menus (101).
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    /// Only while the capture field is open; otherwise the panel never takes keyboard focus.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    // The panel deliberately overlaps the menu bar; don't let AppKit push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Root view of the panel. Reports when the pointer enters or leaves the island's interactive
/// area using a tracking area, which costs nothing while the pointer is elsewhere.
final class NotchContainerView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    /// Clicks that reach this view itself (not a SwiftUI subview).
    var onClick: (() -> Void)?
    /// File drags over this view, once `acceptFileDrops()` was called.
    var onFileDragChange: ((Bool) -> Void)?
    var onFileDrop: (([URL]) -> Void)?

    /// In this view's coordinates.
    var interactiveRect: CGRect = .zero {
        didSet {
            guard interactiveRect != oldValue else { return }
            updateTrackingAreas()
        }
    }

    private var trackingArea: NSTrackingArea?
    private var assumesInside = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func embed(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    /// Rebuilds the tracking area. Pass `true` when the pointer is already inside, so that leaving
    /// is reported even though no "entered" event came first.
    func resetTracking(pointerIsInside: Bool) {
        assumesInside = pointerIsInside
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if assumesInside { options.insert(.assumeInside) }
        assumesInside = false
        let area = NSTrackingArea(
            rect: interactiveRect,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if let onClick { onClick() } else { super.mouseDown(with: event) }
    }

    // MARK: File drops

    func acceptFileDrops() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard !fileURLs(in: sender).isEmpty else { return [] }
        onFileDragChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onFileDragChange?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(in: sender)
        guard !urls.isEmpty else { return false }
        onFileDrop?(urls)
        return true
    }

    private func fileURLs(in info: any NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
    }
}

/// Hosting view that reacts to the first click even though the app is never active.
final class NotchHostingView: NSHostingView<NotchRootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
