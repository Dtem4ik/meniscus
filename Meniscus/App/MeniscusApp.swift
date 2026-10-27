import SwiftUI

@main
struct MeniscusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and the Settings window are AppKit (`StatusItemController`,
        // `SettingsWindowController`); SwiftUI only needs a scene to exist.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { SettingsWindowController.shared.show() }
                        .keyboardShortcut(",")
                }
            }
    }
}
