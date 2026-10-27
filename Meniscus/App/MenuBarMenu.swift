import AppKit
import SwiftUI

struct MenuBarMenu: View {
    @Bindable var settings: AppSettings
    let appDelegate: AppDelegate

    var body: some View {
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")

        Divider()

        Menu("Developer") {
            Button("Open or Close Island") { appDelegate.notchController?.toggleFromMenu() }
            Button("Simulate Charging") { ActivityServices.shared.simulateCharging() }
            Divider()
            Toggle("Slow Animations", isOn: $settings.slowAnimations)
            Toggle("Outline Computed Notch", isOn: $settings.showGeometryOverlay)
            Toggle("Use Virtual Notch", isOn: $settings.forceVirtualNotch)
            Divider()
            Button("Copy Geometry Report") {
                guard let report = appDelegate.notchController?.geometryReport() else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            }
        }

        Divider()

        Button("Quit Meniscus") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
