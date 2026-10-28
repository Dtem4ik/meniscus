import Foundation

/// Hands work from system callbacks to the main actor. Many callbacks (IOKit, IOBluetooth,
/// notifications) arrive on the main thread, but some move to background queues between macOS
/// versions; asserting the main actor there would stop the app. This runs the work right away on
/// the main thread and otherwise queues it there. Never traps.
nonisolated enum MainThread {
    static func run(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in work() }
        }
    }
}
