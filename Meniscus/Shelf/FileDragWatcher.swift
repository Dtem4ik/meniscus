import AppKit

/// Notices a file being dragged anywhere, from any app, so the island can open a drop target
/// before the pointer reaches the top edge, where macOS would open Mission Control.
///
/// Global mouse monitors need no permission. They only see events, so the drag pasteboard tells
/// a file drag apart from moving a window or selecting text: it changes when a drag starts. The
/// work is a few comparisons per mouse event, and only while the button is down.
final class FileDragWatcher {
    /// Where a file drag is, in screen coordinates; `nil` once it ended (dropped or cancelled).
    var onDrag: ((CGPoint?) -> Void)?

    private var monitors: [Any] = []
    private var changeCountAtMouseDown = 0
    /// `nil` until the drag pasteboard shows what is being dragged.
    private var isFileDrag: Bool?

    func start() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.mouseDragged() }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    private func mouseDown() {
        changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        isFileDrag = nil
    }

    private func mouseDragged() {
        if isFileDrag == nil {
            let pasteboard = NSPasteboard(name: .drag)
            // Not a drag-and-drop yet (or at all): nothing was put on the drag pasteboard.
            guard pasteboard.changeCount != changeCountAtMouseDown else { return }
            isFileDrag = pasteboard.types?.contains(.fileURL) ?? false
        }
        guard isFileDrag == true else { return }
        onDrag?(NSEvent.mouseLocation)
    }

    private func mouseUp() {
        if isFileDrag == true { onDrag?(nil) }
        isFileDrag = nil
    }
}
