import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; they don't need a panel over the menu bar.
        guard !RuntimeEnvironment.isRunningTests else { return }

        let controller = NotchWindowController(settings: .shared)
        controller.start()
        notchController = controller
        SettingsWindowController.shared.notchController = controller
    }
}

enum RuntimeEnvironment {
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}
