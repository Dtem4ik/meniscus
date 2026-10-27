import Foundation
import IOKit.ps
import Observation
import OSLog

/// Publishes the battery state and charger events. IOKit calls back on the main run loop
/// whenever a power source changes, so nothing polls.
@Observable
final class PowerSourceMonitor {
    private(set) var state: PowerState?
    /// Called for every charger connect/disconnect and when the battery becomes full.
    @ObservationIgnored var onEvent: ((PowerEvent) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    /// Macs without an internal battery report nothing; the monitor then stays idle.
    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourcesDidChange, context)?
            .takeRetainedValue() else {
            Logger.power.error("Couldn't subscribe to power source notifications")
            return
        }
        // Common modes, so changes arrive even while a menu is open.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        refresh()
    }

    func stop() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.runLoopSource = nil
    }

    fileprivate func refresh() {
        let current = Self.readInternalBattery()
        let previous = state
        guard current != previous else { return }
        if let current {
            Logger.power.notice(
                "Battery \(current.level, privacy: .public)%, on AC: \(current.isOnACPower, privacy: .public), charging: \(current.isCharging, privacy: .public), charged: \(current.isCharged, privacy: .public)"
            )
        } else {
            Logger.power.notice("No internal battery reported")
        }
        state = current
        if let current, let event = PowerEventDetector.event(from: previous, to: current) {
            onEvent?(event)
        }
    }

    private static func readInternalBattery() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            if let state = PowerState(powerSourceDescription: description) { return state }
        }
        return nil
    }
}

/// IOKit callback. The run loop source is scheduled on the main run loop, so this runs on the
/// main thread.
private nonisolated func powerSourcesDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { monitor.refresh() }
}
