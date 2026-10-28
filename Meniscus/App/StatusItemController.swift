import AppKit

/// The menu bar icon. An `NSStatusItem` with a menu opens that menu on a left and a right click
/// alike, so Settings are one click away either way. Shown unless turned off in Settings.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let settings: AppSettings
    private let notchController: () -> NotchWindowController?
    private var statusItem: NSStatusItem?
    private var defaultsObserver: (any NSObjectProtocol)?

    private var slowAnimationsItem: NSMenuItem?
    private var geometryOverlayItem: NSMenuItem?
    private var virtualNotchItem: NSMenuItem?

    init(settings: AppSettings, notchController: @escaping () -> NotchWindowController?) {
        self.settings = settings
        self.notchController = notchController
        super.init()
    }

    static var isIconShown: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.showMenuBarIcon) as? Bool ?? true
    }

    func start() {
        updateVisibility()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }
    }

    private func updateVisibility() {
        if Self.isIconShown {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Meniscus")
            item.menu = makeMenu()
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item(String(localized: "Quick Capture")) { [weak self] in
            self?.notchController()?.beginCapture()
        })
        menu.addItem(item(String(localized: "Settings…"), key: ",") {
            SettingsWindowController.shared.show()
        })
        menu.addItem(.separator())

        let developer = NSMenu()
        developer.addItem(item(String(localized: "Open or Close Island")) { [weak self] in
            self?.notchController()?.toggleFromMenu()
        })
        developer.addItem(item(String(localized: "Simulate Charging")) {
            ActivityServices.shared.simulateCharging()
        })
        developer.addItem(item(String(localized: "Simulate Low Battery")) {
            ActivityServices.shared.simulateLowBattery()
        })
        developer.addItem(item(String(localized: "Simulate Upcoming Meeting")) {
            ActivityServices.shared.calendar.simulateStartingSoon()
        })
        developer.addItem(item(String(localized: "Simulate Headphones")) {
            ActivityServices.shared.simulateHeadphones()
        })
        developer.addItem(item(String(localized: "Simulate Focus")) {
            ActivityServices.shared.simulateFocus()
        })
        developer.addItem(.separator())
        slowAnimationsItem = addAction(to: developer, String(localized: "Slow Animations")) { [settings] in
            settings.slowAnimations.toggle()
        }
        geometryOverlayItem = addAction(to: developer, String(localized: "Outline Computed Notch")) { [settings] in
            settings.showGeometryOverlay.toggle()
        }
        virtualNotchItem = addAction(to: developer, String(localized: "Use Virtual Notch")) { [settings] in
            settings.forceVirtualNotch.toggle()
        }
        developer.addItem(.separator())
        developer.addItem(item(String(localized: "Copy Geometry Report")) { [weak self] in
            guard let report = self?.notchController()?.geometryReport() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        })
        let developerItem = NSMenuItem(title: String(localized: "Developer"), action: nil, keyEquivalent: "")
        developerItem.submenu = developer
        menu.addItem(developerItem)

        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Meniscus"), key: "q") {
            NSApp.terminate(nil)
        })
        return menu
    }

    private func item(_ title: String, key: String = "", handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = MenuAction(handler)
        return item
    }

    private func addAction(to menu: NSMenu, _ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = self.item(title, handler: handler)
        menu.addItem(item)
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        slowAnimationsItem?.state = settings.slowAnimations ? .on : .off
        geometryOverlayItem?.state = settings.showGeometryOverlay ? .on : .off
        virtualNotchItem?.state = settings.forceVirtualNotch ? .on : .off
    }
}

/// Holds a menu item's closure in its `representedObject`. `NSMenuItem` itself isn't subclassed:
/// its initializers aren't main-actor isolated, so a subclass here wouldn't compile.
private final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
}

private extension StatusItemController {
    @objc func runMenuAction(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuAction)?.handler()
    }
}
