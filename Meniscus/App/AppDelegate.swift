import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var notchController: NotchWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; they don't need a panel over the menu bar.
        guard !RuntimeEnvironment.isRunningTests else { return }

        ActivityServices.shared.start(settings: .shared)
        ModesStore.shared.start()

        let controller = NotchWindowController(settings: .shared)
        controller.start()
        notchController = controller
        CaptureController.shared.bindHotKey { [weak controller] in controller?.beginCapture() }
        ModeRunner.beginCapture = { [weak controller] in controller?.beginCapture() }
        SettingsWindowController.shared.notchController = controller

        let statusItem = StatusItemController(settings: .shared) { [weak self] in self?.notchController }
        statusItem.start()
        statusItemController = statusItem
    }

    /// `meniscus://v1/notify?…` links: anonymous, so only text and state, off by default.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "meniscus" {
            ActivityServices.shared.external.handleLink(url)
        }
    }

    /// Opening Meniscus again (from Finder, Spotlight or the Dock) shows Settings, which is the
    /// way back when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
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
