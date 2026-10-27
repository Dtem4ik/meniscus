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
        menu.addItem(ActionMenuItem(String(localized: "Settings…"), key: ",") {
            SettingsWindowController.shared.show()
        })
        menu.addItem(.separator())

        let developer = NSMenu()
        developer.addItem(ActionMenuItem(String(localized: "Open or Close Island")) { [weak self] in
            self?.notchController()?.toggleFromMenu()
        })
        developer.addItem(ActionMenuItem(String(localized: "Simulate Charging")) {
            ActivityServices.shared.simulateCharging()
        })
        developer.addItem(.separator())
        slowAnimationsItem = developer.addAction(String(localized: "Slow Animations")) { [settings] in
            settings.slowAnimations.toggle()
        }
        geometryOverlayItem = developer.addAction(String(localized: "Outline Computed Notch")) { [settings] in
            settings.showGeometryOverlay.toggle()
        }
        virtualNotchItem = developer.addAction(String(localized: "Use Virtual Notch")) { [settings] in
            settings.forceVirtualNotch.toggle()
        }
        developer.addItem(.separator())
        developer.addItem(ActionMenuItem(String(localized: "Copy Geometry Report")) { [weak self] in
            guard let report = self?.notchController()?.geometryReport() else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        })
        let developerItem = NSMenuItem(title: String(localized: "Developer"), action: nil, keyEquivalent: "")
        developerItem.submenu = developer
        menu.addItem(developerItem)

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Quit Meniscus"), key: "q") {
            NSApp.terminate(nil)
        })
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        slowAnimationsItem?.state = settings.slowAnimations ? .on : .off
        geometryOverlayItem?.state = settings.showGeometryOverlay ? .on : .off
        virtualNotchItem?.state = settings.forceVirtualNotch ? .on : .off
    }
}

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

private extension NSMenu {
    @discardableResult
    func addAction(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title, handler: handler)
        addItem(item)
        return item
    }
}
