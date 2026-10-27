import AppKit
import OSLog
import SwiftUI

/// Owns the notch windows and drives the collapsed ⇄ expanded transitions.
///
/// Two windows:
/// - The island panel never changes size. It always has the expanded frame, so nothing but the
///   shape animates. While collapsed it ignores the mouse, so the menu bar under its transparent
///   parts stays fully clickable.
/// - A hot zone window exactly over the hardware notch, where the menu bar never draws anything.
///   It notices the pointer and clicks while the island is collapsed.
final class NotchWindowController {
    let state: NotchState
    private let settings: AppSettings
    private let panel = NotchPanel()
    private let container = NotchContainerView(frame: .zero)
    private let hotZone = NotchPanel()
    private let hotZoneView = NotchContainerView(frame: .zero)
    private let logger = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "notch")

    private var screen: NSScreen?
    /// Opened from the menu bar: stays open until the pointer has visited and left it.
    private var isPinned = false
    private var pointerTask: Task<Void, Never>?
    /// Incremented on every transition so a stale collapse completion is ignored.
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
            endCapture: { [weak self] in self?.collapse() }
        )
        let hostingView = NotchHostingView(rootView: NotchRootView(state: state, settings: settings, actions: actions))
        // The controller sizes the panel; SwiftUI must not resize it to fit its content.
        hostingView.sizingOptions = []
        container.embed(hostingView)
        container.onHoverChange = { [weak self] inside in self?.islandPointerDidChange(inside: inside) }
        panel.contentView = container
        panel.ignoresMouseEvents = true

        hotZoneView.onHoverChange = { [weak self] inside in self?.notchPointerDidChange(inside: inside) }
        hotZoneView.onClick = { [weak self] in self?.expand() }
        hotZone.contentView = hotZoneView
        // Nearly invisible fill: a window only receives the mouse where it has pixels. It sits
        // over the hardware notch, so even this 1% black is never seen.
        hotZoneView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        hotZone.ignoresMouseEvents = false

        // Clicking anywhere else ends quick capture.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, CaptureController.shared.isActive else { return }
                self.collapse()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshGeometry() }
        }
        observeSettings()
        observeActivities()
        observeContent()
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

        panel.ignoresMouseEvents = false
        let islandRect = state.layout.interactiveScreenRect(for: .expanded, content: state.content)
        container.resetTracking(pointerIsInside: islandRect.contains(NSEvent.mouseLocation))
        let motion = currentMotion()
        withAnimation(motion.expand) { state.phase = .expanded }
        withAnimation(motion.contentIn) { state.isContentVisible = true }

        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    /// Opens the island with the capture field focused, without activating Meniscus: typing goes
    /// to the island while the frontmost app stays frontmost.
    func beginCapture() {
        CaptureController.shared.begin()
        // Size the island for the field before it opens, not after.
        applyContent(currentContent())
        expand(pinned: true)
        panel.allowsKey = true
        panel.makeKeyAndOrderFront(nil)
    }

    func collapse() {
        pointerTask?.cancel()
        isPinned = false
        if CaptureController.shared.isActive {
            CaptureController.shared.end()
            panel.allowsKey = false
            if panel.isKeyWindow { panel.resignKey() }
        }
        guard state.isExpanded else { return }
        transitionID += 1
        let id = transitionID

        // Let clicks through to the menu bar right away, not after the animation.
        panel.ignoresMouseEvents = true
        let motion = currentMotion()
        withAnimation(motion.contentOut) { state.isContentVisible = false }
        withAnimation(motion.collapse, completionCriteria: .removed) {
            state.phase = state.restingPhase
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionID == id else { return }
                // The pointer may already be back on the notch.
                if self.state.layout.geometry.notchRect.contains(NSEvent.mouseLocation) {
                    self.notchPointerDidChange(inside: true)
                }
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

    /// From the hot zone: matters only while collapsed.
    private func notchPointerDidChange(inside: Bool) {
        guard !state.isExpanded else { return }
        pointerTask?.cancel()
        guard inside, settings.expandOnHover else { return }
        pointerTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.hoverIntentDelay)
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    /// From the island: matters only while expanded.
    private func islandPointerDidChange(inside: Bool) {
        // Quick capture stays open until submitted or dismissed.
        guard state.isExpanded, !CaptureController.shared.isActive else { return }
        pointerTask?.cancel()
        if inside {
            isPinned = false
            return
        }
        guard !isPinned else { return }
        pointerTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.collapseGrace)
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    // MARK: Geometry

    private func refreshGeometry() {
        guard let screen = ScreenLocator.screen(for: settings.displayPreference) else {
            panel.orderOut(nil)
            hotZone.orderOut(nil)
            return
        }
        self.screen = screen
        let geometry = NotchGeometry(screen: screen, forceVirtual: settings.forceVirtualNotch)
        let layout = IslandLayout(geometry: geometry)
        logger.debug("Notch geometry: \(String(describing: geometry.notchRect)), kind: \(geometry.kind.rawValue)")

        if layout != state.layout {
            // A display change mid-animation would leave the island in the wrong place;
            // start over from the collapsed state.
            transitionID += 1
            pointerTask?.cancel()
            isPinned = false
            state.isContentVisible = false
            state.phase = state.restingPhase
            state.layout = layout
            panel.ignoresMouseEvents = true
        }

        let panelFrame = layout.windowFrame(for: .expanded)
        if panel.frame != panelFrame { panel.setFrame(panelFrame, display: true) }
        container.interactiveRect = layout.interactiveScreenRect(for: .expanded, content: state.content)
            .offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)

        let hotZoneFrame = layout.geometry.notchRect
        if hotZone.frame != hotZoneFrame { hotZone.setFrame(hotZoneFrame, display: true) }
        hotZoneView.interactiveRect = CGRect(origin: .zero, size: hotZoneFrame.size)

        // The island panel goes above the hot zone so it gets the mouse while expanded.
        hotZone.orderFrontRegardless()
        panel.orderFrontRegardless()
    }

    // MARK: Content

    /// Quick capture comes first. Otherwise the player replaces the home content while something
    /// plays; Now Playing itself rides out short gaps (like a track change), so this doesn't
    /// flicker between the two. The home content also changes size with the date and the next
    /// event.
    private func currentContent() -> IslandContent {
        if CaptureController.shared.isActive { return .capture }
        return ActivityServices.shared.nowPlaying.current == nil ? .home(state.homeContentSize) : .nowPlaying
    }

    private func observeContent() {
        let content = withObservationTracking {
            currentContent()
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.observeContent() }
        }
        applyContent(content)
    }

    private func applyContent(_ content: IslandContent) {
        guard content != state.content else { return }
        withAnimation(currentMotion().expand) { state.content = content }

        // The island's size changed; so did the area that keeps it open.
        let panelFrame = panel.frame
        let islandRect = state.layout.interactiveScreenRect(for: .expanded, content: content)
        container.interactiveRect = islandRect.offsetBy(dx: -panelFrame.minX, dy: -panelFrame.minY)
        guard state.isExpanded else { return }
        let pointerIsInside = islandRect.contains(NSEvent.mouseLocation)
        container.resetTracking(pointerIsInside: pointerIsInside)
        if !pointerIsInside { islandPointerDidChange(inside: false) }
    }

    // MARK: Live activities

    /// Follows the activity center: a live activity turns the resting notch into the compact
    /// island, and the island returns to the plain notch when it ends.
    private func observeActivities() {
        let activity = withObservationTracking {
            ActivityServices.shared.center.current
        } onChange: { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.observeActivities() }
        }
        guard activity != state.compactActivity else { return }
        let motion = currentMotion()
        withAnimation(activity == nil ? motion.collapse : motion.expand) {
            state.compactActivity = activity
            if !state.isExpanded { state.phase = state.restingPhase }
        }
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
