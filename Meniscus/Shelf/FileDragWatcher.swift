import AppKit

/// Notices a file being dragged anywhere, from any app, so the island can open a drop target
/// before the pointer reaches the top edge, where macOS would open Mission Control.
///
/// While the system runs a drag, other apps' mouse-dragged events don't reach global monitors.
/// A press of the mouse button still does, so it starts a short poll of the pointer, the buttons
/// and the drag pasteboard (which changes when a drag starts). The poll stops the moment the
/// button is released; nothing runs otherwise. Global monitors need no permission.
final class FileDragWatcher {
    /// Where a file drag is, in screen coordinates; `nil` once it ended (dropped or cancelled).
    var onDrag: ((CGPoint?) -> Void)?

    /// How often the pointer is checked while the button is held.
    static let pollInterval: Duration = .milliseconds(33)

    private var monitor: Any?
    private var pollTask: Task<Void, Never>?
    private var changeCountAtMouseDown = 0
    /// `nil` until the drag pasteboard shows what is being dragged.
    private var isFileDrag: Bool?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.mouseDown()
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        pollTask?.cancel()
        pollTask = nil
        if isFileDrag == true { onDrag?(nil) }
        isFileDrag = nil
    }

    private func mouseDown() {
        changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        isFileDrag = nil
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.poll() else { return }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    /// Returns `false` once the button is up and polling should stop.
    private func poll() -> Bool {
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if isFileDrag == true { onDrag?(nil) }
            isFileDrag = nil
            return false
        }
        if isFileDrag == nil {
            let pasteboard = NSPasteboard(name: .drag)
            // Not a drag-and-drop (yet): nothing was put on the drag pasteboard.
            guard pasteboard.changeCount != changeCountAtMouseDown else { return true }
            isFileDrag = pasteboard.types?.contains(.fileURL) ?? false
        }
        if isFileDrag == true { onDrag?(NSEvent.mouseLocation) }
        // Moving a window or selecting text: nothing to watch until the next press.
        return isFileDrag != false
    }
}
