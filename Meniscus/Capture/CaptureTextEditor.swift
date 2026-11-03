import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Keep a single-line capture compact; longer notes grow to a bounded, scrollable editor.
nonisolated enum CaptureEditorMetrics {
    static let minimumHeight: CGFloat = 56
    static let maximumHeight: CGFloat = 120
    static let verticalPadding: CGFloat = 36
    static let minimumTextHeight: CGFloat = 20
    static let initialTextWidth: CGFloat = 376
}

/// Native text editing preserves selection, undo and input-method composition.
struct CaptureTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = CaptureTextView(frame: NSRect(x: 0, y: 0, width: CaptureEditorMetrics.initialTextWidth, height: CaptureEditorMetrics.minimumTextHeight))
        editor.setAccessibilityLabel(String(localized: "Capture"))
        editor.isRichText = false
        editor.drawsBackground = false
        editor.textColor = .white
        editor.insertionPointColor = .white
        editor.font = .systemFont(ofSize: 15)
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: CaptureEditorMetrics.initialTextWidth, height: CGFloat.greatestFiniteMagnitude)
        editor.allowsUndo = true
        editor.delegate = context.coordinator
        editor.string = text
        editor.onSubmit = onSubmit
        editor.onCancel = onCancel
        editor.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        scroll.documentView = editor
        context.coordinator.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? CaptureTextView else { return }
        editor.onSubmit = onSubmit
        editor.onCancel = onCancel
        if editor.string != text { editor.string = text }
        context.coordinator.measure()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextEditor
        weak var editor: CaptureTextView?
        init(_ parent: CaptureTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor else { return }
            parent.text = editor.string
            measure()
        }
        func measure() {
            guard let editor else { return }
            let height = editor.captureHeight
            let report = parent.onHeightChange
            DispatchQueue.main.async { report(height) }
        }
    }
}

final class CaptureTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onLayout: (() -> Void)?
    /// Measure AppKit's laid-out text, including an empty line after a trailing Return.
    var captureHeight: CGFloat {
        guard let manager = layoutManager, let container = textContainer else { return CaptureEditorMetrics.minimumHeight }
        manager.ensureLayout(for: container)
        let used = max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY)
        return min(CaptureEditorMetrics.maximumHeight, max(CaptureEditorMetrics.minimumHeight, ceil(used) + CaptureEditorMetrics.verticalPadding))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.makeFirstResponder(self) }
    }
    override func layout() {
        super.layout()
        onLayout?()
    }
    override func keyDown(with event: NSEvent) {
        // Input methods must be allowed to confirm their composition first.
        guard !hasMarkedText() else { super.keyDown(with: event); return }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(self)
            } else {
                onSubmit?()
            }
        } else if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
