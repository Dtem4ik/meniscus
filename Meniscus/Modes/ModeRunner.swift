import AppKit
import OSLog

/// Starts the actions of a mode, in order. Opening is fire-and-forget: a failing action is
/// reported but doesn't stop the others.
enum ModeRunner {
    private static let logger = Logger(subsystem: "io.github.dtem4ik.meniscus", category: "modes")
    /// Opens the quick capture field; set by the app delegate once the island exists.
    static var beginCapture: (() -> Void)?

    struct Failure: Equatable, Sendable {
        var actionIndex: Int
        var message: String
    }

    /// Returns the actions that couldn't be started. Errors reported later by the opened app
    /// (for example an unknown Shortcuts name) only reach the log.
    @discardableResult
    static func run(_ mode: Mode) -> [Failure] {
        var failures: [Failure] = []
        for (index, action) in mode.actions.enumerated() {
            if let message = perform(action) {
                logger.error("Mode \(mode.name, privacy: .public), action \(index + 1): \(message, privacy: .public)")
                failures.append(Failure(actionIndex: index, message: message))
            }
        }
        return failures
    }

    /// Returns why the action couldn't start, or `nil`.
    private static func perform(_ action: ModeAction) -> String? {
        guard let resolved = ModeActionResolver.resolve(action) else {
            return ModeActionResolver.problem(with: action) ?? "The action is incomplete."
        }
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        switch resolved {
        case .url(let url):
            workspace.open(url, configuration: configuration, completionHandler: logFailure)
        case .application(let bundleID):
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
                return "No app with the bundle id \(bundleID) is installed."
            }
            workspace.openApplication(at: appURL, configuration: configuration, completionHandler: logFailure)
        case .quickCapture:
            guard let beginCapture else { return "Quick capture isn't ready yet." }
            beginCapture()
        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return "\(url.path(percentEncoded: false)) doesn't exist."
            }
            workspace.open(url, configuration: configuration, completionHandler: logFailure)
        }
        return nil
    }

    private nonisolated static let logFailure: @Sendable (NSRunningApplication?, (any Error)?) -> Void = { _, error in
        guard let error else { return }
        Logger(subsystem: "io.github.dtem4ik.meniscus", category: "modes")
            .error("Opening failed: \(error.localizedDescription, privacy: .public)")
    }
}
