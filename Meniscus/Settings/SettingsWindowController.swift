import AppKit
import SwiftUI

/// The Settings window, managed by AppKit so the menu bar icon and reopening the app can show it
/// (SwiftUI's `openSettings` is only available inside SwiftUI scenes).
/// A toolbar-style tab view gives it the standard macOS settings look.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController(settings: .shared)

    /// Set by the app delegate once the notch controller exists; used by the Developer tab.
    var notchController: NotchWindowController?

    /// Starting size of every tab; the window can be resized, and the tabs scroll.
    private static let pageSize = NSSize(width: 560, height: 620)
    private static let minimumSize = NSSize(width: 480, height: 300)

    private init(settings: AppSettings) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let pages: [(String, String, String, AnyView)] = [
            (String(localized: "General"), "gearshape", "general", AnyView(GeneralSettingsView(settings: settings))),
            (String(localized: "Live Activities"), "bell.badge", "activities", AnyView(LiveActivitiesSettingsView(settings: settings))),
            (String(localized: "Music"), "music.note", "music", AnyView(MusicSettingsView(settings: settings))),
            (String(localized: "Calendar"), "calendar", "calendar", AnyView(CalendarSettingsView(settings: settings))),
            (String(localized: "Modes"), "square.grid.2x2", "modes", AnyView(ModesSettingsView(store: .shared))),
            (String(localized: "Capture"), "square.and.pencil", "capture", AnyView(CaptureSettingsView(settings: .shared))),
            (String(localized: "Shelf"), "paperclip", "shelf", AnyView(ShelfSettingsView(settings: settings))),
            (String(localized: "Developer"), "hammer", "developer", AnyView(DeveloperSettingsView(settings: settings, copyGeometry: {
                SettingsWindowController.shared.notchController?.geometryReport()
            }))),
        ]
        for (label, symbol, id, view) in pages {
            tabs.addTabViewItem(SettingsWindowController.tab(label, symbol: symbol, id: id, view: view))
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .resizable]
        window.toolbarStyle = .preference
        window.contentMinSize = Self.minimumSize
        window.title = tabs.tabViewItems.first?.label ?? String(localized: "Settings")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            fitOnScreen(window)
            window.center()
        }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Never taller than the visible part of the screen.
    private func fitOnScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        let maxHeight = visible.height - 40
        if frame.height > maxHeight {
            frame.size.height = maxHeight
            window.setFrame(frame, display: false)
        }
    }

    private static func tab(_ label: String, symbol: String, id: String, view: AnyView) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        // A fixed starting size: the content scrolls instead of stretching the window past the
        // screen. The window stays resizable.
        controller.sizingOptions = []
        controller.preferredContentSize = pageSize
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
