import AppKit
import SwiftUI

/// The Settings window, managed by AppKit so it opens the same way from the menu bar and from
/// inside the island (SwiftUI's `openSettings` is only available inside SwiftUI scenes).
/// A toolbar-style tab view gives it the standard macOS settings look.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController(settings: .shared)

    /// Set by the app delegate once the notch controller exists; used by the Developer tab.
    var notchController: NotchWindowController?

    private init(settings: AppSettings) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(SettingsWindowController.tab(
            "General", symbol: "gearshape", id: "general",
            view: GeneralSettingsView(settings: settings)
        ))
        tabs.addTabViewItem(SettingsWindowController.tab(
            "Developer", symbol: "hammer", id: "developer",
            view: DeveloperSettingsView(settings: settings, copyGeometry: {
                SettingsWindowController.shared.notchController?.geometryReport()
            })
        ))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.title = tabs.tabViewItems.first?.label ?? "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private static func tab(_ label: String, symbol: String, id: String, view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        // NSTabViewController shows the selected tab's title in the window title, the standard
        // look of macOS settings windows.
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.identifier = id
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}
