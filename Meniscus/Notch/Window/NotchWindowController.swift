import AppKit
import OSLog
import SwiftUI

/// Owns the notch panel and drives the collapsed ⇄ expanded transitions.
///
/// The panel is only as large as the current phase needs: notch-sized when collapsed, so the menu
/// bar stays fully clickable, and island-sized while expanded. It grows *before* the expand
/// animation and shrinks *after* the collapse animation; the shape is drawn top-centered, so a
/// resize never moves a visible pixel and never happens mid-animation.
final class NotchWindowController {
    let state: NotchState
    private let settings: AppSettings
    private let panel = NotchPanel()
    private let container = NotchContainerView(frame: .zero)
    private let logger = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "notch")

    private var screen: NSScreen?
    private var isHovering = false
    /// Opened from the menu bar: stays open until the pointer has visited and left it.
    private var isPinned = false
    private var pointerTask: Task<Void, Never>?
    /// Incremented on every transition so a stale collapse completion can't shrink the panel.
    private var transitionID = 0

    init(settings: AppSettings) {
        self.settings = settings
        let fallbackGeometry = NotchGeometry.compute(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil,
            menuBarHeight: 0, backingScale: 2
        )
        state = NotchState(layout: IslandLayout(geometry: fallbackGeometry))
    }

    func start() {
        let actions = NotchActions(
            expand: { [weak self] in self?.expand() },
            openSettings: { [weak self] in
                self?.collapse()
                SettingsWindowController.shared.show()
            }
        )
        let hostingView = NotchHostingView(rootView: NotchRootView(state: state, settings: settings, actions: actions))
        // The controller sizes the panel; SwiftUI must not resize it to fit its content.
        hostingView.sizingOptions = []
        container.frame = CGRect(origin: .zero, size: panel.frame.size)
        container.embed(hostingView)
        container.onHoverChange = { [weak self] inside in self?.pointerDidChange(inside: inside) }
        panel.contentView = container

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }
        observeSettings()
        refreshGeometry()
    }

    // MARK: Transitions

    func toggleFromMenu() {
        if state.isExpanded {
            collapse()
        } else {
            expand(pinned: true)
        }
    }

    func expand(pinned: Bool = false) {
        pointerTask?.cancel()
        isPinned = pinned
        guard !state.isExpanded else { return }
        transitionID += 1

        setPanelFrame(for: .expanded)
        panel.ignoresMouseEvents = false
        let motion = currentMotion()
        withAnimation(motion.expand) { state.phase = .expanded }
        withAnimation(motion.contentIn) { state.isContentVisible = true }

        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        pointerTask?.cancel()
        isPinned = false
        guard state.isExpanded else { return }
        transitionID += 1
        let id = transitionID

        // Let clicks through to the menu bar right away, not after the animation.
        panel.ignoresMouseEvents = true
        let motion = currentMotion()
        withAnimation(motion.contentOut) { state.isContentVisible = false }
        withAnimation(motion.collapse, completionCriteria: .removed) {
            state.phase = .collapsed
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionID == id else { return }
                self.setPanelFrame(for: .collapsed)
                self.panel.ignoresMouseEvents = false
                self.revalidatePointer()
            }
        }
    }

    private func currentMotion() -> MotionProfile {
        MotionProfile(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            slowMotion: settings.slowAnimations
        )
    }

    // MARK: Pointer

    private func pointerDidChange(inside: Bool) {
        guard inside != isHovering else { return }
        isHovering = inside
        pointerTask?.cancel()

        if inside {
            isPinned = false
            guard !state.isExpanded, settings.expandOnHover else { return }
            pointerTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.hoverIntentDelay)
                guard !Task.isCancelled else { return }
                self?.expand()
            }
        } else {
            guard state.isExpanded, !isPinned else { return }
            pointerTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.collapseGrace)
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        }
    }

    /// Tracking areas only report crossings, so after the panel changes size, check where the
    /// pointer actually is.
    private func revalidatePointer() {
        let rect = state.layout.interactiveScreenRect(for: state.phase)
        pointerDidChange(inside: rect.contains(NSEvent.mouseLocation))
    }

    // MARK: Geometry

    private func refreshGeometry() {
        guard let screen = ScreenLocator.screen(for: settings.displayPreference) else {
            panel.orderOut(nil)
            return
        }
        self.screen = screen
        let geometry = NotchGeometry(screen: screen, forceVirtual: settings.forceVirtualNotch)
        let layout = IslandLayout(geometry: geometry)
        logger.debug("Notch geometry: \(String(describing: geometry.notchRect)), kind: \(geometry.kind.rawValue)")

        if layout != state.layout {
            // A display change mid-animation would leave the panel in the wrong place;
            // start over from the collapsed state.
            transitionID += 1
            pointerTask?.cancel()
            isPinned = false
            state.isContentVisible = false
            state.phase = .collapsed
            state.layout = layout
            panel.ignoresMouseEvents = false
        }
        setPanelFrame(for: state.phase)
        panel.orderFrontRegardless()
    }

    private func setPanelFrame(for phase: IslandPhase) {
        let frame = state.layout.windowFrame(for: phase)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        let interactive = state.layout.interactiveScreenRect(for: phase)
        container.interactiveRect = interactive.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.displayPreference
            _ = settings.forceVirtualNotch
        } onChange: { [weak self] in
            guard let self else { return }
            // onChange fires before the new value is stored; read it on the next main-actor turn.
            Task { @MainActor in
                self.refreshGeometry()
                self.observeSettings()
            }
        }
    }

    // MARK: Diagnostics

    func geometryReport() -> String {
        guard let screen else { return "No screen" }
        return ScreenDiagnostics.report(screen: screen, geometry: state.layout.geometry, layout: state.layout)
    }
}
