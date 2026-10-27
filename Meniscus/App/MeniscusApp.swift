import SwiftUI

@main
struct MeniscusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("Meniscus", systemImage: "drop.fill", isInserted: $showMenuBarIcon) {
            MenuBarMenu(settings: .shared, appDelegate: appDelegate)
        }
    }
}
