import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some View {
        Form {
            Section {
                Toggle("Open when the pointer rests on the notch", isOn: $settings.expandOnHover)
                Toggle("Haptic feedback on the trackpad", isOn: $settings.hapticsEnabled)
            }
            Section {
                Picker("Show on", selection: $settings.displayPreference) {
                    ForEach(DisplayPreference.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            } footer: {
                if !showMenuBarIcon {
                    Text("Settings stay available from the gear button inside the notch.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Tools for tuning the island on a real screen. Visible in every build while the app is pre-1.0.
struct DeveloperSettingsView: View {
    @Bindable var settings: AppSettings
    var copyGeometry: () -> String?

    @State private var didCopy = false

    var body: some View {
        Form {
            Section("Island style") {
                Picker("Style", selection: $settings.islandStyle) {
                    ForEach(IslandStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            Section("Tuning") {
                Toggle("Slow animations (×\(Int((1 / Motion.slowMotionFactor).rounded())))", isOn: $settings.slowAnimations)
                Toggle("Outline the computed notch in red", isOn: $settings.showGeometryOverlay)
                Toggle("Use a virtual notch on this screen", isOn: $settings.forceVirtualNotch)
            }
            Section {
                Button(didCopy ? "Copied" : "Copy Geometry Report") {
                    guard let report = copyGeometry() else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    didCopy = true
                }
            } footer: {
                Text("Screen numbers behind the notch outline. Paste them into a bug report.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
