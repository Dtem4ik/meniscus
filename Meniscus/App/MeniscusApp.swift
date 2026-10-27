import SwiftUI

@main
struct MeniscusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Meniscus", systemImage: "drop.fill") {
            Button("Quit Meniscus") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
